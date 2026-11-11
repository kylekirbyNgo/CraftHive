-- =============================================================================
-- CraftHive Marketplace – PostgreSQL schema (Supabase)
-- Based on the ITCC 33 Milestone II data dictionary (22 tables).
--
-- Change from the paper: sign-in uses Supabase Auth instead of Firebase Auth,
-- so users.user_id and admin.auth_uid hold the Supabase Auth user ID
-- (auth.users.id) in place of firebase_uid.
--
-- USER and ORDER are reserved words in PostgreSQL, so those tables are named
-- users and orders.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Status values (Table 2.5)
-- ---------------------------------------------------------------------------
-- seller.verification_status : unverified, pending, verified, rejected
-- custom_request.status      : pending, quoted, accepted, declined, cancelled
-- quote.status               : sent, accepted, changes_requested, declined, superseded
-- orders.status              : pending, confirmed, in_production, shipped, delivered, completed, cancelled
-- payment.status             : submitted, verified, rejected
-- dispute.status             : open, under_review, resolved, closed

create sequence if not exists public.custom_request_number_seq start 1001;
create sequence if not exists public.order_number_seq start 1;

-- 1. USER -------------------------------------------------------------------
create table public.users (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  full_name     varchar(100) not null check (length(trim(full_name)) between 2 and 100),
  email         varchar(100) not null unique check (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  username      varchar(50)  not null unique check (username ~ '^[a-z0-9._]{4,20}$'),
  phone_number  varchar(20)  not null check (phone_number ~ '^[0-9]{7,15}$'),
  sex           varchar(20)  check (sex in ('Female', 'Male', 'Prefer not to say')),
  country       varchar(50)  not null,
  avatar_path   varchar(255),
  created_at    timestamptz  not null default now()
);

-- 4. ADMIN (separate from the USER hierarchy) --------------------------------
create table public.admin (
  admin_id    uuid primary key default gen_random_uuid(),
  auth_uid    uuid not null unique references auth.users (id) on delete cascade,
  first_name  varchar(50)  not null,
  last_name   varchar(50)  not null,
  email       varchar(100) not null unique,
  role        varchar(20)  not null default 'moderator' check (role in ('moderator', 'superadmin')),
  created_at  timestamptz  not null default now()
);

-- 2. BUYER (every user) ------------------------------------------------------
create table public.buyer (
  user_id uuid primary key references public.users (user_id) on delete cascade
);

-- 3. SELLER (users who open a store) -----------------------------------------
create table public.seller (
  user_id              uuid primary key references public.users (user_id) on delete cascade,
  verified_by          uuid references public.admin (admin_id) on delete set null,
  verification_status  varchar(20) not null default 'unverified'
                       check (verification_status in ('unverified', 'pending', 'verified', 'rejected')),
  verified_at          timestamptz,
  id_image_path        varchar(255),
  id_purge_date        date
);

-- 5. STORE -------------------------------------------------------------------
create table public.store (
  store_id           uuid primary key default gen_random_uuid(),
  seller_id          uuid not null unique references public.seller (user_id) on delete cascade,
  store_name         varchar(100) not null,
  store_description  text,
  address            varchar(255) not null,
  city               varchar(50)  not null,
  postal_code        char(4)      not null check (postal_code ~ '^[0-9]{4}$'),
  latitude           numeric(9,6) check (latitude between -90 and 90),
  longitude          numeric(9,6) check (longitude between -180 and 180),
  weekly_capacity    int          not null check (weekly_capacity > 0),
  rating             numeric(3,2) not null default 0 check (rating between 0 and 5),
  items_sold_count   int          not null default 0 check (items_sold_count >= 0),
  is_archived        boolean      not null default false
);

-- 6. CATEGORY ----------------------------------------------------------------
create table public.category (
  category_id    uuid primary key default gen_random_uuid(),
  category_name  varchar(50) not null unique,
  description    text
);

-- 7. PRODUCT -----------------------------------------------------------------
create table public.product (
  product_id         uuid primary key default gen_random_uuid(),
  store_id           uuid not null references public.store (store_id) on delete cascade,
  category_id        uuid not null references public.category (category_id),
  title              varchar(100) not null check (length(trim(title)) >= 3),
  description        text,
  price              numeric(10,2) not null check (price > 0),
  stock_quantity     int not null default 0 check (stock_quantity >= 0),
  lead_time_days     int not null check (lead_time_days > 0),
  has_custom_option  boolean not null default false,
  is_draft           boolean not null default false,
  is_archived        boolean not null default false,
  created_at         timestamptz not null default now()
);

-- 8. PRODUCT_IMAGE -----------------------------------------------------------
create table public.product_image (
  image_id    uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.product (product_id) on delete cascade,
  image_path  varchar(255) not null,
  sort_order  int not null check (sort_order between 1 and 5),
  unique (product_id, sort_order)
);

-- 16. PRODUCT_CUSTOM_OPTION --------------------------------------------------
create table public.product_custom_option (
  option_id   uuid primary key default gen_random_uuid(),
  product_id  uuid not null references public.product (product_id) on delete cascade,
  label       varchar(50) not null,
  unique (product_id, label)
);

-- 9. CUSTOM_REQUEST ----------------------------------------------------------
create table public.custom_request (
  request_id      uuid primary key default gen_random_uuid(),
  request_number  varchar(20) not null unique
                  default ('CR-' || nextval('public.custom_request_number_seq')),
  buyer_id        uuid not null references public.buyer (user_id),
  product_id      uuid not null references public.product (product_id),
  description     text not null check (length(description) between 1 and 500),
  quantity        int not null check (quantity > 0),
  budget          numeric(10,2) check (budget > 0),
  needed_by_date  date not null,
  status          varchar(20) not null default 'pending'
                  check (status in ('pending', 'quoted', 'accepted', 'declined', 'cancelled')),
  created_at      timestamptz not null default now()
);

-- 10. CUSTOM_REQUEST_IMAGE ---------------------------------------------------
create table public.custom_request_image (
  request_image_id  uuid primary key default gen_random_uuid(),
  request_id        uuid not null references public.custom_request (request_id) on delete cascade,
  image_path        varchar(255) not null
);

-- 17. CUSTOM_REQUEST_OPTION --------------------------------------------------
create table public.custom_request_option (
  request_id  uuid not null references public.custom_request (request_id) on delete cascade,
  option_id   uuid not null references public.product_custom_option (option_id) on delete cascade,
  primary key (request_id, option_id)
);

-- 11. QUOTE ------------------------------------------------------------------
create table public.quote (
  quote_id                   uuid primary key default gen_random_uuid(),
  request_id                 uuid not null references public.custom_request (request_id) on delete cascade,
  version_no                 int not null check (version_no > 0),
  offered_price              numeric(10,2) not null check (offered_price > 0),
  estimated_completion_date  date not null,
  message                    text,
  decline_reason             text,
  status                     varchar(20) not null default 'sent'
                             check (status in ('sent', 'accepted', 'changes_requested', 'declined', 'superseded')),
  created_at                 timestamptz not null default now(),
  unique (request_id, version_no)
);

-- 12. ORDER ------------------------------------------------------------------
create table public.orders (
  order_id                uuid primary key default gen_random_uuid(),
  order_number            varchar(20) not null unique
                          default ('CH-' || to_char(now(), 'YYYY') || '-' || lpad(nextval('public.order_number_seq')::text, 6, '0')),
  buyer_id                uuid not null references public.buyer (user_id),
  store_id                uuid not null references public.store (store_id),
  quote_id                uuid unique references public.quote (quote_id),
  order_date              timestamptz not null default now(),
  total_amount            numeric(10,2) not null check (total_amount > 0),
  status                  varchar(20) not null default 'pending'
                          check (status in ('pending', 'confirmed', 'in_production', 'shipped', 'delivered', 'completed', 'cancelled')),
  due_date                date not null,
  completed_at            timestamptz,
  reservation_expires_at  timestamptz,
  is_archived             boolean not null default false
);

-- 13. ORDER_ITEM -------------------------------------------------------------
create table public.order_item (
  order_item_id      uuid primary key default gen_random_uuid(),
  order_id           uuid not null references public.orders (order_id) on delete cascade,
  product_id         uuid not null references public.product (product_id),
  quantity           int not null check (quantity > 0),
  price_at_purchase  numeric(10,2) not null check (price_at_purchase > 0)
);

-- 14. PAYMENT ----------------------------------------------------------------
create table public.payment (
  payment_id        uuid primary key default gen_random_uuid(),
  order_id          uuid not null references public.orders (order_id) on delete cascade,
  reference_number  varchar(50) not null unique,
  proof_image_path  varchar(255) not null,
  proof_image_hash  varchar(64) not null unique,
  amount_paid       numeric(10,2) not null check (amount_paid > 0),
  status            varchar(20) not null default 'submitted' check (status in ('submitted', 'verified', 'rejected')),
  verified_at       timestamptz
);

-- 15. REVIEW -----------------------------------------------------------------
create table public.review (
  review_id   uuid primary key default gen_random_uuid(),
  order_id    uuid not null references public.orders (order_id) on delete cascade,
  product_id  uuid not null references public.product (product_id),
  rating      int not null check (rating between 1 and 5),
  comment     text,
  created_at  timestamptz not null default now(),
  unique (order_id, product_id)
);

-- 18. SELLER_PORTFOLIO_IMAGE -------------------------------------------------
create table public.seller_portfolio_image (
  portfolio_image_id  uuid primary key default gen_random_uuid(),
  seller_id           uuid not null references public.seller (user_id) on delete cascade,
  image_path          varchar(255) not null,
  uploaded_at         timestamptz not null default now()
);

-- 19. CAPACITY_BOOKING -------------------------------------------------------
create table public.capacity_booking (
  booking_id  uuid primary key default gen_random_uuid(),
  store_id    uuid not null references public.store (store_id) on delete cascade,
  order_id    uuid not null unique references public.orders (order_id) on delete cascade,
  week_start  date not null check (extract(isodow from week_start) = 1)
);

-- 20. ORDER_STATUS_HISTORY ---------------------------------------------------
create table public.order_status_history (
  history_id   uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders (order_id) on delete cascade,
  from_status  varchar(20),
  to_status    varchar(20) not null,
  changed_by   uuid references public.users (user_id) on delete set null,
  note         text,
  photo_path   varchar(255),
  changed_at   timestamptz not null default now()
);

-- 21. DISPUTE ----------------------------------------------------------------
create table public.dispute (
  dispute_id   uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.orders (order_id) on delete cascade,
  opened_by    uuid not null references public.users (user_id),
  reason       text not null,
  status       varchar(20) not null default 'open' check (status in ('open', 'under_review', 'resolved', 'closed')),
  resolution   text,
  resolved_by  uuid references public.admin (admin_id) on delete set null,
  opened_at    timestamptz not null default now(),
  resolved_at  timestamptz
);

-- 22. DISPUTE_EVIDENCE -------------------------------------------------------
create table public.dispute_evidence (
  evidence_id  uuid primary key default gen_random_uuid(),
  dispute_id   uuid not null references public.dispute (dispute_id) on delete cascade,
  uploaded_by  uuid not null references public.users (user_id),
  file_path    varchar(255) not null,
  description  text,
  uploaded_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes on foreign keys and common filters
-- ---------------------------------------------------------------------------
create index on public.product (store_id);
create index on public.product (category_id);
create index on public.product (created_at desc) where not is_draft and not is_archived;
create index on public.product_image (product_id);
create index on public.product_custom_option (product_id);
create index on public.custom_request (buyer_id);
create index on public.custom_request (product_id);
create index on public.custom_request_image (request_id);
create index on public.custom_request_option (option_id);
create index on public.quote (request_id);
create index on public.orders (buyer_id);
create index on public.orders (store_id);
create index on public.order_item (order_id);
create index on public.order_item (product_id);
create index on public.payment (order_id);
create index on public.review (product_id);
create index on public.seller (verified_by);
create index on public.seller_portfolio_image (seller_id);
create index on public.capacity_booking (store_id, week_start);
create index on public.order_status_history (order_id);
create index on public.order_status_history (changed_by);
create index on public.dispute (order_id);
create index on public.dispute (opened_by);
create index on public.dispute (resolved_by);
create index on public.dispute_evidence (dispute_id);
create index on public.dispute_evidence (uploaded_by);
