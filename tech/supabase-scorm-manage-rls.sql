-- RLS: разрешить админам/методологам проекта вставлять и обновлять разобранный SCORM (организации, ресурсы, items, SCO).
-- Выполните в Supabase SQL Editor, если при upsert в course_scorm_* получаете 403.

-- ---------- course_scorm_resources ----------
alter table public.course_scorm_resources enable row level security;

drop policy if exists scorm_resources_manage_select on public.course_scorm_resources;
create policy scorm_resources_manage_select
on public.course_scorm_resources
for select
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_resources.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_resources_manage_insert on public.course_scorm_resources;
create policy scorm_resources_manage_insert
on public.course_scorm_resources
for insert
to authenticated
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_resources.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_resources_manage_update on public.course_scorm_resources;
create policy scorm_resources_manage_update
on public.course_scorm_resources
for update
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_resources.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
)
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_resources.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

-- ---------- course_scorm_organizations ----------
alter table public.course_scorm_organizations enable row level security;

drop policy if exists scorm_orgs_manage_select on public.course_scorm_organizations;
create policy scorm_orgs_manage_select
on public.course_scorm_organizations
for select
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_organizations.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_orgs_manage_insert on public.course_scorm_organizations;
create policy scorm_orgs_manage_insert
on public.course_scorm_organizations
for insert
to authenticated
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_organizations.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_orgs_manage_update on public.course_scorm_organizations;
create policy scorm_orgs_manage_update
on public.course_scorm_organizations
for update
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_organizations.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
)
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_organizations.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

-- ---------- course_scorm_organization_items ----------
alter table public.course_scorm_organization_items enable row level security;

drop policy if exists scorm_org_items_manage_select on public.course_scorm_organization_items;
create policy scorm_org_items_manage_select
on public.course_scorm_organization_items
for select
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_organizations o
    join public.course_scorm_package_versions v on v.id = o.package_version_id
    join public.project_members pm on pm.project_id = v.project_id
    where o.id = course_scorm_organization_items.organization_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_org_items_manage_insert on public.course_scorm_organization_items;
create policy scorm_org_items_manage_insert
on public.course_scorm_organization_items
for insert
to authenticated
with check (
  exists (
    select 1
    from public.course_scorm_organizations o
    join public.course_scorm_package_versions v on v.id = o.package_version_id
    join public.project_members pm on pm.project_id = v.project_id
    where o.id = course_scorm_organization_items.organization_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_org_items_manage_update on public.course_scorm_organization_items;
create policy scorm_org_items_manage_update
on public.course_scorm_organization_items
for update
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_organizations o
    join public.course_scorm_package_versions v on v.id = o.package_version_id
    join public.project_members pm on pm.project_id = v.project_id
    where o.id = course_scorm_organization_items.organization_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
)
with check (
  exists (
    select 1
    from public.course_scorm_organizations o
    join public.course_scorm_package_versions v on v.id = o.package_version_id
    join public.project_members pm on pm.project_id = v.project_id
    where o.id = course_scorm_organization_items.organization_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

-- ---------- course_scorm_scos ----------
alter table public.course_scorm_scos enable row level security;

drop policy if exists scorm_scos_manage_select on public.course_scorm_scos;
create policy scorm_scos_manage_select
on public.course_scorm_scos
for select
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_scos.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_scos_manage_insert on public.course_scorm_scos;
create policy scorm_scos_manage_insert
on public.course_scorm_scos
for insert
to authenticated
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_scos.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);

drop policy if exists scorm_scos_manage_update on public.course_scorm_scos;
create policy scorm_scos_manage_update
on public.course_scorm_scos
for update
to authenticated
using (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_scos.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
)
with check (
  exists (
    select 1
    from public.course_scorm_package_versions v
    join public.project_members pm on pm.project_id = v.project_id
    where v.id = course_scorm_scos.package_version_id
      and pm.user_id = auth.uid()
      and pm.role in ('admin', 'methodologist')
  )
);
