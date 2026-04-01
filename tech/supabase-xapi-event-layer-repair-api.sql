-- Если в браузере 404 на POST .../rest/v1/rpc/ingest_event, а функция есть в БД:
-- 1) передайте права ролям API PostgREST;
-- 2) перезагрузите кэш схемы PostgREST.
--
-- Выполните в Supabase SQL Editor (один раз после миграции xapi).

grant execute on function public.ingest_event(jsonb) to authenticated;
grant execute on function public.ingest_event(jsonb) to service_role;

grant execute on function public.map_internal_event_to_xapi(jsonb) to authenticated;
grant execute on function public.xapi_statements_list(uuid, uuid, integer) to authenticated;
grant execute on function public.xapi_statements_list(uuid, uuid, integer) to service_role;

-- PostgREST подхватывает новые функции без перезапуска (на Hosted Supabase):
notify pgrst, 'reload schema';

-- Проверка: должно быть true для authenticated
select has_function_privilege('authenticated', 'public.ingest_event(jsonb)', 'execute') as auth_can_execute_ingest;
