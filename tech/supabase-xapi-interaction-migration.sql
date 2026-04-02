-- Семантика событий: context.extensions + колонка interaction для отчётов.
-- Выполните в SQL Editor после существующей схемы xAPI.
-- Если база развёрнута из актуального tech/supabase-xapi-event-layer.sql (с колонкой interaction),
-- блоки ALTER/INDEX и CREATE OR REPLACE функций идемпотентны; при необходимости обновите только расхождения.

alter table public.xapi_statements
  add column if not exists interaction text;

create index if not exists xapi_statements_course_interaction_idx
  on public.xapi_statements (course_id, interaction)
  where course_id is not null;

-- ---------- Mapper: extensions + новые типы PeopleGames ----------
create or replace function public.map_internal_event_to_xapi(p_event jsonb)
returns jsonb
language plpgsql
stable
set search_path = public
as $$
declare
  v_base text := public.xapi_lms_base_url();
  v_ext_key text := rtrim(public.xapi_lms_base_url(), '/') || '/xapi/extensions/lms';
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
  v_ix text;
  v_src text;
  v_ch text;
  v_ext_inner jsonb;
  v_ctx jsonb;
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
    when 'peoplegames_correct_choice' then 'http://adlnet.gov/expapi/verbs/answered'
    when 'peoplegames_hint_used' then 'http://adlnet.gov/expapi/verbs/experienced'
    else null
  end;

  if v_verb_id is null then
    return null;
  end if;

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

  v_ix := nullif(trim(both from coalesce(v_payload->>'interaction', '')), '');
  if v_ix is null then
    v_ix := case v_type
      when 'peoplegames_wrong_choice' then 'wrong_choice'
      when 'peoplegames_correct_choice' then 'correct_answer'
      when 'peoplegames_hint_used' then 'hint'
      when 'peoplegames_run_save' then 'course_completed'
      when 'scorm_start_attempt' then 'session_start'
      when 'scorm_progress' then 'progress'
      when 'scorm_finish_attempt' then 'session_end'
      else null
    end;
  end if;

  v_src := nullif(trim(both from coalesce(v_payload->>'source', '')), '');
  if v_src is null then
    if v_type like 'peoplegames%' then v_src := 'peoplegames';
    elsif v_type like 'scorm%' then v_src := 'scorm';
    elsif v_type like 'user_%' then v_src := 'lms';
    end if;
  end if;

  v_ch := nullif(trim(both from coalesce(v_payload->>'chapter', '')), '');

  v_ext_inner := jsonb_strip_nulls(jsonb_build_object(
    'interaction', v_ix,
    'source', v_src,
    'chapter', v_ch
  ));

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

  v_ctx := jsonb_build_object(
    'extensions', jsonb_build_object(v_ext_key, v_ext_inner)
  );
  if v_parent is not null then
    v_ctx := jsonb_build_object(
      'contextActivities', jsonb_build_object('parent', v_parent),
      'extensions', jsonb_build_object(v_ext_key, v_ext_inner)
    );
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
    'timestamp', v_ts,
    'context', v_ctx
  );

  if v_result is not null then
    v_stmt := v_stmt || jsonb_build_object('result', v_result);
  end if;

  return v_stmt;
end;
$$;

-- ---------- ingest: сохраняем interaction ----------
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
  v_interaction text;
  v_ext_key text;
begin
  if v_uid is null then
    return jsonb_build_object('stored', false, 'error', 'not_authenticated');
  end if;

  if p_event is null or jsonb_typeof(p_event) <> 'object' then
    return jsonb_build_object('stored', false, 'error', 'invalid_payload');
  end if;

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

  v_ext_key := rtrim(public.xapi_lms_base_url(), '/') || '/xapi/extensions/lms';
  v_interaction := null;
  if v_stmt->'context' ? 'extensions' then
    select (e.value->>'interaction')::text into v_interaction
    from jsonb_each(v_stmt->'context'->'extensions') e
    where e.key = v_ext_key
    limit 1;
  end if;

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
    idempotency_key,
    interaction
  )
  values (
    v_uid,
    v_course,
    v_verb,
    v_obj,
    v_stmt,
    v_occurred,
    v_idem,
    v_interaction
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

-- ---------- Аналитика: разрез по смыслу (interaction) ----------
create or replace function public.xapi_analytics_get(p_course_id uuid)
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
    'total_events',
      (select count(*)::bigint from public.xapi_statements x where x.course_id = p_course_id),
    'unique_learners',
      (select count(distinct x.user_id)::bigint from public.xapi_statements x where x.course_id = p_course_id),
    'by_verb',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'verb_id', v.verb_id,
              'label',
                case
                  when v.verb_id like '%/initialized' then 'Инициализация'
                  when v.verb_id like '%/completed' then 'Завершение'
                  when v.verb_id like '%/answered' then 'Ответы'
                  when v.verb_id like '%/experienced' then 'Просмотр'
                  when v.verb_id like '%/progressed' then 'Прогресс'
                  else v.verb_id
                end,
              'count', v.cnt
            ) order by v.cnt desc
          )
          from (
            select x.verb_id, count(*)::bigint as cnt
            from public.xapi_statements x
            where x.course_id = p_course_id
            group by x.verb_id
          ) v
        ),
        '[]'::jsonb
      ),
    'by_interaction',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'code', bx.ix,
              'label',
                case bx.ix
                  when 'wrong_choice' then 'Неверный ответ'
                  when 'correct_answer' then 'Верный ответ'
                  when 'hint' then 'Подсказка'
                  when 'course_completed' then 'Завершение сценария'
                  when 'session_start' then 'Старт сессии (SCORM)'
                  when 'progress' then 'Прогресс (SCORM)'
                  when 'session_end' then 'Завершение сессии (SCORM)'
                  when 'unknown' then 'Без типа (старые записи)'
                  else bx.ix
                end,
              'count', bx.cnt
            ) order by bx.cnt desc
          )
          from (
            select coalesce(x.interaction, 'unknown') as ix, count(*)::bigint as cnt
            from public.xapi_statements x
            where x.course_id = p_course_id
            group by coalesce(x.interaction, 'unknown')
          ) bx
        ),
        '[]'::jsonb
      ),
    'by_day',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'date', d.d,
              'count', d.cnt
            ) order by d.d
          )
          from (
            select to_char(x.occurred_at::date, 'YYYY-MM-DD') as d, count(*)::bigint as cnt
            from public.xapi_statements x
            where x.course_id = p_course_id
            group by x.occurred_at::date
          ) d
        ),
        '[]'::jsonb
      ),
    'top_users',
      coalesce(
        (
          select jsonb_agg(
            jsonb_build_object(
              'user_id', u.uid,
              'event_count', u.cnt
            ) order by u.cnt desc
          )
          from (
            select x.user_id as uid, count(*)::bigint as cnt
            from public.xapi_statements x
            where x.course_id = p_course_id
            group by x.user_id
            order by cnt desc
            limit 10
          ) u
        ),
        '[]'::jsonb
      )
  );
end;
$$;

grant execute on function public.xapi_analytics_get(uuid) to authenticated;
grant execute on function public.xapi_analytics_get(uuid) to service_role;

notify pgrst, 'reload schema';
