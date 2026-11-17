-- =============================================================================
-- CraftHive – 12: Disputes ("Report a problem")
-- Run after 01–11 (uses send_db_event from 05_firebase.sql). Safe to run more
-- than once.
--
-- Milestone II: "If a buyer or seller disagrees about an order, either party
-- may open a dispute. The dispute references the order, its accepted quote,
-- and its payments, and both parties may attach evidence such as photos or
-- screenshots. An administrator reviews the case and records the resolution,
-- the date, and the handling staff member."
--
--   Buyer / seller : open_dispute, add_dispute_evidence, order_dispute
--   Admin          : dispute_queue, update_dispute (under review → resolved / closed)
--   Notifications  : the dispute trigger sends each change to firebase-bridge
--
-- Evidence photos go to private-files/{user_id}/{order_id}/dispute_*.jpg, which
-- the order's buyer and seller and the admins can open (02 storage policy).
-- Every change goes through the functions below.
-- =============================================================================

-- One active dispute per order.
create unique index if not exists dispute_one_active_per_order
  on public.dispute (order_id) where status in ('open', 'under_review');

drop policy if exists "dispute: participants open" on public.dispute;
drop policy if exists "dispute: admins resolve" on public.dispute;
drop policy if exists "dispute_evidence: participants add" on public.dispute_evidence;
revoke insert, update, delete on public.dispute, public.dispute_evidence from anon, authenticated;

-- ---------------------------------------------------------------------------
-- The full case as JSON: dispute, order, accepted quote, payments, evidence.
-- Only called by the functions below, after they checked who is asking.
-- ---------------------------------------------------------------------------
create or replace function public._dispute_json(p_dispute_id uuid)
returns jsonb language sql stable security definer set search_path = ''
as $$
  select jsonb_build_object(
    'dispute_id', d.dispute_id,
    'order_id', o.order_id,
    'order_number', o.order_number,
    'order_status', o.status,
    'order_total', o.total_amount,
    'order_date', o.order_date,
    'is_custom', o.quote_id is not null,
    'buyer_name', bu.full_name,
    'buyer_username', bu.username,
    'store_name', st.store_name,
    'opened_by_role', case when d.opened_by = o.buyer_id then 'buyer' else 'seller' end,
    'opened_by_me', d.opened_by = auth.uid(),
    'my_role', case when auth.uid() = o.buyer_id then 'buyer' when auth.uid() = st.seller_id then 'seller' else 'admin' end,
    'reason', d.reason,
    'status', d.status,
    'resolution', d.resolution,
    'opened_at', d.opened_at,
    'resolved_at', d.resolved_at,
    'resolved_by_name', nullif(trim(coalesce(a.first_name, '') || ' ' || coalesce(a.last_name, '')), ''),
    'quote', (select jsonb_build_object('version', q.version_no, 'price', q.offered_price, 'ready_by', q.estimated_completion_date)
                from public.quote q where q.quote_id = o.quote_id),
    'payments', coalesce((select jsonb_agg(jsonb_build_object(
                   'reference', p.reference_number, 'amount', p.amount_paid, 'status', p.status,
                   'proof_path', p.proof_image_path, 'verified_at', p.verified_at) order by p.verified_at nulls last)
                 from public.payment p where p.order_id = o.order_id), '[]'::jsonb),
    'evidence', coalesce((select jsonb_agg(jsonb_build_object(
                   'evidence_id', e.evidence_id, 'path', e.file_path, 'description', e.description, 'uploaded_at', e.uploaded_at,
                   'by_role', case when e.uploaded_by = o.buyer_id then 'buyer' else 'seller' end,
                   'by_me', e.uploaded_by = auth.uid()) order by e.uploaded_at)
                 from public.dispute_evidence e where e.dispute_id = d.dispute_id), '[]'::jsonb))
  from public.dispute d
  join public.orders o on o.order_id = d.order_id
  join public.store st on st.store_id = o.store_id
  join public.users bu on bu.user_id = o.buyer_id
  left join public.admin a on a.admin_id = d.resolved_by
  where d.dispute_id = p_dispute_id;
$$;

-- Evidence paths must sit in the caller's own folder for this order.
create or replace function public._check_evidence_paths(p_order_id uuid, p_paths text[])
returns void language plpgsql stable set search_path = ''
as $$
declare v_path text;
begin
  if coalesce(array_length(p_paths, 1), 0) > 5 then
    raise exception 'Add at most 5 photos at a time.' using errcode = 'P0001';
  end if;
  foreach v_path in array coalesce(p_paths, '{}') loop
    if coalesce(v_path, '') not like auth.uid()::text || '/' || p_order_id::text || '/dispute_%' then
      raise exception 'A photo did not upload. Try again.' using errcode = 'P0001';
    end if;
  end loop;
end;
$$;

-- ---------------------------------------------------------------------------
-- 1. Buyer or seller
-- ---------------------------------------------------------------------------
create or replace function public.open_dispute(p_order_id uuid, p_reason text, p_evidence_paths text[] default '{}', p_note text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_o record;
  v_reason text := trim(coalesce(p_reason, ''));
  v_id uuid;
begin
  select o.order_id, o.buyer_id, o.status, st.seller_id into v_o
    from public.orders o join public.store st on st.store_id = o.store_id
   where o.order_id = p_order_id;
  if not found or v_uid is null or (v_uid <> v_o.buyer_id and v_uid <> v_o.seller_id) then
    raise exception 'Order not found.' using errcode = 'P0001';
  end if;
  if v_o.status = 'pending' and not exists (select 1 from public.payment p where p.order_id = p_order_id) then
    raise exception 'Nothing has been paid yet. Cancel the order instead.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.dispute d where d.order_id = p_order_id and d.status in ('open', 'under_review')) then
    raise exception 'This order already has an open report. Add your photos to it instead.' using errcode = 'P0001';
  end if;
  if length(v_reason) < 15 then
    raise exception 'Describe the problem in at least 15 characters.' using errcode = 'P0001';
  end if;
  perform public._check_evidence_paths(p_order_id, p_evidence_paths);

  insert into public.dispute (order_id, opened_by, reason) values (p_order_id, v_uid, left(v_reason, 1000))
  returning dispute_id into v_id;
  insert into public.dispute_evidence (dispute_id, uploaded_by, file_path, description)
  select v_id, v_uid, unnest(p_evidence_paths), nullif(trim(coalesce(p_note, '')), '');
  return public._dispute_json(v_id);
end;
$$;

create or replace function public.add_dispute_evidence(p_dispute_id uuid, p_paths text[], p_note text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_d record;
begin
  select d.dispute_id, d.order_id, d.status, o.buyer_id, st.seller_id into v_d
    from public.dispute d join public.orders o on o.order_id = d.order_id join public.store st on st.store_id = o.store_id
   where d.dispute_id = p_dispute_id;
  if not found or v_uid is null or (v_uid <> v_d.buyer_id and v_uid <> v_d.seller_id) then
    raise exception 'Report not found.' using errcode = 'P0001';
  end if;
  if v_d.status not in ('open', 'under_review') then
    raise exception 'This report is already closed.' using errcode = 'P0001';
  end if;
  if coalesce(array_length(p_paths, 1), 0) = 0 then raise exception 'Add at least one photo.' using errcode = 'P0001'; end if;
  if (select count(*) from public.dispute_evidence e where e.dispute_id = p_dispute_id and e.uploaded_by = v_uid) + array_length(p_paths, 1) > 10 then
    raise exception 'You can add up to 10 photos to a report.' using errcode = 'P0001';
  end if;
  perform public._check_evidence_paths(v_d.order_id, p_paths);
  insert into public.dispute_evidence (dispute_id, uploaded_by, file_path, description)
  select p_dispute_id, v_uid, unnest(p_paths), nullif(trim(coalesce(p_note, '')), '');
  return public._dispute_json(p_dispute_id);
end;
$$;

-- The latest report on an order (null when there is none).
create or replace function public.order_dispute(p_order_id uuid)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare v_id uuid;
begin
  if not public.can_see_order(p_order_id) then raise exception 'Order not found.' using errcode = 'P0001'; end if;
  select d.dispute_id into v_id from public.dispute d where d.order_id = p_order_id order by d.opened_at desc limit 1;
  return case when v_id is null then null else public._dispute_json(v_id) end;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Admin
-- ---------------------------------------------------------------------------
create or replace function public.dispute_queue(p_active boolean default true)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Only CraftHive admins can review disputes.' using errcode = 'P0001'; end if;
  return coalesce((
    select jsonb_agg(public._dispute_json(d.dispute_id) order by
             case when p_active then extract(epoch from d.opened_at) else -extract(epoch from coalesce(d.resolved_at, d.opened_at)) end)
    from (select x.dispute_id, x.opened_at, x.resolved_at from public.dispute x
           where (x.status in ('open', 'under_review')) = p_active
           order by coalesce(x.resolved_at, x.opened_at) desc limit 200) d), '[]'::jsonb);
end;
$$;

create or replace function public.update_dispute(p_dispute_id uuid, p_status text, p_resolution text default null)
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_admin uuid;
  v_d record;
  v_text text := nullif(trim(coalesce(p_resolution, '')), '');
begin
  select a.admin_id into v_admin from public.admin a where a.auth_uid = auth.uid();
  if v_admin is null then raise exception 'Only CraftHive admins can review disputes.' using errcode = 'P0001'; end if;
  select d.dispute_id, d.status into v_d from public.dispute d where d.dispute_id = p_dispute_id for update;
  if not found then raise exception 'Report not found.' using errcode = 'P0001'; end if;
  if v_d.status in ('resolved', 'closed') then
    raise exception 'This report was already decided. Refresh the list.' using errcode = 'P0001';
  end if;

  if p_status = 'under_review' then
    if v_d.status <> 'open' then raise exception 'This report is already being reviewed.' using errcode = 'P0001'; end if;
    update public.dispute set status = 'under_review', resolved_by = v_admin where dispute_id = p_dispute_id;
  elsif p_status in ('resolved', 'closed') then
    if v_text is null or length(v_text) < 10 then
      raise exception 'Write the decision for both sides (at least 10 characters).' using errcode = 'P0001';
    end if;
    update public.dispute
       set status = p_status, resolution = left(v_text, 1000), resolved_by = v_admin, resolved_at = now()
     where dispute_id = p_dispute_id;
  else
    raise exception 'Unknown status.' using errcode = 'P0001';
  end if;
  return public._dispute_json(p_dispute_id);
end;
$$;

revoke execute on function public._dispute_json(uuid), public._check_evidence_paths(uuid, text[]) from public, anon, authenticated;
revoke execute on function public.open_dispute(uuid, text, text[], text), public.add_dispute_evidence(uuid, text[], text),
  public.order_dispute(uuid), public.dispute_queue(boolean), public.update_dispute(uuid, text, text) from public, anon;
grant execute on function public.open_dispute(uuid, text, text[], text), public.add_dispute_evidence(uuid, text[], text),
  public.order_dispute(uuid), public.dispute_queue(boolean), public.update_dispute(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. Notifications: new report (→ the other side), under review, decision (→ both)
-- ---------------------------------------------------------------------------
drop trigger if exists dispute_firebase on public.dispute;
create trigger dispute_firebase
  after insert or update of status on public.dispute
  for each row execute function public.send_db_event();
