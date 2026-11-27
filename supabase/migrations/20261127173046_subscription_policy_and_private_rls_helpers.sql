-- Subscription policy alignment and API hardening for Maaref.
-- Free access applies to all account types. Paid periods are monthly.
-- Renewal remains manual unless the account owner explicitly opts in.

create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

create or replace function private.is_org_member(p_org_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.memberships m
    where m.organization_id = p_org_id and m.user_id = (select auth.uid()));
$$;

create or replace function private.has_org_role(p_org_id uuid, p_roles text[])
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.memberships m
    where m.organization_id = p_org_id and m.user_id = (select auth.uid())
      and m.member_role = any(p_roles));
$$;

create or replace function private.is_platform_admin()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.platform_admins a
    where a.user_id = (select auth.uid()));
$$;

revoke all on function private.is_org_member(uuid) from public;
revoke all on function private.has_org_role(uuid,text[]) from public;
revoke all on function private.is_platform_admin() from public;
grant execute on function private.is_org_member(uuid) to anon, authenticated;
grant execute on function private.has_org_role(uuid,text[]) to authenticated;
grant execute on function private.is_platform_admin() to authenticated;

drop policy if exists "organization_select_members" on public.organizations;
create policy "organization_select_members" on public.organizations for select
using (private.is_org_member(id) or private.is_platform_admin());
drop policy if exists "organization_update_admins" on public.organizations;
create policy "organization_update_admins" on public.organizations for update
using (private.has_org_role(id, array['owner','admin']))
with check (private.has_org_role(id, array['owner','admin']));

drop policy if exists "membership_select_team" on public.memberships;
create policy "membership_select_team" on public.memberships for select
using (user_id = (select auth.uid()) or private.has_org_role(organization_id, array['owner','admin']));
drop policy if exists "membership_update_admins" on public.memberships;
create policy "membership_update_admins" on public.memberships for update
using (private.has_org_role(organization_id, array['owner','admin']))
with check (private.has_org_role(organization_id, array['owner','admin']));

drop policy if exists "request_select_public_or_member" on public.service_requests;
create policy "request_select_public_or_member" on public.service_requests for select
using ((is_public = true and status = 'open') or private.is_org_member(organization_id));
drop policy if exists "request_insert_member" on public.service_requests;
create policy "request_insert_member" on public.service_requests for insert
with check (created_by = (select auth.uid()) and private.is_org_member(organization_id));
drop policy if exists "request_update_member_admin" on public.service_requests;
create policy "request_update_member_admin" on public.service_requests for update
using (private.has_org_role(organization_id, array['owner','admin','manager']))
with check (private.has_org_role(organization_id, array['owner','admin','manager']));

drop policy if exists "offer_select_parties" on public.offers;
create policy "offer_select_parties" on public.offers for select
using (private.is_org_member(provider_organization_id) or exists (
  select 1 from public.service_requests r join public.memberships m on m.organization_id = r.organization_id
  where r.id = request_id and m.user_id = (select auth.uid())
));
drop policy if exists "offer_insert_provider_member" on public.offers;
create policy "offer_insert_provider_member" on public.offers for insert
with check (created_by = (select auth.uid()) and private.is_org_member(provider_organization_id)
  and exists (select 1 from public.service_requests r where r.id = request_id
    and r.status = 'open' and r.organization_id <> provider_organization_id));
drop policy if exists "offer_update_parties" on public.offers;
create policy "offer_update_parties" on public.offers for update
using (private.has_org_role(provider_organization_id, array['owner','admin','manager']) or exists (
  select 1 from public.service_requests r join public.memberships m on m.organization_id = r.organization_id
  where r.id = request_id and m.user_id = (select auth.uid()) and m.member_role in ('owner','admin','manager')
))
with check (private.has_org_role(provider_organization_id, array['owner','admin','manager']) or exists (
  select 1 from public.service_requests r join public.memberships m on m.organization_id = r.organization_id
  where r.id = request_id and m.user_id = (select auth.uid()) and m.member_role in ('owner','admin','manager')
));

drop policy if exists "activity_select_members" on public.activity_log;
create policy "activity_select_members" on public.activity_log for select
using (organization_id is not null and private.is_org_member(organization_id));
drop policy if exists "activity_insert_members" on public.activity_log;
create policy "activity_insert_members" on public.activity_log for insert
with check (actor_user_id = (select auth.uid()) and organization_id is not null
  and private.is_org_member(organization_id));

drop policy if exists "plans_read_active" on public.subscription_plans;
create policy "plans_read_active" on public.subscription_plans for select to anon, authenticated
using (is_active = true or private.is_platform_admin());
drop policy if exists "plans_admin_manage" on public.subscription_plans;
create policy "plans_admin_manage" on public.subscription_plans for all to authenticated
using (private.is_platform_admin()) with check (private.is_platform_admin());

drop policy if exists "subscriptions_read_org_admins" on public.subscriptions;
create policy "subscriptions_read_org_admins" on public.subscriptions for select to authenticated
using (private.is_platform_admin() or private.has_org_role(organization_id, array['owner','admin']));
drop policy if exists "payments_read_org_admins" on public.subscription_payments;
create policy "payments_read_org_admins" on public.subscription_payments for select to authenticated
using (private.is_platform_admin() or private.has_org_role(organization_id, array['owner','admin']));

revoke all on function public.is_org_member(uuid,uuid) from public, anon, authenticated;
revoke all on function public.has_org_role(uuid,text[],uuid) from public, anon, authenticated;
revoke all on function public.is_platform_admin() from public, anon, authenticated;
drop function public.is_org_member(uuid,uuid);
drop function public.has_org_role(uuid,text[],uuid);
drop function public.is_platform_admin();

create or replace function public.get_organization_subscription_access(p_organization_id uuid)
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_sub public.subscriptions%rowtype;
  v_plan public.subscription_plans%rowtype;
  v_access text;
begin
  if (select auth.uid()) is null or not private.is_org_member(p_organization_id) then
    raise exception 'Not authorized to inspect this organization subscription';
  end if;
  select * into v_sub from public.subscriptions where organization_id = p_organization_id;
  if not found then
    select * into v_plan from public.subscription_plans where code = 'free' and is_active = true;
    return jsonb_build_object('status','free','plan_code',v_plan.code,'plan_name',v_plan.name,
      'features',v_plan.features,'access_until',null,'days_remaining',null);
  end if;
  select * into v_plan from public.subscription_plans where id = v_sub.plan_id;
  if now() <= v_sub.current_period_end then
    v_access := case when v_sub.status = 'trialing' then 'trialing' else 'active' end;
  elsif now() <= v_sub.grace_until then v_access := 'grace';
  else v_access := 'expired'; end if;
  if v_access = 'expired' then
    select * into v_plan from public.subscription_plans where code = 'free' and is_active = true;
  end if;
  return jsonb_build_object('status',v_access,'record_status',v_sub.status,
    'plan_code',v_plan.code,'plan_name',v_plan.name,'features',v_plan.features,
    'period_end',v_sub.current_period_end,'grace_until',v_sub.grace_until,
    'days_remaining',greatest(0,ceil(extract(epoch from (v_sub.grace_until - now())) / 86400.0)));
end;
$$;

create or replace function public.get_platform_subscription_dashboard()
returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare v_result jsonb;
begin
  if not private.is_platform_admin() then raise exception 'Platform administrator access required'; end if;
  select jsonb_build_object(
    'active_count', count(*) filter (where s.status = 'active' and now() <= s.current_period_end),
    'trial_count', count(*) filter (where s.status = 'trialing' and now() <= s.current_period_end),
    'grace_count', count(*) filter (where now() > s.current_period_end and now() <= s.grace_until),
    'expired_count', count(*) filter (where now() > s.grace_until or s.status in ('expired','canceled')),
    'ending_soon_count', count(*) filter (where s.current_period_end > now() and s.current_period_end <= now() + interval '7 days'),
    'paid_revenue_this_month', coalesce((select sum(p.amount_egp) from public.subscription_payments p
      where p.status = 'paid' and p.paid_at >= date_trunc('month', now())
      and p.paid_at < date_trunc('month', now()) + interval '1 month'),0),
    'latest_subscriptions', coalesce((select jsonb_agg(x) from (
      select jsonb_build_object('subscription_id',s2.id,'organization_id',o.id,
        'organization_name',o.name,'plan_name',pl.name,
        'status',case when now() <= s2.current_period_end and s2.status = 'trialing' then 'trialing'
          when now() <= s2.current_period_end then 'active'
          when now() <= s2.grace_until then 'grace' else 'expired' end,
        'period_end',s2.current_period_end,'grace_until',s2.grace_until,'auto_renew',s2.auto_renew) as x
      from public.subscriptions s2
      join public.organizations o on o.id = s2.organization_id
      join public.subscription_plans pl on pl.id = s2.plan_id
      order by s2.updated_at desc limit 100
    ) q),'[]'::jsonb)
  ) into v_result from public.subscriptions s;
  return coalesce(v_result, '{}'::jsonb);
end;
$$;

revoke all on function public.get_organization_subscription_access(uuid) from public;
grant execute on function public.get_organization_subscription_access(uuid) to authenticated;
revoke all on function public.get_platform_subscription_dashboard() from public;
grant execute on function public.get_platform_subscription_dashboard() to authenticated;

-- The approved plan starts with the free tier; no new 14-day paid trial.
revoke all on function public.start_organization_trial(uuid,text) from public, anon, authenticated;

create or replace function public.set_subscription_grace_period()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.grace_until := new.current_period_end + interval '7 days';
  return new;
end;
$$;
drop trigger if exists subscriptions_set_grace_period on public.subscriptions;
create trigger subscriptions_set_grace_period
before insert or update of current_period_end on public.subscriptions
for each row execute function public.set_subscription_grace_period();

update public.subscriptions
set grace_until = current_period_end + interval '7 days'
where grace_until is distinct from current_period_end + interval '7 days';
update public.subscription_plans
set billing_period_days = 30, updated_at = now()
where is_free = false and billing_period_days <> 30;
