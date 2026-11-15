-- =============================================================================
-- CraftHive – 05: Firebase messaging and notifications
--
-- PostgreSQL stays the source of truth (Milestone II, assumption 15): orders,
-- payments, quotes, requests and reviews are saved here first. After each
-- change commits, a trigger sends the row to the firebase-bridge Edge Function
-- (through pg_net), which then
--   • adds the notification to Firestore notifications/{uid}/items,
--   • sends the push notification (Firebase Cloud Messaging), and
--   • posts quote cards and order updates into the buyer–seller chat.
--
-- pg_net sends the request only after the transaction commits, so a failed
-- order never sends a notification. A failed notification never blocks an order.
--
-- Run this file once in the Supabase SQL editor, after 01–04. Then save the
-- function URL and secret in Vault (step 6 of FIREBASE_SETUP.md):
--
--   select vault.create_secret('https://<project-ref>.supabase.co/functions/v1/firebase-bridge', 'db_events_url');
--   select vault.create_secret('<same value as the DB_EVENTS_SECRET function secret>', 'db_events_secret');
-- =============================================================================

create extension if not exists pg_net;

-- ---------------------------------------------------------------------------
-- 1. Send a changed row to the Edge Function
-- ---------------------------------------------------------------------------
create or replace function public.send_db_event()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare
  v_url text;
  v_secret text;
begin
  select s.decrypted_secret into v_url from vault.decrypted_secrets s where s.name = 'db_events_url';
  select s.decrypted_secret into v_secret from vault.decrypted_secrets s where s.name = 'db_events_secret';
  if v_url is null or v_secret is null then
    return null; -- Not set up yet: skip quietly.
  end if;

  perform net.http_post(
    url := v_url,
    body := jsonb_build_object(
      'action', 'db_event',
      'table', tg_table_name,
      'type', tg_op,
      'record', to_jsonb(new),
      'old_record', case when tg_op = 'UPDATE' then to_jsonb(old) end),
    headers := jsonb_build_object('Content-Type', 'application/json', 'x-crafthive-secret', v_secret),
    timeout_milliseconds := 8000);
  return null;
exception when others then
  -- Notifications must never stop an order, payment or quote from saving.
  raise warning 'send_db_event (%): %', tg_table_name, sqlerrm;
  return null;
end;
$$;

revoke execute on function public.send_db_event() from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 2. Which changes are sent
-- ---------------------------------------------------------------------------
-- New custom request (→ seller) and cancelled request (→ seller)
drop trigger if exists custom_request_firebase on public.custom_request;
create trigger custom_request_firebase
  after insert or update of status on public.custom_request
  for each row execute function public.send_db_event();

-- New quote or decline (→ buyer); quote accepted or changes asked (→ seller)
drop trigger if exists quote_firebase on public.quote;
create trigger quote_firebase
  after insert or update of status on public.quote
  for each row execute function public.send_db_event();

-- New order, in production, shipped, delivered, completed, cancelled
drop trigger if exists order_status_history_firebase on public.order_status_history;
create trigger order_status_history_firebase
  after insert on public.order_status_history
  for each row execute function public.send_db_event();

-- Payment proof sent (→ seller); payment confirmed or rejected (→ buyer)
drop trigger if exists payment_firebase on public.payment;
create trigger payment_firebase
  after insert or update of status on public.payment
  for each row execute function public.send_db_event();

-- New review (→ seller)
drop trigger if exists review_firebase on public.review;
create trigger review_firebase
  after insert on public.review
  for each row execute function public.send_db_event();

-- ---------------------------------------------------------------------------
-- 3. Who is in a chat
-- Every buyer has one chat per store, with the Firestore ID
-- {buyer user_id}_{store_id}. The app calls this before opening a chat, so it
-- knows both people and their names (users rows are private).
--   chat_target(p_store_id)   – the signed-in buyer messages a store
--   chat_target(p_order_id)   – buyer or seller of the order
--   chat_target(p_request_id) – buyer or seller of the custom request
-- ---------------------------------------------------------------------------
create or replace function public.chat_target(p_store_id uuid default null, p_order_id uuid default null, p_request_id uuid default null)
returns jsonb language plpgsql stable security definer set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_buyer uuid;
  v_store uuid;
  v_s record;
  v_buyer_name text;
begin
  if v_uid is null then raise exception 'Please log in again.' using errcode = 'P0001'; end if;

  if p_order_id is not null then
    select o.buyer_id, o.store_id into v_buyer, v_store from public.orders o where o.order_id = p_order_id;
  elsif p_request_id is not null then
    select r.buyer_id, p.store_id into v_buyer, v_store
      from public.custom_request r join public.product p on p.product_id = r.product_id
     where r.request_id = p_request_id;
  elsif p_store_id is not null then
    v_buyer := v_uid;
    v_store := p_store_id;
  end if;

  select s.store_id, s.store_name, s.seller_id into v_s from public.store s where s.store_id = v_store;
  if not found then raise exception 'Chat not found.' using errcode = 'P0001'; end if;
  if v_uid <> v_buyer and v_uid <> v_s.seller_id then raise exception 'Chat not found.' using errcode = 'P0001'; end if;
  if v_buyer = v_s.seller_id then raise exception 'This is your own store.' using errcode = 'P0001'; end if;

  select u.full_name into v_buyer_name from public.users u where u.user_id = v_buyer;

  return jsonb_build_object(
    'chat_id', v_buyer::text || '_' || v_store::text,
    'buyer_id', v_buyer,
    'seller_id', v_s.seller_id,
    'store_id', v_store,
    'buyer_name', coalesce(v_buyer_name, 'Buyer'),
    'store_name', v_s.store_name);
end;
$$;

revoke execute on function public.chat_target(uuid, uuid, uuid) from public, anon;
grant execute on function public.chat_target(uuid, uuid, uuid) to authenticated;
