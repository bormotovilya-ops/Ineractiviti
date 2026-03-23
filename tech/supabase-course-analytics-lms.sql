-- LMS: аналитика прохождений — ОДНА схема на все курсы (project_courses.id).
-- Отдельных таблиц «на каждый курс» нет: везде колонка course_id + общие таблицы.
--
-- Любой SCORM/контент может писать сводку через course_analytics_record_run (поле metrics jsonb).
-- Интерактивные сценарии (напр. PeopleGames) кладут в metrics ключи chapterPoints, wrongByChapter и т.д.
-- Счётчики по вариантам ответов — course_analytics_choice_totals (course_id + choice_id).
--
-- ---------------------------------------------------------------------------
-- Уже есть в проекте (tech/supabase-scorm-lms-rpc.sql) — это НЕ дублируется:
--   • course_scorm_attempts — попытки SCORM (статус, номер попытки, связь с пакетом);
--   • course_scorm_sco_states — CMI 1.2 (cmi_data), то, что коммитит штатный SCORM API.
-- Эти таблицы нужны для совместимости с SCORM и хранения сырого cmi.*.
--
-- Таблицы course_analytics_* — другой слой: структурированная аналитика для кабинета
-- (баллы/исходы сценария, агрегаты по «ловушкам»), которую контент отдаёт через postMessage
-- в scorm-player, а не обязательно через LMSSetValue по каждому событию. Пересечение по смыслу
-- с «завершением попытки» возможно, но данные разного вида; объединять в одну таблицу без
-- потери удобства отчётов не требуется.
--
-- Проверка доступа в _course_analytics_assert_player_course_access сознательно повторяет правила
-- scorm_start_attempt (участник проекта, публикация для слушателя) — одна бизнес-логика, не второй набор таблиц.
-- При желании позже можно вынести общую проверку в один internal SQL-функцию и вызывать из обоих RPC.
--
-- Выполните в Supabase SQL Editor после project_courses / project_members.
-- ---------------------------------------------------------------------------

-- ---------- Таблицы (общие для всей LMS) ----------
create table if not exists public.course_analytics_runs (
  id uuid primary key default gen_random_uuid(),
  course_id uuid not null references public.project_courses (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  finished_at timestamptz not null default now(),
  points integer not null default 0,
  result text not null default '',
  learner_name text,
  metrics jsonb not null default '{}'::jsonb
);

create index if not exists course_analytics_runs_course_finished_idx
  on public.course_analytics_runs (course_id, finished_at);

create table if not exists public.course_analytics_choice_totals (
  course_id uuid not null references public.project_courses (id) on delete cascade,
  choice_id text not null,
  count integer not null default 0,
  primary key (course_id, choice_id)
);

alter table public.course_analytics_runs enable row level security;
alter table public.course_analytics_choice_totals enable row level security;

-- ---------- Доступ игрока к курсу (как в scorm_start_attempt) ----------
create or replace function public._course_analytics_assert_player_course_access(p_course_id uuid)
returns uuid
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
  v_project uuid;
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

  if exists (
    select 1 from public.project_members pm
    where pm.project_id = v_project and pm.user_id = v_user
  ) then
    select pm.role into v_role
    from public.project_members pm
    where pm.project_id = v_project and pm.user_id = v_user
    limit 1;
  else
    -- Для режима «Поделиться» допускаем анонимного listener
    -- (как в scorm_start_attempt): можно писать аналитические агрегаты
    -- только если курс опубликован.
    v_role := 'listener';
  end if;

  if coalesce(v_role, 'listener') = 'listener' and not coalesce(v_published, false) then
    raise exception 'Course not published';
  end if;

  return v_project;
end;
$$;

-- ---------- Запись завершённого прохождения (любой пакет) ----------
create or replace function public.course_analytics_record_run(
  p_course_id uuid,
  p_points integer,
  p_result text,
  p_learner_name text,
  p_metrics jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user uuid := auth.uid();
begin
  perform public._course_analytics_assert_player_course_access(p_course_id);

  insert into public.course_analytics_runs (
    course_id,
    user_id,
    points,
    result,
    learner_name,
    metrics
  )
  values (
    p_course_id,
    v_user,
    coalesce(p_points, 0),
    coalesce(nullif(trim(p_result), ''), ''),
    left(coalesce(p_learner_name, ''), 200),
    coalesce(p_metrics, '{}'::jsonb)
  );
end;
$$;

-- ---------- Инкремент счётчика по идентификатору выбора (интерактив, квизы и т.д.) ----------
create or replace function public.course_analytics_record_choice_event(
  p_course_id uuid,
  p_choice_id text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cid text := left(trim(coalesce(p_choice_id, '')), 200);
begin
  if length(v_cid) < 1 then
    return;
  end if;

  perform public._course_analytics_assert_player_course_access(p_course_id);

  insert into public.course_analytics_choice_totals (course_id, choice_id, count)
  values (p_course_id, v_cid, 1)
  on conflict (course_id, choice_id) do update
    set count = public.course_analytics_choice_totals.count + 1;
end;
$$;

-- ---------- Сводка по одному курсу (admin / methodologist проекта) ----------
create or replace function public.course_analytics_get(p_course_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_project uuid;
begin
  if v_uid is null then
    raise exception 'Not authenticated';
  end if;

  select pc.project_id into v_project
  from public.project_courses pc
  where pc.id = p_course_id;

  if v_project is null then
    raise exception 'Course not found';
  end if;

  if not exists (
    select 1 from public.project_members pm
    where pm.project_id = v_project
      and pm.user_id = v_uid
      and pm.role in ('admin', 'methodologist')
  ) then
    raise exception 'Forbidden';
  end if;

  return jsonb_build_object(
    'runs', coalesce(
      (
        select jsonb_agg(s.row_json)
        from (
          select jsonb_build_object(
            'ts', (floor(extract(epoch from r.finished_at) * 1000))::bigint,
            'date', to_char(r.finished_at::date, 'YYYY-MM-DD'),
            'points', r.points,
            'result', r.result,
            'name', coalesce(r.learner_name, ''),
            'chapterPoints', coalesce(r.metrics->'chapterPoints', '{}'::jsonb),
            'wrongByChapter', coalesce(r.metrics->'wrongByChapter', '{}'::jsonb)
          ) as row_json,
          r.finished_at
          from public.course_analytics_runs r
          where r.course_id = p_course_id
          order by r.finished_at asc
        ) s
      ),
      '[]'::jsonb
    ),
    'wrongChoices', coalesce(
      (
        select jsonb_object_agg(w.choice_id, w.count)
        from public.course_analytics_choice_totals w
        where w.course_id = p_course_id
      ),
      '{}'::jsonb
    )
  );
end;
$$;

grant execute on function public.course_analytics_record_run(uuid, integer, text, text, jsonb) to authenticated;
grant execute on function public.course_analytics_record_choice_event(uuid, text) to authenticated;
grant execute on function public.course_analytics_get(uuid) to authenticated;

revoke execute on function public._course_analytics_assert_player_course_access(uuid) from public;
revoke execute on function public._course_analytics_assert_player_course_access(uuid) from anon;
revoke execute on function public._course_analytics_assert_player_course_access(uuid) from authenticated;

-- =============================================================================
-- Миграция: если уже выполняли tech/supabase-peoplegames-analytics.sql
-- (перенос данных в общие таблицы и удаление старых имён). Запускать один раз.
-- =============================================================================
/*
-- Выполнить только если существуют старые объекты peoplegames_*:

insert into public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
select
  r.course_id,
  r.user_id,
  r.finished_at,
  r.points,
  r.result,
  r.learner_name,
  jsonb_build_object(
    'chapterPoints', coalesce(r.chapter_points, '{}'::jsonb),
    'wrongByChapter', coalesce(r.wrong_by_chapter, '{}'::jsonb)
  )
from public.peoplegames_course_runs r;

insert into public.course_analytics_choice_totals (course_id, choice_id, count)
select course_id, choice_id, count
from public.peoplegames_wrong_choice_totals
on conflict (course_id, choice_id) do update
  set count = public.course_analytics_choice_totals.count + excluded.count;

drop table if exists public.peoplegames_wrong_choice_totals cascade;
drop table if exists public.peoplegames_course_runs cascade;
drop function if exists public.peoplegames_record_run(uuid, integer, text, text, jsonb, jsonb);
drop function if exists public.peoplegames_record_wrong_choice(uuid, text);
drop function if exists public.peoplegames_get_analytics(uuid);
drop function if exists public._peoplegames_assert_player_course_access(uuid);
*/
