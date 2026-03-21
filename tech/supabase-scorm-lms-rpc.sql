-- SCORM LMS: RPC для плеера (landing/scorm-player.html)
-- Выполните в Supabase SQL Editor.
--
-- Ожидаемые имена аргументов для PostgREST: p_course_id, p_package_version_id, p_sco_identifier и т.д.
--
-- Статус попытки: колонка status часто имеет тип enum scorm_attempt_status.
-- RPC использует метки in_progress (старт) и completed (финиш). Список ваших меток:
--   select e.enumlabel from pg_enum e
--   join pg_type t on t.oid = e.enumtypid
--   where t.typname = 'scorm_attempt_status' order by e.enumsortorder;
-- При других именах замените литералы в INSERT/UPDATE внутри scorm_start_attempt / scorm_finish_attempt.
-- Либо: alter type public.scorm_attempt_status add value 'in_progress';
--       alter type public.scorm_attempt_status add value 'completed';
--
-- Если таблицы course_scorm_attempts / course_scorm_sco_states уже есть — блок CREATE TABLE
-- будет пропущен (IF NOT EXISTS). Проверьте, что есть столбцы, которые используют функции ниже.

-- ---------- Таблицы (только если ещё нет) ----------
create table if not exists public.course_scorm_attempts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  project_id uuid not null references public.projects (id) on delete cascade,
  course_id uuid not null references public.project_courses (id) on delete cascade,
  package_version_id uuid not null references public.course_scorm_package_versions (id) on delete cascade,
  attempt_number integer not null,
  status text not null default 'in_progress',
  started_at timestamptz not null default now(),
  completed_at timestamptz
);

create index if not exists course_scorm_attempts_user_course_idx
  on public.course_scorm_attempts (user_id, course_id);

create index if not exists course_scorm_attempts_project_idx
  on public.course_scorm_attempts (project_id);

create table if not exists public.course_scorm_sco_states (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.course_scorm_attempts (id) on delete cascade,
  sco_id uuid not null references public.course_scorm_scos (id) on delete cascade,
  cmi_data jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now(),
  constraint course_scorm_sco_states_attempt_sco_unique unique (attempt_id, sco_id)
);

create index if not exists course_scorm_sco_states_attempt_idx
  on public.course_scorm_sco_states (attempt_id);

-- ---------- Уже существующая таблица без cmi_data: привести к схеме RPC ----------
-- RPC и плеер ожидают jsonb-колонку cmi_data и (для commit) updated_at.
DO $sco_migrate$
BEGIN
  IF to_regclass('public.course_scorm_sco_states') IS NULL THEN
    RETURN;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'course_scorm_sco_states'
      AND column_name = 'cmi_data'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'course_scorm_sco_states'
        AND column_name = 'data'
    ) THEN
      ALTER TABLE public.course_scorm_sco_states RENAME COLUMN data TO cmi_data;
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'course_scorm_sco_states'
        AND column_name = 'state'
    ) THEN
      ALTER TABLE public.course_scorm_sco_states RENAME COLUMN state TO cmi_data;
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'course_scorm_sco_states'
        AND column_name = 'fields'
    ) THEN
      ALTER TABLE public.course_scorm_sco_states RENAME COLUMN fields TO cmi_data;
    ELSIF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'course_scorm_sco_states'
        AND column_name = 'cmi'
    ) THEN
      ALTER TABLE public.course_scorm_sco_states RENAME COLUMN cmi TO cmi_data;
    ELSE
      ALTER TABLE public.course_scorm_sco_states
        ADD COLUMN cmi_data jsonb NOT NULL DEFAULT '{}'::jsonb;
    END IF;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'course_scorm_sco_states'
      AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.course_scorm_sco_states
      ADD COLUMN updated_at timestamptz NOT NULL DEFAULT now();
  END IF;
END $sco_migrate$;

-- ---------- RLS ----------
alter table public.course_scorm_attempts enable row level security;
alter table public.course_scorm_sco_states enable row level security;

drop policy if exists course_scorm_attempts_own_select on public.course_scorm_attempts;
create policy course_scorm_attempts_own_select
  on public.course_scorm_attempts for select
  to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists course_scorm_sco_states_own_select on public.course_scorm_sco_states;
create policy course_scorm_sco_states_own_select
  on public.course_scorm_sco_states for select
  to authenticated
  using (
    exists (
      select 1 from public.course_scorm_attempts a
      where a.id = course_scorm_sco_states.attempt_id
        and a.user_id = (select auth.uid())
    )
  );

-- Запись попыток/состояний идёт через SECURITY DEFINER RPC ниже; прямой insert с клиента не обязателен.

-- ---------- RPC ----------
create or replace function public.scorm_start_attempt(
  p_course_id uuid,
  p_package_version_id uuid,
  p_sco_identifier text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_project uuid;
  v_sco_id uuid;
  v_attempt uuid;
  v_attempt_number integer;
  v_published boolean;
  v_role text;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select pc.project_id, pc.is_published
  into v_project, v_published
  from public.project_courses pc
  where pc.id = p_course_id;

  if v_project is null then
    raise exception 'Course not found';
  end if;

  if not exists (
    select 1 from public.project_members pm
    where pm.project_id = v_project and pm.user_id = v_user
  ) then
    raise exception 'Not a project member';
  end if;

  select pm.role into v_role
  from public.project_members pm
  where pm.project_id = v_project and pm.user_id = v_user
  limit 1;

  if coalesce(v_role, 'listener') = 'listener' and not coalesce(v_published, false) then
    raise exception 'Course not published';
  end if;

  if not exists (
    select 1 from public.course_scorm_package_versions v
    where v.id = p_package_version_id and v.course_id = p_course_id
  ) then
    raise exception 'Package version does not belong to course';
  end if;

  if p_sco_identifier is null or length(trim(p_sco_identifier)) = 0 then
    select s.id into v_sco_id
    from public.course_scorm_scos s
    where s.package_version_id = p_package_version_id
    order by s.sort_order nulls last, s.id
    limit 1;
  else
    select s.id into v_sco_id
    from public.course_scorm_scos s
    where s.package_version_id = p_package_version_id
      and s.sco_identifier = p_sco_identifier
    limit 1;
  end if;

  if v_sco_id is null then
    raise exception 'SCO not found for package version';
  end if;

  -- Номер попытки для пользователя по курсу (1, 2, 3, …)
  select coalesce(max(a.attempt_number), 0) + 1
  into v_attempt_number
  from public.course_scorm_attempts a
  where a.user_id = v_user
    and a.course_id = p_course_id;

  insert into public.course_scorm_attempts (
    user_id,
    project_id,
    course_id,
    package_version_id,
    attempt_number,
    status
  )
  values (
    v_user,
    v_project,
    p_course_id,
    p_package_version_id,
    v_attempt_number,
    'in_progress'
  )
  returning id into v_attempt;

  insert into public.course_scorm_sco_states (attempt_id, sco_id, cmi_data)
  values (v_attempt, v_sco_id, '{}'::jsonb)
  on conflict (attempt_id, sco_id) do nothing;

  return v_attempt;
end;
$$;

create or replace function public.scorm_get_sco_state(
  p_attempt_id uuid,
  p_sco_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
stable
as $$
declare
  v_user uuid := auth.uid();
  v_data jsonb;
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  select coalesce(s.cmi_data, '{}'::jsonb)
  into v_data
  from public.course_scorm_sco_states s
  inner join public.course_scorm_attempts a on a.id = s.attempt_id
  where s.attempt_id = p_attempt_id
    and s.sco_id = p_sco_id
    and a.user_id = v_user;

  return jsonb_build_object('cmi', coalesce(v_data, '{}'::jsonb));
end;
$$;

create or replace function public.scorm_set_sco_fields(
  p_attempt_id uuid,
  p_sco_id uuid,
  p_fields jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  update public.course_scorm_sco_states s
  set
    cmi_data = coalesce(s.cmi_data, '{}'::jsonb) || coalesce(p_fields, '{}'::jsonb),
    updated_at = now()
  from public.course_scorm_attempts a
  where s.attempt_id = p_attempt_id
    and s.sco_id = p_sco_id
    and s.attempt_id = a.id
    and a.user_id = v_user;

  if not found then
    raise exception 'SCO state not found or access denied';
  end if;
end;
$$;

create or replace function public.scorm_finish_attempt(p_attempt_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then
    raise exception 'Not authenticated';
  end if;

  update public.course_scorm_attempts
  set status = 'completed', completed_at = now()
  where id = p_attempt_id and user_id = v_user;

  if not found then
    raise exception 'Attempt not found or access denied';
  end if;
end;
$$;

-- Права на вызов с клиента (JWT)
grant execute on function public.scorm_start_attempt(uuid, uuid, text) to authenticated;
grant execute on function public.scorm_get_sco_state(uuid, uuid) to authenticated;
grant execute on function public.scorm_set_sco_fields(uuid, uuid, jsonb) to authenticated;
grant execute on function public.scorm_finish_attempt(uuid) to authenticated;

-- Явные права на таблицы (RLS всё равно фильтрует)
grant select on public.course_scorm_attempts to authenticated;
grant select on public.course_scorm_sco_states to authenticated;
