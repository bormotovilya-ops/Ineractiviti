-- Агрегированная аналитика xAPI по курсу для кабинета (admin / methodologist).
-- Выполните в SQL Editor после tech/supabase-xapi-event-layer.sql
-- (должен совпадать с блоком xapi_analytics_get в tech/supabase-xapi-interaction-migration.sql)

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

do $g$
begin
  execute 'grant execute on function public.xapi_analytics_get(uuid) to authenticator';
exception when others then
  null;
end;
$g$;

notify pgrst, 'reload schema';
