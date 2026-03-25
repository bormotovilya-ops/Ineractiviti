-- Панель «Платформа» в landing/app.html: заявки с лендинга (#form) и общие настройки.
-- Выполните в Supabase → SQL Editor после tech/supabase-landing-project-requests.sql

-- Кто считается администратором экземпляра платформы (не роль внутри проекта).
create table if not exists public.platform_admins (
  user_id uuid primary key references auth.users (id) on delete cascade
);

comment on table public.platform_admins is 'Пользователи с доступом к панели «Платформа» в app.html';

alter table public.platform_admins enable row level security;

grant select on table public.platform_admins to authenticated;

drop policy if exists "platform_admins_read_own" on public.platform_admins;
create policy "platform_admins_read_own"
  on public.platform_admins
  for select
  to authenticated
  using (user_id = auth.uid());

-- Первого админа добавьте вручную (UUID из Authentication → Users или из профиля в кабинете):
-- insert into public.platform_admins (user_id) values ('00000000-0000-0000-0000-000000000000');

-- Чтение заявок с лендинга только для platform_admins
grant select on table public.landing_project_requests to authenticated;

drop policy if exists "landing_project_requests_select_platform_admin" on public.landing_project_requests;
create policy "landing_project_requests_select_platform_admin"
  on public.landing_project_requests
  for select
  to authenticated
  using (
    exists (
      select 1 from public.platform_admins pa
      where pa.user_id = auth.uid()
    )
  );

-- Одна строка глобальных настроек (заметки команды и т.п.)
create table if not exists public.platform_settings (
  id smallint primary key default 1 check (id = 1),
  operator_notes text,
  updated_at timestamptz not null default now()
);

comment on table public.platform_settings is 'Глобальные настройки экземпляра; правит только platform_admins';

insert into public.platform_settings (id) values (1)
  on conflict (id) do nothing;

alter table public.platform_settings enable row level security;

grant select, insert, update on table public.platform_settings to authenticated;

drop policy if exists "platform_settings_admin_select" on public.platform_settings;
create policy "platform_settings_admin_select"
  on public.platform_settings
  for select
  to authenticated
  using (
    exists (
      select 1 from public.platform_admins pa
      where pa.user_id = auth.uid()
    )
  );

drop policy if exists "platform_settings_admin_insert" on public.platform_settings;
create policy "platform_settings_admin_insert"
  on public.platform_settings
  for insert
  to authenticated
  with check (
    exists (
      select 1 from public.platform_admins pa
      where pa.user_id = auth.uid()
    )
  );

drop policy if exists "platform_settings_admin_update" on public.platform_settings;
create policy "platform_settings_admin_update"
  on public.platform_settings
  for update
  to authenticated
  using (
    exists (
      select 1 from public.platform_admins pa
      where pa.user_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.platform_admins pa
      where pa.user_id = auth.uid()
    )
  );
