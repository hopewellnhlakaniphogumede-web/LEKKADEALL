create extension if not exists pgcrypto;

create type public.user_role as enum ('customer','provider','support','admin');
create type public.request_status as enum ('draft','open','awarded','cancelled','expired');
create type public.bid_status as enum ('submitted','accepted','declined','withdrawn','expired');
create type public.booking_status as enum ('payment_pending','funded','scheduled','in_progress','completed','cancelled','disputed','refunded','partially_refunded','payout_released');
create type public.verification_status as enum ('not_started','pending','verified','manual_review','rejected','expired');
create type public.dispute_status as enum ('open','awaiting_customer','awaiting_provider','under_review','resolved','appealed','closed');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  role public.user_role not null default 'customer',
  display_name text not null check (char_length(display_name) between 2 and 100),
  phone_e164 text,
  phone_verified_at timestamptz,
  email_verified_at timestamptz,
  suburb text,
  city text not null default 'Potchefstroom',
  avatar_path text,
  account_status text not null default 'active' check (account_status in ('active','restricted','suspended','closed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.provider_profiles (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  business_name text not null,
  bio text,
  service_radius_km numeric(6,2) check (service_radius_km between 0 and 250),
  verification_status public.verification_status not null default 'not_started',
  verification_reference text,
  bank_name_match boolean,
  review_status text not null default 'pending' check (review_status in ('pending','approved','rejected','suspended')),
  reviewed_by uuid references public.profiles(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.service_categories (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  active boolean not null default true,
  requires_manual_review boolean not null default false,
  created_at timestamptz not null default now()
);

create table public.provider_services (
  provider_id uuid not null references public.provider_profiles(user_id) on delete cascade,
  category_id uuid not null references public.service_categories(id),
  description text,
  base_price_minor integer check (base_price_minor >= 0),
  active boolean not null default true,
  primary key (provider_id, category_id)
);

create table public.service_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles(id),
  category_id uuid not null references public.service_categories(id),
  title text not null check (char_length(title) between 3 and 120),
  description text not null check (char_length(description) between 10 and 3000),
  suburb text not null,
  city text not null,
  precise_address_ciphertext text,
  requested_start timestamptz not null,
  budget_minor integer check (budget_minor is null or budget_minor >= 0),
  status public.request_status not null default 'draft',
  closes_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.bids (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests(id) on delete cascade,
  provider_id uuid not null references public.provider_profiles(user_id),
  amount_minor integer not null check (amount_minor > 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  proposed_start timestamptz not null,
  message text check (char_length(message) <= 1500),
  perks text[] not null default '{}',
  status public.bid_status not null default 'submitted',
  expires_at timestamptz not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(request_id, provider_id)
);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  public_reference text not null unique,
  request_id uuid not null unique references public.service_requests(id),
  bid_id uuid not null unique references public.bids(id),
  customer_id uuid not null references public.profiles(id),
  provider_id uuid not null references public.provider_profiles(user_id),
  service_amount_minor integer not null check (service_amount_minor > 0),
  platform_fee_minor integer not null check (platform_fee_minor >= 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  scheduled_start timestamptz not null,
  status public.booking_status not null default 'payment_pending',
  completion_confirmed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (customer_id <> provider_id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id),
  provider_name text not null,
  provider_reference text unique,
  status text not null,
  amount_minor integer not null check (amount_minor > 0),
  currency char(3) not null default 'ZAR' check (currency = 'ZAR'),
  release_paused boolean not null default false,
  funded_at timestamptz,
  released_at timestamptz,
  refunded_minor integer not null default 0 check (refunded_minor >= 0 and refunded_minor <= amount_minor),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.vendor_events (
  id uuid primary key default gen_random_uuid(),
  provider_name text not null,
  provider_event_id text not null,
  event_type text not null,
  related_reference text,
  payload_hash text not null,
  processed_at timestamptz,
  received_at timestamptz not null default now(),
  unique(provider_name, provider_event_id)
);

create table public.identity_verifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  provider_name text not null,
  provider_reference text not null unique,
  status public.verification_status not null,
  assurance_level text,
  failure_codes text[] not null default '{}',
  consent_version text not null,
  consent_recorded_at timestamptz not null,
  completed_at timestamptz,
  deletion_requested_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  public_reference text not null unique,
  booking_id uuid not null references public.bookings(id),
  opened_by uuid not null references public.profiles(id),
  issue_code text not null,
  description text not null check (char_length(description) between 10 and 5000),
  status public.dispute_status not null default 'open',
  assigned_to uuid references public.profiles(id),
  outcome_code text,
  outcome_reason text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.dispute_evidence (
  id uuid primary key default gen_random_uuid(),
  dispute_id uuid not null references public.disputes(id) on delete cascade,
  uploaded_by uuid not null references public.profiles(id),
  storage_path text not null,
  media_type text not null,
  sha256 text not null,
  created_at timestamptz not null default now()
);

create table public.reviews (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id),
  reviewer_id uuid not null references public.profiles(id),
  subject_id uuid not null references public.profiles(id),
  rating smallint not null check (rating between 1 and 5),
  body text check (char_length(body) <= 2000),
  moderation_status text not null default 'published' check (moderation_status in ('published','hidden','under_review','removed')),
  created_at timestamptz not null default now(),
  unique(booking_id, reviewer_id),
  check (reviewer_id <> subject_id)
);

create table public.consents (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  purpose text not null,
  policy_version text not null,
  granted boolean not null,
  source text not null,
  recorded_at timestamptz not null default now(),
  withdrawn_at timestamptz
);

create table public.data_subject_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id),
  request_type text not null check (request_type in ('access','correction','deletion','objection','marketing_opt_out')),
  status text not null default 'received' check (status in ('received','identity_check','in_progress','completed','refused')),
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.audit_events (
  id bigint generated always as identity primary key,
  actor_id uuid references public.profiles(id),
  action text not null,
  object_type text not null,
  object_id text,
  reason text,
  metadata jsonb not null default '{}',
  occurred_at timestamptz not null default now()
);

create index requests_open_idx on public.service_requests(category_id, city, requested_start) where status='open';
create index bids_request_idx on public.bids(request_id, status, amount_minor);
create index bookings_customer_idx on public.bookings(customer_id, created_at desc);
create index bookings_provider_idx on public.bookings(provider_id, created_at desc);
create index disputes_booking_idx on public.disputes(booking_id, status);
create index audit_object_idx on public.audit_events(object_type, object_id, occurred_at desc);

alter table public.profiles enable row level security;
alter table public.provider_profiles enable row level security;
alter table public.service_requests enable row level security;
alter table public.bids enable row level security;
alter table public.bookings enable row level security;
alter table public.payments enable row level security;
alter table public.identity_verifications enable row level security;
alter table public.disputes enable row level security;
alter table public.dispute_evidence enable row level security;
alter table public.reviews enable row level security;
alter table public.consents enable row level security;
alter table public.data_subject_requests enable row level security;
alter table public.audit_events enable row level security;

create policy "profile owner reads self" on public.profiles for select using (auth.uid()=id);
create policy "profile owner updates self" on public.profiles for update using (auth.uid()=id) with check (auth.uid()=id);
create policy "approved providers are discoverable" on public.provider_profiles for select using (review_status='approved' or auth.uid()=user_id);
create policy "provider owns provider profile" on public.provider_profiles for update using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "customer owns requests" on public.service_requests for all using (auth.uid()=customer_id) with check (auth.uid()=customer_id);
create policy "providers see open requests" on public.service_requests for select using (status='open');
create policy "provider owns bids" on public.bids for all using (auth.uid()=provider_id) with check (auth.uid()=provider_id);
create policy "customer sees request bids" on public.bids for select using (exists(select 1 from public.service_requests r where r.id=request_id and r.customer_id=auth.uid()));
create policy "booking parties read bookings" on public.bookings for select using (auth.uid() in (customer_id,provider_id));
create policy "booking customer reads payment" on public.payments for select using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.customer_id,b.provider_id)));
create policy "user reads identity status" on public.identity_verifications for select using (auth.uid()=user_id);
create policy "dispute parties read cases" on public.disputes for select using (exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.customer_id,b.provider_id)));
create policy "party opens dispute" on public.disputes for insert with check (auth.uid()=opened_by and exists(select 1 from public.bookings b where b.id=booking_id and auth.uid() in (b.customer_id,b.provider_id)));
create policy "evidence owner inserts" on public.dispute_evidence for insert with check (auth.uid()=uploaded_by);
create policy "booking parties read evidence" on public.dispute_evidence for select using (exists(select 1 from public.disputes d join public.bookings b on b.id=d.booking_id where d.id=dispute_id and auth.uid() in (b.customer_id,b.provider_id)));
create policy "published reviews visible" on public.reviews for select using (moderation_status='published' or auth.uid()=reviewer_id);
create policy "reviewer creates review" on public.reviews for insert with check (auth.uid()=reviewer_id and exists(select 1 from public.bookings b where b.id=booking_id and b.status in ('completed','payout_released') and auth.uid() in (b.customer_id,b.provider_id)));
create policy "user controls consent" on public.consents for all using (auth.uid()=user_id) with check (auth.uid()=user_id);
create policy "user controls privacy requests" on public.data_subject_requests for all using (auth.uid()=user_id) with check (auth.uid()=user_id);

-- Privileged support/admin access is deliberately absent from client RLS.
-- It must use server-side functions with explicit role checks and append audit_events.
-- Clients receive no policy for vendor_events or audit_events.
