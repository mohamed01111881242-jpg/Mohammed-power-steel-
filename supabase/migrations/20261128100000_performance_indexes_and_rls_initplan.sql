-- Performance and RLS planner improvements for the live Maaref platform.
-- Safe additive indexes: do not remove or rewrite existing records.
create index if not exists activity_log_actor_user_idx on public.activity_log(actor_user_id);
create index if not exists offers_created_by_idx on public.offers(created_by);
create index if not exists offers_provider_org_idx on public.offers(provider_organization_id);
create index if not exists organizations_created_by_idx on public.organizations(created_by);
create index if not exists platform_financial_entries_created_by_idx on public.platform_financial_entries(created_by);
create index if not exists provider_reviews_reviewer_user_idx on public.provider_reviews(reviewer_user_id);
create index if not exists service_requests_created_by_idx on public.service_requests(created_by);
create index if not exists subscription_payments_subscription_idx on public.subscription_payments(subscription_id);
create index if not exists subscriptions_plan_idx on public.subscriptions(plan_id);
create index if not exists whatsapp_inbox_profile_idx on public.whatsapp_inbox(profile_id);

-- Wrap auth.uid() in SELECT so PostgreSQL can evaluate it once per statement.
drop policy if exists profile_select_self on public.profiles;
create policy profile_select_self on public.profiles for select using (id = (select auth.uid()));
drop policy if exists profile_insert_self on public.profiles;
create policy profile_insert_self on public.profiles for insert with check (id = (select auth.uid()));
drop policy if exists profile_update_self on public.profiles;
create policy profile_update_self on public.profiles for update using (id = (select auth.uid())) with check (id = (select auth.uid()));
drop policy if exists organization_insert_creator on public.organizations;
create policy organization_insert_creator on public.organizations for insert with check (created_by = (select auth.uid()));
drop policy if exists membership_insert_owner on public.memberships;
create policy membership_insert_owner on public.memberships for insert with check (
  user_id = (select auth.uid()) and exists (
    select 1 from public.organizations o
    where o.id = memberships.organization_id and o.created_by = (select auth.uid())
  )
);
