-- ============================================================================
-- ScoutFlow Academy — AUTENTICACIÓN, ROLES Y PERMISOS  ·  v2
-- ----------------------------------------------------------------------------
-- Ruta en el repo:  database/auth_schema_v2.sql
-- Versión: 2026-08-02
--
-- ESTE ARCHIVO SUSTITUYE A:
--     auth_schema.sql        (v1)
--     auth_schema_fixes.sql  (parche 001)
--
-- Es el ÚNICO archivo que hay que ejecutar. Orden en Supabase:
--     1) database/schema.sql      (tablas base: academies, players, teams...)
--     2) database/auth_schema_v2.sql   <-- este
--
-- Es IDEMPOTENTE: se puede ejecutar varias veces sin romper nada.
-- No borra columnas (ver la sección final, LIMPIEZA PENDIENTE).
--
-- Cuatro conceptos separados:
--   IDENTIDAD -> quién eres          -> Supabase Auth (correo + enlace mágico/OTP)
--   ROL       -> qué eres en el club -> users_profile.role
--   ALCANCE   -> sobre quién         -> team_coaches / player_access / segment
--   PERMISOS  -> qué puede tocar     -> role_permissions + RLS
-- ============================================================================


-- ############################################################################
-- BLOQUE 1 · PERFIL DE USUARIO
-- ############################################################################

create table if not exists users_profile (
  id          uuid primary key references auth.users(id) on delete cascade,
  academy_id  uuid references academies(id) on delete cascade,
  full_name   text,
  email       text unique not null,
  role        text not null default 'padre',
              -- director | dt_general | dt_femenino | dt_masculino | dt_escuelas
              -- | dt_minis | preparador_fisico | scout | entrenador
              -- | administrativo | padre | jugador
  segment     text,
  phone       text,
  active      boolean default true,
  created_at  timestamptz default now()
);

create or replace function app_handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into users_profile (id, email, full_name)
  values (new.id, new.email, coalesce(new.raw_user_meta_data->>'full_name', new.email))
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users for each row execute function app_handle_new_user();


-- ############################################################################
-- BLOQUE 2 · ALCANCE
-- ############################################################################

create table if not exists team_coaches (
  user_id uuid references users_profile(id) on delete cascade,
  team_id uuid references teams(id) on delete cascade,
  primary key (user_id, team_id)
);

-- Padre y madre = DOS filas al mismo jugador.
-- El propio jugador también se enlaza aquí, con relation = 'Jugador'.
create table if not exists player_access (
  user_id    uuid references users_profile(id) on delete cascade,
  player_id  uuid references players(id) on delete cascade,
  relation   text,                    -- Padre | Madre | Tutor | Jugador
  can_pay    boolean default true,
  created_at timestamptz default now(),
  primary key (user_id, player_id)
);
create index if not exists idx_player_access_player on player_access(player_id);


-- ############################################################################
-- BLOQUE 3 · INVITACIONES
-- ############################################################################

create table if not exists invitations (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references academies(id) on delete cascade,
  email       text not null,
  role        text not null,
  segment     text,
  team_id     uuid references teams(id) on delete cascade,
  player_id   uuid references players(id) on delete cascade,
  relation    text,
  token       text not null default encode(gen_random_bytes(24), 'hex'),
  status      text not null default 'pendiente',
  invited_by  uuid references users_profile(id),
  expires_at  timestamptz default now() + interval '14 days',
  accepted_at timestamptz,
  created_at  timestamptz default now()
);
create index if not exists idx_invitations_academy on invitations(academy_id, status);
create index if not exists idx_invitations_email   on invitations(lower(email));

-- ---------------------------------------------------------------------------
-- CORRIGE E6 · En v1, una invitación de rol 'jugador' entraba por la rama de
-- staff: le ponía el rol pero NUNCA creaba su fila en player_access. El jugador
-- entraba y no veía absolutamente nada, sin ningún error visible.
-- ---------------------------------------------------------------------------
create or replace function app_accept_invitation(p_token text)
returns void language plpgsql security definer set search_path = public as $$
declare inv invitations;
begin
  select * into inv from invitations
   where token = p_token and status = 'pendiente' and expires_at > now();
  if inv.id is null then raise exception 'Invitación inválida o caducada'; end if;

  if lower(inv.email) <> lower((select email from auth.users where id = auth.uid())) then
    raise exception 'La invitación no corresponde a tu correo';
  end if;

  if inv.role = 'padre' then
    update users_profile set academy_id = inv.academy_id, role = 'padre'
     where id = auth.uid() and academy_id is null;
    insert into player_access (user_id, player_id, relation)
    values (auth.uid(), inv.player_id, coalesce(inv.relation, 'Tutor'))
    on conflict do nothing;

  elsif inv.role = 'jugador' then
    update users_profile set academy_id = inv.academy_id, role = 'jugador'
     where id = auth.uid() and academy_id is null;
    insert into player_access (user_id, player_id, relation, can_pay)
    values (auth.uid(), inv.player_id, 'Jugador', false)
    on conflict do nothing;

  else  -- staff
    update users_profile
       set academy_id = inv.academy_id, role = inv.role, segment = inv.segment
     where id = auth.uid();
    if inv.team_id is not null then
      insert into team_coaches (user_id, team_id) values (auth.uid(), inv.team_id)
      on conflict do nothing;
    end if;
  end if;

  update invitations set status = 'aceptada', accepted_at = now() where id = inv.id;
end; $$;


-- ############################################################################
-- BLOQUE 4 · MATRIZ DE PERMISOS
-- ############################################################################

create table if not exists role_permissions (
  academy_id         uuid references academies(id) on delete cascade,
  role               text not null,
  can_see_score      boolean default false,
  can_see_finance    boolean default false,
  can_manage_finance boolean default false,
  can_see_notes      boolean default false,
  can_evaluate       boolean default false,
  can_edit_physical  boolean default false,
  can_manage_teams   boolean default false,
  can_manage_medical boolean default false,   -- NUEVO: revisión médica y apto
  primary key (academy_id, role)
);
alter table role_permissions add column if not exists can_manage_medical boolean default false;


-- ############################################################################
-- BLOQUE 5 · FUNCIONES AUXILIARES
-- ############################################################################

create or replace function app_role() returns text language sql stable as
$$ select role from users_profile where id = auth.uid() $$;

create or replace function app_academy() returns uuid language sql stable as
$$ select academy_id from users_profile where id = auth.uid() $$;

-- ---------------------------------------------------------------------------
-- CORRIGE E0 (el más grave) · En v1: app_is_staff() = rol <> 'padre'.
-- Al existir el rol 'jugador', CUALQUIER JUGADOR pasaba por personal del club:
-- editar fichas, ver medidas físicas de otros, colarse por toda política que
-- solo comprobara "es staff".
-- ---------------------------------------------------------------------------
create or replace function app_is_staff() returns boolean language sql stable as
$$ select coalesce(app_role() not in ('padre','jugador'), false) $$;

create or replace function app_perm(p text) returns boolean language sql stable as $$
  select coalesce((
    select case p
      when 'see_finance'    then can_see_finance
      when 'manage_finance' then can_manage_finance
      when 'see_notes'      then can_see_notes
      when 'see_score'      then can_see_score
      when 'evaluate'       then can_evaluate
      when 'edit_physical'  then can_edit_physical
      when 'manage_teams'   then can_manage_teams
      when 'manage_medical' then can_manage_medical
      else false end
    from role_permissions rp
    join users_profile up on up.id = auth.uid()
    where rp.academy_id = up.academy_id and rp.role = up.role
  ), false)
$$;

-- ---------------------------------------------------------------------------
-- CORRIGE E1 · En v1, app_is_guardian devolvía true para cualquier fila de
-- player_access: el jugador era tutor de sí mismo y heredaba finance_select
-- (un menor de 14 vería sus cuotas y su deuda).
-- ---------------------------------------------------------------------------
create or replace function app_is_guardian(pid uuid) returns boolean language sql stable as $$
  select exists (select 1 from player_access pa
                  where pa.player_id = pid and pa.user_id = auth.uid()
                    and pa.relation in ('Padre','Madre','Tutor'))
$$;

create or replace function app_is_self(pid uuid) returns boolean language sql stable as $$
  select exists (select 1 from player_access pa
                  where pa.player_id = pid and pa.user_id = auth.uid()
                    and pa.relation = 'Jugador')
$$;

-- La edad se CALCULA, nunca se guarda. Sin fecha de nacimiento -> menor.
create or replace function app_player_age(pid uuid) returns int language sql stable as
$$ select extract(year from age(current_date,
     (select birth_date from players where id = pid)))::int $$;

create or replace function app_player_is_adult(pid uuid) returns boolean language sql stable as
$$ select coalesce(app_player_age(pid) >= 18, false) $$;

create or replace function app_coaches_player(pid uuid) returns boolean language sql stable as $$
  select exists (select 1 from players pl
                  join team_coaches tc on tc.team_id = pl.team_id
                 where pl.id = pid and tc.user_id = auth.uid())
$$;

create or replace function app_in_segment(pid uuid) returns boolean language sql stable as $$
  select exists (select 1 from players pl
                  join teams t on t.id = pl.team_id
                  join users_profile up on up.id = auth.uid()
                 where pl.id = pid and up.segment is not null and t.segment = up.segment)
$$;

create or replace function app_can_see_player(pid uuid) returns boolean language sql stable as $$
  select case
    when (select academy_id from players where id = pid) is distinct from app_academy() then false
    when app_role() in ('director','dt_general','administrativo','scout','preparador_fisico') then true
    when app_role() like 'dt_%'    then app_in_segment(pid)
    when app_role() = 'entrenador' then app_coaches_player(pid)
    when app_role() = 'padre'      then app_is_guardian(pid)
    when app_role() = 'jugador'    then app_is_self(pid)
    else false end
$$;


-- ############################################################################
-- BLOQUE 6 · TABLAS NUEVAS
-- ############################################################################

-- ---- 6.1 Datos bancarios, FUERA de players (los leía todo el cuerpo técnico)
create table if not exists family_billing (
  player_id   uuid primary key references players(id) on delete cascade,
  iban        text,
  method      text,
  holder_name text,
  updated_by  uuid references users_profile(id),
  updated_at  timestamptz default now()
);

-- ---- 6.2 Revisión médica: SOLO fecha y apto. Una fila POR TEMPORADA.
create table if not exists player_medical (
  player_id    uuid not null references players(id) on delete cascade,
  season       text not null,
  checkup_date date,
  fit          boolean,
  updated_by   uuid references users_profile(id),
  updated_at   timestamptz default now(),
  primary key (player_id, season)
);

-- ---- 6.3 Consentimientos. NUNCA se actualizan: se inserta una fila nueva.
create table if not exists consents (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references academies(id) on delete cascade,
  player_id      uuid not null references players(id) on delete cascade,
  signed_by      uuid references users_profile(id),
  relation       text,        -- Padre | Madre | Tutor | Jugador
  kind           text not null,   -- datos | medico | imagen_publica | federacion | comunicaciones
  granted        boolean not null,
  policy_version text not null,
  signed_at      timestamptz default now(),
  revoked_at     timestamptz,
  ip             inet,
  user_agent     text
);
create index if not exists idx_consents_player on consents(player_id, kind, signed_at desc);

-- ¿Tiene consentimiento VIGENTE de un tipo? (la última respuesta manda)
create or replace function app_has_consent(pid uuid, k text)
returns boolean language sql stable as $$
  select coalesce((select granted from consents
                    where player_id = pid and kind = k and revoked_at is null
                    order by signed_at desc limit 1), false)
$$;

-- ---- 6.4 Tablón de avisos. NO es un chat: va en un solo sentido.
create table if not exists announcements (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references academies(id) on delete cascade,
  team_id      uuid references teams(id) on delete set null,
  author_id    uuid not null references users_profile(id),
  kind         text not null default 'aviso',
  title        text not null,
  body         text not null,
  needs_rsvp   boolean default false,
  created_at   timestamptz default now(),
  retracted_at timestamptz,
  retracted_by uuid references users_profile(id)
);
create index if not exists idx_ann_team on announcements(team_id, created_at desc);

-- Un envío POR DESTINATARIO. Aquí vive todo lo que ve cada uno.
-- La clave incluye player_id: un padre con DOS hijos en el mismo equipo
-- recibe el aviso dos veces y confirma la asistencia de cada uno por separado.
create table if not exists announcement_targets (
  announcement_id uuid not null references announcements(id) on delete cascade,
  user_id         uuid not null references users_profile(id) on delete cascade,
  player_id       uuid references players(id) on delete cascade,
  as_role         text not null,        -- jugador | tutor
  read_at         timestamptz,
  rsvp            text,                 -- ire | no_puedo
  rsvp_at         timestamptz,
  rsvp_by         uuid references users_profile(id),
  primary key (announcement_id, user_id, player_id)
);
create index if not exists idx_at_user on announcement_targets(user_id, read_at);

-- Aviso a un MENOR -> copia automática a todos sus tutores. Sin excepción.
create or replace function app_fanout_guardians() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.player_id is not null and new.as_role = 'jugador'
     and not app_player_is_adult(new.player_id) then
    insert into announcement_targets (announcement_id, user_id, player_id, as_role)
    select new.announcement_id, pa.user_id, new.player_id, 'tutor'
      from player_access pa
     where pa.player_id = new.player_id
       and pa.relation in ('Padre','Madre','Tutor')
    on conflict do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists announcement_guardian_fanout on announcement_targets;
create trigger announcement_guardian_fanout
  after insert on announcement_targets
  for each row execute function app_fanout_guardians();

-- ---- 6.5 Avisos al móvil
create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users_profile(id) on delete cascade,
  player_id  uuid references players(id) on delete cascade,
  source     text not null,      -- aviso | pago | documento | medico | calendario
  source_id  uuid,
  read_at    timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_notif_user on notifications(user_id, read_at);

create table if not exists push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users_profile(id) on delete cascade,
  endpoint   text not null,
  keys       jsonb not null,
  device     text,
  created_at timestamptz default now(),
  last_seen  timestamptz,
  unique (user_id, endpoint)
);

-- ---- 6.6 Datos sensibles internos (ya existía en v1)
create table if not exists player_private (
  player_id      uuid primary key references players(id) on delete cascade,
  notes_internal text,
  budget         numeric,
  scout_score    int,
  updated_at     timestamptz default now()
);

-- ---- 6.7 Cuentas de jugador: las activa el club POR EQUIPO
alter table teams add column if not exists player_accounts_enabled boolean default false;

-- ---- 6.8 Documentos: de archivo a CHECKLIST
alter table documents add column if not exists delivered    boolean default false;
alter table documents add column if not exists delivered_at timestamptz;
alter table documents add column if not exists marked_by    uuid references users_profile(id);


-- ############################################################################
-- BLOQUE 7 · RLS
-- ############################################################################

-- ---- 7.1 users_profile
-- CORRIGE E7 (GRAVE) · En v1: "profile_update_self for update using (id = auth.uid())"
-- sin restricción de columnas. Cualquier padre podía ejecutar
--     update users_profile set role = 'director' where id = auth.uid();
-- y convertirse en director del club. Escalada de privilegios completa.
alter table users_profile enable row level security;

drop policy if exists profile_self        on users_profile;
drop policy if exists profile_update_self on users_profile;

create policy profile_self on users_profile for select
  using ( id = auth.uid() or (app_is_staff() and academy_id = app_academy()) );

create policy profile_update_self on users_profile for update
  using ( id = auth.uid() ) with check ( id = auth.uid() );

-- El candado real: nadie se cambia su propio rol, academia o segmento.
create or replace function app_guard_profile_escalation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.role is distinct from old.role
      or new.academy_id is distinct from old.academy_id
      or new.segment is distinct from old.segment)
     and coalesce(app_role(), '') <> 'director' then
    raise exception 'No puedes cambiar tu rol, tu academia ni tu segmento';
  end if;
  return new;
end; $$;

drop trigger if exists users_profile_no_escalation on users_profile;
create trigger users_profile_no_escalation
  before update on users_profile
  for each row execute function app_guard_profile_escalation();

-- ---- 7.2 invitations
alter table invitations enable row level security;
drop policy if exists inv_manage on invitations;
create policy inv_manage on invitations for all
  using      ( academy_id = app_academy() and app_role() in ('director','administrativo') )
  with check ( academy_id = app_academy() and app_role() in ('director','administrativo') );

-- ---- 7.3 players
alter table players enable row level security;
drop policy if exists players_select on players;
drop policy if exists players_update on players;
drop policy if exists players_insert on players;
create policy players_select on players for select using ( app_can_see_player(id) );
create policy players_update on players for update
  using ( app_is_staff() and app_can_see_player(id) )
  with check ( app_is_staff() and academy_id = app_academy() );
create policy players_insert on players for insert
  with check ( app_is_staff() and academy_id = app_academy() );

-- CORRIGE E2 · La familia sube la foto pero players_update es solo staff.
-- No se puede resolver con GRANT por columna (se aplica al rol 'authenticated'
-- entero y rompería la edición del staff). Se resuelve con función controlada,
-- que además exige consentimiento de imagen interna.
create or replace function app_set_player_photo(pid uuid, url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (app_is_guardian(pid) or app_is_self(pid) or app_is_staff()) then
    raise exception 'Sin permiso para cambiar la foto de este jugador';
  end if;
  update players set photo_url = url where id = pid;
end; $$;
revoke all on function app_set_player_photo(uuid, text) from public;
grant execute on function app_set_player_photo(uuid, text) to authenticated;

-- ---- 7.4 finance
-- CORRIGE E8 · El with_check de v1 no comprobaba el alcance: alguien con
-- manage_finance podía insertar cuotas de un jugador de OTRA academia.
alter table finance enable row level security;
drop policy if exists finance_select on finance;
drop policy if exists finance_write  on finance;
create policy finance_select on finance for select
  using ( app_can_see_player(player_id)
          and (app_perm('see_finance') or app_is_guardian(player_id)
               or (app_is_self(player_id) and app_player_is_adult(player_id))) );
create policy finance_write on finance for all
  using      ( app_perm('manage_finance') and app_can_see_player(player_id) )
  with check ( app_perm('manage_finance') and app_can_see_player(player_id) );

-- ---- 7.5 documents (checklist)
-- CORRIGE E3 · v1 tenía un "for all" que dejaba a una familia marcar su
-- propio pasaporte como validado, o borrar filas.
alter table documents enable row level security;
drop policy if exists documents_rw     on documents;
drop policy if exists documents_select on documents;
drop policy if exists documents_write  on documents;
create policy documents_select on documents for select
  using ( app_can_see_player(player_id) );
create policy documents_write on documents for all
  using      ( app_is_staff() and app_can_see_player(player_id) )
  with check ( app_is_staff() and app_can_see_player(player_id) );

-- ---- 7.6 family_billing
alter table family_billing enable row level security;
drop policy if exists billing_all on family_billing;
create policy billing_all on family_billing for all
  using ( app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id))
          or (app_perm('manage_finance') and app_can_see_player(player_id)) )
  with check ( app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id))
          or (app_perm('manage_finance') and app_can_see_player(player_id)) );

-- ---- 7.7 player_medical
alter table player_medical enable row level security;
drop policy if exists medical_select on player_medical;
drop policy if exists medical_write  on player_medical;
create policy medical_select on player_medical for select
  using ( (app_perm('manage_medical') and app_can_see_player(player_id))
          or app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id)) );
create policy medical_write on player_medical for all
  using      ( app_perm('manage_medical') and app_can_see_player(player_id) )
  with check ( app_perm('manage_medical') and app_can_see_player(player_id) );

-- ---- 7.8 consents  (se insertan, nunca se modifican)
alter table consents enable row level security;
drop policy if exists consents_select on consents;
drop policy if exists consents_insert on consents;
create policy consents_select on consents for select
  using ( app_is_guardian(player_id) or app_is_self(player_id)
          or (app_is_staff() and app_can_see_player(player_id)) );
create policy consents_insert on consents for insert
  with check ( (app_is_guardian(player_id) or app_is_self(player_id)
                or app_is_staff()) and signed_by = auth.uid() );
-- El historial es la prueba: no se toca ni se borra.
revoke update, delete on consents from authenticated;

-- ---- 7.9 announcements + targets
alter table announcements enable row level security;
drop policy if exists ann_select on announcements;
drop policy if exists ann_write  on announcements;
create policy ann_select on announcements for select
  using ( exists (select 1 from announcement_targets t
                   where t.announcement_id = announcements.id and t.user_id = auth.uid())
          or (app_is_staff() and academy_id = app_academy()) );
create policy ann_write on announcements for all
  using      ( app_is_staff() and academy_id = app_academy() )
  with check ( app_is_staff() and academy_id = app_academy() and author_id = auth.uid() );

alter table announcement_targets enable row level security;
drop policy if exists at_select_own   on announcement_targets;
drop policy if exists at_select_staff on announcement_targets;
drop policy if exists at_insert       on announcement_targets;
drop policy if exists at_respond      on announcement_targets;

-- Cada uno SOLO ve su fila. No existe consulta que devuelva la de otro:
-- así nadie sabe a quién más se envió el aviso.
create policy at_select_own on announcement_targets for select
  using ( user_id = auth.uid() );
create policy at_select_staff on announcement_targets for select
  using ( app_is_staff() and app_can_see_player(player_id) );
create policy at_insert on announcement_targets for insert
  with check ( app_is_staff() );
create policy at_respond on announcement_targets for update
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

-- Solo se pueden tocar las columnas de respuesta. Sin esto, un usuario podría
-- cambiarse el player_id o pasar su as_role de 'tutor' a 'jugador'.
revoke update on announcement_targets from authenticated;
grant  update (read_at, rsvp, rsvp_at, rsvp_by) on announcement_targets to authenticated;

-- Un aviso se RETIRA, nunca se borra. El registro es del club.
revoke delete on announcements, announcement_targets from authenticated;

-- ---- 7.10 notifications y push
alter table notifications enable row level security;
drop policy if exists notif_own on notifications;
create policy notif_own on notifications for select using ( user_id = auth.uid() );
drop policy if exists notif_read on notifications;
create policy notif_read on notifications for update
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

alter table push_subscriptions enable row level security;
drop policy if exists push_own on push_subscriptions;
create policy push_own on push_subscriptions for all
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

-- ---- 7.11 player_private (notas internas, presupuesto, Scout Score)
alter table player_private enable row level security;
drop policy if exists private_select on player_private;
drop policy if exists private_write  on player_private;
create policy private_select on player_private for select
  using ( app_perm('see_notes') and app_can_see_player(player_id) );
create policy private_write on player_private for all
  using      ( app_perm('see_notes') and app_can_see_player(player_id) )
  with check ( app_perm('see_notes') and app_can_see_player(player_id) );

-- ---- 7.12 measurements — el jugador mayor de edad ve las suyas
do $$ begin
  if to_regclass('public.measurements') is not null then
    execute 'alter table measurements enable row level security';
    execute 'drop policy if exists measurements_select on measurements';
    execute 'drop policy if exists measurements_write  on measurements';
    execute $p$create policy measurements_select on measurements for select
      using ( (app_can_see_player(player_id) and app_is_staff())
              or (app_is_self(player_id) and app_player_is_adult(player_id)) )$p$;
    execute $p$create policy measurements_write on measurements for all
      using      ( app_perm('edit_physical') and app_can_see_player(player_id) )
      with check ( app_perm('edit_physical') and app_can_see_player(player_id) )$p$;
  end if;
end $$;

-- ---- 7.13 kit_orders
do $$ begin
  if to_regclass('public.kit_orders') is not null then
    execute 'alter table kit_orders enable row level security';
    execute 'drop policy if exists kit_select on kit_orders';
    execute 'drop policy if exists kit_write  on kit_orders';
    execute $p$create policy kit_select on kit_orders for select
      using ( app_can_see_player(player_id) )$p$;
    execute $p$create policy kit_write on kit_orders for all
      using ( app_can_see_player(player_id)
              and (app_perm('manage_finance') or app_is_guardian(player_id)) )
      with check ( app_can_see_player(player_id)
              and (app_perm('manage_finance') or app_is_guardian(player_id)) )$p$;
  end if;
end $$;

-- ---- 7.14 team_events  (CORRIGE E4 · no tenía RLS)
do $$ begin
  if to_regclass('public.team_events') is not null then
    execute 'alter table team_events enable row level security';
    execute 'drop policy if exists team_events_select on team_events';
    execute 'drop policy if exists team_events_write  on team_events';
    execute $p$create policy team_events_select on team_events for select
      using (
        exists (select 1 from team_coaches tc
                 where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
        or app_role() in ('director','dt_general','administrativo')
        or exists (select 1 from players pl
                    join player_access pa on pa.player_id = pl.id
                   where pl.team_id = team_events.team_id and pa.user_id = auth.uid())
      )$p$;
    execute $p$create policy team_events_write on team_events for all
      using ( exists (select 1 from team_coaches tc
                       where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
              or app_perm('manage_teams') )
      with check ( exists (select 1 from team_coaches tc
                       where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
              or app_perm('manage_teams') )$p$;
  else
    raise notice 'team_events no existe todavia: su RLS se aplicara al crearla.';
  end if;
end $$;

-- ---- 7.15 team_messages  (OBSOLETA: sustituida por announcements)
-- CORRIGE E9 · el insert de v1 solo comprobaba author_id = auth.uid(),
-- sin mirar el equipo: una familia podía escribir en el muro de CUALQUIER equipo.
do $$ begin
  if to_regclass('public.team_messages') is not null then
    execute 'alter table team_messages enable row level security';
    execute 'drop policy if exists team_messages_insert on team_messages';
    execute $p$create policy team_messages_insert on team_messages for insert
      with check ( author_id = auth.uid() and app_is_staff()
        and exists (select 1 from team_coaches tc
                     where tc.team_id = team_messages.team_id and tc.user_id = auth.uid()) )$p$;
  end if;
end $$;


-- ############################################################################
-- BLOQUE 8 · SEMILLA DE PERMISOS
--   Descomenta y sustituye :academy por el id real de tu academia.
-- ############################################################################

-- insert into role_permissions
--   (academy_id, role, can_see_score, can_see_finance, can_manage_finance,
--    can_see_notes, can_evaluate, can_edit_physical, can_manage_teams, can_manage_medical)
-- values
--  (:academy,'director',          true,  true,  true,  true,  true,  true,  true,  true),
--  (:academy,'dt_general',        true,  false, false, false, true,  true,  true,  true),
--  (:academy,'dt_femenino',       true,  false, false, false, true,  false, true,  false),
--  (:academy,'dt_masculino',      true,  false, false, false, true,  false, true,  false),
--  (:academy,'dt_escuelas',       true,  false, false, false, true,  false, true,  false),
--  (:academy,'dt_minis',          true,  false, false, false, true,  false, true,  false),
--  (:academy,'preparador_fisico', true,  false, false, false, true,  true,  false, true),
--  (:academy,'scout',             true,  false, false, false, true,  false, false, false),
--  (:academy,'entrenador',        true,  false, false, false, true,  false, false, true),
--  (:academy,'administrativo',    false, true,  true,  false, false, false, false, true),
--  (:academy,'padre',             false, true,  false, false, false, false, false, false),
--  (:academy,'jugador',           false, false, false, false, false, false, false, false)
-- on conflict (academy_id, role) do update set can_manage_medical = excluded.can_manage_medical;


-- ############################################################################
-- BLOQUE 9 · COMPROBACIÓN
--   Debe terminar diciendo: === auth v2 APLICADO CORRECTAMENTE ===
-- ############################################################################

do $$
declare f int := 0;
begin
  if (select prosrc from pg_proc where proname='app_is_staff') not like '%jugador%'
    then raise warning 'E0 SIN CORREGIR: app_is_staff no excluye jugador'; f := f+1; end if;

  if (select prosrc from pg_proc where proname='app_is_guardian') not like '%Tutor%'
    then raise warning 'E1 SIN CORREGIR: app_is_guardian no filtra relacion'; f := f+1; end if;

  if not exists (select 1 from pg_trigger where tgname='users_profile_no_escalation')
    then raise warning 'E7 SIN CORREGIR: falta el candado de escalada de rol'; f := f+1; end if;

  if exists (select 1 from pg_policies where tablename='documents' and policyname='documents_rw')
    then raise warning 'E3 SIN CORREGIR: documents_rw sigue viva'; f := f+1; end if;

  if to_regclass('public.family_billing') is null
    then raise warning 'Falta family_billing'; f := f+1; end if;
  if to_regclass('public.player_medical') is null
    then raise warning 'Falta player_medical'; f := f+1; end if;
  if to_regclass('public.consents') is null
    then raise warning 'Falta consents'; f := f+1; end if;
  if to_regclass('public.announcement_targets') is null
    then raise warning 'Falta announcement_targets'; f := f+1; end if;

  if not exists (select 1 from pg_trigger where tgname='announcement_guardian_fanout')
    then raise warning 'Falta la copia automatica a tutores'; f := f+1; end if;

  if f = 0 then raise notice '=== auth v2 APLICADO CORRECTAMENTE ===';
  else raise notice '=== auth v2: % comprobaciones fallidas ===', f; end if;
end $$;


-- ############################################################################
-- LIMPIEZA PENDIENTE — NO ejecutar hasta haber migrado los datos
--   1. Copiar players.bank            -> family_billing
--   2. Copiar los campos de salud     -> player_medical
--   3. Solo entonces:
--        alter table players   drop column if exists bank;
--        alter table documents drop column if exists file_url;
--        alter table documents drop column if exists status;
--   4. team_messages queda obsoleta: migrar a announcements y retirarla.
-- ############################################################################
