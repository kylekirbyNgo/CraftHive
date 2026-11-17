-- =============================================================================
-- CraftHive – 13: Admin accounts and dashboard
-- Run after 01–12. Safe to run more than once.
--
-- Milestone II: "Platform administrators consist of CraftHive personnel using
-- dedicated accounts" (ADMIN, outside the USER hierarchy, roles moderator and
-- superadmin). Milestone III: "Administrator accounts and dashboard for
-- verification review and dispute resolution".
--
--   Every admin : admin_dashboard (counts for the overview), admin_accounts (staff list)
--   Superadmin  : set_admin_role. Adding and removing staff needs the Auth admin
--                 API, so it is done by the admin-accounts Edge Function.
-- =============================================================================

-- Staff who leave are deactivated, not deleted, so their name stays on the
-- decisions they made (verified_by, resolved_by). The Edge Function also blocks
-- their sign-in.
alter table public.admin add column if not exists is_active boolean not null default true;

-- Same as in 02, but deactivated staff are no longer admins.
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admin a where a.auth_uid = (select auth.uid()) and a.is_active); $$;

create or replace function public.my_admin_role()
returns text language sql stable security definer set search_path = ''
as $$ select a.role from public.admin a where a.auth_uid = auth.uid() and a.is_active; $$;

create or replace function public.admin_dashboard()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_role text := public.my_admin_role();
begin
  if v_role is null then raise exception 'Only CraftHive admins can open the dashboard.' using errcode = 'P0001'; end if;
  return jsonb_build_object(
    'my_role', v_role,
    -- Verified Maker (11_verified_maker.sql)
    'makers_waiting', (select count(*) from public.seller s where s.verification_status = 'pending'),
    'oldest_waiting_at', (select min(s.submitted_at) from public.seller s where s.verification_status = 'pending'),
    'makers_verified', (select count(*) from public.seller s where s.verification_status = 'verified'),
    'approved_7d', (select count(*) from public.seller s where s.verification_status = 'verified' and s.verified_at >= now() - interval '7 days'),
    -- A rejection has no date column; its ID purge date is the decision day + id_retention_days().
    'rejected_7d', (select count(*) from public.seller s where s.verification_status = 'rejected'
                     and s.id_purge_date - public.id_retention_days() >= current_date - 7),
    'ids_on_file', (select count(*) from public.seller s where s.id_image_path is not null),
    'ids_due_7d', (select count(*) from public.private_file_purge f where f.purged_at is null and f.reason = 'seller_id' and f.purge_on <= current_date + 7),
    'ids_overdue', (select count(*) from public.private_file_purge f where f.purged_at is null and f.reason = 'seller_id' and f.purge_on < current_date),
    'ids_deleted_30d', (select count(*) from public.private_file_purge f where f.reason = 'seller_id' and f.purged_at >= now() - interval '30 days'),
    -- Disputes (12_disputes.sql)
    'disputes_open', (select count(*) from public.dispute d where d.status = 'open'),
    'disputes_under_review', (select count(*) from public.dispute d where d.status = 'under_review'),
    'oldest_open_dispute_at', (select min(d.opened_at) from public.dispute d where d.status in ('open', 'under_review')),
    'disputes_decided_7d', (select count(*) from public.dispute d where d.status in ('resolved', 'closed') and d.resolved_at >= now() - interval '7 days'),
    'my_decisions_7d', (select count(*) from public.dispute d join public.admin a on a.admin_id = d.resolved_by
                         where a.auth_uid = auth.uid() and d.status in ('resolved', 'closed') and d.resolved_at >= now() - interval '7 days'),
    -- Marketplace
    'stores', (select count(*) from public.store st where not st.is_archived),
    'staff', (select count(*) from public.admin a where a.is_active));
end;
$$;

create or replace function public.admin_accounts()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.my_admin_role() is null then raise exception 'Only CraftHive admins can see the staff list.' using errcode = 'P0001'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
             'admin_id', a.admin_id, 'first_name', a.first_name, 'last_name', a.last_name, 'email', a.email,
             'role', a.role, 'is_active', a.is_active, 'created_at', a.created_at, 'is_me', a.auth_uid = auth.uid(),
             'last_sign_in_at', u.last_sign_in_at,
             'decisions', (select count(*) from public.dispute d where d.resolved_by = a.admin_id and d.status in ('resolved', 'closed'))
                        + (select count(*) from public.seller s where s.verified_by = a.admin_id))
           order by a.is_active desc, (a.role = 'superadmin') desc, a.first_name, a.last_name)
    from public.admin a left join auth.users u on u.id = a.auth_uid), '[]'::jsonb);
end;
$$;

create or replace function public.set_admin_role(p_admin_id uuid, p_role text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_target record;
begin
  if public.my_admin_role() is distinct from 'superadmin' then
    raise exception 'Only a superadmin can change staff roles.' using errcode = 'P0001';
  end if;
  if p_role not in ('moderator', 'superadmin') then raise exception 'Unknown role.' using errcode = 'P0001'; end if;
  select a.admin_id, a.role into v_target from public.admin a where a.admin_id = p_admin_id and a.is_active for update;
  if not found then raise exception 'Staff member not found.' using errcode = 'P0001'; end if;
  if v_target.role = 'superadmin' and p_role <> 'superadmin'
     and (select count(*) from public.admin a where a.role = 'superadmin' and a.is_active) <= 1 then
    raise exception 'CraftHive needs at least one superadmin.' using errcode = 'P0001';
  end if;
  update public.admin set role = p_role where admin_id = p_admin_id;
end;
$$;

revoke execute on function public.my_admin_role(), public.admin_dashboard(), public.admin_accounts(), public.set_admin_role(uuid, text) from public, anon;
grant execute on function public.my_admin_role(), public.admin_dashboard(), public.admin_accounts(), public.set_admin_role(uuid, text) to authenticated;

-- review_verification and update_dispute (11, 12) look up the caller's admin_id
-- without checking is_active; a deactivated admin cannot sign in, and is_admin()
-- above also stops them from reading the queues.

-- Staff can read every admin row (names on decisions); only the functions and
-- the admin-accounts Edge Function (service role) change them.
drop policy if exists "admin: staff read" on public.admin;
create policy "admin: staff read" on public.admin for select to authenticated
  using ((select public.is_admin()));
revoke insert, update, delete on public.admin from anon, authenticated;
