-- =============================================================================
-- CraftHive – 06: Edit profile
--
-- • The app may change only these profile columns: full name, phone number,
--   sex, country and profile photo. Username and email cannot be edited
--   directly, so username log-in (email_for_username) always finds the email
--   that Supabase Auth signs in with.
-- • A new email address is changed through Supabase Auth (a confirmation link
--   is sent to it); once confirmed, the trigger below copies it to USERS.
-- • Users may delete their old profile photos from the avatars bucket.
--
-- Run once in the Supabase SQL editor, after 01–05.
-- =============================================================================

-- 1. Which columns of USERS the app may update ("users: update own" in 02 still
--    limits it to the signed-in user's own row).
revoke update on public.users from authenticated;
grant update (full_name, phone_number, sex, country, avatar_path) on public.users to authenticated;

-- 2. Keep users.email equal to the confirmed Supabase Auth email.
create or replace function public.sync_user_email()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.email is not null and new.email is distinct from old.email then
    update public.users set email = lower(new.email) where user_id = new.id;
  end if;
  return new;
end;
$$;

revoke execute on function public.sync_user_email() from public, anon, authenticated;

drop trigger if exists on_auth_user_email_changed on auth.users;
create trigger on_auth_user_email_changed
  after update of email on auth.users
  for each row execute function public.sync_user_email();

-- 3. Old profile photos are removed when a new one is uploaded.
drop policy if exists "avatars: delete own" on storage.objects;
create policy "avatars: delete own" on storage.objects for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
