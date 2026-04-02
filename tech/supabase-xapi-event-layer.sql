-- xAPI-совместимый слой событий (MVP) для LMS на Supabase.
-- Выполните в SQL Editor после project_courses, project_members и
-- tech/supabase-course-analytics-lms.sql (функция _course_analytics_assert_player_course_access).
--
-- После деплоя замените базовый URL LMS в public.xapi_lms_base_url() на продакшен-домен
-- или добавьте строку в public.xapi_settings (см. ниже).

-- pgcrypto не обязателен: idempotency через встроенный md5(text)

-- ---------- Базовый URL LMS (для actor.homePage и activity id) ----------
create table if not exists public.xapi_settings (
  id smallint primary key default 1 check (id = 1),
  lms_base_url text not null default 'https://YOUR_LMS_DOMAIN'
);

insert into public.xapi_settings (id, lms_base_url)
values (1, 'https://YOUR_LMS_DOMAIN')
on conflict (id) do nothing;

create or replace function public.xapi_lms_base_url()
returns text
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    nullif(trim(s.lms_base_url), ''),
    'https://YOUR_LMS_DOMAIN'
  )
  from public.xapi_settings s
  where s.id = 1;
$$;

alter table public.xapi_settings enable row level security;

-- Только через service role / владельца; клиентам не нужен прямой доступ
revoke all on public.xapi_settings from public;
revoke all on public.xapi_settings from anon;
revoke all on public.xapi_settings from authenticated;

-- ---------- Таблица statement'ов ----------
create table if not exists public.xapi_statements (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  course_id uuid references public.project_courses (id) on delete set null,
  verb_id text not null,
  object_id text not null,
  statement jsonb not null,
  occurred_at timestamptz not null,
  ingested_at timestamptz not null default now(),
  idempotency_key text not null unique
);

create index if not exists xapi_statements_user_occurred_idx
  on public.xapi_statements (user_id, occurred_at desc);

create index if not exists xapi_statements_course_occurred_idx
  on public.xapi_statements (course_id, occurred_at desc)
  where course_id is not null;

alter table public.xapi_statements enable row level security;

revoke all on public.xapi_statements from public;
grant select on public.xapi_statements to authenticated;

drop policy if exists xapi_statements_select_own on public.xapi_statements;
drop policy if exists xapi_statements_select_project_staff on public.xapi_statements;

create policy xapi_statements_select_own
  on public.xapi_statements
  for select
  to authenticated
  using (user_id = auth.uid());

create policy xapi_statements_select_project_staff
  on public.xapi_statements
  for select
  to authenticated
  using (
    course_id is not null
    and exists (
      select 1
      from public.project_courses pc
      join public.project_members pm on pm.project_id = pc.project_id
      where pc.id = xapi_statements.course_id
        and pm.user_id = auth.uid()
        and pm.role in ('admin', 'methodologist')
    )
  );

-- ---------- Вспомогательные: verb / display ----------
create or replace function public._xapi_verb_display_en(p_verb_id text)
returns text
language sql
immutable
as $$
  select case p_verb_id
    when 'http://adlnet.gov/expapi/verbs/initialized' then 'Initialized'
    when 'http://adlnet.gov/expapi/verbs/completed' then 'Completed'
    when 'http://adlnet.gov/expapi/verbs/answered' then 'Answered'
    when 'http://adlnet.gov/expapi/verbs/experienced' then 'Experienced'
    when 'http://adlnet.gov/expapi/verbs/progressed' then 'Progressed'
    else 'Verb'
  end;
$$;

-- ---------- Mapper: внутреннее событие → xAPI statement (jsonb) ----------
create or replace function public.map_internal_event_to_xapi(p_event jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_base text := public.xapi_lms_base_url();
  v_type text := nullif(trim(both from coalesce(p_event->>'type', '')), '');
  v_user_txt text := nullif(trim(both from coalesce(p_event->>'user_id', '')), '');
  v_user uuid;
  v_course_txt text := nullif(trim(both from coalesce(p_event->>'course_id', '')), '');
  v_course uuid;
  v_lesson text := nullif(trim(both from coalesce(p_event->>'lesson_id', '')), '');
  v_question text := nullif(trim(both from coalesce(p_event->>'question_id', '')), '');
  v_verb_id text;
  v_object_kind text;
  v_object_slug text;
  v_object_id text;
  v_ts timestamptz;
  v_payload jsonb := coalesce(p_event->'payload', '{}'::jsonb);
  v_result jsonb;
  v_success boolean;
  v_score numeric;
  v_response text;
  v_progress numeric;
  v_stmt jsonb;
  v_parent jsonb;
begin
  if v_type is null or length(v_type) < 1 then
    return null;
  end if;

  begin
    v_user := v_user_txt::uuid;
  exception when others then
    return null;
  end;

  if v_course_txt is not null and length(v_course_txt) > 0 then
    begin
      v_course := v_course_txt::uuid;
    exception when others then
      v_course := null;
    end;
  end if;

  begin
    if (p_event->>'occurred_at') is not null and length(trim(both from (p_event->>'occurred_at'))) > 0 then
      v_ts := (p_event->>'occurred_at')::timestamptz;
    else
      v_ts := now();
    end if;
  exception when others then
    v_ts := now();
  end;

  v_verb_id := case v_type
    when 'user_started_course' then 'http://adlnet.gov/expapi/verbs/initialized'
    when 'user_completed_course' then 'http://adlnet.gov/expapi/verbs/completed'
    when 'user_answered_question' then 'http://adlnet.gov/expapi/verbs/answered'
    when 'user_progressed' then 'http://adlnet.gov/expapi/verbs/progressed'
    when 'scorm_start_attempt' then 'http://adlnet.gov/expapi/verbs/initialized'
    when 'scorm_finish_attempt' then 'http://adlnet.gov/expapi/verbs/completed'
    when 'scorm_progress' then 'http://adlnet.gov/expapi/verbs/progressed'
    when 'peoplegames_run_save' then 'http://adlnet.gov/expapi/verbs/completed'
    when 'peoplegames_wrong_choice' then 'http://adlnet.gov/expapi/verbs/answered'
    else null
  end;

  if v_verb_id is null then
    return null;
  end if;

  -- Объект активности: приоритет question > lesson > course
  if v_question is not null and length(v_question) > 0 then
    v_object_kind := 'question';
    v_object_slug := v_question;
  elsif v_lesson is not null and length(v_lesson) > 0 then
    v_object_kind := 'lesson';
    v_object_slug := v_lesson;
  elsif v_course is not null then
    v_object_kind := 'course';
    v_object_slug := v_course::text;
  else
    return null;
  end if;

  v_object_id := rtrim(v_base, '/') || '/xapi/activities/' || v_object_kind || '/' || v_object_slug;

  v_success := case when v_payload ? 'success' then (v_payload->>'success')::boolean else null end;
  v_score := case when v_payload ? 'score' and (v_payload->>'score') ~ '^-?[0-9]+(\.[0-9]+)?$'
    then (v_payload->>'score')::numeric else null end;
  v_response := nullif(trim(both from coalesce(v_payload->>'response', '')), '');
  v_progress := case when v_payload ? 'progress' and (v_payload->>'progress') ~ '^-?[0-9]+(\.[0-9]+)?$'
    then (v_payload->>'progress')::numeric else null end;

  v_result := null;
  if v_verb_id in (
    'http://adlnet.gov/expapi/verbs/answered',
    'http://adlnet.gov/expapi/verbs/completed',
    'http://adlnet.gov/expapi/verbs/progressed'
  ) then
    v_result := jsonb_strip_nulls(jsonb_build_object(
      'success', v_success,
      'response', v_response,
      'score', case when v_score is not null then jsonb_build_object('raw', v_score) else null end,
      'completion', case when v_type in ('user_completed_course', 'peoplegames_run_save', 'scorm_finish_attempt') then true else null end,
      'progress', v_progress
    ));
    if v_result = '{}'::jsonb then
      v_result := null;
    end if;
  end if;

  if v_course is not null then
    v_parent := jsonb_build_array(jsonb_build_object(
      'objectType', 'Activity',
      'id', rtrim(v_base, '/') || '/xapi/activities/course/' || v_course::text
    ));
  else
    v_parent := null;
  end if;

  v_stmt := jsonb_build_object(
    'actor', jsonb_build_object(
      'objectType', 'Agent',
      'account', jsonb_build_object(
        'homePage', v_base,
        'name', v_user::text
      )
    ),
    'verb', jsonb_build_object(
      'id', v_verb_id,
      'display', jsonb_build_object('en-US', public._xapi_verb_display_en(v_verb_id))
    ),
    'object', jsonb_build_object(
      'objectType', 'Activity',
      'id', v_object_id
    ),
    'timestamp', v_ts
  );

  if v_result is not null then
    v_stmt := v_stmt || jsonb_build_object('result', v_result);
  end if;

  if v_parent is not null then
    v_stmt := v_stmt || jsonb_build_object(
      'context', jsonb_build_object(
        'contextActivities', jsonb_build_object('parent', v_parent)
      )
    );
  end if;

  return v_stmt;
end;
$$;

-- ---------- Проверка минимальной валидности statement ----------
create or replace function public._xapi_statement_is_valid(p_statement jsonb)
returns boolean
language sql
immutable
as $$
  select
    p_statement is not null
    and p_statement ? 'actor'
    and p_statement ? 'verb'
    and p_statement ? 'object'
    and coalesce(p_statement->'actor'->>'objectType', '') = 'Agent'
    and coalesce(p_statement->'actor'->'account'->>'homePage', '') <> ''
    and coalesce(p_statement->'actor'->'account'->>'name', '') <> ''
    and coalesce(p_statement->'verb'->>'id', '') <> ''
    and coalesce(p_statement->'object'->>'objectType', '') = 'Activity'
    and coalesce(p_statement->'object'->>'id', '') <> '';
$$;

-- ---------- Idempotency (если клиент не передал ключ) ----------
-- Встроенный md5(text) — без расширения pgcrypto (digest/ sha256 там недоступны без enable)
create or replace function public._xapi_make_idempotency_key(p_event jsonb, p_actor uuid)
returns text
language sql
stable
as $$
  select md5(
    concat_ws(
      '|',
      p_actor::text,
      coalesce(nullif(trim(both from p_event->>'type'), ''), ''),
      coalesce(nullif(trim(both from p_event->>'course_id'), ''), ''),
      coalesce(nullif(trim(both from p_event->>'lesson_id'), ''), ''),
      coalesce(nullif(trim(both from p_event->>'question_id'), ''), ''),
      coalesce(nullif(trim(both from p_event->>'occurred_at'), ''), ''),
      coalesce(p_event->'payload'::text, '{}')
    )
  );
$$;

-- ---------- Ingest ----------
create or replace function public.ingest_event(p_event jsonb)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
  v_event jsonb;
  v_stmt jsonb;
  v_course uuid;
  v_idem text;
  v_occurred timestamptz;
  v_verb text;
  v_obj text;
  v_new_id uuid;
begin
  if v_uid is null then
    return jsonb_build_object('stored', false, 'error', 'not_authenticated');
  end if;

  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    return jsonb_build_object('stored', false, 'error', 'invalid_payload');
  end if;

  -- user_id из события игнорируем; источник истины — JWT
  v_event := p_event - 'user_id' || jsonb_build_object('user_id', v_uid::text);

  if (v_event->>'course_id') is not null and length(trim(both from (v_event->>'course_id'))) > 0 then
    begin
      v_course := trim(both from (v_event->>'course_id'))::uuid;
      perform public._course_analytics_assert_player_course_access(v_course);
    exception when others then
      return jsonb_build_object('stored', false, 'error', 'invalid_course_or_access');
    end;
  end if;

  v_stmt := public.map_internal_event_to_xapi(v_event);
  if not public._xapi_statement_is_valid(v_stmt) then
    return jsonb_build_object('stored', false, 'error', 'invalid_statement');
  end if;

  v_verb := v_stmt->'verb'->>'id';
  v_obj := v_stmt->'object'->>'id';

  begin
    if (v_event->>'occurred_at') is not null and length(trim(both from (v_event->>'occurred_at'))) > 0 then
      v_occurred := (v_event->>'occurred_at')::timestamptz;
    else
      v_occurred := null;
    end if;
  exception when others then
    v_occurred := null;
  end;
  v_occurred := coalesce(v_occurred, (v_stmt->>'timestamp')::timestamptz, now());

  v_idem := nullif(trim(both from coalesce(v_event->>'idempotency_key', '')), '');
  if v_idem is null then
    v_idem := public._xapi_make_idempotency_key(v_event, v_uid);
  end if;

  insert into public.xapi_statements (
    user_id,
    course_id,
    verb_id,
    object_id,
    statement,
    occurred_at,
    idempotency_key
  )
  values (
    v_uid,
    v_course,
    v_verb,
    v_obj,
    v_stmt,
    v_occurred,
    v_idem
  )
  on conflict (idempotency_key) do nothing
  returning id into v_new_id;

  if v_new_id is null then
    return jsonb_build_object('stored', false, 'duplicate', true);
  end if;

  return jsonb_build_object(
    'stored', true,
    'id', v_new_id
  );
end;
$$;

-- ---------- Просмотр (отладка / кабинет) ----------
create or replace function public.xapi_statements_list(
  p_course_id uuid default null,
  p_user_id uuid default null,
  p_limit integer default 100
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller uuid := auth.uid();
  v_uid uuid;
  v_lim int := greatest(1, least(coalesce(p_limit, 100), 500));
  v_project uuid;
  v_role text;
begin
  if v_caller is null then
    raise exception 'Not authenticated';
  end if;

  v_uid := coalesce(p_user_id, v_caller);

  if v_uid <> v_caller then
    if p_course_id is null then
      raise exception 'course_id required when filtering by another user';
    end if;

    select pc.project_id into v_project
    from public.project_courses pc
    where pc.id = p_course_id;

    if v_project is null then
      raise exception 'Course not found';
    end if;

    select pm.role into v_role
    from public.project_members pm
    where pm.project_id = v_project
      and pm.user_id = v_caller
    limit 1;

    if v_role is null or v_role not in ('admin', 'methodologist') then
      raise exception 'Forbidden';
    end if;
  end if;

  if p_course_id is not null and v_uid = v_caller then
    perform public._course_analytics_assert_player_course_access(p_course_id);
  end if;

  return coalesce(
    (
      select jsonb_agg(row_to_json(s)::jsonb)
      from (
        select
          x.id,
          x.user_id,
          x.course_id,
          x.verb_id,
          x.object_id,
          x.statement,
          x.occurred_at,
          x.ingested_at,
          x.idempotency_key
        from public.xapi_statements x
        where (p_course_id is null or x.course_id = p_course_id)
          and x.user_id = v_uid
        order by x.occurred_at desc
        limit v_lim
      ) s
    ),
    '[]'::jsonb
  );
end;
$$;

grant execute on function public.map_internal_event_to_xapi(jsonb) to authenticated;
grant execute on function public.ingest_event(jsonb) to authenticated;
grant execute on function public.ingest_event(jsonb) to service_role;
grant execute on function public.xapi_statements_list(uuid, uuid, integer) to authenticated;
grant execute on function public.xapi_statements_list(uuid, uuid, integer) to service_role;

-- Обёртка для REST (клиент: rpc('xapi_ingest_event', { p_event })) — см. tech/supabase-xapi-42883-rest-workaround.sql
create or replace function public.xapi_ingest_event(p_event jsonb)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select public.ingest_event(p_event);
$$;

grant execute on function public.xapi_ingest_event(jsonb) to authenticated;
grant execute on function public.xapi_ingest_event(jsonb) to service_role;

do $g$
begin
  execute 'grant execute on function public.ingest_event(jsonb) to authenticator';
exception when others then
  null;
end;
$g$;

do $g$
begin
  execute 'grant execute on function public.xapi_ingest_event(jsonb) to authenticator';
exception when others then
  null;
end;
$g$;

-- PostgREST подхватывает новые RPC без перезапуска проекта (Supabase Hosted)
notify pgrst, 'reload schema';

revoke execute on function public.xapi_lms_base_url() from public;
revoke execute on function public.xapi_lms_base_url() from anon;
-- authenticated не вызывает напрямую (только из map), но security definer читает

revoke execute on function public._xapi_verb_display_en(text) from public;
revoke execute on function public._xapi_statement_is_valid(jsonb) from public;
revoke execute on function public._xapi_make_idempotency_key(jsonb, uuid) from public;
