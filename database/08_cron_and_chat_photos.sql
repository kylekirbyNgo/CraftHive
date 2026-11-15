-- =============================================================================
-- CraftHive – 08: Automatic stock release + photos in chat
--
-- 1. Every 15 minutes, pg_cron runs release_expired_reservations() (from 04):
--    unpaid ready-made orders past their 24-hour reservation are cancelled and
--    their stock goes back on sale, even when nobody opens the app. The
--    triggers from 05 then notify the buyer and the seller.
--
-- 2. Photos sent in chat are kept in a private bucket, chat-photos, under the
--    chat's folder: chat-photos/{buyer user_id}_{store_id}/{file}. Only the
--    buyer and the owner of that store may upload or open them.
--
-- Run once in the Supabase SQL editor, after 01–07.
-- =============================================================================

-- 1. Release expired reservations every 15 minutes -------------------------
create extension if not exists pg_cron;

-- Replace the job if this file is run again.
select cron.unschedule(jobid) from cron.job where jobname = 'release-expired-reservations';
select cron.schedule(
  'release-expired-reservations',
  '*/15 * * * *',
  $$select public.release_expired_reservations();$$
);

-- 2. Chat photos ------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('chat-photos', 'chat-photos', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- True when the signed-in user is the buyer or the store owner of the chat
-- whose Firestore ID is the folder name ({buyer user_id}_{store_id}).
create or replace function public.in_chat_folder(p_folder text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select case
    when p_folder ~ '^[0-9a-f-]{36}_[0-9a-f-]{36}$' then
      split_part(p_folder, '_', 1)::uuid = (select auth.uid())
      or public.owns_store(split_part(p_folder, '_', 2)::uuid)
    else false
  end;
$$;

revoke execute on function public.in_chat_folder(text) from public, anon;
grant execute on function public.in_chat_folder(text) to authenticated;

drop policy if exists "chat-photos: people in the chat upload" on storage.objects;
create policy "chat-photos: people in the chat upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'chat-photos' and public.in_chat_folder((storage.foldername(name))[1]));

drop policy if exists "chat-photos: people in the chat view" on storage.objects;
create policy "chat-photos: people in the chat view" on storage.objects for select to authenticated
  using (bucket_id = 'chat-photos' and public.in_chat_folder((storage.foldername(name))[1]));
