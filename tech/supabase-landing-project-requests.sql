-- Заявки с лендинга (слайд #form, index.html).
-- Выполните в Supabase → SQL Editor для нужного проекта.

create table if not exists public.landing_project_requests (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  name text not null,
  company text not null,
  contact text not null,
  task text not null
);

comment on table public.landing_project_requests is 'Заявки на проект с публичной формы лендинга';

create index if not exists landing_project_requests_created_at_idx
  on public.landing_project_requests (created_at desc);

alter table public.landing_project_requests enable row level security;

grant usage on schema public to anon;
grant insert on table public.landing_project_requests to anon;
grant insert on table public.landing_project_requests to authenticated;

-- Вставка с фронта: anon key и залогиненные пользователи того же проекта (JWT = authenticated).
-- Если политика только для anon, а в браузере есть сессия кабинета, PostgREST шлёт роль authenticated → 403.
drop policy if exists "landing_project_requests_anon_insert" on public.landing_project_requests;
create policy "landing_project_requests_anon_insert"
  on public.landing_project_requests
  for insert
  to anon
  with check (true);

drop policy if exists "landing_project_requests_authenticated_insert" on public.landing_project_requests;
create policy "landing_project_requests_authenticated_insert"
  on public.landing_project_requests
  for insert
  to authenticated
  with check (true);
