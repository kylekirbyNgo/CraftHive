-- =============================================================================
-- CraftHive – Search by distance
-- Run after 07_store_photos.sql (it keeps 07's avatar_path). Safe to run more than once.
--
-- Search can filter and sort stores by distance from the buyer. The store card
-- view now carries the store's position, rounded to 2 decimals (about 1 km) so
-- the exact address stays private. Stores without coordinates fall back to the
-- centre of their city in the app.
-- =============================================================================

create or replace view public.store_card with (security_invoker = on) as
select
  s.store_id, s.seller_id, s.store_name, s.store_description, s.city, s.rating,
  s.items_sold_count, s.is_archived, se.verification_status,
  public.store_owner_avatar(s.seller_id) as avatar_path,
  round(s.latitude, 2)  as latitude,
  round(s.longitude, 2) as longitude
from public.store s
join public.seller se on se.user_id = s.seller_id;

revoke all on public.store_card from anon;
grant select on public.store_card to authenticated;
