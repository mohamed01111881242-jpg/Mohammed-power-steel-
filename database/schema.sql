-- PostgreSQL starter schema for النظام الخارق للمعارف
-- Apply only after provisioning a PostgreSQL database and configuring secure credentials.
create extension if not exists pgcrypto;

create type account_role as enum ('company','workshop','factory','professional','supplier','customer','admin');
create type request_status as enum ('new','matching','offers_received','in_progress','completed','cancelled');
create type approval_status as enum ('pending','approved','rejected');

create table accounts (
  id uuid primary key default gen_random_uuid(),
  role account_role not null,
  display_name text not null,
  phone_e164 text not null unique,
  governorate text,
  area text,
  description text,
  verified_at timestamptz,
  created_at timestamptz not null default now()
);

create table service_profiles (
  account_id uuid primary key references accounts(id) on delete cascade,
  specialties text[] not null default '{}',
  service_areas text[] not null default '{}',
  capacity_notes text,
  is_listed boolean not null default false
);

create table work_requests (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references accounts(id),
  request_type text not null,
  title text not null,
  details text not null,
  governorate text,
  area text,
  needed_by date,
  status request_status not null default 'new',
  created_at timestamptz not null default now()
);

create table quotations (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references work_requests(id) on delete cascade,
  provider_id uuid not null references accounts(id),
  amount numeric(14,2) check (amount >= 0),
  currency char(3) not null default 'EGP',
  scope text not null,
  valid_until date,
  status approval_status not null default 'pending',
  created_at timestamptz not null default now(),
  unique(request_id, provider_id)
);

create table agreements (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references work_requests(id),
  quotation_id uuid not null references quotations(id),
  customer_approved_at timestamptz,
  provider_approved_at timestamptz,
  admin_approval_status approval_status not null default 'pending',
  approved_by uuid references accounts(id),
  created_at timestamptz not null default now()
);

create table work_updates (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references work_requests(id) on delete cascade,
  author_id uuid not null references accounts(id),
  update_text text not null,
  progress_percent smallint check (progress_percent between 0 and 100),
  created_at timestamptz not null default now()
);

create table financial_approvals (
  id uuid primary key default gen_random_uuid(),
  request_id uuid references work_requests(id),
  submitted_by uuid not null references accounts(id),
  amount numeric(14,2) not null check (amount >= 0),
  currency char(3) not null default 'EGP',
  purpose text not null,
  status approval_status not null default 'pending',
  reviewed_by uuid references accounts(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);

create index work_requests_status_created_idx on work_requests(status, created_at desc);
create index work_requests_area_idx on work_requests(governorate, area);
create index quotations_request_idx on quotations(request_id);
create index work_updates_request_idx on work_updates(request_id, created_at desc);

-- Before production: enforce row-level security on every tenant-owned table,
-- define role policies, audit sensitive changes, and keep secrets out of source control.
