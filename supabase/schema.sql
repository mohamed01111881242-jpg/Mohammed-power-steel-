-- النظام الخارق للمعارف
-- PostgreSQL / Supabase starter schema
-- Apply in a fresh Supabase project using the SQL Editor.
-- This schema stores account data centrally; WhatsApp integration is a later server-side step.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  phone text,
  city text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.organizations (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  account_type text not null check (account_type in ('company','contractor','workshop','factory','professional','supplier','customer')),
  description text,
  city text,
  phone text,
  whatsapp_phone text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.memberships (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  member_role text not null default 'owner' check (member_role in ('owner','admin','manager','staff')),
  created_at timestamptz not null default now(),
  unique (organization_id, user_id)
);

create table if not exists public.service_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  request_type text not null check (request_type in ('execution','contracting','manufacturing','materials','worker','product','other')),
  title text not null,
  details text not null,
  city text,
  budget_min numeric(12,2),
  budget_max numeric(12,2),
  status text not null default 'open' check (status in ('draft','open','in_progress','completed','cancelled')),
  is_public boolean not null default true,
  needed_by date,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (budget_min is null or budget_min >= 0),
  check (budget_max is null or budget_max >= 0),
  check (budget_min is null or budget_max is null or budget_max >= budget_min)
);

create table if not exists public.offers (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.service_requests(id) on delete cascade,
  provider_organization_id uuid not null references public.organizations(id) on delete cascade,
  created_by uuid not null references auth.users(id),
  price numeric(12,2) check (price is null or price >= 0),
  details text not null,
  estimated_days integer check (estimated_days is null or estimated_days >= 0),
  status text not null default 'submitted' check (status in ('submitted','accepted','rejected','withdrawn')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (request_id, provider_organization_id)
);

create table if not exists public.activity_log (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid references public.organizations(id) on delete set null,
  actor_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  entity_type text not null,
  entity_id uuid,
  summary text,
  created_at timestamptz not null default now()
);

create index if not exists memberships_user_idx on public.memberships(user_id);
create index if not exists memberships_org_idx on public.memberships(organization_id);
create index if not exists requests_status_city_idx on public.service_requests(status, city, created_at desc);
create index if not exists requests_org_idx on public.service_requests(organization_id, created_at desc);
create index if not exists offers_request_idx on public.offers(request_id, created_at desc);
create index if not exists activity_org_idx on public.activity_log(organization_id, created_at desc);


-- SECURITY DEFINER helpers avoid recursive row-level-security checks on memberships.
create or replace function public.is_org_member(p_org_id uuid, p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_org_id and m.user_id = p_user_id
  );
$;

create or replace function public.has_org_role(p_org_id uuid, p_roles text[], p_user_id uuid default auth.uid())
returns boolean language sql stable security definer set search_path = public as $
  select exists (
    select 1 from public.memberships m
    where m.organization_id = p_org_id
      and m.user_id = p_user_id
      and m.member_role = any(p_roles)
  );
$;

create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at before update on public.profiles
for each row execute function public.set_updated_at();

drop trigger if exists organizations_set_updated_at on public.organizations;
create trigger organizations_set_updated_at before update on public.organizations
for each row execute function public.set_updated_at();

drop trigger if exists requests_set_updated_at on public.service_requests;
create trigger requests_set_updated_at before update on public.service_requests
for each row execute function public.set_updated_at();

drop trigger if exists offers_set_updated_at on public.offers;
create trigger offers_set_updated_at before update on public.offers
for each row execute function public.set_updated_at();

alter table public.profiles enable row level security;
alter table public.organizations enable row level security;
alter table public.memberships enable row level security;
alter table public.service_requests enable row level security;
alter table public.offers enable row level security;
alter table public.activity_log enable row level security;

-- A user can read and update only their own profile.
drop policy if exists "profile_select_self" on public.profiles;
create policy "profile_select_self" on public.profiles for select
using (id = auth.uid());
drop policy if exists "profile_insert_self" on public.profiles;
create policy "profile_insert_self" on public.profiles for insert
with check (id = auth.uid());
drop policy if exists "profile_update_self" on public.profiles;
create policy "profile_update_self" on public.profiles for update
using (id = auth.uid()) with check (id = auth.uid());

-- Organization records are visible to their members; creator may create the organization.
drop policy if exists "organization_select_members" on public.organizations;
create policy "organization_select_members" on public.organizations for select
using (public.is_org_member(id));
drop policy if exists "organization_insert_creator" on public.organizations;
create policy "organization_insert_creator" on public.organizations for insert
with check (created_by = auth.uid());
drop policy if exists "organization_update_admins" on public.organizations;
create policy "organization_update_admins" on public.organizations for update
using (public.has_org_role(id, array['owner','admin']))
with check (public.has_org_role(id, array['owner','admin']));

-- Members can see their own membership and organization admins can see the team's memberships.
drop policy if exists "membership_select_team" on public.memberships;
create policy "membership_select_team" on public.memberships for select
using (user_id = auth.uid() or public.has_org_role(organization_id, array['owner','admin']));
drop policy if exists "membership_insert_owner" on public.memberships;
create policy "membership_insert_owner" on public.memberships for insert
with check (
  user_id = auth.uid()
  and exists (select 1 from public.organizations o where o.id = organization_id and o.created_by = auth.uid())
);
drop policy if exists "membership_update_admins" on public.memberships;
create policy "membership_update_admins" on public.memberships for update
using (public.has_org_role(organization_id, array['owner','admin']))
with check (public.has_org_role(organization_id, array['owner','admin']));

-- Public open requests can be discovered; private and non-open requests stay with their members.
drop policy if exists "request_select_public_or_member" on public.service_requests;
create policy "request_select_public_or_member" on public.service_requests for select
using (
  (is_public = true and status = 'open')
  or public.is_org_member(organization_id)
);
drop policy if exists "request_insert_member" on public.service_requests;
create policy "request_insert_member" on public.service_requests for insert
with check (
  created_by = auth.uid()
  and public.is_org_member(organization_id)
);
drop policy if exists "request_update_member_admin" on public.service_requests;
create policy "request_update_member_admin" on public.service_requests for update
using (public.has_org_role(organization_id, array['owner','admin','manager']))
with check (public.has_org_role(organization_id, array['owner','admin','manager']));

-- Offers are visible only to the provider and the owner of the request.
drop policy if exists "offer_select_parties" on public.offers;
create policy "offer_select_parties" on public.offers for select
using (
  public.is_org_member(provider_organization_id)
  or exists (
    select 1 from public.service_requests r
    join public.memberships m on m.organization_id = r.organization_id
    where r.id = request_id and m.user_id = auth.uid()
  )
);
drop policy if exists "offer_insert_provider_member" on public.offers;
create policy "offer_insert_provider_member" on public.offers for insert
with check (
  created_by = auth.uid()
  and public.is_org_member(provider_organization_id)
  and exists (select 1 from public.service_requests r where r.id = request_id and r.status = 'open' and r.organization_id <> provider_organization_id)
);
drop policy if exists "offer_update_parties" on public.offers;
create policy "offer_update_parties" on public.offers for update
using (
  public.has_org_role(provider_organization_id, array['owner','admin','manager'])
  or exists (
    select 1 from public.service_requests r
    join public.memberships m on m.organization_id = r.organization_id
    where r.id = request_id and m.user_id = auth.uid() and m.member_role in ('owner','admin','manager')
  )
)
with check (
  public.has_org_role(provider_organization_id, array['owner','admin','manager'])
  or exists (
    select 1 from public.service_requests r
    join public.memberships m on m.organization_id = r.organization_id
    where r.id = request_id and m.user_id = auth.uid() and m.member_role in ('owner','admin','manager')
  )
);

-- Activity history is private to members of the related organization.
drop policy if exists "activity_select_members" on public.activity_log;
create policy "activity_select_members" on public.activity_log for select
using (organization_id is not null and public.is_org_member(organization_id));
drop policy if exists "activity_insert_members" on public.activity_log;
create policy "activity_insert_members" on public.activity_log for insert
with check (
  actor_user_id = auth.uid()
  and organization_id is not null
  and public.is_org_member(organization_id)
);

-- IMPORTANT:
-- Never put a Supabase service_role key or WhatsApp access token in browser JavaScript.
-- WhatsApp Cloud API calls must run from a trusted server/edge function.
