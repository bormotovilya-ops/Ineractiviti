-- Обход 404 / Proxy-Status: PostgREST; error=42883 на /rpc/ingest_event при том,
-- что в SQL public.ingest_event(p_event jsonb) вызывается нормально.
--
-- 1) Права для роли PostgREST (часто нужны для RPC через REST).
-- 2) Тонкая обёртка с другим имени — иногда PostgREST кэширует/резолвит иначе.
--
-- Выполните в SQL Editor одного проекта с тем же ref, что в SUPABASE_URL в приложении.

-- Права на «исходную» функцию
grant execute on function public.ingest_event(jsonb) to authenticated;
grant execute on function public.ingest_event(jsonb) to service_role;

do $$
begin
  execute 'grant execute on function public.ingest_event(jsonb) to authenticator';
exception
  when undefined_object then
    raise notice 'role authenticator missing, skip';
  when others then
    raise notice 'grant authenticator skipped: %', sqlerrm;
end;
$$;

-- Обёртка для REST (вызывайте из клиента: rpc('xapi_ingest_event', { p_event: ... }))
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

do $$
begin
  execute 'grant execute on function public.xapi_ingest_event(jsonb) to authenticator';
exception
  when others then
    raise notice 'grant authenticator (wrapper) skipped: %', sqlerrm;
end;
$$;

notify pgrst, 'reload schema';
