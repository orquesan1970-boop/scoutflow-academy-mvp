-- =============================================================================
-- Simulador mínimo de lo que Supabase ya trae, para probar database/schema_v3.sql
-- en un PostgreSQL normal (16 o superior). NO se ejecuta en Supabase.
--   · el esquema `auth` con `auth.users` y `auth.uid()`
--   · los roles `authenticated` y `anon`
-- `auth.uid()` lee el usuario de `request.jwt.claim.sub`, como en Supabase.
-- =============================================================================
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text);
create or replace function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
end $$;
grant usage on schema auth to authenticated, anon;
grant execute on function auth.uid() to authenticated, anon;
