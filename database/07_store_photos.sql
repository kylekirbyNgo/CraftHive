-- =============================================================================
-- CraftHive – 07: Store owners' profile photos on store cards
--
-- USERS rows are private (each person reads only their own), so buyers could
-- not see a seller's photo. This adds avatar_path to the store_card view
-- through a small function that returns the photo only for people who have a
-- store. Buyers' profiles stay private. The photos themselves are in the
-- public avatars bucket.
--
-- Run once in the Supabase SQL editor, after 01–06.
-- =============================================================================

create or replace function public.store_owner_avatar(p_seller_id uuid)
returns text language sql stable security definer set search_path = ''
as $$
  select u.avatar_path
  from public.users u
  where u.user_id = p_seller_id
    and exists (select 1 from public.store s where s.seller_id = p_seller_id);
$$;

revoke execute on function public.store_owner_avatar(uuid) from public, anon;
grant execute on function public.store_owner_avatar(uuid) to authenticated;

-- Same columns as in 02_logic_and_security.sql, plus avatar_path at the end.
create or replace view public.store_card with (security_invoker = on) as
select
  s.store_id, s.seller_id, s.store_name, s.store_description, s.city, s.rating,
  s.items_sold_count, s.is_archived, se.verification_status,
  public.store_owner_avatar(s.seller_id) as avatar_path
from public.store s
join public.seller se on se.user_id = s.seller_id;

revoke all on public.store_card from anon;
grant select on public.store_card to authenticated;
