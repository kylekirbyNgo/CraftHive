-- =============================================================================
-- CraftHive – 14: Reports (Milestone II, "Information Needs")
-- Run after 01–13. Safe to run more than once.
--
--   1 Store Directory          report_store_directory()                         admins
--   2 Product Listing          report_product_listing(store, category)          admins, store owner
--   3 Search and Browse        built in the app from the catalog + store_trust_scores()
--   4 Custom Request and Quote report_custom_requests(store, from, to)          admins, store owner
--   5 Order and Payment        report_orders(store, from, to)                   admins, store owner
--   6 Seller Reliability       report_seller_reliability(store, from, to)       admins, store owner
--   7 Marketplace Activity     report_marketplace_activity(from, to)            admins
--
-- Each function returns JSON rows; header fields appear once, with repeating
-- lines (quote versions, order items, payments) nested under them.
--
-- Seller trust score (0–100), used by reports 3, 6 and 7:
--   30% on-time completion + 25% average rating + 20% completed vs cancelled
--   + 15% orders without disputes + 10% Verified Maker.
--   A part with no data yet counts as 0.7, so new stores start in the middle.
-- =============================================================================

-- Admins see every store; a seller sees only their own.
create or replace function public._report_access(p_store_id uuid)
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if public.is_admin() then return; end if;
  if p_store_id is null or not public.owns_store(p_store_id) then
    raise exception 'Only CraftHive admins and the store owner can see this report.' using errcode = 'P0001';
  end if;
end;
$$;

create or replace function public._admin_only()
returns void language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'Only CraftHive admins can see this report.' using errcode = 'P0001'; end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- Seller reliability per store for a period (report 6, and the trust score)
-- ---------------------------------------------------------------------------
create or replace function public._seller_reliability(p_from date, p_to date)
returns table (
  store_id uuid, store_name text, seller_username text, verified boolean,
  orders int, completed int, cancelled int, on_time int, on_time_rate numeric,
  requests int, quotes_accepted int, conversion_rate numeric,
  avg_rating numeric, reviews int, disputes int, trust_score int)
language sql stable security definer set search_path = ''
as $$
  with o as (
    select x.store_id, x.order_id, x.status, x.due_date,
           coalesce((select min(h.changed_at) from public.order_status_history h
                      where h.order_id = x.order_id and h.to_status in ('delivered', 'completed')), x.completed_at) as done_at
    from public.orders x
    where x.order_date::date between p_from and p_to
  ),
  base as (
    select st.store_id, st.store_name::text as store_name, u.username::text as seller_username,
           se.verification_status = 'verified' as verified,
           count(o.order_id)::int as orders,
           count(*) filter (where o.status in ('delivered', 'completed'))::int as completed,
           count(*) filter (where o.status = 'cancelled')::int as cancelled,
           count(*) filter (where o.status in ('delivered', 'completed') and o.done_at::date <= o.due_date)::int as on_time,
           (select count(*) from public.custom_request r join public.product p on p.product_id = r.product_id
             where p.store_id = st.store_id and r.created_at::date between p_from and p_to)::int as requests,
           (select count(*) from public.custom_request r join public.product p on p.product_id = r.product_id
             where p.store_id = st.store_id and r.created_at::date between p_from and p_to and r.status = 'accepted')::int as quotes_accepted,
           (select round(avg(rv.rating), 2) from public.review rv join public.orders x on x.order_id = rv.order_id
             where x.store_id = st.store_id and rv.created_at::date between p_from and p_to) as avg_rating,
           (select count(*) from public.review rv join public.orders x on x.order_id = rv.order_id
             where x.store_id = st.store_id and rv.created_at::date between p_from and p_to)::int as reviews,
           (select count(*) from public.dispute d join public.orders x on x.order_id = d.order_id
             where x.store_id = st.store_id and d.opened_at::date between p_from and p_to)::int as disputes
    from public.store st
    join public.seller se on se.user_id = st.seller_id
    join public.users u on u.user_id = st.seller_id
    left join o on o.store_id = st.store_id
    group by st.store_id, st.store_name, u.username, se.verification_status
  )
  select b.store_id, b.store_name, b.seller_username, b.verified, b.orders, b.completed, b.cancelled, b.on_time,
         case when b.completed > 0 then round(b.on_time::numeric / b.completed, 4) end,
         b.requests, b.quotes_accepted,
         case when b.requests > 0 then round(b.quotes_accepted::numeric / b.requests, 4) end,
         b.avg_rating, b.reviews, b.disputes,
         round(100 * (
             0.30 * coalesce(case when b.completed > 0 then b.on_time::numeric / b.completed end, 0.7)
           + 0.25 * coalesce(b.avg_rating / 5, 0.7)
           + 0.20 * coalesce(case when b.completed + b.cancelled > 0 then b.completed::numeric / (b.completed + b.cancelled) end, 0.7)
           + 0.15 * case when b.orders > 0 then 1 - least(1, b.disputes::numeric / b.orders) else 1 end
           + 0.10 * case when b.verified then 1 else 0 end))::int
  from base b;
$$;

-- Trust score per store over the last 180 days (Search and Browse report).
create or replace function public.store_trust_scores()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_object_agg(r.store_id::text, r.trust_score), '{}'::jsonb)
  from public._seller_reliability(current_date - 180, current_date) r;
$$;

-- ---------------------------------------------------------------------------
-- 1. Store Directory
-- ---------------------------------------------------------------------------
create or replace function public.report_store_directory()
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public._admin_only();
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'store_name', st.store_name,
      'seller_username', u.username,
      'store_description', st.store_description,
      'address', st.address || ', ' || st.city || ' ' || st.postal_code,
      'category_count', (select count(distinct p.category_id) from public.product p
                          where p.store_id = st.store_id and not p.is_draft and not p.is_archived),
      'active_listings', (select count(*) from public.product p where p.store_id = st.store_id and not p.is_draft and not p.is_archived),
      'avg_rating', (select round(avg(rv.rating), 2) from public.review rv join public.orders o on o.order_id = rv.order_id where o.store_id = st.store_id),
      'items_sold', coalesce((select sum(oi.quantity) from public.order_item oi join public.orders o on o.order_id = oi.order_id
                               where o.store_id = st.store_id and o.status in ('delivered', 'completed')), 0),
      'verified_status', se.verification_status,
      'archived', st.is_archived)
      order by st.is_archived, st.store_name)
    from public.store st
    join public.seller se on se.user_id = st.seller_id
    join public.users u on u.user_id = st.seller_id), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Product Listing (by store and/or category)
-- ---------------------------------------------------------------------------
create or replace function public.report_product_listing(p_store_id uuid default null, p_category_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public._report_access(p_store_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'product_title', p.title,
      'category_name', c.category_name,
      'store_name', st.store_name,
      'price', p.price,
      'stock_quantity', p.stock_quantity,
      'has_custom_option', p.has_custom_option,
      'created_at', p.created_at,
      'images', (select count(*) from public.product_image i where i.product_id = p.product_id),
      -- Reviews can only be written for completed orders (02), so these are fulfilled-order reviews.
      'reviews', (select count(*) from public.review rv where rv.product_id = p.product_id),
      'avg_rating', (select round(avg(rv.rating), 2) from public.review rv where rv.product_id = p.product_id),
      'status', case when p.is_archived then 'archived' when p.is_draft then 'draft' else 'active' end)
      order by st.store_name, p.created_at desc)
    from public.product p
    join public.category c on c.category_id = p.category_id
    join public.store st on st.store_id = p.store_id
    where (p_store_id is null or p.store_id = p_store_id)
      and (p_category_id is null or p.category_id = p_category_id)), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 4. Custom Request and Quote (request once, quote versions in order)
-- ---------------------------------------------------------------------------
create or replace function public.report_custom_requests(p_store_id uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public._report_access(p_store_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'request_number', r.request_number,
      'buyer_username', bu.username,
      'seller_username', su.username,
      'store_name', st.store_name,
      'product_title', p.title,
      'quantity', r.quantity,
      'budget', r.budget,
      'needed_by', r.needed_by_date,
      'reference_photos', (select count(*) from public.custom_request_image i where i.request_id = r.request_id),
      'status', r.status,
      'created_at', r.created_at,
      'quotes', coalesce((select jsonb_agg(jsonb_build_object(
                   'version', q.version_no, 'price', q.offered_price, 'completion', q.estimated_completion_date,
                   'status', q.status, 'created_at', q.created_at) order by q.version_no)
                 from public.quote q where q.request_id = r.request_id), '[]'::jsonb))
      order by r.created_at desc)
    from public.custom_request r
    join public.product p on p.product_id = r.product_id
    join public.store st on st.store_id = p.store_id
    join public.users bu on bu.user_id = r.buyer_id
    join public.users su on su.user_id = st.seller_id
    where (p_store_id is null or p.store_id = p_store_id)
      and (p_from is null or r.created_at::date >= p_from)
      and (p_to is null or r.created_at::date <= p_to)), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Order and Payment (order once, item lines and payments under it)
-- ---------------------------------------------------------------------------
create or replace function public.report_orders(p_store_id uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
begin
  perform public._report_access(p_store_id);
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'order_number', o.order_number,
      'customer_name', bu.full_name,
      'customer_username', bu.username,
      'store_name', st.store_name,
      'order_date', o.order_date,
      'total', o.total_amount,
      'status', o.status,
      'items', coalesce((select jsonb_agg(jsonb_build_object('title', p.title, 'quantity', oi.quantity, 'unit_price', oi.price_at_purchase))
                           from public.order_item oi join public.product p on p.product_id = oi.product_id
                          where oi.order_id = o.order_id), '[]'::jsonb),
      'payments', coalesce((select jsonb_agg(jsonb_build_object('reference', pm.reference_number, 'amount', pm.amount_paid,
                              'status', pm.status, 'verified_at', pm.verified_at) order by pm.verified_at nulls last)
                             from public.payment pm where pm.order_id = o.order_id), '[]'::jsonb),
      'total_paid', coalesce((select sum(pm.amount_paid) from public.payment pm where pm.order_id = o.order_id and pm.status = 'verified'), 0))
      order by o.order_date desc)
    from public.orders o
    join public.store st on st.store_id = o.store_id
    join public.users bu on bu.user_id = o.buyer_id
    where (p_store_id is null or o.store_id = p_store_id)
      and (p_from is null or o.order_date::date >= p_from)
      and (p_to is null or o.order_date::date <= p_to)), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Seller Reliability
-- ---------------------------------------------------------------------------
create or replace function public.report_seller_reliability(p_store_id uuid default null, p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_from date := coalesce(p_from, current_date - 90);
  v_to date := coalesce(p_to, current_date);
begin
  perform public._report_access(p_store_id);
  return coalesce((
    select jsonb_agg(to_jsonb(r) || jsonb_build_object('from', v_from, 'to', v_to) order by r.trust_score desc, r.store_name)
    from public._seller_reliability(v_from, v_to) r
    where p_store_id is null or r.store_id = p_store_id), '[]'::jsonb);
end;
$$;

-- ---------------------------------------------------------------------------
-- 7. Marketplace Activity (per category)
-- ---------------------------------------------------------------------------
create or replace function public.report_marketplace_activity(p_from date default null, p_to date default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_from date := coalesce(p_from, current_date - 90);
  v_to date := coalesce(p_to, current_date);
begin
  perform public._admin_only();
  return coalesce((
    with trust as (select * from public._seller_reliability(v_from, v_to)),
    sales as (
      select p.category_id, o.order_id, o.status, oi.quantity * oi.price_at_purchase as value
      from public.orders o
      join public.order_item oi on oi.order_id = o.order_id
      join public.product p on p.product_id = oi.product_id
      where o.order_date::date between v_from and v_to)
    select jsonb_agg(jsonb_build_object(
      'category_name', c.category_name,
      'from', v_from,
      'to', v_to,
      'listings', (select count(*) from public.product p where p.category_id = c.category_id and not p.is_draft and not p.is_archived
                    and p.created_at::date <= v_to),
      'orders', (select count(distinct s.order_id) from sales s where s.category_id = c.category_id),
      'custom_requests', (select count(*) from public.custom_request r join public.product p on p.product_id = r.product_id
                           where p.category_id = c.category_id and r.created_at::date between v_from and v_to),
      'total_order_value', coalesce((select sum(s.value) from sales s where s.category_id = c.category_id and s.status <> 'cancelled'), 0),
      'verified_sellers', (select count(distinct p.store_id) from public.product p join public.store st on st.store_id = p.store_id
                            join public.seller se on se.user_id = st.seller_id
                            where p.category_id = c.category_id and not p.is_archived and se.verification_status = 'verified'),
      'avg_trust_score', (select round(avg(t.trust_score), 1) from trust t
                           where t.store_id in (select p.store_id from public.product p where p.category_id = c.category_id and not p.is_archived)))
      order by c.category_name)
    from public.category c), '[]'::jsonb);
end;
$$;

revoke execute on function public._report_access(uuid), public._admin_only(), public._seller_reliability(date, date) from public, anon, authenticated;
revoke execute on function public.store_trust_scores(), public.report_store_directory(), public.report_product_listing(uuid, uuid),
  public.report_custom_requests(uuid, date, date), public.report_orders(uuid, date, date),
  public.report_seller_reliability(uuid, date, date), public.report_marketplace_activity(date, date) from public, anon;
grant execute on function public.store_trust_scores(), public.report_store_directory(), public.report_product_listing(uuid, uuid),
  public.report_custom_requests(uuid, date, date), public.report_orders(uuid, date, date),
  public.report_seller_reliability(uuid, date, date), public.report_marketplace_activity(date, date) to authenticated;
