drop policy if exists "organization_select_public_directory" on public.organizations;
create policy "organization_select_public_directory"
on public.organizations for select to authenticated
using (is_listed = true);
