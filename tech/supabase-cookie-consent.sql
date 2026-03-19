-- Cookie consent + UTM tracking for landings.
-- Run this script in Supabase SQL editor once.

create table if not exists public.cookie_consents (
  id uuid primary key default gen_random_uuid(),
  visitor_id text not null unique,
  user_id uuid null references auth.users(id) on delete set null,
  consent_accepted boolean not null default false,
  consented_at timestamptz null,
  landing_path text null,
  referrer text null,
  utm_source text null,
  utm_medium text null,
  utm_campaign text null,
  utm_term text null,
  utm_content text null,
  utm_id text null,
  gclid text null,
  fbclid text null,
  yclid text null,
  user_agent text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists cookie_consents_user_id_idx on public.cookie_consents(user_id);
create index if not exists cookie_consents_consented_at_idx on public.cookie_consents(consented_at);

create or replace function public.touch_cookie_consents_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists cookie_consents_set_updated_at on public.cookie_consents;
create trigger cookie_consents_set_updated_at
before update on public.cookie_consents
for each row
execute function public.touch_cookie_consents_updated_at();

alter table public.cookie_consents enable row level security;

-- Access is intended through SECURITY DEFINER RPC below.
drop policy if exists cookie_consents_no_direct_access on public.cookie_consents;
create policy cookie_consents_no_direct_access
on public.cookie_consents
for all
to anon, authenticated
using (false)
with check (false);

create or replace function public.upsert_cookie_consent(
  p_visitor_id text,
  p_landing_path text default null,
  p_referrer text default null,
  p_utm_source text default null,
  p_utm_medium text default null,
  p_utm_campaign text default null,
  p_utm_term text default null,
  p_utm_content text default null,
  p_utm_id text default null,
  p_gclid text default null,
  p_fbclid text default null,
  p_yclid text default null,
  p_consent_accepted boolean default true,
  p_consented_at timestamptz default now(),
  p_user_id uuid default null
)
returns public.cookie_consents
language plpgsql
security definer
set search_path = public
as $$
declare
  v_actor uuid := auth.uid();
  v_user_id uuid := null;
  v_row public.cookie_consents;
begin
  if p_visitor_id is null or length(trim(p_visitor_id)) = 0 then
    raise exception 'visitor_id is required';
  end if;

  -- Bind to authenticated user only when session exists.
  if v_actor is not null then
    v_user_id := v_actor;
  end if;

  insert into public.cookie_consents (
    visitor_id,
    user_id,
    consent_accepted,
    consented_at,
    landing_path,
    referrer,
    utm_source,
    utm_medium,
    utm_campaign,
    utm_term,
    utm_content,
    utm_id,
    gclid,
    fbclid,
    yclid,
    user_agent
  )
  values (
    trim(p_visitor_id),
    coalesce(v_user_id, p_user_id),
    coalesce(p_consent_accepted, true),
    coalesce(p_consented_at, now()),
    p_landing_path,
    p_referrer,
    p_utm_source,
    p_utm_medium,
    p_utm_campaign,
    p_utm_term,
    p_utm_content,
    p_utm_id,
    p_gclid,
    p_fbclid,
    p_yclid,
    current_setting('request.headers', true)::json->>'user-agent'
  )
  on conflict (visitor_id)
  do update set
    user_id = coalesce(public.cookie_consents.user_id, excluded.user_id),
    consent_accepted = excluded.consent_accepted,
    consented_at = coalesce(public.cookie_consents.consented_at, excluded.consented_at),
    landing_path = coalesce(excluded.landing_path, public.cookie_consents.landing_path),
    referrer = coalesce(excluded.referrer, public.cookie_consents.referrer),
    utm_source = coalesce(excluded.utm_source, public.cookie_consents.utm_source),
    utm_medium = coalesce(excluded.utm_medium, public.cookie_consents.utm_medium),
    utm_campaign = coalesce(excluded.utm_campaign, public.cookie_consents.utm_campaign),
    utm_term = coalesce(excluded.utm_term, public.cookie_consents.utm_term),
    utm_content = coalesce(excluded.utm_content, public.cookie_consents.utm_content),
    utm_id = coalesce(excluded.utm_id, public.cookie_consents.utm_id),
    gclid = coalesce(excluded.gclid, public.cookie_consents.gclid),
    fbclid = coalesce(excluded.fbclid, public.cookie_consents.fbclid),
    yclid = coalesce(excluded.yclid, public.cookie_consents.yclid),
    user_agent = coalesce(excluded.user_agent, public.cookie_consents.user_agent)
  returning * into v_row;

  return v_row;
end;
$$;

grant execute on function public.upsert_cookie_consent(
  text, text, text, text, text, text, text, text, text, text, text, text, boolean, timestamptz, uuid
) to anon, authenticated;

