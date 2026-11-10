-- =============================================================================
-- CraftHive – triggers, helper functions, views, row-level security, storage
-- Run after 01_schema.sql.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Table privileges for the app's roles. Row-level security (below) then
-- decides which rows each signed-in user may see or change.
-- Signed-out visitors (anon) may only read categories and call the three
-- login/sign-up check functions.
-- ---------------------------------------------------------------------------
revoke all on all tables in schema public from anon;
grant select, insert, update, delete on all tables in schema public to authenticated;
grant usage, select on all sequences in schema public to authenticated;
grant select on public.category to anon;

-- ---------------------------------------------------------------------------
-- Sign-up: copy the new Supabase Auth account into USER and BUYER.
-- The app sends full_name, username, phone_number, sex and country as metadata.
-- Accounts without a username (staff accounts) are not marketplace users.
-- ---------------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if coalesce(new.raw_user_meta_data ->> 'username', '') <> '' then
    insert into public.users (user_id, full_name, email, username, phone_number, sex, country)
    values (
      new.id,
      trim(new.raw_user_meta_data ->> 'full_name'),
      lower(new.email),
      lower(trim(new.raw_user_meta_data ->> 'username')),
      new.raw_user_meta_data ->> 'phone_number',
      nullif(new.raw_user_meta_data ->> 'sex', ''),
      coalesce(nullif(new.raw_user_meta_data ->> 'country', ''), 'Philippines')
    );
    insert into public.buyer (user_id) values (new.id);
  end if;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Log in with a username: look up the linked email first (Basic Operations).
-- Sign up: check that the username and email are still free.
-- ---------------------------------------------------------------------------
create or replace function public.email_for_username(p_username text)
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select u.email from public.users u where u.username = lower(trim(p_username));
$$;

create or replace function public.is_username_available(p_username text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (select 1 from public.users u where u.username = lower(trim(p_username)));
$$;

create or replace function public.is_email_available(p_email text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select not exists (select 1 from auth.users a where lower(a.email) = lower(trim(p_email)));
$$;

revoke execute on function public.email_for_username(text), public.is_username_available(text), public.is_email_available(text) from public;
grant execute on function public.email_for_username(text), public.is_username_available(text), public.is_email_available(text) to anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helper checks used by the row-level security policies
-- ---------------------------------------------------------------------------
create or replace function public.is_admin()
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.admin a where a.auth_uid = (select auth.uid())); $$;

create or replace function public.owns_store(p_store_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.store s where s.store_id = p_store_id and s.seller_id = (select auth.uid())); $$;

create or replace function public.owns_product(p_product_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.product p join public.store s on s.store_id = p.store_id
    where p.product_id = p_product_id and s.seller_id = (select auth.uid())
  );
$$;

create or replace function public.can_see_request(p_request_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.custom_request r
    join public.product p on p.product_id = r.product_id
    join public.store s on s.store_id = p.store_id
    where r.request_id = p_request_id
      and (r.buyer_id = (select auth.uid()) or s.seller_id = (select auth.uid()))
  ) or public.is_admin();
$$;

create or replace function public.can_see_order(p_order_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.orders o join public.store s on s.store_id = o.store_id
    where o.order_id = p_order_id
      and (o.buyer_id = (select auth.uid()) or s.seller_id = (select auth.uid()))
  ) or public.is_admin();
$$;

create or replace function public.can_see_dispute(p_dispute_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$ select exists (select 1 from public.dispute d where d.dispute_id = p_dispute_id and public.can_see_order(d.order_id)); $$;

revoke execute on function public.is_admin(), public.owns_store(uuid), public.owns_product(uuid),
  public.can_see_request(uuid), public.can_see_order(uuid), public.can_see_dispute(uuid) from public, anon;
grant execute on function public.is_admin(), public.owns_store(uuid), public.owns_product(uuid),
  public.can_see_request(uuid), public.can_see_order(uuid), public.can_see_dispute(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- Order status history: every status change is logged (Basic Operations)
-- ---------------------------------------------------------------------------
create or replace function public.log_order_status()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.order_status_history (order_id, from_status, to_status, changed_by)
    values (new.order_id, case when tg_op = 'UPDATE' then old.status end, new.status,
            (select u.user_id from public.users u where u.user_id = (select auth.uid())));
  end if;
  return new;
end;
$$;

create trigger orders_log_status
  after insert or update of status on public.orders
  for each row execute function public.log_order_status();

-- ---------------------------------------------------------------------------
-- Store rating and items sold are kept up to date from reviews and orders
-- ---------------------------------------------------------------------------
create or replace function public.refresh_store_stats(p_store_id uuid)
returns void language sql security definer set search_path = ''
as $$
  update public.store s set
    rating = coalesce((
      select round(avg(r.rating)::numeric, 2) from public.review r
      join public.product p on p.product_id = r.product_id where p.store_id = s.store_id), 0),
    items_sold_count = coalesce((
      select sum(oi.quantity) from public.order_item oi
      join public.orders o on o.order_id = oi.order_id
      where o.store_id = s.store_id and o.status in ('delivered', 'completed')), 0)
  where s.store_id = p_store_id;
$$;

create or replace function public.on_review_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.refresh_store_stats(p.store_id)
  from public.product p where p.product_id = coalesce(new.product_id, old.product_id);
  return null;
end;
$$;

create or replace function public.on_order_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.refresh_store_stats(coalesce(new.store_id, old.store_id));
  return null;
end;
$$;

create or replace function public.on_order_item_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  perform public.refresh_store_stats(o.store_id)
  from public.orders o where o.order_id = coalesce(new.order_id, old.order_id);
  return null;
end;
$$;

create trigger review_refresh_store after insert or update or delete on public.review
  for each row execute function public.on_review_change();
create trigger orders_refresh_store after update of status on public.orders
  for each row execute function public.on_order_change();
create trigger order_item_refresh_store after insert or update or delete on public.order_item
  for each row execute function public.on_order_item_change();

revoke execute on function public.refresh_store_stats(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Product ratings and items sold (aggregates only; individual orders stay private)
-- ---------------------------------------------------------------------------
create or replace function public.product_stats()
returns table (product_id uuid, avg_rating numeric, review_count bigint, sold_count bigint)
language sql stable security definer set search_path = ''
as $$
  select p.product_id,
    (select round(avg(r.rating)::numeric, 1) from public.review r where r.product_id = p.product_id),
    (select count(*) from public.review r where r.product_id = p.product_id),
    (select coalesce(sum(oi.quantity), 0) from public.order_item oi
       join public.orders o on o.order_id = oi.order_id
      where oi.product_id = p.product_id and o.status in ('delivered', 'completed'))
  from public.product p;
$$;
revoke execute on function public.product_stats() from public, anon;
grant execute on function public.product_stats() to authenticated;

-- Product cards for Home, search and stores
create or replace view public.product_card with (security_invoker = on) as
select
  p.product_id, p.store_id, p.category_id, p.title, p.description, p.price,
  p.stock_quantity, p.lead_time_days, p.has_custom_option, p.is_draft, p.is_archived, p.created_at,
  coalesce(st.avg_rating, 0)   as rating,
  coalesce(st.review_count, 0) as review_count,
  coalesce(st.sold_count, 0)   as sold_count,
  coalesce((select array_agg(i.image_path order by i.sort_order) from public.product_image i where i.product_id = p.product_id), '{}') as image_paths,
  coalesce((select array_agg(o.label order by o.label) from public.product_custom_option o where o.product_id = p.product_id), '{}') as custom_options
from public.product p
left join public.product_stats() st on st.product_id = p.product_id;

-- Store cards (no private seller details)
create or replace view public.store_card with (security_invoker = on) as
select
  s.store_id, s.seller_id, s.store_name, s.store_description, s.city, s.rating,
  s.items_sold_count, s.is_archived, se.verification_status
from public.store s
join public.seller se on se.user_id = s.seller_id;

revoke all on public.product_card, public.store_card from anon;
grant select on public.product_card, public.store_card to authenticated;

-- ---------------------------------------------------------------------------
-- Row-level security
-- ---------------------------------------------------------------------------
alter table public.users enable row level security;
alter table public.admin enable row level security;
alter table public.buyer enable row level security;
alter table public.seller enable row level security;
alter table public.store enable row level security;
alter table public.category enable row level security;
alter table public.product enable row level security;
alter table public.product_image enable row level security;
alter table public.product_custom_option enable row level security;
alter table public.custom_request enable row level security;
alter table public.custom_request_image enable row level security;
alter table public.custom_request_option enable row level security;
alter table public.quote enable row level security;
alter table public.orders enable row level security;
alter table public.order_item enable row level security;
alter table public.payment enable row level security;
alter table public.review enable row level security;
alter table public.seller_portfolio_image enable row level security;
alter table public.capacity_booking enable row level security;
alter table public.order_status_history enable row level security;
alter table public.dispute enable row level security;
alter table public.dispute_evidence enable row level security;

-- USER: each person sees and edits only their own profile
create policy "users: read own" on public.users for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));
create policy "users: update own" on public.users for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ADMIN: staff see their own record
create policy "admin: read own" on public.admin for select to authenticated
  using (auth_uid = (select auth.uid()));

-- BUYER
create policy "buyer: read own" on public.buyer for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

-- SELLER: badge state is public; ID details are hidden by column privileges below
create policy "seller: read" on public.seller for select to authenticated using (true);
create policy "seller: become a seller" on public.seller for insert to authenticated
  with check (user_id = (select auth.uid()) and verification_status = 'unverified');
create policy "seller: request verification" on public.seller for update to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()))
  with check (user_id = (select auth.uid()) and verification_status in ('unverified', 'pending') or (select public.is_admin()));
revoke select on public.seller from anon, authenticated;
grant select (user_id, verification_status, verified_at) on public.seller to authenticated;

-- STORE
create policy "store: read" on public.store for select to authenticated
  using (not is_archived or seller_id = (select auth.uid()) or (select public.is_admin()));
create policy "store: open own" on public.store for insert to authenticated
  with check (seller_id = (select auth.uid()));
create policy "store: edit own" on public.store for update to authenticated
  using (seller_id = (select auth.uid())) with check (seller_id = (select auth.uid()));

-- CATEGORY: static list kept by admins
create policy "category: read" on public.category for select to anon, authenticated using (true);
create policy "category: admin writes" on public.category for all to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));

-- PRODUCT: published listings are public; drafts and archived items only to their seller
create policy "product: read" on public.product for select to authenticated
  using ((not is_draft and not is_archived) or (select public.owns_store(store_id)) or (select public.is_admin()));
create policy "product: add to own store" on public.product for insert to authenticated
  with check ((select public.owns_store(store_id)));
create policy "product: edit own" on public.product for update to authenticated
  using ((select public.owns_store(store_id))) with check ((select public.owns_store(store_id)));
create policy "product: delete own" on public.product for delete to authenticated
  using ((select public.owns_store(store_id)));

-- PRODUCT_IMAGE and PRODUCT_CUSTOM_OPTION
create policy "product_image: read" on public.product_image for select to authenticated using (true);
create policy "product_image: seller writes" on public.product_image for all to authenticated
  using ((select public.owns_product(product_id))) with check ((select public.owns_product(product_id)));
create policy "product_custom_option: read" on public.product_custom_option for select to authenticated using (true);
create policy "product_custom_option: seller writes" on public.product_custom_option for all to authenticated
  using ((select public.owns_product(product_id))) with check ((select public.owns_product(product_id)));

-- CUSTOM_REQUEST and its photos/options: the buyer and the product's seller
create policy "custom_request: read" on public.custom_request for select to authenticated
  using ((select public.can_see_request(request_id)));
create policy "custom_request: buyer creates" on public.custom_request for insert to authenticated
  with check (buyer_id = (select auth.uid()));
create policy "custom_request: participants update" on public.custom_request for update to authenticated
  using ((select public.can_see_request(request_id))) with check ((select public.can_see_request(request_id)));
create policy "custom_request_image: read" on public.custom_request_image for select to authenticated
  using ((select public.can_see_request(request_id)));
create policy "custom_request_image: buyer adds" on public.custom_request_image for insert to authenticated
  with check (exists (select 1 from public.custom_request r where r.request_id = custom_request_image.request_id and r.buyer_id = (select auth.uid())));
create policy "custom_request_option: read" on public.custom_request_option for select to authenticated
  using ((select public.can_see_request(request_id)));
create policy "custom_request_option: buyer adds" on public.custom_request_option for insert to authenticated
  with check (exists (select 1 from public.custom_request r where r.request_id = custom_request_option.request_id and r.buyer_id = (select auth.uid())));

-- QUOTE: the seller writes it, the buyer accepts or asks for changes
create policy "quote: read" on public.quote for select to authenticated
  using ((select public.can_see_request(request_id)));
create policy "quote: seller sends" on public.quote for insert to authenticated
  with check (exists (select 1 from public.custom_request r where r.request_id = quote.request_id and public.owns_product(r.product_id)));
create policy "quote: participants update" on public.quote for update to authenticated
  using ((select public.can_see_request(request_id))) with check ((select public.can_see_request(request_id)));

-- ORDER and ORDER_ITEM
create policy "orders: read" on public.orders for select to authenticated
  using (buyer_id = (select auth.uid()) or (select public.owns_store(store_id)) or (select public.is_admin()));
create policy "orders: buyer places" on public.orders for insert to authenticated
  with check (buyer_id = (select auth.uid()));
create policy "orders: participants update" on public.orders for update to authenticated
  using (buyer_id = (select auth.uid()) or (select public.owns_store(store_id)))
  with check (buyer_id = (select auth.uid()) or (select public.owns_store(store_id)));
create policy "order_item: read" on public.order_item for select to authenticated
  using ((select public.can_see_order(order_id)));
create policy "order_item: buyer adds" on public.order_item for insert to authenticated
  with check (exists (select 1 from public.orders o where o.order_id = order_item.order_id and o.buyer_id = (select auth.uid())));

-- PAYMENT: the buyer uploads proof, the seller verifies it
create policy "payment: read" on public.payment for select to authenticated
  using ((select public.can_see_order(order_id)));
create policy "payment: buyer submits" on public.payment for insert to authenticated
  with check (exists (select 1 from public.orders o where o.order_id = payment.order_id and o.buyer_id = (select auth.uid())));
create policy "payment: seller verifies" on public.payment for update to authenticated
  using (exists (select 1 from public.orders o where o.order_id = payment.order_id and public.owns_store(o.store_id)))
  with check (exists (select 1 from public.orders o where o.order_id = payment.order_id and public.owns_store(o.store_id)));

-- REVIEW: public; only the buyer of a delivered or completed order, once per product
create policy "review: read" on public.review for select to authenticated using (true);
create policy "review: buyer writes" on public.review for insert to authenticated
  with check (exists (
    select 1 from public.orders o join public.order_item oi on oi.order_id = o.order_id
    where o.order_id = review.order_id and oi.product_id = review.product_id
      and o.buyer_id = (select auth.uid()) and o.status in ('delivered', 'completed')));

-- SELLER_PORTFOLIO_IMAGE: the seller and the admins who review it
create policy "portfolio: read" on public.seller_portfolio_image for select to authenticated
  using (seller_id = (select auth.uid()) or (select public.is_admin()));
create policy "portfolio: seller adds" on public.seller_portfolio_image for insert to authenticated
  with check (seller_id = (select auth.uid()));
create policy "portfolio: seller removes" on public.seller_portfolio_image for delete to authenticated
  using (seller_id = (select auth.uid()));

-- CAPACITY_BOOKING
create policy "capacity_booking: read" on public.capacity_booking for select to authenticated
  using ((select public.owns_store(store_id)) or (select public.can_see_order(order_id)));
create policy "capacity_booking: participants add" on public.capacity_booking for insert to authenticated
  with check ((select public.can_see_order(order_id)));

-- ORDER_STATUS_HISTORY: written by the trigger, read by the order's buyer and seller
create policy "order_status_history: read" on public.order_status_history for select to authenticated
  using ((select public.can_see_order(order_id)));
create policy "order_status_history: participants add notes" on public.order_status_history for insert to authenticated
  with check ((select public.can_see_order(order_id)) and changed_by = (select auth.uid()));

-- DISPUTE and DISPUTE_EVIDENCE
create policy "dispute: read" on public.dispute for select to authenticated
  using ((select public.can_see_order(order_id)));
create policy "dispute: participants open" on public.dispute for insert to authenticated
  with check (opened_by = (select auth.uid()) and (select public.can_see_order(order_id)));
create policy "dispute: admins resolve" on public.dispute for update to authenticated
  using ((select public.is_admin())) with check ((select public.is_admin()));
create policy "dispute_evidence: read" on public.dispute_evidence for select to authenticated
  using ((select public.can_see_dispute(dispute_id)));
create policy "dispute_evidence: participants add" on public.dispute_evidence for insert to authenticated
  with check (uploaded_by = (select auth.uid()) and (select public.can_see_dispute(dispute_id)));

-- ---------------------------------------------------------------------------
-- Storage buckets (image files; the tables keep their paths)
--   product-images  public   {store_id}/{product_id}/{n}.jpg
--   avatars         public   {user_id}/avatar.jpg
--   private-files   private  {user_id}/...  (payment proofs, request photos,
--                            seller IDs, dispute evidence)
-- ---------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('product-images', 'product-images', true, 5242880, array['image/jpeg', 'image/png', 'image/webp']),
  ('avatars', 'avatars', true, 2097152, array['image/jpeg', 'image/png', 'image/webp']),
  ('private-files', 'private-files', false, 5242880, array['image/jpeg', 'image/png', 'image/webp', 'application/pdf'])
on conflict (id) do nothing;

create policy "product-images: seller uploads" on storage.objects for insert to authenticated
  with check (bucket_id = 'product-images' and public.owns_store(((storage.foldername(name))[1])::uuid));
create policy "product-images: seller replaces" on storage.objects for update to authenticated
  using (bucket_id = 'product-images' and public.owns_store(((storage.foldername(name))[1])::uuid));
create policy "product-images: seller deletes" on storage.objects for delete to authenticated
  using (bucket_id = 'product-images' and public.owns_store(((storage.foldername(name))[1])::uuid));

create policy "avatars: own folder" on storage.objects for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "avatars: replace own" on storage.objects for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "private-files: own folder upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'private-files' and (storage.foldername(name))[1] = (select auth.uid())::text);
create policy "private-files: own folder read" on storage.objects for select to authenticated
  using (bucket_id = 'private-files' and (
    (storage.foldername(name))[1] = (select auth.uid())::text
    or public.is_admin()
    -- {buyer_id}/{order_id}/... : the order's seller can open the payment proof
    or (case when (storage.foldername(name))[2] ~ '^[0-9a-f-]{36}$'
             then public.can_see_order(((storage.foldername(name))[2])::uuid) else false end)));

-- ---------------------------------------------------------------------------
-- Trigger functions only run from their triggers; nobody calls them through the API.
-- (email_for_username, is_username_available and is_email_available stay open to
-- signed-out visitors on purpose: Log in and Sign up need them.)
-- ---------------------------------------------------------------------------
revoke execute on function public.handle_new_user(), public.log_order_status(), public.on_review_change(),
  public.on_order_change(), public.on_order_item_change() from public, anon, authenticated;
