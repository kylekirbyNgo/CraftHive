-- =============================================================================
-- CraftHive – Orders and Custom orders (Milestone 3 features)
-- Run after 02_logic_and_security.sql (03_seed.sql is optional).
--
-- Every change to an order, payment, custom request or quote goes through the
-- functions below. They run as the database owner (security definer) but check
-- auth.uid() first, so a buyer or seller can only do what the paper allows:
--
--   Ready-made order : place_order → submit_payment → review_payment (seller)
--                      → set_order_status (in_production, shipped) → completed
--   Custom order     : submit_custom_request → send_quote / decline_custom_request
--                      → respond_to_quote (accept = binding order, capacity booked)
--
-- Errors meant for the user are raised with SQLSTATE P0001 and a plain message,
-- which the app shows as is.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Orders may only move along these steps (Basic Operations: "the database
-- enforcing authorized state updates"). Applies to every update, even ones
-- made from the dashboard.
-- ---------------------------------------------------------------------------
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
    raise exception 'An order cannot go from % to %.', old.status, new.status using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists orders_check_transition on public.orders;
create trigger orders_check_transition
  before update of status on public.orders
  for each row execute function public.check_order_transition();

-- Orders, payments, quotes and bookings are changed only through the functions
-- below, so nobody can skip a step from the app.
revoke insert, update on public.orders from authenticated;
grant update (is_archived) on public.orders to authenticated;
revoke insert, update on public.order_item from authenticated;
revoke insert, update on public.payment from authenticated;
revoke insert, update on public.quote from authenticated;
revoke insert, update on public.capacity_booking from authenticated;
revoke update on public.custom_request from authenticated;

-- Adds a note (and who wrote it) to the newest history row of an order.
create or replace function public._note_latest_history(p_order_id uuid, p_note text)
returns void language sql security definer set search_path = ''
as $$
  update public.order_status_history h set note = p_note
  where h.history_id = (
    select h2.history_id from public.order_status_history h2
    where h2.order_id = p_order_id order by h2.changed_at desc, h2.history_id desc limit 1);
$$;

-- A history row that records something without a status change (payment proof, rejection).
create or replace function public._log_order_note(p_order_id uuid, p_note text)
returns void language sql security definer set search_path = ''
as $$
  insert into public.order_status_history (order_id, from_status, to_status, changed_by, note)
  select o.order_id, o.status, o.status,
         (select u.user_id from public.users u where u.user_id = (select auth.uid())), p_note
  from public.orders o where o.order_id = p_order_id;
$$;

revoke execute on function public._note_latest_history(uuid, text), public._log_order_note(uuid, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 1. Ready-made order: Buy now
-- Stock is reserved at checkout; an unpaid reservation expires after 24 hours.
-- When the item is out of stock it is made to order (lead_time_days).
-- ---------------------------------------------------------------------------
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
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'P0001'; end if;
  if p_quantity is null or p_quantity < 1 or p_quantity > 99 then
    raise exception 'Choose a quantity from 1 to 99.' using errcode = 'P0001';
  end if;

  select p.product_id, p.store_id, p.price, p.stock_quantity, p.lead_time_days, p.is_draft, p.is_archived, s.seller_id
    into v_p
    from public.product p join public.store s on s.store_id = p.store_id
   where p.product_id = p_product_id
     for update of p;
  if not found or v_p.is_draft or v_p.is_archived then
    raise exception 'This item is no longer available.' using errcode = 'P0001';
  end if;
  if v_p.seller_id = v_uid then raise exception 'You cannot buy your own item.' using errcode = 'P0001'; end if;

  v_reserve := v_p.stock_quantity > 0;
  if v_reserve and v_p.stock_quantity < p_quantity then
    raise exception 'Only % left in stock. Lower the quantity and try again.', v_p.stock_quantity using errcode = 'P0001';
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

-- ---------------------------------------------------------------------------
-- Unpaid reservations are released (Basic Operations: "Unpaid reservations
-- are released by automated background processes upon timeout"). The app calls
-- this before loading orders; it can also be scheduled with pg_cron.
-- ---------------------------------------------------------------------------
create or replace function public.release_expired_reservations()
returns int language plpgsql security definer set search_path = ''
as $$
declare
  v_order record;
  v_count int := 0;
begin
  for v_order in
    select o.order_id from public.orders o
     where o.status = 'pending' and o.quote_id is null
       and o.reservation_expires_at is not null and o.reservation_expires_at < now()
       and not exists (select 1 from public.payment p where p.order_id = o.order_id and p.status in ('submitted', 'verified'))
     for update skip locked
  loop
    update public.product p set stock_quantity = p.stock_quantity + oi.quantity
      from public.order_item oi where oi.order_id = v_order.order_id and oi.product_id = p.product_id;
    update public.orders set status = 'cancelled' where order_id = v_order.order_id;
    perform public._note_latest_history(v_order.order_id, 'Cancelled automatically: no payment within 24 hours. The stock was released.');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;

-- ---------------------------------------------------------------------------
-- 2. Payment proof (buyer) and payment check (seller)
-- Reference numbers and receipt image hashes are unique system-wide.
-- ---------------------------------------------------------------------------
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
    raise exception 'Order not found.' using errcode = 'P0001';
  end if;
  if v_o.status <> 'pending' then raise exception 'This order is no longer waiting for payment.' using errcode = 'P0001'; end if;
  if v_ref !~ '^[A-Za-z0-9-]{6,50}$' then
    raise exception 'Enter the reference number from your receipt (6 to 50 letters or digits).' using errcode = 'P0001';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Enter the amount you paid.' using errcode = 'P0001'; end if;
  if exists (select 1 from public.payment p where p.order_id = p_order_id and p.status in ('submitted', 'verified')) then
    raise exception 'You already sent a payment proof for this order.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.payment p where p.reference_number = v_ref) then
    raise exception 'This reference number was already used for another payment.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.payment p where p.proof_image_hash = p_proof_hash) then
    raise exception 'This receipt screenshot was already uploaded before. Upload the receipt for this payment.' using errcode = 'P0001';
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
    raise exception 'Only the seller can check this payment.' using errcode = 'P0001';
  end if;
  select p.payment_id into v_pay from public.payment p
   where p.order_id = p_order_id and p.status = 'submitted' for update;
  if not found then raise exception 'There is no payment proof to check.' using errcode = 'P0001'; end if;

  if p_accept then
    update public.payment set status = 'verified', verified_at = now() where payment_id = v_pay.payment_id;
    update public.orders set status = 'confirmed', reservation_expires_at = null where order_id = p_order_id;
    perform public._note_latest_history(p_order_id, 'Payment confirmed by the seller.');
  else
    if coalesce(trim(p_reason), '') = '' then raise exception 'Tell the buyer why the payment was rejected.' using errcode = 'P0001'; end if;
    update public.payment set status = 'rejected' where payment_id = v_pay.payment_id;
    -- Give the buyer another day to send a correct proof.
    update public.orders set reservation_expires_at = now() + interval '24 hours'
     where order_id = p_order_id and reservation_expires_at is not null;
    perform public._log_order_note(p_order_id, 'Payment proof rejected: ' || trim(p_reason));
  end if;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. Order progress
--   seller : confirmed → in_production → shipped; may cancel a pending order
--   buyer  : shipped → completed ("I received my order"); may cancel while pending
-- ---------------------------------------------------------------------------
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
  if not found then raise exception 'Order not found.' using errcode = 'P0001'; end if;
  v_is_buyer := v_o.buyer_id = v_uid;
  v_is_seller := public.owns_store(v_o.store_id);
  if not (v_is_buyer or v_is_seller) then raise exception 'Order not found.' using errcode = 'P0001'; end if;

  if not (
       (v_is_seller and p_status in ('in_production', 'shipped', 'delivered'))
    or (v_is_buyer and p_status = 'completed')
    or (p_status = 'cancelled' and v_o.status = 'pending')
  ) then
    raise exception 'You cannot change this order to %.', p_status using errcode = 'P0001';
  end if;
  if p_status = 'cancelled' and exists (select 1 from public.payment p where p.order_id = p_order_id and p.status = 'verified') then
    raise exception 'The payment was already confirmed. Open a dispute instead.' using errcode = 'P0001';
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

-- ---------------------------------------------------------------------------
-- 4. Custom request (buyer)
-- ---------------------------------------------------------------------------
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
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'P0001'; end if;
  select p.product_id, p.has_custom_option, p.is_draft, p.is_archived, s.seller_id
    into v_p from public.product p join public.store s on s.store_id = p.store_id
   where p.product_id = p_product_id;
  if not found or v_p.is_draft or v_p.is_archived then raise exception 'This item is no longer available.' using errcode = 'P0001'; end if;
  if not v_p.has_custom_option then raise exception 'This maker does not take custom orders for this item.' using errcode = 'P0001'; end if;
  if v_p.seller_id = v_uid then raise exception 'You cannot request a custom order from your own store.' using errcode = 'P0001'; end if;
  if length(trim(coalesce(p_description, ''))) < 10 then raise exception 'Describe your request in at least 10 characters.' using errcode = 'P0001'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Choose a quantity of at least 1.' using errcode = 'P0001'; end if;
  if p_budget is not null and p_budget <= 0 then raise exception 'Enter a budget above zero, or leave it empty.' using errcode = 'P0001'; end if;
  if p_needed_by is null or p_needed_by <= current_date then raise exception 'Choose a date after today.' using errcode = 'P0001'; end if;

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
  if not found or v_r.buyer_id is distinct from auth.uid() then raise exception 'Request not found.' using errcode = 'P0001'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request can no longer be cancelled.' using errcode = 'P0001'; end if;
  update public.quote set status = 'declined', decline_reason = 'The buyer cancelled the request.'
   where request_id = p_request_id and status = 'sent';
  update public.custom_request set status = 'cancelled' where request_id = p_request_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 5. Quotes (seller): send a price, or decline with a reason.
-- A new quote replaces the open one (status superseded); version_no counts up.
-- ---------------------------------------------------------------------------
create or replace function public.send_quote(p_request_id uuid, p_price numeric, p_ready_by date, p_message text default null)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r record;
begin
  select r.request_id, r.status, r.quantity, r.needed_by_date, p.price, p.product_id
    into v_r from public.custom_request r join public.product p on p.product_id = r.product_id
   where r.request_id = p_request_id for update of r;
  if not found or not public.owns_product(v_r.product_id) then raise exception 'Request not found.' using errcode = 'P0001'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request is already %.', v_r.status using errcode = 'P0001'; end if;
  if p_price is null or p_price <= 0 then raise exception 'Enter a price above zero.' using errcode = 'P0001'; end if;
  if p_ready_by is null or p_ready_by < current_date then raise exception 'Choose a ready date from today onwards.' using errcode = 'P0001'; end if;

  update public.quote set status = 'superseded' where request_id = p_request_id and status = 'sent';
  insert into public.quote (request_id, version_no, offered_price, estimated_completion_date, message)
  values (p_request_id,
          coalesce((select max(q.version_no) from public.quote q where q.request_id = p_request_id), 0) + 1,
          round(p_price, 2), p_ready_by, nullif(trim(p_message), ''));
  update public.custom_request set status = 'quoted' where request_id = p_request_id;
end;
$$;

-- The data dictionary keeps the decline reason on QUOTE, so a decline is saved
-- as a closing quote version with status 'declined' (price = base price × quantity).
create or replace function public.decline_custom_request(p_request_id uuid, p_reason text)
returns void language plpgsql security definer set search_path = ''
as $$
declare v_r record;
begin
  select r.request_id, r.status, r.quantity, r.needed_by_date, p.price, p.product_id
    into v_r from public.custom_request r join public.product p on p.product_id = r.product_id
   where r.request_id = p_request_id for update of r;
  if not found or not public.owns_product(v_r.product_id) then raise exception 'Request not found.' using errcode = 'P0001'; end if;
  if v_r.status not in ('pending', 'quoted') then raise exception 'This request is already %.', v_r.status using errcode = 'P0001'; end if;
  if length(trim(coalesce(p_reason, ''))) < 3 then raise exception 'Tell the buyer why you are declining.' using errcode = 'P0001'; end if;

  update public.quote set status = 'superseded' where request_id = p_request_id and status = 'sent';
  insert into public.quote (request_id, version_no, offered_price, estimated_completion_date, decline_reason, status)
  values (p_request_id,
          coalesce((select max(q.version_no) from public.quote q where q.request_id = p_request_id), 0) + 1,
          v_r.price * v_r.quantity, v_r.needed_by_date, trim(p_reason), 'declined');
  update public.custom_request set status = 'declined' where request_id = p_request_id;
end;
$$;

-- ---------------------------------------------------------------------------
-- 6. Buyer answers a quote.
-- Accept: the quote becomes a binding order, as long as the store still has a
-- free capacity slot in the week the order is due (CAPACITY_BOOKING).
-- Ask for changes: the request goes back to the seller for a new quote.
-- ---------------------------------------------------------------------------
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
  if not found or v_q.buyer_id is distinct from v_uid then raise exception 'Quote not found.' using errcode = 'P0001'; end if;
  if v_q.status <> 'sent' or v_q.request_status <> 'quoted' then
    raise exception 'This quote is no longer open. Refresh to see the latest one.' using errcode = 'P0001';
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
      to_char(v_week, 'Mon DD') using errcode = 'P0001';
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

-- ---------------------------------------------------------------------------
-- 7. Reading: one call returns everything the Orders and Custom requests
-- screens need, including the other person's name (users rows are private,
-- so only the name of the person you trade with is shared).
-- ---------------------------------------------------------------------------
create or replace function public.my_orders()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(row_data order by order_date desc), '[]'::jsonb)
  from (
    select o.order_date, jsonb_build_object(
      'order_id', o.order_id,
      'order_number', o.order_number,
      'side', case when o.buyer_id = (select auth.uid()) then 'buying' else 'selling' end,
      'counterpart', case when o.buyer_id = (select auth.uid()) then s.store_name else bu.full_name end,
      'order_date', o.order_date,
      'total_amount', o.total_amount,
      'status', o.status,
      'due_date', o.due_date,
      'completed_at', o.completed_at,
      'reservation_expires_at', o.reservation_expires_at,
      'is_custom', o.quote_id is not null,
      'request_number', (select r.request_number from public.quote q join public.custom_request r on r.request_id = q.request_id where q.quote_id = o.quote_id),
      'product_id', oi.product_id,
      'product_title', pr.title,
      'quantity', oi.quantity,
      'payment', (select jsonb_build_object('payment_id', p.payment_id, 'reference_number', p.reference_number,
                    'status', p.status, 'amount_paid', p.amount_paid, 'proof_image_path', p.proof_image_path, 'verified_at', p.verified_at)
                  from public.payment p where p.order_id = o.order_id
                  order by (p.status = 'rejected'), p.verified_at desc nulls first limit 1),
      'reviewed', exists (select 1 from public.review rv where rv.order_id = o.order_id),
      'history', (select coalesce(jsonb_agg(jsonb_build_object('from_status', h.from_status, 'to_status', h.to_status,
                    'note', h.note, 'changed_at', h.changed_at) order by h.changed_at, h.history_id), '[]'::jsonb)
                  from public.order_status_history h where h.order_id = o.order_id)
    ) as row_data
    from public.orders o
    join public.store s on s.store_id = o.store_id
    join public.users bu on bu.user_id = o.buyer_id
    left join lateral (select i.product_id, i.quantity from public.order_item i where i.order_id = o.order_id limit 1) oi on true
    left join public.product pr on pr.product_id = oi.product_id
    where not o.is_archived
      and (o.buyer_id = (select auth.uid()) or s.seller_id = (select auth.uid()))
  ) t;
$$;

create or replace function public.my_custom_requests()
returns jsonb language sql stable security definer set search_path = ''
as $$
  select coalesce(jsonb_agg(row_data order by created_at desc), '[]'::jsonb)
  from (
    select r.created_at, jsonb_build_object(
      'request_id', r.request_id,
      'request_number', r.request_number,
      'side', case when r.buyer_id = (select auth.uid()) then 'buying' else 'selling' end,
      'counterpart', case when r.buyer_id = (select auth.uid()) then s.store_name else bu.full_name end,
      'product_id', r.product_id,
      'product_title', p.title,
      'description', r.description,
      'quantity', r.quantity,
      'budget', r.budget,
      'needed_by_date', r.needed_by_date,
      'status', r.status,
      'created_at', r.created_at,
      'options', (select coalesce(jsonb_agg(o.label order by o.label), '[]'::jsonb)
                  from public.custom_request_option ro join public.product_custom_option o on o.option_id = ro.option_id
                  where ro.request_id = r.request_id),
      'image_paths', (select coalesce(jsonb_agg(i.image_path), '[]'::jsonb) from public.custom_request_image i where i.request_id = r.request_id),
      'quotes', (select coalesce(jsonb_agg(jsonb_build_object('quote_id', q.quote_id, 'version_no', q.version_no,
                   'offered_price', q.offered_price, 'estimated_completion_date', q.estimated_completion_date,
                   'message', q.message, 'decline_reason', q.decline_reason, 'status', q.status, 'created_at', q.created_at)
                   order by q.version_no), '[]'::jsonb)
                 from public.quote q where q.request_id = r.request_id),
      'order_number', (select o.order_number from public.orders o join public.quote q on q.quote_id = o.quote_id where q.request_id = r.request_id limit 1)
    ) as row_data
    from public.custom_request r
    join public.product p on p.product_id = r.product_id
    join public.store s on s.store_id = p.store_id
    join public.users bu on bu.user_id = r.buyer_id
    where r.buyer_id = (select auth.uid()) or s.seller_id = (select auth.uid())
  ) t;
$$;

revoke execute on function
  public.place_order(uuid, int), public.release_expired_reservations(),
  public.submit_payment(uuid, text, text, text, numeric), public.review_payment(uuid, boolean, text),
  public.set_order_status(uuid, text, text), public.submit_custom_request(uuid, text, int, numeric, date, text[]),
  public.cancel_custom_request(uuid), public.send_quote(uuid, numeric, date, text),
  public.decline_custom_request(uuid, text), public.respond_to_quote(uuid, boolean, text),
  public.my_orders(), public.my_custom_requests()
from public, anon;
grant execute on function
  public.place_order(uuid, int), public.release_expired_reservations(),
  public.submit_payment(uuid, text, text, text, numeric), public.review_payment(uuid, boolean, text),
  public.set_order_status(uuid, text, text), public.submit_custom_request(uuid, text, int, numeric, date, text[]),
  public.cancel_custom_request(uuid), public.send_quote(uuid, numeric, date, text),
  public.decline_custom_request(uuid, text), public.respond_to_quote(uuid, boolean, text),
  public.my_orders(), public.my_custom_requests()
to authenticated;
revoke execute on function public.check_order_transition() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Storage: reference photos of a custom request are saved in
-- private-files/{buyer_id}/{request_id}/…; the request's seller may open them.
-- (Payment proofs use {buyer_id}/{order_id}/…, already covered in 02.)
-- ---------------------------------------------------------------------------
drop policy if exists "private-files: request seller read" on storage.objects;
create policy "private-files: request seller read" on storage.objects for select to authenticated
  using (bucket_id = 'private-files'
    and case when (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
             then public.can_see_request(((storage.foldername(name))[2])::uuid) else false end);
