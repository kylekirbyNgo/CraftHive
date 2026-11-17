-- =============================================================================
-- CraftHive – Verified Maker
-- Run after 01–10. Safe to run more than once.
--
--   Maker  : submit_verification  (government ID + 2 to 6 portfolio photos)
--   Admin  : verification_queue → review_verification (approve / reject with reason)
--   Badge  : seller.verification_status = 'verified' (already shown by store_card)
--   Privacy: ID images are deleted 30 days after the admin's decision
--            (Data Privacy Act of 2012, RA 10173: keep personal data no longer
--            than needed). Replaced files are deleted at once. The deletion is
--            done by the purge-private-files Edge Function, which runs daily
--            (see the schedule at the end of this file).
--
-- Every change goes through the functions below; makers can no longer update
-- their seller row directly.
-- =============================================================================

alter table public.seller add column if not exists id_type      varchar(40);
alter table public.seller add column if not exists submitted_at timestamptz;
alter table public.seller add column if not exists review_note  varchar(300);

-- Files in the private-files bucket waiting to be deleted.
create table if not exists public.private_file_purge (
  path       varchar(255) primary key,
  purge_on   date        not null,
  reason     varchar(30) not null check (reason in ('seller_id', 'portfolio_replaced', 'id_replaced')),
  queued_at  timestamptz not null default now(),
  purged_at  timestamptz
);
create index if not exists private_file_purge_due on public.private_file_purge (purge_on) where purged_at is null;
alter table public.private_file_purge enable row level security;
-- No policies: only the functions below and the service role touch this table.

-- Makers used to change verification_status themselves; now only the functions do.
drop policy if exists "seller: request verification" on public.seller;
revoke update on public.seller from anon, authenticated;

-- How long ID images are kept after the decision.
create or replace function public.id_retention_days()
returns int language sql immutable as $$ select 30 $$;

create or replace function public._queue_purge(p_path text, p_on date, p_reason text)
returns void language sql security definer set search_path = ''
as $$
  insert into public.private_file_purge as f (path, purge_on, reason)
  select p_path, p_on, p_reason where coalesce(p_path, '') <> ''
  on conflict (path) do update set purge_on = least(f.purge_on, excluded.purge_on), purged_at = null;
$$;

-- ---------------------------------------------------------------------------
-- 1. Maker: my verification and submitting it
-- ---------------------------------------------------------------------------
create or replace function public.my_verification()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'status', s.verification_status,
    'id_type', s.id_type,
    'submitted_at', s.submitted_at,
    'verified_at', s.verified_at,
    'review_note', s.review_note,
    'id_purge_date', s.id_purge_date,
    'id_on_file', s.id_image_path is not null,
    'portfolio', coalesce((select jsonb_agg(p.image_path order by p.uploaded_at)
                             from public.seller_portfolio_image p where p.seller_id = s.user_id), '[]'::jsonb))
  from public.seller s where s.user_id = auth.uid();
$$;

create or replace function public.submit_verification(p_id_type text, p_id_path text, p_portfolio_paths text[])
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_s record;
  v_prefix text := auth.uid()::text || '/verification/';
  v_n int := coalesce(array_length(p_portfolio_paths, 1), 0);
  v_path text;
begin
  select s.user_id, s.verification_status, s.id_image_path into v_s from public.seller s where s.user_id = v_uid for update;
  if not found or not exists (select 1 from public.store st where st.seller_id = v_uid) then
    raise exception 'Open your store first, then apply for the Verified Maker badge.' using errcode = 'P0001';
  end if;
  if v_s.verification_status = 'pending' then raise exception 'Your documents are already being reviewed.' using errcode = 'P0001'; end if;
  if v_s.verification_status = 'verified' then raise exception 'Your store is already verified.' using errcode = 'P0001'; end if;
  if coalesce(trim(p_id_type), '') = '' or length(trim(p_id_type)) > 40 then
    raise exception 'Choose the type of ID you are sending.' using errcode = 'P0001';
  end if;
  if coalesce(p_id_path, '') not like v_prefix || '%' then raise exception 'Upload a photo of your ID.' using errcode = 'P0001'; end if;
  if v_n < 2 or v_n > 6 then raise exception 'Add 2 to 6 photos of your work.' using errcode = 'P0001'; end if;
  foreach v_path in array p_portfolio_paths loop
    if coalesce(v_path, '') not like v_prefix || '%' then raise exception 'A portfolio photo did not upload. Try again.' using errcode = 'P0001'; end if;
  end loop;

  -- A new submission replaces the old files: delete those right away.
  if v_s.id_image_path is not null and v_s.id_image_path <> p_id_path then
    perform public._queue_purge(v_s.id_image_path, current_date, 'id_replaced');
  end if;
  perform public._queue_purge(p.image_path, current_date, 'portfolio_replaced')
     from public.seller_portfolio_image p where p.seller_id = v_uid and p.image_path <> all (p_portfolio_paths);
  delete from public.seller_portfolio_image where seller_id = v_uid;
  insert into public.seller_portfolio_image (seller_id, image_path) select v_uid, unnest(p_portfolio_paths);

  -- The new ID is no longer due for deletion until it has been reviewed.
  delete from public.private_file_purge where path = p_id_path or path = any (p_portfolio_paths);

  update public.seller set
    verification_status = 'pending',
    id_type = trim(p_id_type),
    id_image_path = p_id_path,
    id_purge_date = null,
    submitted_at = now(),
    review_note = null,
    verified_by = null,
    verified_at = null
  where user_id = v_uid;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Admin: queue and decision
-- ---------------------------------------------------------------------------
create or replace function public.verification_queue(p_status text default 'pending')
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Only CraftHive admins can review makers.' using errcode = 'P0001'; end if;
  return coalesce((
    -- Pending: oldest first (first come, first served). Reviewed: newest first.
    select jsonb_agg(row_to_json(q)::jsonb order by
             case when p_status = 'pending' then extract(epoch from q.submitted_at) else -extract(epoch from q.submitted_at) end)
    from (
      select s.user_id as seller_id, st.store_name, st.city, st.store_description, u.full_name, u.username,
             s.verification_status as status, s.id_type, s.id_image_path, s.submitted_at, s.verified_at,
             s.review_note, s.id_purge_date,
             coalesce((select jsonb_agg(p.image_path order by p.uploaded_at)
                         from public.seller_portfolio_image p where p.seller_id = s.user_id), '[]'::jsonb) as portfolio
      from public.seller s
      join public.store st on st.seller_id = s.user_id
      join public.users u on u.user_id = s.user_id
      where (p_status = 'pending' and s.verification_status = 'pending')
         or (p_status = 'reviewed' and s.verification_status in ('verified', 'rejected') and s.submitted_at is not null)
      order by s.submitted_at desc nulls last
      limit 200
    ) q), '[]'::jsonb);
end;
$$;

create or replace function public.review_verification(p_seller_id uuid, p_approve boolean, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_admin uuid;
  v_s record;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_purge date := current_date + public.id_retention_days();
begin
  select a.admin_id into v_admin from public.admin a where a.auth_uid = auth.uid();
  if v_admin is null then raise exception 'Only CraftHive admins can review makers.' using errcode = 'P0001'; end if;
  select s.user_id, s.verification_status, s.id_image_path into v_s from public.seller s where s.user_id = p_seller_id for update;
  if not found or v_s.verification_status <> 'pending' then
    raise exception 'This application was already reviewed. Refresh the list.' using errcode = 'P0001';
  end if;
  if not p_approve and (v_note is null or length(v_note) < 5) then
    raise exception 'Tell the maker why the application was not approved.' using errcode = 'P0001';
  end if;

  update public.seller set
    verification_status = case when p_approve then 'verified' else 'rejected' end,
    verified_by = v_admin,
    verified_at = case when p_approve then now() else null end,
    review_note = left(v_note, 300),
    id_purge_date = case when v_s.id_image_path is null then null else v_purge end
  where user_id = p_seller_id;

  perform public._queue_purge(v_s.id_image_path, v_purge, 'seller_id');
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Purge (service role only: used by the purge-private-files Edge Function)
-- ---------------------------------------------------------------------------
create or replace function public.due_private_files(p_limit int default 500)
returns setof text language sql stable security definer set search_path = ''
as $$
  select f.path from public.private_file_purge f
  where f.purged_at is null and f.purge_on <= current_date
  order by f.purge_on limit greatest(1, least(coalesce(p_limit, 500), 1000));
$$;

create or replace function public.mark_private_files_purged(p_paths text[])
returns int language plpgsql security definer set search_path = ''
as $$
declare v_n int;
begin
  update public.private_file_purge set purged_at = now() where path = any (p_paths) and purged_at is null;
  get diagnostics v_n = row_count;
  -- The ID is gone: forget its path (the purge date stays as the record of when).
  update public.seller set id_image_path = null where id_image_path = any (p_paths);
  return v_n;
end;
$$;

revoke execute on function public._queue_purge(text, date, text), public.due_private_files(int),
  public.mark_private_files_purged(text[]) from public, anon, authenticated;
grant execute on function public.due_private_files(int), public.mark_private_files_purged(text[]) to service_role;

revoke execute on function public.my_verification(), public.submit_verification(text, text, text[]),
  public.verification_queue(text), public.review_verification(uuid, boolean, text) from public, anon;
grant execute on function public.my_verification(), public.submit_verification(text, text, text[]),
  public.verification_queue(text), public.review_verification(uuid, boolean, text) to authenticated;

-- Makers may delete files in their own private folder (clean-up after a failed submission).
drop policy if exists "private-files: own folder delete" on storage.objects;
create policy "private-files: own folder delete" on storage.objects for delete to authenticated
  using (bucket_id = 'private-files' and (storage.foldername(name))[1] = (select auth.uid())::text);

-- ---------------------------------------------------------------------------
-- 4. Daily schedule (optional, run once after deploying the Edge Function)
--
-- pg_cron is already enabled by 08_cron_and_chat_photos.sql. Also needs pg_net
-- (Database → Extensions) and two
-- Vault secrets (Project Settings → Vault):
--   project_url       https://<project-ref>.supabase.co
--   purge_cron_secret the same value you set as the function's CRON_SECRET
--
-- select cron.schedule('purge-private-files', '15 3 * * *', $cron$
--   select net.http_post(
--     url     := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url') || '/functions/v1/purge-private-files',
--     headers := jsonb_build_object('Content-Type', 'application/json',
--                  'x-cron-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'purge_cron_secret')),
--     body    := '{}'::jsonb);
-- $cron$);
-- ---------------------------------------------------------------------------
