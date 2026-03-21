-- Проверка результатов прохождения SCORM (Supabase → SQL Editor).
--
-- ВАЖНО: выполняйте ОДИН блок за раз. Если вставить весь файл сразу, редактор часто
-- показывает только последний результат — кажется, что «пусто», хотя сработал другой запрос.
--
-- «Success. No rows returned» у запросов 1–2 чаще всего значит:
--   • не заменили PLACEHOLDER_EMAIL на реальный email (осталось буквально PLACEHOLDER_EMAIL);
--   • в auth.users другой email (регистрация через провайдера, опечатка);
--   • попыток ещё нет: RPC scorm_start_attempt не отработал (ошибка в консоли плеера) или другой проект/курс.
--
-- Частая картина: много строк в course_scorm_attempts, везде status = in_progress, completed_at null,
-- progress_percent = 0. Так бывает, если пакет не вызывает LMSFinish при выходе или вкладку закрыли без завершения
-- сессии SCORM. Детальный прогресс смотрите в course_scorm_sco_states.cmi_data (запрос Д4).

-- =============================================================================
-- ДИАГНОСТИКА — по очереди, по одному блоку
-- =============================================================================

-- --- Д1) Есть ли вообще строки в таблице попыток ---
select count(*)::bigint as total_rows_in_course_scorm_attempts
from public.course_scorm_attempts;

-- --- Д2) Найти ваш аккаунт по email (подставьте свой адрес) ---
select id as user_id, email, created_at
from auth.users
where lower(email) = lower('PLACEHOLDER_EMAIL');

-- Если пусто — поиск по части строки:
-- select id, email from auth.users where email ilike '%ваш_фрагмент%';

-- --- Д3) Последние попытки с email пользователя (видно, под каким логином они пишутся) ---
select
  a.id as attempt_id,
  a.attempt_number,
  a.status,
  a.started_at,
  a.completed_at,
  u.email as user_email,
  pc.title as course_title
from public.course_scorm_attempts a
join auth.users u on u.id = a.user_id
left join public.project_courses pc on pc.id = a.course_id
order by a.started_at desc
limit 30;

-- Если Д1 = 0 → в БД попыток никто не записал (смотрите консоль scorm-player при открытии курса).
-- Если Д3 есть строки, а запросы 1–2 пустые → в 1–2 неверный email или не тот user_id.

-- --- Д4) Детальные CMI по последним попыткам (подставьте user_id из Д2 / Table Editor) ---
-- Показывает, сохранял ли пакет статус/баллы в course_scorm_sco_states, даже если строка попытки ещё in_progress.
select
  a.id as attempt_id,
  a.attempt_number,
  a.started_at,
  a.status as attempt_row_status,
  sco.sco_identifier,
  s.cmi_data ->> 'cmi.core.lesson_status' as lesson_status,
  s.cmi_data ->> 'cmi.core.lesson_mode' as lesson_mode,
  s.cmi_data ->> 'cmi.core.score.raw' as score_raw,
  s.updated_at as cmi_updated_at
from public.course_scorm_attempts a
join public.course_scorm_sco_states s on s.attempt_id = a.id
left join public.course_scorm_scos sco on sco.id = s.sco_id
where a.user_id = 'PLACEHOLDER_USER_ID'::uuid
order by a.started_at desc, sco.sort_order nulls last
limit 40;

-- =============================================================================
-- ОСНОВНЫЕ ЗАПРОСЫ — замените PLACEHOLDER_EMAIL; выполняйте отдельно от диагностики
-- =============================================================================

-- Имена колонок: ниже completed_at. Если у вас finished_at — замените в SELECT.

-- ========== 1) Все попытки выбранного пользователя по курсам ==========
with u as (
  select id as user_id
  from auth.users
  where lower(email) = lower('PLACEHOLDER_EMAIL')
  limit 1
)
select
  a.id as attempt_id,
  a.attempt_number,
  a.status,
  a.started_at,
  a.completed_at,
  pc.title as course_title,
  v.version_number as scorm_package_version
from public.course_scorm_attempts a
join u on u.user_id = a.user_id
left join public.project_courses pc on pc.id = a.course_id
left join public.course_scorm_package_versions v on v.id = a.package_version_id
order by a.started_at desc;

-- ========== 2) Сохранённые поля CMI по попыткам этого пользователя ==========
with u as (
  select id as user_id
  from auth.users
  where lower(email) = lower('PLACEHOLDER_EMAIL')
  limit 1
),
attempts as (
  select a.id, a.attempt_number, a.status, a.started_at, a.completed_at
  from public.course_scorm_attempts a
  join u on u.user_id = a.user_id
)
select
  t.attempt_number,
  t.status as attempt_status,
  t.started_at,
  t.completed_at,
  sco.sco_identifier,
  s.updated_at as cmi_saved_at,
  s.cmi_data ->> 'cmi.core.lesson_status' as lesson_status,
  s.cmi_data ->> 'cmi.core.lesson_location' as lesson_location,
  s.cmi_data ->> 'cmi.core.score.raw' as score_raw,
  s.cmi_data ->> 'cmi.core.score.max' as score_max,
  left(s.cmi_data ->> 'cmi.suspend_data', 120) as suspend_data_preview
from attempts t
join public.course_scorm_sco_states s on s.attempt_id = t.id
left join public.course_scorm_scos sco on sco.id = s.sco_id
order by t.started_at desc, sco.sort_order nulls last;

-- Как интерпретировать:
-- • Несколько проходов курса → несколько строк с разными attempt_number.
-- • LMSFinish → status = 'completed' и обычно заполнен completed_at.
-- • Закрыли вкладку без LMSFinish → часто in_progress, но cmi_data мог обновиться по Commit.
-- • SCORM 2004 — другие ключи в cmi_data (не cmi.core.*).
