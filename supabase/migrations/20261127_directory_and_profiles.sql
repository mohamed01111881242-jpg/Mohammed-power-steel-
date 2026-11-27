-- منصة المعارف: migration لتحسين دليل الأنشطة وإنشاء ملف المستخدم تلقائيًا
-- شغّل هذا الملف مرة واحدة من Supabase SQL Editor بعد schema.sql.

alter table public.organizations
  add column if not exists is_listed boolean not null default true,
  add column if not exists is_verified boolean not null default false;

-- السماح بعرض الأنشطة التي اختارت الظهور في الدليل العام فقط.
drop policy if exists "organization_select_public_directory" on public.organizations;
create policy "organization_select_public_directory"
on public.organizations for select
using (is_listed = true);

-- إنشاء ملف profile تلقائيًا عند إنشاء مستخدم جديد في Supabase Auth.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, full_name, phone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    nullif(new.raw_user_meta_data ->> 'phone', '')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_user();

-- لا تمنح is_verified تلقائيًا؛ اعتماد النشاط يتم يدويًا من الإدارة.
