-- ============================================================================
-- ScoutFlow Academy — ESQUEMA COMPLETO
-- ----------------------------------------------------------------------------
-- Ruta en el repo:  database/schema_completo.sql
-- Versión: 2026-08-04
--
-- ESTE ARCHIVO SUSTITUYE A LOS TRES ANTERIORES:
--     schema.sql            (borrador incompleto: solo 5 tablas)
--     auth_schema.sql       (asumía 11 tablas que no existían)
--     SUPABASE_auth_v2.sql  (heredaba el mismo problema)
--
-- Es el ÚNICO archivo que hay que ejecutar. No hay orden ni dependencias.
-- Se ejecuta entero en el editor SQL de Supabase, sobre un proyecto NUEVO.
--
-- Nombres de campo alineados con js/data.js: lo que se ve en pantalla y lo
-- que se guarda se llaman igual.
--
-- Después, para verificar: database/PRUEBAS_RLS.sql
-- ============================================================================


-- ############################################################################
-- 0 · COMPROBACIÓN PREVIA
--   Evita el fallo que nos costó el día: ejecutar esto encima del schema viejo
--   dejaría tablas con la forma antigua y "create table if not exists" se las
--   saltaría en silencio, sin dar ningún error.
-- ############################################################################

do $$
begin
  if to_regclass('public.player_access') is not null
     and not exists (select 1 from information_schema.columns
                     where table_name='player_access' and column_name='relation') then
    raise exception
      'Hay un esquema ANTIGUO en esta base de datos. Usa un proyecto Supabase nuevo, o borra las tablas antes de ejecutar este archivo.';
  end if;
end $$;


-- ############################################################################
-- 1 · CLUB
-- ############################################################################

create table if not exists academies (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  country         text,
  city            text,
  primary_sport   text default 'baloncesto',
  plan            text default 'Starter',        -- Starter | Pro | Elite | White Label
  payment_methods jsonb default '[]',            -- [{label, detail}]
  kit             jsonb default '{}',            -- {pack_name, pack_price, sizes[], garments[]}
  season          text,                          -- '2026/2027'
  policy_version  text default 'v1',             -- versión del texto legal vigente
  created_at      timestamptz default now()
);

create table if not exists teams (
  id       uuid primary key default gen_random_uuid(),
  academy_id uuid not null references academies(id) on delete cascade,
  name     text not null,
  sport    text default 'baloncesto',
  segment  text,      -- femenino | masculino | escuelas | minis | mixto
  category text,      -- Cadete | Infantil | Mini | Escuela...
  player_accounts_enabled boolean default false,   -- ¿los jugadores tienen cuenta?
  created_at timestamptz default now()
);
create index if not exists idx_teams_academy on teams(academy_id);


-- ############################################################################
-- 2 · IDENTIDAD, ALCANCE Y PERMISOS
-- ############################################################################

-- 1:1 con auth.users. El alta y el login los resuelve Supabase.
create table if not exists users_profile (
  id         uuid primary key references auth.users(id) on delete cascade,
  academy_id uuid references academies(id) on delete cascade,
  full_name  text,
  email      text unique not null,
  role       text not null default 'padre',
             -- director | dt_general | dt_femenino | dt_masculino | dt_escuelas
             -- | dt_minis | preparador_fisico | scout | entrenador
             -- | administrativo | padre | jugador
  segment    text,
  phone      text,
  language   text default 'es',
  active     boolean default true,
  created_at timestamptz default now()
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

-- Entrenador -> sus equipos
create table if not exists team_coaches (
  user_id uuid references users_profile(id) on delete cascade,
  team_id uuid references teams(id) on delete cascade,
  primary key (user_id, team_id)
);

-- NOTA DE ORDEN: player_access e invitations apuntan a players,
-- así que se crean en el bloque 3, después de la tabla players.

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
  can_manage_medical boolean default false,
  primary key (academy_id, role)
);


-- ############################################################################
-- 3 · JUGADOR
-- ############################################################################

create table if not exists players (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references academies(id) on delete cascade,
  team_id       uuid references teams(id) on delete set null,
  scoutflow_id  text unique,
  photo_url     text,
  first_name    text,
  last_name     text,
  full_name     text not null,
  birth_date    date,
  birth_year    int,
  gender        text,
  nationality   text[],
  residence_country text,
  city          text,
  phone         text,
  email         text,
  sport         text default 'baloncesto',
  primary_position   text,
  secondary_position text,
  height_cm     int,
  weight_kg     numeric,
  status        text default 'Datos incompletos',
                -- Nuevo | Datos incompletos | Pendiente de vídeo | En evaluación
                -- | Entrevista | Oferta enviada | Inscrito | Rechazado
  -- captación
  channel       text,
  capture_date  date,
  captured_by   text,
  objective     text,
  responsible_user_id uuid references users_profile(id),
  created_at    timestamptz default now()
);
create index if not exists idx_players_academy on players(academy_id);
create index if not exists idx_players_team    on players(team_id);

-- Familia -> su hijo/a.  Padre y madre = DOS filas al mismo jugador.
-- El propio jugador también se enlaza aquí, con relation = 'Jugador'.
create table if not exists player_access (
  user_id    uuid references users_profile(id) on delete cascade,
  player_id  uuid references players(id) on delete cascade,
  relation   text not null,          -- Padre | Madre | Tutor | Jugador
  can_pay    boolean default true,
  created_at timestamptz default now(),
  primary key (user_id, player_id)
);
create index if not exists idx_player_access_player on player_access(player_id);

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
  status      text not null default 'pendiente',   -- pendiente|aceptada|revocada|caducada
  invited_by  uuid references users_profile(id),
  expires_at  timestamptz default now() + interval '14 days',
  accepted_at timestamptz,
  created_at  timestamptz default now()
);
create index if not exists idx_inv_academy on invitations(academy_id, status);
create index if not exists idx_inv_email   on invitations(lower(email));

-- Notas internas, presupuesto y Scout Score: SIEMPRE en tabla aparte,
-- para que nunca viajen con la ficha.
create table if not exists player_private (
  player_id      uuid primary key references players(id) on delete cascade,
  notes_internal text,
  budget         numeric,
  scout_score    int,
  updated_at     timestamptz default now()
);

-- Revisión médica: SOLO fecha y apto. Una fila POR TEMPORADA.
create table if not exists player_medical (
  player_id    uuid not null references players(id) on delete cascade,
  season       text not null,
  checkup_date date,
  fit          boolean,
  updated_by   uuid references users_profile(id),
  updated_at   timestamptz default now(),
  primary key (player_id, season)
);

-- Medidas físicas (preparador físico)
create table if not exists measurements (
  id           uuid primary key default gen_random_uuid(),
  player_id    uuid not null references players(id) on delete cascade,
  measured_on  date default current_date,
  height_cm    int,
  weight_kg    numeric,
  wingspan_cm  int,
  reach_cm     int,
  dominant_hand text,
  both_hands   boolean,
  measured_by  uuid references users_profile(id)
);
create index if not exists idx_meas_player on measurements(player_id, measured_on desc);


-- ############################################################################
-- 4 · DOCUMENTACIÓN  (CHECKLIST, no archivo)
--   La app NO guarda documentos. Solo lleva la cuenta de qué se ha entregado.
-- ############################################################################

create table if not exists documents (
  id            uuid primary key default gen_random_uuid(),
  player_id     uuid not null references players(id) on delete cascade,
  document_type text not null,      -- dni | pasaporte | seguro_medico | expediente | autorizacion
  delivered     boolean default false,
  delivered_at  timestamptz,
  marked_by     uuid references users_profile(id),
  created_at    timestamptz default now(),
  unique (player_id, document_type)
);


-- ############################################################################
-- 5 · CONSENTIMIENTOS
--   NUNCA se actualizan: se inserta una fila nueva. El historial es la prueba.
-- ############################################################################

create table if not exists consents (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references academies(id) on delete cascade,
  player_id      uuid not null references players(id) on delete cascade,
  signed_by      uuid references users_profile(id),
  relation       text,          -- Padre | Madre | Tutor | Jugador
  kind           text not null, -- datos | medico | imagen_publica | federacion | comunicaciones
  granted        boolean not null,
  policy_version text not null,
  signed_at      timestamptz default now(),
  revoked_at     timestamptz,
  ip             inet,
  user_agent     text
);
create index if not exists idx_consents_player on consents(player_id, kind, signed_at desc);

-- ¿Hay consentimiento vigente? La última respuesta manda.
create or replace function app_has_consent(pid uuid, k text)
returns boolean language sql stable as $$
  select coalesce((select granted from consents
                    where player_id = pid and kind = k and revoked_at is null
                    order by signed_at desc limit 1), false)
$$;


-- ############################################################################
-- 6 · DINERO
-- ############################################################################

-- Plan de pago del jugador: inscripción, cuotas por mes, torneos, equipación.
create table if not exists finance (
  id         uuid primary key default gen_random_uuid(),
  player_id  uuid not null references players(id) on delete cascade,
  type       text not null default 'cuota',   -- inscripcion | cuota | torneo | equipacion | otro
  label      text not null,
  month      text,
  amount     numeric not null default 0,
  status     text not null default 'pendiente',  -- pendiente | pagado | vencido
  due_date   date,
  paid_at    timestamptz,
  created_at timestamptz default now()
);
create index if not exists idx_finance_player on finance(player_id, status);

-- Datos bancarios: FUERA de players (los leería todo el cuerpo técnico).
create table if not exists family_billing (
  player_id   uuid primary key references players(id) on delete cascade,
  iban        text,
  method      text,
  holder_name text,
  updated_by  uuid references users_profile(id),
  updated_at  timestamptz default now()
);

create table if not exists kit_orders (
  player_id    uuid primary key references players(id) on delete cascade,
  sizes        jsonb default '{}',      -- {prenda: talla}
  name_print   text,
  number_print text,
  status       text default 'pedido',   -- pedido | confirmado | entregado | cerrado
  locked       boolean default false,   -- cerrado por el club: la familia ya no lo toca
  requested_at date default current_date
);

-- Economía del club (ya funciona en la app)
create table if not exists expenses (
  id         uuid primary key default gen_random_uuid(),
  academy_id uuid not null references academies(id) on delete cascade,
  season     text,
  date       date default current_date,
  concept    text not null,
  category   text,
  amount     numeric not null,
  created_by uuid references users_profile(id),
  status     text default 'pendiente',   -- pendiente | aprobado | rechazado
  note       text,
  ticket_url text,
  approved_by uuid references users_profile(id),
  approved_at timestamptz
);
create index if not exists idx_expenses_academy on expenses(academy_id, season, status);


-- ############################################################################
-- 7 · CALENDARIO Y AVISOS
--   El tablón NO es un chat: va en un solo sentido y nadie ve a nadie.
-- ############################################################################

create table if not exists team_events (
  id          uuid primary key default gen_random_uuid(),
  team_id     uuid not null references teams(id) on delete cascade,
  type        text not null default 'entrenamiento',  -- entrenamiento | partido
  date        date not null,
  time        text,
  place       text,
  opponent    text,
  competition text,
  note        text,
  created_by  uuid references users_profile(id),
  created_at  timestamptz default now()
);
create index if not exists idx_events_team on team_events(team_id, date);

create table if not exists announcements (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references academies(id) on delete cascade,
  team_id      uuid references teams(id) on delete set null,
  event_id     uuid references team_events(id) on delete set null,
  author_id    uuid not null references users_profile(id),
  kind         text not null default 'aviso',   -- aviso | convocatoria | horario | partido
  title        text not null,
  body         text not null,
  needs_rsvp   boolean default false,
  created_at   timestamptz default now(),
  retracted_at timestamptz,
  retracted_by uuid references users_profile(id)
);
create index if not exists idx_ann_team on announcements(team_id, created_at desc);

-- Un envío POR DESTINATARIO. La clave incluye player_id: un padre con DOS
-- hijos en el mismo equipo recibe dos filas y confirma cada una por separado.
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

create table if not exists notifications (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null references users_profile(id) on delete cascade,
  player_id  uuid references players(id) on delete cascade,
  source     text not null,     -- aviso | pago | documento | medico | calendario
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

create table if not exists notification_prefs (
  user_id uuid references users_profile(id) on delete cascade,
  kind    text not null,          -- servicio | informativo
  enabled boolean default true,
  primary key (user_id, kind)
);

-- Transición a la mayoría de edad
create table if not exists majority_transitions (
  player_id     uuid primary key references players(id) on delete cascade,
  turns_18_on   date not null,
  notified_at   timestamptz,
  decided_at    timestamptz,
  decision      text,          -- mantener | solo_pagos | retirar
  grace_ends_on date
);


-- ############################################################################
-- 8 · FUNCIONES DE SEGURIDAD
-- ############################################################################

create or replace function app_role() returns text language sql stable as
$$ select role from users_profile where id = auth.uid() $$;

create or replace function app_academy() returns uuid language sql stable as
$$ select academy_id from users_profile where id = auth.uid() $$;

-- Ni el padre ni el jugador son personal del club.
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

-- Tutor = SOLO Padre / Madre / Tutor. El jugador NO es tutor de sí mismo.
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

-- La edad se CALCULA. Sin fecha de nacimiento -> menor (opción protectora).
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

-- Aceptar invitación. Tres ramas: familia, jugador y staff.
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
    values (auth.uid(), inv.player_id, coalesce(inv.relation,'Tutor')) on conflict do nothing;

  elsif inv.role = 'jugador' then
    update users_profile set academy_id = inv.academy_id, role = 'jugador'
     where id = auth.uid() and academy_id is null;
    insert into player_access (user_id, player_id, relation, can_pay)
    values (auth.uid(), inv.player_id, 'Jugador', false) on conflict do nothing;

  else
    update users_profile set academy_id = inv.academy_id, role = inv.role, segment = inv.segment
     where id = auth.uid();
    if inv.team_id is not null then
      insert into team_coaches (user_id, team_id) values (auth.uid(), inv.team_id)
      on conflict do nothing;
    end if;
  end if;

  update invitations set status = 'aceptada', accepted_at = now() where id = inv.id;
end; $$;

-- La familia sube la foto, pero players solo lo edita el staff.
create or replace function app_set_player_photo(pid uuid, url text)
returns void language plpgsql security definer set search_path = public as $$
begin
  if not (app_is_guardian(pid) or app_is_self(pid) or app_is_staff()) then
    raise exception 'Sin permiso para cambiar la foto de este jugador';
  end if;
  update players set photo_url = url where id = pid;
end; $$;
revoke all on function app_set_player_photo(uuid,text) from public;
grant execute on function app_set_player_photo(uuid,text) to authenticated;

-- Nadie se cambia su propio rol, academia ni segmento.
create or replace function app_guard_profile_escalation() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (new.role is distinct from old.role
      or new.academy_id is distinct from old.academy_id
      or new.segment is distinct from old.segment)
     and coalesce(app_role(),'') <> 'director' then
    raise exception 'No puedes cambiar tu rol, tu academia ni tu segmento';
  end if;
  return new;
end; $$;

drop trigger if exists users_profile_no_escalation on users_profile;
create trigger users_profile_no_escalation
  before update on users_profile
  for each row execute function app_guard_profile_escalation();

-- Aviso a un MENOR -> copia automática a todos sus tutores. Siempre.
create or replace function app_fanout_guardians() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.player_id is not null and new.as_role = 'jugador'
     and not app_player_is_adult(new.player_id) then
    insert into announcement_targets (announcement_id, user_id, player_id, as_role)
    select new.announcement_id, pa.user_id, new.player_id, 'tutor'
      from player_access pa
     where pa.player_id = new.player_id and pa.relation in ('Padre','Madre','Tutor')
    on conflict do nothing;
  end if;
  return new;
end; $$;

drop trigger if exists announcement_guardian_fanout on announcement_targets;
create trigger announcement_guardian_fanout
  after insert on announcement_targets
  for each row execute function app_fanout_guardians();


-- ############################################################################
-- 9 · RLS
-- ############################################################################

alter table academies            enable row level security;
alter table teams                enable row level security;
alter table users_profile        enable row level security;
alter table team_coaches         enable row level security;
alter table player_access        enable row level security;
alter table role_permissions     enable row level security;
alter table invitations          enable row level security;
alter table players              enable row level security;
alter table player_private       enable row level security;
alter table player_medical       enable row level security;
alter table measurements         enable row level security;
alter table documents            enable row level security;
alter table consents             enable row level security;
alter table finance              enable row level security;
alter table family_billing       enable row level security;
alter table kit_orders           enable row level security;
alter table expenses             enable row level security;
alter table team_events          enable row level security;
alter table announcements        enable row level security;
alter table announcement_targets enable row level security;
alter table notifications        enable row level security;
alter table push_subscriptions   enable row level security;
alter table notification_prefs   enable row level security;
alter table majority_transitions enable row level security;

-- ---- club
drop policy if exists academies_select on academies;
create policy academies_select on academies for select using ( id = app_academy() );
drop policy if exists academies_write on academies;
create policy academies_write on academies for update
  using ( id = app_academy() and app_role() = 'director' )
  with check ( id = app_academy() and app_role() = 'director' );

drop policy if exists teams_select on teams;
create policy teams_select on teams for select using ( academy_id = app_academy() );
drop policy if exists teams_write on teams;
create policy teams_write on teams for all
  using ( academy_id = app_academy() and app_perm('manage_teams') )
  with check ( academy_id = app_academy() and app_perm('manage_teams') );

-- ---- identidad
drop policy if exists profile_self on users_profile;
create policy profile_self on users_profile for select
  using ( id = auth.uid() or (app_is_staff() and academy_id = app_academy()) );
drop policy if exists profile_update_self on users_profile;
create policy profile_update_self on users_profile for update
  using ( id = auth.uid() ) with check ( id = auth.uid() );

drop policy if exists coaches_select on team_coaches;
create policy coaches_select on team_coaches for select
  using ( user_id = auth.uid() or app_is_staff() );
drop policy if exists coaches_write on team_coaches;
create policy coaches_write on team_coaches for all
  using ( app_perm('manage_teams') ) with check ( app_perm('manage_teams') );

drop policy if exists access_select on player_access;
create policy access_select on player_access for select
  using ( user_id = auth.uid() or (app_is_staff() and app_can_see_player(player_id)) );
drop policy if exists access_write on player_access;
create policy access_write on player_access for all
  using ( app_role() in ('director','administrativo') )
  with check ( app_role() in ('director','administrativo') );

drop policy if exists perms_select on role_permissions;
create policy perms_select on role_permissions for select using ( academy_id = app_academy() );
drop policy if exists perms_write on role_permissions;
create policy perms_write on role_permissions for all
  using ( academy_id = app_academy() and app_role() = 'director' )
  with check ( academy_id = app_academy() and app_role() = 'director' );

drop policy if exists inv_manage on invitations;
create policy inv_manage on invitations for all
  using      ( academy_id = app_academy() and app_role() in ('director','administrativo') )
  with check ( academy_id = app_academy() and app_role() in ('director','administrativo') );

-- ---- jugador
drop policy if exists players_select on players;
create policy players_select on players for select using ( app_can_see_player(id) );
drop policy if exists players_update on players;
create policy players_update on players for update
  using ( app_is_staff() and app_can_see_player(id) )
  with check ( app_is_staff() and academy_id = app_academy() );
drop policy if exists players_insert on players;
create policy players_insert on players for insert
  with check ( app_is_staff() and academy_id = app_academy() );

drop policy if exists private_all on player_private;
create policy private_all on player_private for all
  using      ( app_perm('see_notes') and app_can_see_player(player_id) )
  with check ( app_perm('see_notes') and app_can_see_player(player_id) );

drop policy if exists medical_select on player_medical;
create policy medical_select on player_medical for select
  using ( (app_perm('manage_medical') and app_can_see_player(player_id))
          or app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id)) );
drop policy if exists medical_write on player_medical;
create policy medical_write on player_medical for all
  using      ( app_perm('manage_medical') and app_can_see_player(player_id) )
  with check ( app_perm('manage_medical') and app_can_see_player(player_id) );

drop policy if exists meas_select on measurements;
create policy meas_select on measurements for select
  using ( (app_can_see_player(player_id) and app_is_staff())
          or (app_is_self(player_id) and app_player_is_adult(player_id)) );
drop policy if exists meas_write on measurements;
create policy meas_write on measurements for all
  using      ( app_perm('edit_physical') and app_can_see_player(player_id) )
  with check ( app_perm('edit_physical') and app_can_see_player(player_id) );

-- ---- documentación (la familia LEE; solo el club MARCA)
drop policy if exists documents_select on documents;
create policy documents_select on documents for select
  using ( app_can_see_player(player_id) );
drop policy if exists documents_write on documents;
create policy documents_write on documents for all
  using      ( app_is_staff() and app_can_see_player(player_id) )
  with check ( app_is_staff() and app_can_see_player(player_id) );

-- ---- consentimientos (se insertan, nunca se tocan)
drop policy if exists consents_select on consents;
create policy consents_select on consents for select
  using ( app_is_guardian(player_id) or app_is_self(player_id)
          or (app_is_staff() and app_can_see_player(player_id)) );
drop policy if exists consents_insert on consents;
create policy consents_insert on consents for insert
  with check ( (app_is_guardian(player_id) or app_is_self(player_id) or app_is_staff())
               and signed_by = auth.uid() );

-- ---- dinero
drop policy if exists finance_select on finance;
create policy finance_select on finance for select
  using ( app_can_see_player(player_id)
          and (app_perm('see_finance') or app_is_guardian(player_id)
               or (app_is_self(player_id) and app_player_is_adult(player_id))) );
drop policy if exists finance_write on finance;
create policy finance_write on finance for all
  using      ( app_perm('manage_finance') and app_can_see_player(player_id) )
  with check ( app_perm('manage_finance') and app_can_see_player(player_id) );

drop policy if exists billing_all on family_billing;
create policy billing_all on family_billing for all
  using ( app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id))
          or (app_perm('manage_finance') and app_can_see_player(player_id)) )
  with check ( app_is_guardian(player_id)
          or (app_is_self(player_id) and app_player_is_adult(player_id))
          or (app_perm('manage_finance') and app_can_see_player(player_id)) );

drop policy if exists kit_select on kit_orders;
create policy kit_select on kit_orders for select using ( app_can_see_player(player_id) );
drop policy if exists kit_write on kit_orders;
create policy kit_write on kit_orders for all
  using ( app_can_see_player(player_id)
          and (app_perm('manage_finance') or (app_is_guardian(player_id) and not locked)) )
  with check ( app_can_see_player(player_id)
          and (app_perm('manage_finance') or (app_is_guardian(player_id) and not locked)) );

-- Economía: cualquiera del staff pasa un gasto; solo finanzas aprueba.
drop policy if exists expenses_select on expenses;
create policy expenses_select on expenses for select
  using ( academy_id = app_academy() and app_is_staff() );
drop policy if exists expenses_insert on expenses;
create policy expenses_insert on expenses for insert
  with check ( academy_id = app_academy() and app_is_staff() and created_by = auth.uid() );
drop policy if exists expenses_manage on expenses;
create policy expenses_manage on expenses for update
  using      ( academy_id = app_academy() and app_perm('manage_finance') )
  with check ( academy_id = app_academy() and app_perm('manage_finance') );

-- ---- calendario y avisos
drop policy if exists events_select on team_events;
create policy events_select on team_events for select using (
  exists (select 1 from team_coaches tc where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
  or app_role() in ('director','dt_general','administrativo')
  or exists (select 1 from players pl join player_access pa on pa.player_id = pl.id
              where pl.team_id = team_events.team_id and pa.user_id = auth.uid()) );
drop policy if exists events_write on team_events;
create policy events_write on team_events for all
  using ( exists (select 1 from team_coaches tc
                   where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
          or app_perm('manage_teams') )
  with check ( exists (select 1 from team_coaches tc
                   where tc.team_id = team_events.team_id and tc.user_id = auth.uid())
          or app_perm('manage_teams') );

drop policy if exists ann_select on announcements;
create policy ann_select on announcements for select
  using ( exists (select 1 from announcement_targets t
                   where t.announcement_id = announcements.id and t.user_id = auth.uid())
          or (app_is_staff() and academy_id = app_academy()) );
drop policy if exists ann_write on announcements;
create policy ann_write on announcements for all
  using      ( app_is_staff() and academy_id = app_academy() )
  with check ( app_is_staff() and academy_id = app_academy() and author_id = auth.uid() );

-- Cada uno SOLO ve su fila: nadie sabe a quién más se envió el aviso.
drop policy if exists at_select_own on announcement_targets;
create policy at_select_own on announcement_targets for select
  using ( user_id = auth.uid() );
drop policy if exists at_select_staff on announcement_targets;
create policy at_select_staff on announcement_targets for select
  using ( app_is_staff() and app_can_see_player(player_id) );
drop policy if exists at_insert on announcement_targets;
create policy at_insert on announcement_targets for insert with check ( app_is_staff() );
drop policy if exists at_respond on announcement_targets;
create policy at_respond on announcement_targets for update
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

drop policy if exists notif_own on notifications;
create policy notif_own on notifications for select using ( user_id = auth.uid() );
drop policy if exists notif_read on notifications;
create policy notif_read on notifications for update
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

drop policy if exists push_own on push_subscriptions;
create policy push_own on push_subscriptions for all
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

drop policy if exists prefs_own on notification_prefs;
create policy prefs_own on notification_prefs for all
  using ( user_id = auth.uid() ) with check ( user_id = auth.uid() );

drop policy if exists majority_select on majority_transitions;
create policy majority_select on majority_transitions for select
  using ( app_can_see_player(player_id) );
drop policy if exists majority_write on majority_transitions;
create policy majority_write on majority_transitions for all
  using ( app_is_self(player_id) or app_role() in ('director','administrativo') )
  with check ( app_is_self(player_id) or app_role() in ('director','administrativo') );


-- ############################################################################
-- 10 · CANDADOS DE COLUMNA Y BORRADO
-- ############################################################################

-- Solo se pueden tocar las columnas de respuesta de un aviso.
revoke update on announcement_targets from authenticated;
grant  update (read_at, rsvp, rsvp_at, rsvp_by) on announcement_targets to authenticated;

-- Un aviso se RETIRA, nunca se borra: el registro es del club.
revoke delete on announcements, announcement_targets from authenticated;

-- El historial de consentimientos es la prueba: no se toca ni se borra.
revoke update, delete on consents from authenticated;


-- ############################################################################
-- 11 · SEMILLA
--   Descomenta, ejecuta, y copia el id que devuelve para el resto.
-- ############################################################################

-- insert into academies (name, country, city, primary_sport, season)
-- values ('CBJA Academy','España','Madrid','baloncesto','2026/2027')
-- returning id;

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
--  (:academy,'jugador',           false, false, false, false, false, false, false, false);


-- ############################################################################
-- 12 · COMPROBACIÓN
-- ############################################################################

do $$
declare f int := 0; t text;
begin
  foreach t in array array['academies','teams','users_profile','team_coaches',
    'player_access','role_permissions','invitations','players','player_private',
    'player_medical','measurements','documents','consents','finance',
    'family_billing','kit_orders','expenses','team_events','announcements',
    'announcement_targets','notifications','push_subscriptions',
    'notification_prefs','majority_transitions'] loop
    if to_regclass('public.'||t) is null then
      raise warning 'Falta la tabla %', t; f := f+1;
    end if;
  end loop;

  if (select prosrc from pg_proc where proname='app_is_staff') not like '%jugador%'
    then raise warning 'app_is_staff no excluye jugador'; f := f+1; end if;
  if (select prosrc from pg_proc where proname='app_is_guardian') not like '%Tutor%'
    then raise warning 'app_is_guardian no filtra relacion'; f := f+1; end if;
  if not exists (select 1 from pg_trigger where tgname='users_profile_no_escalation')
    then raise warning 'Falta el candado de escalada de rol'; f := f+1; end if;
  if not exists (select 1 from pg_trigger where tgname='announcement_guardian_fanout')
    then raise warning 'Falta la copia automatica a tutores'; f := f+1; end if;

  if f = 0 then raise notice '=== ESQUEMA COMPLETO APLICADO CORRECTAMENTE (24 tablas) ===';
  else raise notice '=== % comprobaciones fallidas ===', f; end if;
end $$;


-- ############################################################################
-- FUERA DE ALCANCE (se añadirá al especificar los roles que lo usan)
--   evaluations · reports · videos · tracking · recruitment
--   academy_subscriptions · ai_logs · audit_log · política de conservación
-- ############################################################################
