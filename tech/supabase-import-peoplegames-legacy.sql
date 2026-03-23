-- Импорт аналитики PeopleGames из legacy JSON
-- Источник: c:/Users/User/Desktop/PeopleGames.txt
-- Сгенерировано автоматически.

DO $import$
DECLARE
  v_course_id uuid := 'b5fb729d-6c31-419a-a56f-4faf16310678';
  v_user_id uuid;
BEGIN
  SELECT pc.created_by INTO v_user_id
  FROM public.project_courses pc
  WHERE pc.id = v_course_id;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Не найден course_id % или у курса пустой created_by. Укажите корректный v_course_id.', v_course_id;
  END IF;

  DELETE FROM public.course_analytics_runs WHERE course_id = v_course_id;
  DELETE FROM public.course_analytics_choice_totals WHERE course_id = v_course_id;

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-15T22:59:41.28244+00:00'::timestamptz,
    0,
    'fired',
    LEFT('Алёна', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": 10, "ch3": -10, "ch4": 0, "ch5": -30}, "wrongByChapter": {"ch1": 0, "ch2": 0, "ch3": 1, "ch4": 2, "ch5": 5}, "legacy": {"session_id": 3371, "tg_user_id": null, "legacy_run_id": 15377, "run_date": "2026-03-15"}}'::jsonb
  );

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-13T11:38:11.238975+00:00'::timestamptz,
    110,
    'promoted',
    LEFT('Коллега', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": 10, "ch3": 20, "ch4": 20, "ch5": 50}, "wrongByChapter": {"ch1": 0, "ch2": 0, "ch3": 0, "ch4": 1, "ch5": 1}, "legacy": {"session_id": 3245, "tg_user_id": null, "legacy_run_id": 14663, "run_date": "2026-03-13"}}'::jsonb
  );

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-13T07:50:29.310436+00:00'::timestamptz,
    20,
    'fired',
    LEFT('Коллега', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": 0, "ch3": 20, "ch4": 0, "ch5": -10}, "wrongByChapter": {"ch1": 0, "ch2": 1, "ch3": 0, "ch4": 2, "ch5": 4}, "legacy": {"session_id": 3221, "tg_user_id": null, "legacy_run_id": 14526, "run_date": "2026-03-13"}}'::jsonb
  );

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-12T18:10:47.647467+00:00'::timestamptz,
    40,
    'fired',
    LEFT('Коллега', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": -20, "ch3": 0, "ch4": 20, "ch5": 30}, "wrongByChapter": {"ch1": 0, "ch2": 2, "ch3": 1, "ch4": 1, "ch5": 2}, "legacy": {"session_id": 3213, "tg_user_id": null, "legacy_run_id": 14454, "run_date": "2026-03-12"}}'::jsonb
  );

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-10T21:27:24.09983+00:00'::timestamptz,
    150,
    'promoted',
    LEFT('Илья', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": 10, "ch3": 20, "ch4": 40, "ch5": 70}, "wrongByChapter": {"ch1": 0, "ch2": 0, "ch3": 0, "ch4": 0, "ch5": 0}, "legacy": {"session_id": 3104, "tg_user_id": null, "legacy_run_id": 14072, "run_date": "2026-03-10"}}'::jsonb
  );

  INSERT INTO public.course_analytics_runs (course_id, user_id, finished_at, points, result, learner_name, metrics)
  VALUES (
    v_course_id,
    v_user_id,
    '2026-03-10T21:24:57.885884+00:00'::timestamptz,
    10,
    'fired',
    LEFT('Елена', 200),
    '{"chapterPoints": {"ch1": 10, "ch2": 10, "ch3": 0, "ch4": 20, "ch5": -30}, "wrongByChapter": {"ch1": 0, "ch2": 0, "ch3": 1, "ch4": 1, "ch5": 5}, "legacy": {"session_id": 3102, "tg_user_id": null, "legacy_run_id": 14064, "run_date": "2026-03-10"}}'::jsonb
  );

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch2_2_0', 200), 7)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch1_0', 200), 4)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_7_2', 200), 4)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch4_parent', 200), 3)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_4_2', 200), 3)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch2_1_0', 200), 2)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch3_2_0', 200), 2)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch4_trap_guarantee', 200), 2)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_2_2', 200), 2)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch1_1', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch2_3_0', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch3_1_0', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch3_1_1', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch4_fail_tyrant', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch4_fail_worker', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_1_2', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_2_0', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_3_0', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_3_1', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_4_1', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_5_0', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_5_1', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  INSERT INTO public.course_analytics_choice_totals (course_id, choice_id, count)
  VALUES (v_course_id, LEFT('ch5_5_2', 200), 1)
  ON CONFLICT (course_id, choice_id) DO UPDATE SET count = EXCLUDED.count;

  RAISE NOTICE 'Импорт завершён: runs=% wrong_choices=% для course_id=%', 6, 23, v_course_id;
END
$import$;
