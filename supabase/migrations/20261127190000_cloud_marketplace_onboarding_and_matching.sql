alter table public.organizations add column if not exists specialties text[] not null default '{}', add column if not exists service_areas text[] not null default '{}', add column if not exists website_url text, add column if not exists is_listed boolean not null default true, add column if not exists is_verified boolean not null default false;
create index if not exists organizations_directory_idx on public.organizations(account_type,city) where is_listed=true;
create index if not exists organizations_specialties_idx on public.organizations using gin(specialties);
create index if not exists requests_open_city_idx on public.service_requests(city,created_at desc) where is_public=true and status='open';
create or replace function public.create_organization_with_owner(p_name text,p_account_type text,p_description text default null,p_city text default null,p_phone text default null,p_whatsapp_phone text default null,p_specialties text[] default '{}',p_service_areas text[] default '{}') returns uuid language plpgsql security invoker set search_path='' as $$
declare v_user_id uuid := (select auth.uid()); v_org_id uuid;
begin
 if v_user_id is null then raise exception 'Sign in is required'; end if;
 if nullif(trim(p_name),'') is null then raise exception 'Business name is required'; end if;
 if p_account_type not in ('company','contractor','workshop','factory','professional','supplier','customer') then raise exception 'Invalid account type'; end if;
 insert into public.organizations(name,account_type,description,city,phone,whatsapp_phone,created_by,specialties,service_areas,is_listed)
 values(trim(p_name),p_account_type,nullif(trim(p_description),''),nullif(trim(p_city),''),nullif(trim(p_phone),''),nullif(trim(p_whatsapp_phone),''),v_user_id,coalesce(p_specialties,'{}'),coalesce(p_service_areas,'{}'),true)
 returning id into v_org_id;
 insert into public.memberships(organization_id,user_id,member_role) values(v_org_id,v_user_id,'owner');
 return v_org_id;
end; $$;
revoke all on function public.create_organization_with_owner(text,text,text,text,text,text,text[],text[]) from public,anon;
grant execute on function public.create_organization_with_owner(text,text,text,text,text,text,text[],text[]) to authenticated;
create or replace function public.match_service_requests_for_provider(p_provider_organization_id uuid) returns table(request_id uuid,request_title text,request_type text,request_details text,request_city text,budget_min numeric,budget_max numeric,created_at timestamptz,match_reason text) language plpgsql stable security invoker set search_path='' as $$
declare v_city text; v_specialties text[];
begin
 if (select auth.uid()) is null or not private.is_org_member(p_provider_organization_id) then raise exception 'Provider organization access required'; end if;
 select o.city,o.specialties into v_city,v_specialties from public.organizations o where o.id=p_provider_organization_id;
 return query select r.id,r.title,r.request_type,r.details,r.city,r.budget_min,r.budget_max,r.created_at,
 case when v_city is not null and lower(coalesce(r.city,''))=lower(v_city) then 'same_city' else 'specialty' end
 from public.service_requests r where r.is_public=true and r.status='open' and r.organization_id<>p_provider_organization_id
 and ((v_city is not null and lower(coalesce(r.city,''))=lower(v_city))
 or exists(select 1 from unnest(coalesce(v_specialties,'{}')) s where length(trim(s))>=2 and r.details ilike '%'||trim(s)||'%')
 or exists(select 1 from unnest(coalesce(v_specialties,'{}')) s where length(trim(s))>=2 and r.title ilike '%'||trim(s)||'%'))
 order by case when v_city is not null and lower(coalesce(r.city,''))=lower(v_city) then 0 else 1 end,r.created_at desc limit 100;
end; $$;
revoke all on function public.match_service_requests_for_provider(uuid) from public,anon;
grant execute on function public.match_service_requests_for_provider(uuid) to authenticated;
