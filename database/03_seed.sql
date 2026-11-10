-- =============================================================================
-- CraftHive – sample data (generated). Run after 02_logic_and_security.sql.
-- Every sample account uses the password craftlover8.
-- =============================================================================

-- Categories (static list kept by admins)
insert into public.category (category_id, category_name, description) values
  ('c0000000-0000-4000-8000-000000000001', 'Flowers', 'Fresh and dried bouquets and floral arrangements'),
  ('c0000000-0000-4000-8000-000000000002', '3D Prints', '3D-printed gifts, planters, figures and keychains'),
  ('c0000000-0000-4000-8000-000000000003', 'Woodcrafts', 'Carved and turned wood for the kitchen and home'),
  ('c0000000-0000-4000-8000-000000000004', 'Custom Shirts', 'Printed and embroidered apparel'),
  ('c0000000-0000-4000-8000-000000000005', 'Crochet', 'Crocheted bags, toys and accessories'),
  ('c0000000-0000-4000-8000-000000000006', 'Candles', 'Hand-poured soy and beeswax candles'),
  ('c0000000-0000-4000-8000-000000000007', 'Pottery', 'Hand-thrown mugs, bowls and planters'),
  ('c0000000-0000-4000-8000-000000000008', 'Accessories', 'Beaded jewelry, bracelets and small accessories');

-- Sample accounts (the sign-up trigger fills USER and BUYER from the metadata)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000001', 'authenticated', 'authenticated', 'ana.reyes@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Ana Reyes", "username": "ana.makes", "phone_number": "639171234567", "sex": "Female", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000001', 'email', 'ana.reyes@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000002', 'authenticated', 'authenticated', 'narra.craft@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Ramon Bautista", "username": "narra.craft", "phone_number": "639181112233", "sex": "Male", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000002', 'email', 'narra.craft@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000003', 'authenticated', 'authenticated', 'petal.twine@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Liza Mendoza", "username": "petal.twine", "phone_number": "639192223344", "sex": "Female", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000003', 'email', 'petal.twine@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000004', 'authenticated', 'authenticated', 'layerlab.ph@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Carlo Santos", "username": "layerlab.ph", "phone_number": "639173334455", "sex": "Male", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000004', 'email', 'layerlab.ph@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000005', 'authenticated', 'authenticated', 'threadink.tees@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Joy Villanueva", "username": "threadink.tees", "phone_number": "639184445566", "sex": "Female", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000005', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000005', 'email', 'threadink.tees@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000006', 'authenticated', 'authenticated', 'wickwax.mnl@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Paolo Garcia", "username": "wickwax.mnl", "phone_number": "639195556677", "sex": "Male", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000006', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000006', 'email', 'wickwax.mnl@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000007', 'authenticated', 'authenticated', 'clayfolk.studio@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Maya Torres", "username": "clayfolk.studio", "phone_number": "639176667788", "sex": "Female", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000007', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000007', 'email', 'clayfolk.studio@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000051', 'authenticated', 'authenticated', 'juan.delacruz@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Juan Dela Cruz", "username": "juan.delacruz", "phone_number": "639201234567", "sex": "Male", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000051', 'a0000000-0000-4000-8000-000000000051', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000051', 'email', 'juan.delacruz@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000052', 'authenticated', 'authenticated', 'bea.lim@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Bea Lim", "username": "bea.lim", "phone_number": "639211234567", "sex": "Female", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000052', 'a0000000-0000-4000-8000-000000000052', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000052', 'email', 'bea.lim@crafthive.test', 'email_verified', true), now(), now(), now());
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000053', 'authenticated', 'authenticated', 'miguel.tan@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"full_name": "Miguel Tan", "username": "miguel.tan", "phone_number": "639221234567", "sex": "Male", "country": "Philippines"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000053', 'a0000000-0000-4000-8000-000000000053', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000053', 'email', 'miguel.tan@crafthive.test', 'email_verified', true), now(), now(), now());

-- One staff account (outside the USER hierarchy)
insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at, confirmation_token, recovery_token,
  email_change, email_change_token_new, email_change_token_current, phone_change, phone_change_token, reauthentication_token)
values ('00000000-0000-0000-0000-000000000000', 'a0000000-0000-4000-8000-000000000099', 'authenticated', 'authenticated', 'admin@crafthive.test',
  extensions.crypt('craftlover8', extensions.gen_salt('bf')), now(),
  '{"provider":"email","providers":["email"]}', '{"role_hint": "admin"}', now() - interval '60 days', now(), '', '', '', '', '', '', '', '');
insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
values (gen_random_uuid(), 'a0000000-0000-4000-8000-000000000099', 'a0000000-0000-4000-8000-000000000099', 'email',
  jsonb_build_object('sub', 'a0000000-0000-4000-8000-000000000099', 'email', 'admin@crafthive.test', 'email_verified', true), now(), now(), now());
insert into public.admin (admin_id, auth_uid, first_name, last_name, email, role)
values ('e0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000099', 'CraftHive', 'Admin', 'admin@crafthive.test', 'superadmin');

-- Sellers and their stores
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000001', 'verified', 'e0000000-0000-4000-8000-000000000001', now() - interval '30 days');
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000002', 'verified', 'e0000000-0000-4000-8000-000000000001', now() - interval '30 days');
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000003', 'verified', 'e0000000-0000-4000-8000-000000000001', now() - interval '30 days');
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000004', 'pending', null, null);
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000005', 'verified', 'e0000000-0000-4000-8000-000000000001', now() - interval '30 days');
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000006', 'verified', 'e0000000-0000-4000-8000-000000000001', now() - interval '30 days');
insert into public.seller (user_id, verification_status, verified_by, verified_at) values ('a0000000-0000-4000-8000-000000000007', 'unverified', null, null);
insert into public.store (store_id, seller_id, store_name, store_description, address, city, postal_code, latitude, longitude, weekly_capacity) values
  ('b0000000-0000-4000-8000-000000000001', 'a0000000-0000-4000-8000-000000000001', 'Ana Makes Crochet', 'Crochet bags, keychains and small gifts, made by hand. Custom colors and names welcome; most orders ready in 3 to 5 days.', '12 Mango Avenue', 'Cebu City', '6000', 10.3157, 123.8854, 10),
  ('b0000000-0000-4000-8000-000000000002', 'a0000000-0000-4000-8000-000000000002', 'Narra Craft Co.', 'Kitchen tools and home pieces carved from reclaimed narra and acacia. Engraving available on most items.', '45 Session Road', 'Baguio City', '2600', 16.4119, 120.596, 10),
  ('b0000000-0000-4000-8000-000000000003', 'a0000000-0000-4000-8000-000000000003', 'Petal & Twine', 'Hand-tied bouquets for graduations, birthdays and just because. Same-day pickup in QC.', '88 Maginhawa Street', 'Quezon City', '1101', 14.6507, 121.057, 10),
  ('b0000000-0000-4000-8000-000000000004', 'a0000000-0000-4000-8000-000000000004', 'LayerLab PH', 'Small 3D-printed gifts, planters and keychains. Send us your idea and we will print it.', '201 Jupiter Street', 'Makati City', '1209', 14.564, 121.03, 10),
  ('b0000000-0000-4000-8000-000000000005', 'a0000000-0000-4000-8000-000000000005', 'Thread & Ink Tees', 'Custom printed shirts for barkadas, events and small businesses. No minimum order.', '9 Caruncho Avenue', 'Pasig City', '1600', 14.5605, 121.079, 10),
  ('b0000000-0000-4000-8000-000000000006', 'a0000000-0000-4000-8000-000000000006', 'Wick & Wax MNL', 'Soy candles in Filipino scents: calamansi, sampaguita and kapeng barako.', '1150 Taft Avenue', 'Manila', '1000', 14.5786, 120.9847, 10),
  ('b0000000-0000-4000-8000-000000000007', 'a0000000-0000-4000-8000-000000000007', 'Clayfolk Studio', 'Hand-thrown mugs and bowls fired in small batches.', '27 Quimpo Boulevard', 'Davao City', '8000', 7.0731, 125.6128, 10);

-- Products and their custom-order options
insert into public.product (product_id, store_id, category_id, title, description, price, stock_quantity, lead_time_days, has_custom_option, created_at) values
  ('d0000000-0000-4000-8000-000000000001', 'b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'Hand-carved Wooden Spoon', 'Carved from one piece of reclaimed narra wood and finished with food-safe coconut oil. Every spoon has its own grain, so yours will look slightly different. 25 cm long.', 350, 12, 6, true, now() - interval '40 days'),
  ('d0000000-0000-4000-8000-000000000002', 'b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', 'Hand-tied Sunflower Bouquet', 'Three fresh sunflowers with baby''s breath and eucalyptus, wrapped in kraft paper and twine. Lasts about a week in water.', 450, 6, 1, true, now() - interval '39 days'),
  ('d0000000-0000-4000-8000-000000000003', 'b0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000002', '3D-Printed Mini Planter', 'Geometric planter printed in plant-based PLA, with a drainage hole and a small tray. Fits succulents up to 7 cm wide.', 280, 15, 2, true, now() - interval '38 days'),
  ('d0000000-0000-4000-8000-000000000004', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000005', 'Crochet Tote Bag', 'Roomy tote in sage cotton yarn, lined inside. Fits a laptop up to 13 inches.', 680, 8, 4, true, now() - interval '37 days'),
  ('d0000000-0000-4000-8000-000000000005', 'b0000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000006', 'Soy Candle, Calamansi', '180 g soy wax candle with a cotton wick and a bright calamansi scent. Burns for about 35 hours.', 220, 20, 3, true, now() - interval '36 days'),
  ('d0000000-0000-4000-8000-000000000006', 'b0000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000004', 'Custom Name Shirt', 'Soft cotton shirt printed with your name or design. Sizes XS to 3XL.', 390, 0, 3, true, now() - interval '35 days'),
  ('d0000000-0000-4000-8000-000000000007', 'b0000000-0000-4000-8000-000000000003', 'c0000000-0000-4000-8000-000000000001', 'Graduation Bouquet', 'Roses, chrysanthemums and a satin ribbon in your school colors. Order 2 days before the ceremony.', 650, 4, 1, true, now() - interval '34 days'),
  ('d0000000-0000-4000-8000-000000000008', 'b0000000-0000-4000-8000-000000000002', 'c0000000-0000-4000-8000-000000000003', 'Narra Serving Board', 'Long serving board with a juice groove, finished with food-safe oil. 45 × 20 cm.', 890, 5, 2, false, now() - interval '33 days'),
  ('d0000000-0000-4000-8000-000000000009', 'b0000000-0000-4000-8000-000000000004', 'c0000000-0000-4000-8000-000000000002', 'Articulated Dragon Keychain', 'Flexible printed dragon that wiggles and bends. 12 cm long with a metal key ring.', 180, 25, 1, false, now() - interval '32 days'),
  ('d0000000-0000-4000-8000-000000000010', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000005', 'Sunflower Keychain', 'Small crochet sunflower on a gold-tone key ring. A cheerful little gift.', 120, 2, 2, false, now() - interval '31 days'),
  ('d0000000-0000-4000-8000-000000000011', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000008', 'Name Bracelet, Beaded', 'Glass-bead bracelet with letter beads spelling any name up to 10 letters.', 150, 0, 3, true, now() - interval '30 days'),
  ('d0000000-0000-4000-8000-000000000012', 'b0000000-0000-4000-8000-000000000001', 'c0000000-0000-4000-8000-000000000005', 'Mini Crochet Bouquet', 'Three crochet tulips that never wilt, wrapped like a real bouquet.', 390, 0, 5, false, now() - interval '29 days'),
  ('d0000000-0000-4000-8000-000000000013', 'b0000000-0000-4000-8000-000000000006', 'c0000000-0000-4000-8000-000000000006', 'Lavender Candle Set', 'Set of three 80 g lavender soy candles in amber jars. A calming gift.', 480, 9, 2, false, now() - interval '28 days'),
  ('d0000000-0000-4000-8000-000000000014', 'b0000000-0000-4000-8000-000000000005', 'c0000000-0000-4000-8000-000000000004', 'Barkada Tees, Set of 5', 'Five matching printed shirts for your group trip or event.', 1750, 0, 4, true, now() - interval '27 days'),
  ('d0000000-0000-4000-8000-000000000015', 'b0000000-0000-4000-8000-000000000007', 'c0000000-0000-4000-8000-000000000007', 'Hand-thrown Mug', 'Stoneware mug with a speckled glaze. Holds about 350 ml. Microwave safe.', 520, 7, 3, false, now() - interval '26 days');
insert into public.product_custom_option (product_id, label) values
  ('d0000000-0000-4000-8000-000000000001', 'Engraving'),
  ('d0000000-0000-4000-8000-000000000001', 'Size'),
  ('d0000000-0000-4000-8000-000000000001', 'Wood type'),
  ('d0000000-0000-4000-8000-000000000001', 'Finish'),
  ('d0000000-0000-4000-8000-000000000002', 'Flower color'),
  ('d0000000-0000-4000-8000-000000000002', 'Wrapper'),
  ('d0000000-0000-4000-8000-000000000002', 'Message card'),
  ('d0000000-0000-4000-8000-000000000003', 'Color'),
  ('d0000000-0000-4000-8000-000000000003', 'Size'),
  ('d0000000-0000-4000-8000-000000000003', 'Name engraving'),
  ('d0000000-0000-4000-8000-000000000004', 'Color'),
  ('d0000000-0000-4000-8000-000000000004', 'Size'),
  ('d0000000-0000-4000-8000-000000000004', 'Name tag'),
  ('d0000000-0000-4000-8000-000000000005', 'Scent'),
  ('d0000000-0000-4000-8000-000000000005', 'Label text'),
  ('d0000000-0000-4000-8000-000000000006', 'Text'),
  ('d0000000-0000-4000-8000-000000000006', 'Shirt color'),
  ('d0000000-0000-4000-8000-000000000006', 'Size'),
  ('d0000000-0000-4000-8000-000000000006', 'Print side'),
  ('d0000000-0000-4000-8000-000000000007', 'Flower color'),
  ('d0000000-0000-4000-8000-000000000007', 'Ribbon text'),
  ('d0000000-0000-4000-8000-000000000007', 'Add a bear'),
  ('d0000000-0000-4000-8000-000000000011', 'Name'),
  ('d0000000-0000-4000-8000-000000000011', 'Bead color'),
  ('d0000000-0000-4000-8000-000000000014', 'Text'),
  ('d0000000-0000-4000-8000-000000000014', 'Shirt color'),
  ('d0000000-0000-4000-8000-000000000014', 'Sizes');

-- Completed orders with reviews, so ratings and items sold come from real records
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000001', 'CH-2026-000001', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000002', now() - interval '36 days', 1050, 'completed', (now() - interval '29 days')::date, now() - interval '29 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 3, 350);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000001', 'd0000000-0000-4000-8000-000000000001', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000002', 'CH-2026-000002', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000002', now() - interval '35 days', 700, 'completed', (now() - interval '28 days')::date, now() - interval '28 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 2, 350);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000002', 'd0000000-0000-4000-8000-000000000001', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000003', 'CH-2026-000003', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000002', now() - interval '34 days', 350, 'completed', (now() - interval '27 days')::date, now() - interval '27 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 1, 350);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000003', 'd0000000-0000-4000-8000-000000000001', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000004', 'CH-2026-000004', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000003', now() - interval '33 days', 900, 'completed', (now() - interval '26 days')::date, now() - interval '26 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000002', 2, 450);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000004', 'd0000000-0000-4000-8000-000000000002', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000005', 'CH-2026-000005', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000003', now() - interval '32 days', 450, 'completed', (now() - interval '25 days')::date, now() - interval '25 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000002', 1, 450);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000005', 'd0000000-0000-4000-8000-000000000002', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000006', 'CH-2026-000006', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000003', now() - interval '31 days', 900, 'completed', (now() - interval '24 days')::date, now() - interval '24 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000002', 2, 450);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000006', 'd0000000-0000-4000-8000-000000000002', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000007', 'CH-2026-000007', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000004', now() - interval '30 days', 560, 'completed', (now() - interval '23 days')::date, now() - interval '23 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000003', 2, 280);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000007', 'd0000000-0000-4000-8000-000000000003', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000008', 'CH-2026-000008', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000004', now() - interval '29 days', 560, 'completed', (now() - interval '22 days')::date, now() - interval '22 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000003', 2, 280);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000008', 'd0000000-0000-4000-8000-000000000003', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000009', 'CH-2026-000009', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000004', now() - interval '28 days', 280, 'completed', (now() - interval '21 days')::date, now() - interval '21 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000003', 1, 280);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000009', 'd0000000-0000-4000-8000-000000000003', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000010', 'CH-2026-000010', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000001', now() - interval '27 days', 680, 'completed', (now() - interval '20 days')::date, now() - interval '20 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000004', 1, 680);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000010', 'd0000000-0000-4000-8000-000000000004', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000011', 'CH-2026-000011', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000001', now() - interval '26 days', 680, 'completed', (now() - interval '19 days')::date, now() - interval '19 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000011', 'd0000000-0000-4000-8000-000000000004', 1, 680);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000011', 'd0000000-0000-4000-8000-000000000004', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000012', 'CH-2026-000012', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000006', now() - interval '25 days', 880, 'completed', (now() - interval '18 days')::date, now() - interval '18 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000012', 'd0000000-0000-4000-8000-000000000005', 4, 220);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000012', 'd0000000-0000-4000-8000-000000000005', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000013', 'CH-2026-000013', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000006', now() - interval '24 days', 660, 'completed', (now() - interval '17 days')::date, now() - interval '17 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000013', 'd0000000-0000-4000-8000-000000000005', 3, 220);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000013', 'd0000000-0000-4000-8000-000000000005', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000014', 'CH-2026-000014', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000006', now() - interval '23 days', 440, 'completed', (now() - interval '16 days')::date, now() - interval '16 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000014', 'd0000000-0000-4000-8000-000000000005', 2, 220);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000014', 'd0000000-0000-4000-8000-000000000005', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000015', 'CH-2026-000015', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000005', now() - interval '22 days', 780, 'completed', (now() - interval '15 days')::date, now() - interval '15 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000015', 'd0000000-0000-4000-8000-000000000006', 2, 390);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000015', 'd0000000-0000-4000-8000-000000000006', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000016', 'CH-2026-000016', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000005', now() - interval '21 days', 1170, 'completed', (now() - interval '14 days')::date, now() - interval '14 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000016', 'd0000000-0000-4000-8000-000000000006', 3, 390);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000016', 'd0000000-0000-4000-8000-000000000006', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000017', 'CH-2026-000017', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000003', now() - interval '20 days', 650, 'completed', (now() - interval '13 days')::date, now() - interval '13 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000017', 'd0000000-0000-4000-8000-000000000007', 1, 650);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000017', 'd0000000-0000-4000-8000-000000000007', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000018', 'CH-2026-000018', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000003', now() - interval '19 days', 650, 'completed', (now() - interval '12 days')::date, now() - interval '12 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000018', 'd0000000-0000-4000-8000-000000000007', 1, 650);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000018', 'd0000000-0000-4000-8000-000000000007', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000019', 'CH-2026-000019', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000003', now() - interval '18 days', 650, 'completed', (now() - interval '11 days')::date, now() - interval '11 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000019', 'd0000000-0000-4000-8000-000000000007', 1, 650);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000019', 'd0000000-0000-4000-8000-000000000007', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000020', 'CH-2026-000020', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000002', now() - interval '37 days', 890, 'completed', (now() - interval '30 days')::date, now() - interval '30 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000020', 'd0000000-0000-4000-8000-000000000008', 1, 890);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000020', 'd0000000-0000-4000-8000-000000000008', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000021', 'CH-2026-000021', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000002', now() - interval '36 days', 890, 'completed', (now() - interval '29 days')::date, now() - interval '29 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000021', 'd0000000-0000-4000-8000-000000000008', 1, 890);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000021', 'd0000000-0000-4000-8000-000000000008', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000022', 'CH-2026-000022', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000004', now() - interval '35 days', 540, 'completed', (now() - interval '28 days')::date, now() - interval '28 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000022', 'd0000000-0000-4000-8000-000000000009', 3, 180);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000022', 'd0000000-0000-4000-8000-000000000009', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000023', 'CH-2026-000023', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000004', now() - interval '34 days', 720, 'completed', (now() - interval '27 days')::date, now() - interval '27 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000023', 'd0000000-0000-4000-8000-000000000009', 4, 180);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000023', 'd0000000-0000-4000-8000-000000000009', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000024', 'CH-2026-000024', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000004', now() - interval '33 days', 360, 'completed', (now() - interval '26 days')::date, now() - interval '26 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000024', 'd0000000-0000-4000-8000-000000000009', 2, 180);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000024', 'd0000000-0000-4000-8000-000000000009', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000025', 'CH-2026-000025', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000001', now() - interval '32 days', 240, 'completed', (now() - interval '25 days')::date, now() - interval '25 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000025', 'd0000000-0000-4000-8000-000000000010', 2, 120);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000025', 'd0000000-0000-4000-8000-000000000010', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000026', 'CH-2026-000026', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000001', now() - interval '31 days', 360, 'completed', (now() - interval '24 days')::date, now() - interval '24 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000026', 'd0000000-0000-4000-8000-000000000010', 3, 120);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000026', 'd0000000-0000-4000-8000-000000000010', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000027', 'CH-2026-000027', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000001', now() - interval '30 days', 150, 'completed', (now() - interval '23 days')::date, now() - interval '23 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000027', 'd0000000-0000-4000-8000-000000000011', 1, 150);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000027', 'd0000000-0000-4000-8000-000000000011', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000028', 'CH-2026-000028', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000001', now() - interval '29 days', 300, 'completed', (now() - interval '22 days')::date, now() - interval '22 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000028', 'd0000000-0000-4000-8000-000000000011', 2, 150);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000028', 'd0000000-0000-4000-8000-000000000011', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000029', 'CH-2026-000029', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000001', now() - interval '28 days', 150, 'completed', (now() - interval '21 days')::date, now() - interval '21 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000029', 'd0000000-0000-4000-8000-000000000011', 1, 150);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000029', 'd0000000-0000-4000-8000-000000000011', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000030', 'CH-2026-000030', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000001', now() - interval '27 days', 390, 'completed', (now() - interval '20 days')::date, now() - interval '20 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000030', 'd0000000-0000-4000-8000-000000000012', 1, 390);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000030', 'd0000000-0000-4000-8000-000000000012', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000031', 'CH-2026-000031', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000006', now() - interval '26 days', 480, 'completed', (now() - interval '19 days')::date, now() - interval '19 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000031', 'd0000000-0000-4000-8000-000000000013', 1, 480);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000031', 'd0000000-0000-4000-8000-000000000013', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000032', 'CH-2026-000032', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000006', now() - interval '25 days', 480, 'completed', (now() - interval '18 days')::date, now() - interval '18 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000032', 'd0000000-0000-4000-8000-000000000013', 1, 480);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000032', 'd0000000-0000-4000-8000-000000000013', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000033', 'CH-2026-000033', 'a0000000-0000-4000-8000-000000000053', 'b0000000-0000-4000-8000-000000000006', now() - interval '24 days', 960, 'completed', (now() - interval '17 days')::date, now() - interval '17 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000033', 'd0000000-0000-4000-8000-000000000013', 2, 480);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000033', 'd0000000-0000-4000-8000-000000000013', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000034', 'CH-2026-000034', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000005', now() - interval '23 days', 1750, 'completed', (now() - interval '16 days')::date, now() - interval '16 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000034', 'd0000000-0000-4000-8000-000000000014', 1, 1750);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000034', 'd0000000-0000-4000-8000-000000000014', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000035', 'CH-2026-000035', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000005', now() - interval '22 days', 1750, 'completed', (now() - interval '15 days')::date, now() - interval '15 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000035', 'd0000000-0000-4000-8000-000000000014', 1, 1750);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000035', 'd0000000-0000-4000-8000-000000000014', 4, 'Good quality, took a little longer than expected.');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000036', 'CH-2026-000036', 'a0000000-0000-4000-8000-000000000051', 'b0000000-0000-4000-8000-000000000007', now() - interval '21 days', 520, 'completed', (now() - interval '14 days')::date, now() - interval '14 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000036', 'd0000000-0000-4000-8000-000000000015', 1, 520);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000036', 'd0000000-0000-4000-8000-000000000015', 5, 'Lovely work, thank you!');
insert into public.orders (order_id, order_number, buyer_id, store_id, order_date, total_amount, status, due_date, completed_at) values ('f0000000-0000-4000-8000-000000000037', 'CH-2026-000037', 'a0000000-0000-4000-8000-000000000052', 'b0000000-0000-4000-8000-000000000007', now() - interval '20 days', 1040, 'completed', (now() - interval '13 days')::date, now() - interval '13 days');
insert into public.order_item (order_id, product_id, quantity, price_at_purchase) values ('f0000000-0000-4000-8000-000000000037', 'd0000000-0000-4000-8000-000000000015', 2, 520);
insert into public.review (order_id, product_id, rating, comment) values ('f0000000-0000-4000-8000-000000000037', 'd0000000-0000-4000-8000-000000000015', 4, 'Good quality, took a little longer than expected.');
select setval('public.order_number_seq', 37);

