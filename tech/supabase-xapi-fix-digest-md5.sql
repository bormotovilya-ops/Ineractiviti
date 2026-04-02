-- Исправление: function digest(bytea, unknown) does not exist (pgcrypto не включён / не в search_path).
-- Заменяем SHA256 на встроенный md5(text) в _xapi_make_idempotency_key.
-- Выполните в SQL Editor, затем: notify pgrst, 'reload schema';

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

notify pgrst, 'reload schema';
