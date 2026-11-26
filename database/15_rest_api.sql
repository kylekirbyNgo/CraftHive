-- =============================================================================
-- CraftHive – 15: REST API support (ITCC 14 API Design Document, sections 3.2–3.4)
-- Run after 01–14, in Supabase → SQL Editor. Safe to run more than once.
--
-- 1. Each error in the order, payment, custom-request and quote functions gets its
--    own SQLSTATE instead of the shared P0001. PostgREST turns SQLSTATE 'PTxyz'
--    into HTTP status xyz, so the errors now arrive as:
--        PT401  not logged in
--        PT403  signed in but not allowed (e.g. a buyer checking a payment)
--        PT404  the order, request or quote does not exist or is not yours
--        PT409  clashes with existing data (reused reference number, quote no longer open)
--        PT422  breaks a rule (quantity 1–99, out of stock, fully booked week)
--    The messages and the logic are unchanged; only "errcode" differs.
--    The api Edge Function and the updated app read these codes; see API_GUIDE.md
--    for the order to deploy in.
-- 2. save_listing(): saves a listing, its photo list and its custom options in ONE
--    transaction, for POST /products and PUT /products/{productId}.
-- 3. Review policies so buyers can edit and delete their own reviews
--    (PATCH and DELETE /reviews/{reviewId}).
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. Functions from 04_orders_and_custom_orders.sql with specific error codes
-- -----------------------------------------------------------------------------

create or replace function public.place_order(p_product_id uuid, p_quantity int)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p record;
  v_order_id uuid;
  v_number text;
  v_reserve boolean;
begin
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'PT401'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 99 then
    raise exception 'Choose a quantity from 1 to 99.' using errcode = 'PT422';
  end if;

  select p.product_id, p.store_id, p.price, p.stock_quantity, p.lead_time_days, p.is_draft, p.is_archived, s.seller_id
    into v_p
    from public.product p join public.store s on s.store_id = p.store_id
   where p.product_id = p_product_id
     for update of p;
  if not found or v_p.is_draft or v_p.is_archived then
    raise exception 'This item is no longer available.' using errcode = 'PT422';
  end if;
  if v_p.seller_id = v_uid then raise exception 'You cannot buy your own item.' using errcode = 'PT422'; end if;

  v_reserve := v_p.stock_quantity > 0;
  if v_reserve and v_p.stock_quantity < p_quantity then
    raise exception 'Only % left in stock. Lower the quantity and try again.', v_p.stock_quantity using errcode = 'PT422';
  end if;
  if v_reserve then
    update public.product set stock_quantity = stock_quantity - p_quantity where product_id = p_product_id;
  end if;

  insert into public.buyer (user_id) values (v_uid) on conflict do nothing;
  insert into public.orders (buyer_id, store_id, total_amount, status, due_date, reservation_expires_at)
  values (v_uid, v_p.store_id, v_p.price * p_quantity, 'pending',
          current_date + v_p.lead_time_days,
          case when v_reserve then now() + interval '24 hours' end)
  returning order_id, order_number into v_order_id, v_number;

  insert into public.order_item (order_id, product_id, quantity, price_at_purchase)
  values (v_order_id, p_product_id, p_quantity, v_p.price);

  perform public._note_latest_history(v_order_id,
    case when v_reserve then 'Order placed. Your items are reserved for 24 hours while you pay.'
         else 'Order placed. This item is made to order.' end);
  return v_number;
end;
$$;

create or replace function public.submit_payment(p_order_id uuid, p_reference text, p_proof_path text, p_proof_hash text, p_amount numeric)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_o record;
  v_ref text := regexp_replace(coalesce(p_reference, ''), '\s', '', 'g');
begin
  select o.order_id, o.buyer_id, o.status into v_o from public.orders o where o.order_id = p_order_id for update;
  if not found or v_o.buyer_id is distinct from v_uid then
    raise exception 'Order not found.' using errcode = 'PT404';
  end if;
  if v_o.status <> 'pending' then raise exception 'This order is no longer waiting for payment.' using errcode = 'PT409'; end if;
  if v_ref !~ '^[A-Za-z0-9-]{6,50}$' then
    raise exception 'Enter the reference number from your receipt (6 to 50 letters or digits).' using errcode = 'PT422';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Enter the amount you paid.' using errcode = 'PT422'; end if;
  if exists (select 1 from public.payment p where p.order_id = p_order_id and p.status in ('submitted', 'verified')) then
    raise exception 'You already sent a payment proof for this order.' using errcode = 'PT409';
  end if;
  if exists (select 1 from public.payment p where p.reference_number = v_ref) then
    raise exception 'This reference number was already used for another payment.' using errcode = 'PT409';
  end if;
  if exists (select 1 from public.payment p where p.proof_image_hash = p_proof_hash) then
    raise exception 'This receipt screenshot was already uploaded before. Upload the receipt for this payment.' using errcode = 'PT409';
  end if;

  insert into public.payment (order_id, reference_number, proof_image_path, proof_image_hash, amount_paid)
  values (p_order_id, v_ref, p_proof_path, p_proof_hash, p_amount);
  perform public._log_order_note(p_order_id, 'Payment proof uploaded (reference ' || v_ref || '). Waiting for the seller to check it.');
end;
$$;

create or replace function public.review_payment(p_order_id uuid, p_accept boolean, p_reason text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_pay record;
begin
  if not public.can_see_order(p_order_id) or not exists (
       select 1 from public.orders o where o.order_id = p_order_id and public.owns_store(o.store_id)) then
    raise exception 'Only the seller can check this payment.' using errcode = 'PT403';
  end if;
  select p.payment_id into v_pay from public.payment p
   where p.order_id = p_order_id and p.status = 'submitted' for update;
  if not found then raise exception 'There is no payment proof to check.' using errcode = 'PT409'; end if;

  if p_accept then
    update public.payment set status = 'verified', verified_at = now() where payment_id = v_pay.payment_id;
    update public.orders set status = 'confirmed', reservation_expires_at = null where order_id = p_order_id;
    perform public._note_latest_history(p_order_id, 'Payment confirmed by the seller.');
  else
    if coalesce(trim(p_reason), '') = '' then raise exception 'Tell the buyer why the payment was rejected.' using errcode = 'PT422'; end if;
    update public.payment set status = 'rejected' where payment_id = v_pay.payment_id;
    -- Give the buyer another day to send a correct proof.
    update public.orders set reservation_expires_at = now() + interval '24 hours'
     where order_id = p_order_id and reservation_expires_at is not null;
    perform public._log_order_note(p_order_id, 'Payment proof rejected: ' || trim(p_reason));
  end if;
end;
$$;

create or replace function public.set_order_status(p_order_id uuid, p_status text, p_note text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_o record;
  v_is_seller boolean;
  v_is_buyer boolean;
begin
  select o.order_id, o.buyer_id, o.store_id, o.status, o.reservation_expires_at, o.quote_id
    into v_o from public.orders o where o.order_id = p_order_id for update;
  if not found then raise exception 'Order not found.' using errcode = 'PT404'; end if;
  v_is_buyer := v_o.buyer_id = v_uid;
  v_is_seller := public.owns_store(v_o.store_id);
  if not (v_is_buyer or v_is_seller) then raise exception 'Order not found.' using errcode = 'PT404'; end if;

  if not (
       (v_is_seller and p_status in ('in_production', 'shipped', 'delivered'))
    or (v_is_buyer and p_status = 'completed')
    or (p_status = 'cancelled' and v_o.status = 'pending')
  ) then
    raise exception 'You cannot change this order to %.', p_status using errcode = 'PT422';
  end if;
  if p_status = 'cancelled' and exists (select 1 from public.payment p where p.order_id = p_order_id and p.status = 'verified') then
    raise exception 'The payment was already confirmed. Open a dispute instead.' using errcode = 'PT409';
  end if;

  if p_status = 'cancelled' then
    -- Give back reserved stock and the custom-order capacity slot.
    if v_o.reservation_expires_at is not null then
      update public.product p set stock_quantity = p.stock_quantity + oi.quantity
        from public.order_item oi where oi.order_id = p_order_id and oi.product_id = p.product_id;
    end if;
    delete from public.capacity_booking where order_id = p_order_id;
  end if;

  update public.orders set
    status = p_status,
    completed_at = case when p_status in ('delivered', 'completed') then now() else completed_at end
  where order_id = p_order_id;

  perform public._note_latest_history(p_order_id, coalesce(nullif(trim(p_note), ''),
    case p_status
      when 'in_production' then 'The seller started making your order.'
      when 'shipped' then 'The seller sent your order.'
      when 'delivered' then 'The seller marked the order as delivered.'
      when 'completed' then 'The buyer confirmed receipt.'
      when 'cancelled' then case when v_is_buyer then 'Cancelled by the buyer.' else 'Cancelled by the seller.' end
    end));
end;
$$;

create or replace function public.submit_custom_request(
  p_product_id uuid, p_description text, p_quantity int, p_budget numeric, p_needed_by date, p_options text[])
returns jsonb language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_p record;
  v_id uuid;
  v_number text;
begin
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'PT401'; end if;
  select p.product_id, p.has_custom_option, p.is_draft, p.is_archived, s.seller_id
    into v_p from public.product p join public.store s on s.store_id = p.store_id
   where p.product_id = p_product_id;
  if not found or v_p.is_draft or v_p.is_archived then raise exception 'This item is no longer available.' using errcode = 'PT422'; end if;
  if not v_p.has_custom_option then raise exception 'This maker does not take custom orders for this item.' using errcode = 'PT422'; end if;
  if v_p.seller_id = v_uid then raise exception 'You cannot request a custom order from your own store.' using errcode = 'PT422'; end if;
  if length(trim(coalesce(p_description, ''))) < 10 then raise exception 'Describe your request in at least 10 characters.' using errcode = 'PT422'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Choose a quantity of at least 1.' using errcode = 'PT422'; end if;
  if p_budget is not null and p_budget <= 0 then raise exception 'Enter a budget above zero, or leave it empty.' using errcode = 'PT422'; end if;
  if p_needed_by is null or p_needed_by <= current_date then raise exception 'Choose a date after today.' using errcode = 'PT422'; end if;

  insert into public.buyer (user_id) values (v_uid) on conflict do nothing;
  insert into public.custom_request (buyer_id, product_id, description, quantity, budget, needed_by_date)
  values (v_uid, p_product_id, left(trim(p_description), 500), p_quantity, p_budget, p_needed_by)
  returning request_id, request_number into v_id, v_number;

  insert into public.custom_request_option (request_id, option_id)
  select v_id, o.option_id from public.product_custom_option o
   where o.product_id = p_product_id and o.label = any (coalesce(p_options, '{}'));

  return jsonb_build_object('request_id', v_id, 'request_number', v_number);
end;
$$;

create or replace function public.cancel_custom_request(p_request_id uuid)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r record;
begin
  select r.request_id, r.buyer_id, r.status into v_r from public.custom_request r where r.request_id = p_request_id for update;
  if not found or v_r.buyer_id is distinct from auth.uid() then raise exception 'Request not found.' using errcode = 'PT404'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request can no longer be cancelled.' using errcode = 'PT409'; end if;
  update public.quote set status = 'declined', decline_reason = 'The buyer cancelled the request.'
   where request_id = p_request_id and status = 'sent';
  update public.custom_request set status = 'cancelled' where request_id = p_request_id;
end;
$$;

create or replace function public.decline_custom_request(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r record;
begin
  select r.request_id, r.status, r.quantity, r.needed_by_date, p.price, p.product_id
    into v_r from public.custom_request r join public.product p on p.product_id = r.product_id
   where r.request_id = p_request_id for update of r;
  if not found or not public.owns_product(v_r.product_id) then raise exception 'Request not found.' using errcode = 'PT404'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request is already %.', v_r.status using errcode = 'PT409'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Tell the buyer why you are declining.' using errcode = 'PT422'; end if;

  update public.quote set status = 'superseded' where request_id = p_request_id and status = 'sent';
  insert into public.quote (request_id, version_no, offered_price, estimated_completion_date, decline_reason, status)
  values (p_request_id,
          coalesce((select max(q.version_no) from public.quote q where q.request_id = p_request_id), 0) + 1,
          v_r.price * v_r.quantity, v_r.needed_by_date, trim(p_reason), 'declined');
  update public.custom_request set status = 'declined' where request_id = p_request_id;
end;
$$;

create or replace function public.send_quote(p_request_id uuid, p_price numeric, p_ready_by date, p_message text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r record;
begin
  select r.request_id, r.status, r.quantity, r.needed_by_date, p.price, p.product_id
    into v_r from public.custom_request r join public.product p on p.product_id = r.product_id
   where r.request_id = p_request_id for update of r;
  if not found or not public.owns_product(v_r.product_id) then raise exception 'Request not found.' using errcode = 'PT404'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request is already %.', v_r.status using errcode = 'PT409'; end if;
  if p_price is null or p_price <= 0 then raise exception 'Enter a price above zero.' using errcode = 'PT422'; end if;
  if p_ready_by is null or p_ready_by < current_date then raise exception 'Choose a ready date from today onwards.' using errcode = 'PT422'; end if;

  update public.quote set status = 'superseded' where request_id = p_request_id and status = 'sent';
  insert into public.quote (request_id, version_no, offered_price, estimated_completion_date, message)
  values (p_request_id,
          coalesce((select max(q.version_no) from public.quote q where q.request_id = p_request_id), 0) + 1,
          round(p_price, 2), p_ready_by, nullif(trim(p_message), ''));
  update public.custom_request set status = 'quoted' where request_id = p_request_id;
end;
$$;

create or replace function public.respond_to_quote(p_quote_id uuid, p_accept boolean, p_note text default null)
returns text language plpgsql security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_q record;
  v_week date;
  v_used int;
  v_order_id uuid;
  v_number text;
begin
  select q.quote_id, q.request_id, q.version_no, q.offered_price, q.estimated_completion_date, q.status,
         r.buyer_id, r.product_id, r.quantity, r.status as request_status, p.store_id, s.weekly_capacity
    into v_q
    from public.quote q
    join public.custom_request r on r.request_id = q.request_id
    join public.product p on p.product_id = r.product_id
    join public.store s on s.store_id = p.store_id
   where q.quote_id = p_quote_id
     for update of q, r, s;
  if not found or v_q.buyer_id is distinct from v_uid then raise exception 'Quote not found.' using errcode = 'PT404'; end if;
  if v_q.status <> 'sent' or v_q.request_status <> 'quoted' then
    raise exception 'This quote is no longer open. Refresh to see the latest one.' using errcode = 'PT409';
  end if;

  if not p_accept then
    update public.quote set status = 'changes_requested', decline_reason = nullif(trim(p_note), '') where quote_id = p_quote_id;
    update public.custom_request set status = 'pending' where request_id = v_q.request_id;
    return null;
  end if;

  v_week := v_q.estimated_completion_date - (extract(isodow from v_q.estimated_completion_date)::int - 1);
  select count(*) into v_used from public.capacity_booking b
    join public.orders o on o.order_id = b.order_id
   where b.store_id = v_q.store_id and b.week_start = v_week and o.status <> 'cancelled';
  if v_used >= v_q.weekly_capacity then
    raise exception 'This maker is fully booked for the week of %. Ask for changes to get a different ready date.',
      to_char(v_week, 'Mon DD') using errcode = 'PT422';
  end if;

  insert into public.orders (buyer_id, store_id, quote_id, total_amount, status, due_date)
  values (v_uid, v_q.store_id, p_quote_id, v_q.offered_price, 'pending', v_q.estimated_completion_date)
  returning order_id, order_number into v_order_id, v_number;
  insert into public.order_item (order_id, product_id, quantity, price_at_purchase)
  values (v_order_id, v_q.product_id, v_q.quantity, round(v_q.offered_price / v_q.quantity, 2));
  insert into public.capacity_booking (store_id, order_id, week_start) values (v_q.store_id, v_order_id, v_week);

  update public.quote set status = 'accepted' where quote_id = p_quote_id;
  update public.custom_request set status = 'accepted' where request_id = v_q.request_id;
  perform public._note_latest_history(v_order_id, 'Quote v' || v_q.version_no || ' accepted. Waiting for your payment.');
  return v_number;
end;
$$;

create or replace function public.check_order_transition()
returns trigger language plpgsql set search_path = ''
as $$
begin
  if new.status is distinct from old.status and not (
       (old.status = 'pending'       and new.status in ('confirmed', 'cancelled'))
    or (old.status = 'confirmed'     and new.status in ('in_production', 'shipped'))
    or (old.status = 'in_production' and new.status = 'shipped')
    or (old.status = 'shipped'       and new.status in ('delivered', 'completed'))
    or (old.status = 'delivered'     and new.status = 'completed')
  ) then
    raise exception 'An order cannot go from % to %.', old.status, new.status using errcode = 'PT422';
  end if;
  return new;
end;
$$;

-- -----------------------------------------------------------------------------
-- 2. save_listing(product_id, listing): create (product_id null) or replace a listing
--    listing = { "categoryId", "title", "description", "price", "stockQuantity",
--                "leadTimeDays", "acceptsCustomOrders", "status": draft|active|archived,
--                "imagePaths": [cover first, at most 5], "customOptions": [labels] }
--    Runs with the caller's rights (security invoker), so row-level security still
--    decides what they may change. Everything is saved or nothing is.
-- -----------------------------------------------------------------------------
create or replace function public.save_listing(p_product_id uuid, p_listing jsonb)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_store uuid;
  v_id uuid := p_product_id;
  v_status text := coalesce(p_listing->>'status', 'active');
  v_images text[];
  v_options text[];
begin
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'PT401'; end if;
  select s.store_id into v_store from public.store s where s.seller_id = v_uid;
  if v_store is null then raise exception 'Open your store before posting a listing.' using errcode = 'PT403'; end if;
  if v_status not in ('draft', 'active', 'archived') then
    raise exception 'Status must be draft, active or archived.' using errcode = 'PT422';
  end if;

  v_images := array(select jsonb_array_elements_text(coalesce(p_listing->'imagePaths', '[]'::jsonb)));
  v_options := array(select distinct trim(o) from jsonb_array_elements_text(coalesce(p_listing->'customOptions', '[]'::jsonb)) o
                      where trim(o) <> '');
  if cardinality(v_images) > 5 then raise exception 'A listing can have at most 5 photos.' using errcode = 'PT422'; end if;
  if exists (select 1 from unnest(v_images) p where p not like v_store::text || '/%' and p not like 'http%') then
    raise exception 'Upload the photos to your own store folder first.' using errcode = 'PT422';
  end if;

  if v_id is null then
    insert into public.product (store_id, category_id, title, description, price, stock_quantity,
                                lead_time_days, has_custom_option, is_draft)
    values (v_store, (p_listing->>'categoryId')::uuid, trim(p_listing->>'title'), nullif(trim(p_listing->>'description'), ''),
            (p_listing->>'price')::numeric, (p_listing->>'stockQuantity')::int, (p_listing->>'leadTimeDays')::int,
            coalesce((p_listing->>'acceptsCustomOrders')::boolean, false), v_status = 'draft')
    returning product_id into v_id;
  else
    update public.product set
      category_id       = (p_listing->>'categoryId')::uuid,
      title             = trim(p_listing->>'title'),
      description       = nullif(trim(p_listing->>'description'), ''),
      price             = (p_listing->>'price')::numeric,
      stock_quantity    = (p_listing->>'stockQuantity')::int,
      lead_time_days    = (p_listing->>'leadTimeDays')::int,
      has_custom_option = coalesce((p_listing->>'acceptsCustomOrders')::boolean, false),
      is_draft          = v_status = 'draft',
      is_archived       = v_status = 'archived'
    where product_id = v_id and store_id = v_store;
    if not found then raise exception 'Listing not found.' using errcode = 'PT404'; end if;
  end if;

  -- Photo list in display order (sort_order 1 = cover).
  delete from public.product_image where product_id = v_id;
  insert into public.product_image (product_id, image_path, sort_order)
  select v_id, t.path, t.ord from unnest(v_images) with ordinality as t(path, ord);

  -- Custom options: keep the ones still offered (past requests keep their links), add new ones.
  delete from public.product_custom_option c where c.product_id = v_id and not (c.label = any (v_options));
  insert into public.product_custom_option (product_id, label)
  select v_id, o from unnest(v_options) o
   where not exists (select 1 from public.product_custom_option c where c.product_id = v_id and c.label = o);

  return v_id;
end;
$$;

revoke all on function public.save_listing(uuid, jsonb) from public, anon;
grant execute on function public.save_listing(uuid, jsonb) to authenticated;

-- -----------------------------------------------------------------------------
-- 3. Buyers may edit and delete their own reviews
-- -----------------------------------------------------------------------------
drop policy if exists "review: buyer edits own" on public.review;
create policy "review: buyer edits own" on public.review for update to authenticated
  using (exists (select 1 from public.orders o where o.order_id = review.order_id and o.buyer_id = (select auth.uid())))
  with check (exists (select 1 from public.orders o where o.order_id = review.order_id and o.buyer_id = (select auth.uid())));

drop policy if exists "review: buyer deletes own" on public.review;
create policy "review: buyer deletes own" on public.review for delete to authenticated
  using (exists (select 1 from public.orders o where o.order_id = review.order_id and o.buyer_id = (select auth.uid())));

-- Let the Data API see the new function right away.
notify pgrst, 'reload schema';
