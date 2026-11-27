-- Maaref subscription foundation
-- Apply AFTER supabase/schema.sql in Supabase SQL Editor.
-- Prices are initial editable defaults in EGP, not a public price commitment.

create extension if not exists pgcrypto;

create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  granted_at timestamptz not null default now(),
  note text
);

create or replace function public.is_platform_admin()
returns boolean
language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from public.platform_admins a
    where a.user_id = auth.uid()
  );
$$;

revoke all on function public.is_platform_admin() from public;
grant execute on function public.is_platform_admin() to authenticated, service_role;

create table if not exists public.subscription_plans (
  id uuid primary key default gen_random_uuid(),
  code text not null unique,
  name text not null,
  description text not null default '',
  price_egp numeric(12,2) not null default 0 check (price_egp >= 0),
  billing_period_days integer not null default 30 check (billing_period_days > 0),
  features jsonb not null default '{}'::jsonb,
  is_free boolean not null default false,
  is_active boolean not null default true,
  display_order integer not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.subscription_plans
  (code, name, description, price_egp, billing_period_days, features, is_free, display_order)
values
  ('free', 'مجاني', 'حساب أساسي للتعريف بالنشاط واكتشاف المنصة', 0, 30,
   '{"monthly_requests":2,"monthly_offers":3,"featured_listing":false,"advanced_reports":false,"team_members":1}'::jsonb, true, 0),
  ('workshop', 'ورشة صغيرة', 'مزايا تشغيل ومتابعة أكثر للورش', 299, 30,
   '{"monthly_requests":30,"monthly_offers":50,"featured_listing":false,"advanced_reports":false,"team_members":3}'::jsonb, false, 1),
  ('company', 'شركة', 'إدارة أعمال وطلبات وعروض لفريق الشركة', 799, 30,
   '{"monthly_requests":150,"monthly_offers":250,"featured_listing":true,"advanced_reports":true,"team_members":10}'::jsonb, false, 2),
  ('business_plus', 'شركة متقدمة', 'حدود أعلى وظهور وتقارير متقدمة', 1499, 30,
   '{"monthly_requests":500,"monthly_offers":1000,"featured_listing":true,"advanced_reports":true,"team_members":30}'::jsonb, false, 3)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  price_egp = excluded.price_egp,
  billing_period_days = excluded.billing_period_days,
  features = excluded.features,
  is_free = excluded.is_free,
  display_order = excluded.display_order,
  updated_at = now();

create table if not exists public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null unique references public.organizations(id) on delete restrict,
  plan_id uuid not null references public.subscription_plans(id),
  status text not null check (status in ('trialing','active','past_due','expired','canceled')),
  started_at timestamptz not null default now(),
  current_period_start timestamptz not null default now(),
  current_period_end timestamptz not null,
  grace_until timestamptz not null,
  trial_started_at timestamptz,
  trial_ends_at timestamptz,
  auto_renew boolean not null default false,
  auto_renew_consent_at timestamptz,
  canceled_at timestamptz,
  cancellation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (current_period_end > current_period_start),
  check (grace_until >= current_period_end),
  check (auto_renew = false or auto_renew_consent_at is not null)
);

alter table public.organizations
  add column if not exists trial_started_at timestamptz;

create table if not exists public.subscription_payments (
  id uuid primary key default gen_random_uuid(),
  subscription_id uuid not null references public.subscriptions(id) on delete restrict,
  organization_id uuid not null references public.organizations(id) on delete restrict,
  amount_egp numeric(12,2) not null check (amount_egp >= 0),
  currency text not null default 'EGP' check (currency = 'EGP'),
  provider text not null,
  provider_payment_id text,
  provider_event_id text unique,
  status text not null check (status in ('pending','paid','failed','refunded')),
  paid_at timestamptz,
  period_start timestamptz,
  period_end timestamptz,
  receipt_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists subscriptions_status_end_idx
  on public.subscriptions(status, current_period_end);
create index if not exists payments_org_created_idx
  on public.subscription_payments(organization_id, created_at desc);
create index if not exists payments_status_created_idx
  on public.subscription_payments(status, created_at desc);

drop trigger if exists subscription_plans_set_updated_at on public.subscription_plans;
create trigger subscription_plans_set_updated_at before update on public.subscription_plans
for each row execute function public.set_updated_at();
drop trigger if exists subscriptions_set_updated_at on public.subscriptions;
create trigger subscriptions_set_updated_at before update on public.subscriptions
for each row execute function public.set_updated_at();
drop trigger if exists subscription_payments_set_updated_at on public.subscription_payments;
create trigger subscription_payments_set_updated_at before update on public.subscription_payments
for each row execute function public.set_updated_at();

alter table public.platform_admins enable row level security;
alter table public.subscription_plans enable row level security;
alter table public.subscriptions enable row level security;
alter table public.subscription_payments enable row level security;

-- No client-side policies on platform_admins: bootstrap admins manually in SQL Editor.
drop policy if exists "plans_read_active" on public.subscription_plans;
create policy "plans_read_active" on public.subscription_plans
for select to anon, authenticated using (is_active = true or public.is_platform_admin());
drop policy if exists "plans_admin_manage" on public.subscription_plans;
create policy "plans_admin_manage" on public.subscription_plans
for all to authenticated using (public.is_platform_admin())
with check (public.is_platform_admin());

drop policy if exists "subscriptions_read_org_admins" on public.subscriptions;
create policy "subscriptions_read_org_admins" on public.subscriptions
for select to authenticated using (
  public.is_platform_admin()
  or public.has_org_role(organization_id, array['owner','admin'])
);
-- Deliberately no authenticated INSERT/UPDATE/DELETE policy on subscriptions.
-- Only trusted server-side code using the service_role key may create/renew/change paid subscriptions.

drop policy if exists "payments_read_org_admins" on public.subscription_payments;
create policy "payments_read_org_admins" on public.subscription_payments
for select to authenticated using (
  public.is_platform_admin()
  or public.has_org_role(organization_id, array['owner','admin'])
);
-- Deliberately no client INSERT/UPDATE/DELETE policy on payment records.
-- Payment confirmation must come from a verified provider webhook on a trusted server.

create or replace function public.start_organization_trial(
  p_organization_id uuid,
  p_plan_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_plan public.subscription_plans%rowtype;
  v_subscription_id uuid;
  v_now timestamptz := now();
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;
  if not public.has_org_role(p_organization_id, array['owner','admin']) then
    raise exception 'Only organization owners or admins can start a trial';
  end if;

  select * into v_plan
  from public.subscription_plans
  where code = p_plan_code and is_active = true and is_free = false;

  if not found then
    raise exception 'Selected paid plan is not available';
  end if;

  update public.organizations
  set trial_started_at = v_now
  where id = p_organization_id and trial_started_at is null;

  if not found then
    raise exception 'This organization has already used its free trial';
  end if;

  if exists (select 1 from public.subscriptions s where s.organization_id = p_organization_id) then
    raise exception 'This organization already has a subscription record';
  end if;

  insert into public.subscriptions (
    organization_id, plan_id, status, started_at,
    current_period_start, current_period_end, grace_until,
    trial_started_at, trial_ends_at, auto_renew
  ) values (
    p_organization_id, v_plan.id, 'trialing', v_now,
    v_now, v_now + interval '14 days', v_now + interval '21 days',
    v_now, v_now + interval '14 days', false
  ) returning id into v_subscription_id;

  return v_subscription_id;
end;
$$;

revoke all on function public.start_organization_trial(uuid, text) from public;
grant execute on function public.start_organization_trial(uuid, text) to authenticated;

create or replace function public.get_organization_subscription_access(p_organization_id uuid)
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_sub public.subscriptions%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_access text;
begin
  if auth.uid() is null or not public.is_org_member(p_organization_id) then
    raise exception 'Not authorized to inspect this organization subscription';
  end if;

  select * into v_sub from public.subscriptions
  where organization_id = p_organization_id;

  if not found then
    select * into v_plan from public.subscription_plans where code = 'free' and is_active = true;
    return jsonb_build_object(
      'status','free','plan_code',v_plan.code,'plan_name',v_plan.name,
      'features',v_plan.features,'access_until',null,'days_remaining',null
    );
  end if;

  select * into v_plan from public.subscription_plans where id = v_sub.plan_id;

  if v_sub.status = 'canceled' then
    v_access := case when now() <= v_sub.grace_until then 'grace' else 'expired' end;
  elsif now() <= v_sub.current_period_end then
    v_access := case when v_sub.status = 'trialing' then 'trialing' else 'active' end;
  elsif now() <= v_sub.grace_until then
    v_access := 'grace';
  else
    v_access := 'expired';
  end if;

  if v_access = 'expired' then
    select * into v_plan from public.subscription_plans where code = 'free' and is_active = true;
  end if;

  return jsonb_build_object(
    'status',v_access,
    'record_status',v_sub.status,
    'plan_code',v_plan.code,
    'plan_name',v_plan.name,
    'features',v_plan.features,
    'period_end',v_sub.current_period_end,
    'grace_until',v_sub.grace_until,
    'days_remaining',greatest(0,ceil(extract(epoch from (v_sub.grace_until - now())) / 86400.0))
  );
end;
$$;

revoke all on function public.get_organization_subscription_access(uuid) from public;
grant execute on function public.get_organization_subscription_access(uuid) to authenticated;

create or replace function public.get_platform_subscription_dashboard()
returns jsonb
language plpgsql stable security definer
set search_path = public
as $$
declare
  v_result jsonb;
begin
  if not public.is_platform_admin() then
    raise exception 'Platform administrator access required';
  end if;

  select jsonb_build_object(
    'active_count', count(*) filter (where s.status = 'active' and now() <= s.current_period_end),
    'trial_count', count(*) filter (where s.status = 'trialing' and now() <= s.current_period_end),
    'grace_count', count(*) filter (where now() > s.current_period_end and now() <= s.grace_until),
    'expired_count', count(*) filter (where now() > s.grace_until or s.status in ('expired','canceled')),
    'ending_soon_count', count(*) filter (where s.current_period_end > now() and s.current_period_end <= now() + interval '7 days'),
    'paid_revenue_this_month', coalesce((
      select sum(p.amount_egp) from public.subscription_payments p
      where p.status = 'paid'
        and p.paid_at >= date_trunc('month', now())
        and p.paid_at < date_trunc('month', now()) + interval '1 month'
    ),0),
    'latest_subscriptions', coalesce((
      select jsonb_agg(x) from (
        select jsonb_build_object(
          'subscription_id',s2.id,
          'organization_id',o.id,
          'organization_name',o.name,
          'plan_name',pl.name,
          'status',case
            when now() <= s2.current_period_end and s2.status = 'trialing' then 'trialing'
            when now() <= s2.current_period_end then 'active'
            when now() <= s2.grace_until then 'grace'
            else 'expired' end,
          'period_end',s2.current_period_end,
          'grace_until',s2.grace_until,
          'auto_renew',s2.auto_renew
        ) as x
        from public.subscriptions s2
        join public.organizations o on o.id = s2.organization_id
        join public.subscription_plans pl on pl.id = s2.plan_id
        order by s2.updated_at desc
        limit 100
      ) q
    ), '[]'::jsonb)
  ) into v_result
  from public.subscriptions s;

  return coalesce(v_result, '{}'::jsonb);
end;
$$;

revoke all on function public.get_platform_subscription_dashboard() from public;
grant execute on function public.get_platform_subscription_dashboard() to authenticated;

-- Bootstrap the platform owner manually AFTER confirming the correct auth.users UUID:
-- insert into public.platform_admins(user_id, note)
-- values ('YOUR_AUTH_USER_UUID', 'Founding platform owner');
--
-- Never expose Supabase service_role keys or payment-provider secrets in index.html.
-- Use a trusted Edge Function/server to create payment sessions, verify provider webhooks,
-- insert subscription_payments, and renew subscriptions. Do not trust browser payment callbacks.
