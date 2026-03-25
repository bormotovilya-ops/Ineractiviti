-- Приглашения в проект: колонка invite_token и RPC принятия по ссылке.
-- Этот скрипт НЕ отправляет почту. Письмо шлёт Edge Function send-project-invite + Resend (см. landing/README-SUPABASE.md).
-- Выполните в Supabase → SQL Editor.

-- Уникальный токен для ссылки app.html#invite=<uuid>
alter table public.project_invites
  add column if not exists invite_token uuid unique default gen_random_uuid();

update public.project_invites
set invite_token = gen_random_uuid()
where invite_token is null;

alter table public.project_invites
  alter column invite_token set default gen_random_uuid();

alter table public.project_invites
  alter column invite_token set not null;

-- Принятие приглашения по ссылке (email в JWT должен совпадать с project_invites.email)
create or replace function public.accept_project_invite_by_token(p_token uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid;
  v_email text;
  r public.project_invites%rowtype;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'Требуется войти в аккаунт';
  end if;

  select au.email into v_email
  from auth.users au
  where au.id = v_uid;

  if v_email is null or length(trim(v_email)) = 0 then
    raise exception 'У аккаунта нет email';
  end if;

  select * into r
  from public.project_invites
  where invite_token = p_token
    and status = 'pending'
  limit 1;

  if not found then
    raise exception 'Приглашение не найдено или уже использовано';
  end if;

  if lower(trim(r.email)) <> lower(trim(v_email)) then
    raise exception 'Войдите под тем же email, что в приглашении: %', r.email;
  end if;

  if not exists (
    select 1 from public.project_members pm
    where pm.project_id = r.project_id and pm.user_id = v_uid
  ) then
    insert into public.project_members (project_id, user_id, role)
    values (r.project_id, v_uid, r.role);
  end if;

  update public.project_invites
  set status = 'accepted'
  where id = r.id;

  return jsonb_build_object('project_id', r.project_id, 'invite_id', r.id);
end;
$$;

comment on function public.accept_project_invite_by_token(uuid) is 'Принять приглашение по invite_token из ссылки в письме';

revoke all on function public.accept_project_invite_by_token(uuid) from public;
grant execute on function public.accept_project_invite_by_token(uuid) to authenticated;
