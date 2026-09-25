-- =============================================================================
-- ScoutFlow Academy · Esquema v3 — el modelo de datos por entidades (DESTINO)
-- =============================================================================
--
-- Versión: 25/09/2026 (tarea F0-10). Reescrito desde cero: el schema_v3.sql
-- del 29/08/2026 nunca llegó al repositorio. Se ha rehecho a partir de lo que
-- la app guarda HOY (las ~40 colecciones de SF.store) y de las decisiones de
-- claude/ESQUEMA_V3.md, que se conservan todas.
--
-- QUÉ ES Y QUÉ NO ES
--
--   Es el MAPA de hacia dónde van los datos: una tabla por cosa, con sus
--   reglas de acceso en el servidor. NO es lo que usa la app hoy. Hoy manda
--   database/paso2_multiusuario.sql (academies + members + academy_docs, una
--   fila por jugador, staff o equipo).
--
--   Vive en su propio esquema, `sf_v3`, a propósito: se puede ejecutar en el
--   Supabase real sin tocar ni una tabla de las que usa la app. La mudanza se
--   hará módulo a módulo (tarea F5-06), empezando por lo sensible (F1-05):
--   notas internas, sueldos, salud y familias.
--
-- CÓMO SE EJECUTA
--
--   Supabase → SQL Editor → pegar el archivo entero → Run. Se puede ejecutar
--   dos veces seguidas: todo es `if not exists` o se rehace igual.
--   En un Postgres normal (sin Supabase) hay que crear antes el esquema `auth`
--   simulado: tests/esquema/auth_simulado.sql.
--
-- REGLAS DE ESTILO (las del proyecto)
--
--   · Claves `uuid` con gen_random_uuid(); fechas `timestamptz default now()`.
--   · Claves foráneas explícitas, y un índice en cada una.
--   · TODA tabla con datos de un club lleva `academy_id` y RLS. El
--     `academy_id` repetido en tablas hijas no es un descuido: es lo que deja
--     escribir reglas de acceso simples y rápidas (una comparación, sin
--     recorrer la tabla padre), que es lo que recomienda Supabase.
--   · Las funciones `security definer` fijan `search_path = ''` y nombran
--     todo con su esquema, para que nadie pueda colar una tabla propia.
--
-- DECISIONES QUE NO SE DESHACEN (de ESQUEMA_V3.md y del proyecto)
--
--   · Lo sensible va en TABLA APARTE, nunca en columnas de `players`:
--     notas internas y Scout Score (player_private), salud (player_medical,
--     availability, appointments), contacto (player_contact), cuenta del banco
--     (billing_accounts), sueldos (salaries). Una regla sobre una tabla entera
--     es mucho más difícil de equivocar que una condición columna a columna.
--   · El Scout Score se calcula SOLO con evaluaciones deportivas. Ninguna
--     columna económica entra en su cálculo (art. 5.1.c del Reglamento de IA).
--   · `staff_clearance` guarda que administración COMPROBÓ el certificado de
--     delitos sexuales, nunca el documento.
--   · `reports.published`: un informe llega a la familia solo si una persona
--     lo publica, y eso lo decide el servidor.
--   · Licencias y revisiones por TEMPORADA, en filas, para no perder historial.
--   · Los planes de pago tienen VERSIÓN: un plan no se edita en sitio.
--   · `ord` en las listas que el club ordena a mano.
--   · Bajas con papelera: `deleted_at` en jugadores (F0-08). No hay política
--     de DELETE para nadie salvo dirección en papelera: un club no debería
--     poder vaciarse desde la app.
--   · Nada de archivos en la base: solo la ruta (`*_path`) en Supabase Storage,
--     que tiene sus propias reglas por carpeta y club (F3-01).
-- =============================================================================

create schema if not exists sf_v3;

-- -----------------------------------------------------------------------------
-- 0. UTILIDADES
-- -----------------------------------------------------------------------------

-- Pone `updated_at` al día en cada UPDATE.
create or replace function sf_v3.tg_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;


-- =============================================================================
-- 1. EL CLUB, SUS PERSONAS Y SUS PERMISOS
-- =============================================================================

create table if not exists sf_v3.academies (
  id              uuid primary key default gen_random_uuid(),
  name            text not null,
  country         text,
  city            text,
  primary_sport   text not null default 'baloncesto',
  plan            text not null default 'Starter'
                  check (plan in ('Starter', 'Pro', 'Elite', 'White Label')),
  eval_scale      smallint not null default 10,
  policy_version  text not null default 'v1',     -- versión de los textos legales aceptados
  created_by      uuid references auth.users(id) on delete set null,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now()
);

-- Ajustes del club que hoy viven en `academy` (métodos de pago, kit, textos
-- del cuadrante de PF). Una fila por club.
create table if not exists sf_v3.academy_settings (
  academy_id      uuid primary key references sf_v3.academies(id) on delete cascade,
  payment_methods jsonb not null default '[]',
  kit             jsonb not null default '{}',
  economy         jsonb not null default '{}',
  pf_criterios    text[] not null default '{}',
  pf_nota         text,
  pf_operativa    text,
  pf_alcance      text,
  updated_at      timestamptz not null default now()
);

-- Temporadas de verdad (antes, texto suelto en media docena de sitios).
create table if not exists sf_v3.seasons (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  label       text not null,                       -- '2026/2027'
  starts_on   date not null,
  ends_on     date not null,
  is_current  boolean not null default false,
  created_at  timestamptz not null default now(),
  unique (academy_id, label),
  check (ends_on > starts_on)
);
create unique index if not exists ux_seasons_current on sf_v3.seasons (academy_id) where is_current;

-- Personal del club (la ficha de staff). `num` es el correlativo del club.
create table if not exists sf_v3.staff (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  num           integer,
  full_name     text not null,
  alias         text,                              -- cómo sale en las hojas del club
  role          text not null,
  email         text,
  phone         text,
  bio           text,
  languages     text,
  pf_color      text,
  locked        boolean not null default false,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (academy_id, num)
);
create index if not exists ix_staff_academy on sf_v3.staff (academy_id);

-- QUIÉN PERTENECE Y CON QUÉ ROL. El rol lo dice el servidor.
create table if not exists sf_v3.members (
  user_id     uuid not null references auth.users(id) on delete cascade,
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  role        text not null,
  staff_id    uuid references sf_v3.staff(id) on delete set null,
  active      boolean not null default true,
  left_at     timestamptz,                         -- baja de un miembro sin borrar historial (F1-11)
  created_at  timestamptz not null default now(),
  primary key (user_id, academy_id)
);
create index if not exists ix_members_academy on sf_v3.members (academy_id) where active;
create index if not exists ix_members_staff on sf_v3.members (staff_id);

create table if not exists sf_v3.invitations (
  token       text primary key,                    -- sin «O» ni «I» (F1-03)
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  email       text,
  role        text not null,
  staff_id    uuid references sf_v3.staff(id) on delete set null,
  created_by  uuid references auth.users(id) on delete set null,
  expires_at  timestamptz not null default now() + interval '14 days',
  used_by     uuid references auth.users(id) on delete set null,
  used_at     timestamptz,
  created_at  timestamptz not null default now()
);
create index if not exists ix_invitations_academy on sf_v3.invitations (academy_id);

-- Los roles tal como los ha dejado el club (SF.rolDe): etiqueta, pestañas de
-- la ficha, secciones y capacidades. Director, padre y jugador son fijos.
create table if not exists sf_v3.role_settings (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  role        text not null,
  label       text,
  tabs        text[] not null default '{}',
  nav         text[] not null default '{}',
  caps        jsonb not null default '{}',         -- {"canSeeScore": true, ...}
  updated_at  timestamptz not null default now(),
  primary key (academy_id, role)
);

-- Excepciones persona a persona, con caducidad (pantalla Permisos).
create table if not exists sf_v3.user_permissions (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  perm        text not null,                       -- capacidad o 'nav:<ruta>'
  granted_by  uuid references auth.users(id) on delete set null,
  expires_at  timestamptz,
  created_at  timestamptz not null default now(),
  check (perm not in ('canSeeNotes', 'canManagePerms'))   -- nunca se reparten a mano
);
create index if not exists ix_user_permissions_staff on sf_v3.user_permissions (staff_id);

-- Registro de auditoría: fichas abiertas y editadas, permisos, exportaciones
-- (F1-10). Solo se inserta; nadie lo edita.
create table if not exists sf_v3.audit_log (
  id          bigint generated always as identity primary key,
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  actor       uuid references auth.users(id) on delete set null,
  actor_name  text,
  action      text not null,                       -- 'ver_ficha' | 'editar' | 'exportar' | 'permiso' ...
  entity      text not null,
  entity_id   text,
  detail      jsonb not null default '{}',
  at          timestamptz not null default now()
);
create index if not exists ix_audit_academy_at on sf_v3.audit_log (academy_id, at desc);

-- Quién ha entrado y cuándo (hoy `accesos`).
create table if not exists sf_v3.access_log (
  id          bigint generated always as identity primary key,
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  user_id     uuid references auth.users(id) on delete set null,
  what        text not null,
  at          timestamptz not null default now()
);
create index if not exists ix_access_academy_at on sf_v3.access_log (academy_id, at desc);


-- =============================================================================
-- 2. CATÁLOGOS COMUNES (no son de ningún club)
-- =============================================================================

-- Deportes: el núcleo es agnóstico; lo específico va aquí.
create table if not exists sf_v3.sports (
  key         text primary key,                    -- 'baloncesto', 'futbol', 'voley'...
  label       text not null,
  positions   text[] not null default '{}'
);

create table if not exists sf_v3.sport_skills (
  sport       text not null references sf_v3.sports(key) on delete cascade,
  grupo       text not null,                       -- 'Técnica' | 'Física' | 'Mental'
  skill       text not null,
  weight      numeric,                             -- peso del bloque en el Score
  ord         smallint not null default 0,
  primary key (sport, skill)
);


-- =============================================================================
-- 3. INSTALACIONES, EQUIPOS Y CUADRANTES
-- =============================================================================

create table if not exists sf_v3.facilities (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  name        text not null,
  abrev       text,
  address     text,
  ord         smallint not null default 0,
  created_at  timestamptz not null default now()
);
create index if not exists ix_facilities_academy on sf_v3.facilities (academy_id);

create table if not exists sf_v3.courts (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  facility_id  uuid not null references sf_v3.facilities(id) on delete cascade,
  name         text not null,
  ord          smallint not null default 0
);
create index if not exists ix_courts_facility on sf_v3.courts (facility_id);
create index if not exists ix_courts_academy on sf_v3.courts (academy_id);

-- Franjas horarias del cuadrante de pista.
create table if not exists sf_v3.time_slots (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  kind        text not null default 'pista' check (kind in ('pista', 'pf')),
  label       text,
  starts_at   time not null,
  ends_at     time not null,
  ord         smallint not null default 0,
  check (ends_at > starts_at)
);
create index if not exists ix_time_slots_academy on sf_v3.time_slots (academy_id);

create table if not exists sf_v3.teams (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  season_id    uuid references sf_v3.seasons(id) on delete set null,
  name         text not null,
  sport        text not null default 'baloncesto' references sf_v3.sports(key),
  segment      text,                               -- 'masculino' | 'femenino' | 'escuelas' | 'minis'
  category     text,
  programa     text not null default 'federado'
               check (programa in ('federado', 'escuela', 'academia', 'campus')),
  plan_id      uuid,                               -- FK a payment_plans, al final (§12)
  pf_objetivo  smallint,
  ord          smallint not null default 0,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists ix_teams_academy on sf_v3.teams (academy_id);
create index if not exists ix_teams_season on sf_v3.teams (season_id);

-- Cuerpo técnico de cada equipo: UNA sola verdad (antes, lista de nombres).
create table if not exists sf_v3.team_staff (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid not null references sf_v3.teams(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  role_in_team text not null default 'entrenador',
  primary key (team_id, staff_id)
);
create index if not exists ix_team_staff_staff on sf_v3.team_staff (staff_id);
create index if not exists ix_team_staff_academy on sf_v3.team_staff (academy_id);

create table if not exists sf_v3.team_wall_posts (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid not null references sf_v3.teams(id) on delete cascade,
  author_id   uuid references sf_v3.staff(id) on delete set null,
  body        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_team_wall_team on sf_v3.team_wall_posts (team_id, created_at desc);
create index if not exists ix_team_wall_academy on sf_v3.team_wall_posts (academy_id);

create table if not exists sf_v3.team_events (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid not null references sf_v3.teams(id) on delete cascade,
  kind        text not null default 'partido',     -- 'partido' | 'torneo' | 'reunion' | 'otro'
  starts_on   date not null,
  starts_at   time,
  place       text,
  rival       text,
  notes       text,
  created_at  timestamptz not null default now()
);
create index if not exists ix_team_events_team on sf_v3.team_events (team_id, starts_on);
create index if not exists ix_team_events_academy on sf_v3.team_events (academy_id);

-- Cuadrante de pista (hoy `horario`).
create table if not exists sf_v3.court_schedule (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  weekday      smallint not null check (weekday between 0 and 6),   -- 0 = lunes
  slot_id      uuid not null references sf_v3.time_slots(id) on delete cascade,
  facility_id  uuid not null references sf_v3.facilities(id) on delete cascade,
  court        text,
  team_id      uuid references sf_v3.teams(id) on delete set null,
  note         text
);
create index if not exists ix_court_schedule_academy on sf_v3.court_schedule (academy_id);
create index if not exists ix_court_schedule_team on sf_v3.court_schedule (team_id);
create index if not exists ix_court_schedule_slot on sf_v3.court_schedule (slot_id);
create index if not exists ix_court_schedule_facility on sf_v3.court_schedule (facility_id);

-- Cuadrante de preparación física (hoy `pf`).
create table if not exists sf_v3.pf_sessions (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  weekday       smallint not null check (weekday between 0 and 6),
  starts_at     time not null,
  ends_at       time not null,
  court_at      time,                              -- hora a la que salta a pista
  team_id       uuid not null references sf_v3.teams(id) on delete cascade,
  facility_id   uuid references sf_v3.facilities(id) on delete set null,
  court         text,
  prep_staff_id uuid references sf_v3.staff(id) on delete set null,
  check (ends_at > starts_at)
);
create index if not exists ix_pf_sessions_academy on sf_v3.pf_sessions (academy_id);
create index if not exists ix_pf_sessions_team on sf_v3.pf_sessions (team_id);
create index if not exists ix_pf_sessions_prep on sf_v3.pf_sessions (prep_staff_id);
create index if not exists ix_pf_sessions_facility on sf_v3.pf_sessions (facility_id);

-- Sesiones que NO se dan (festivos, torneo, pista cerrada): hoy `excepciones`.
-- Las sesiones en sí salen del cuadrante; aquí solo va lo que cambia.
create table if not exists sf_v3.session_exceptions (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid references sf_v3.teams(id) on delete cascade,   -- null = todo el club
  on_date     date not null,
  cancelled   boolean not null default true,
  reason      text,
  created_by  uuid references sf_v3.staff(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_session_exceptions_academy on sf_v3.session_exceptions (academy_id, on_date);
create index if not exists ix_session_exceptions_team on sf_v3.session_exceptions (team_id);
create index if not exists ix_session_exceptions_by on sf_v3.session_exceptions (created_by);


-- =============================================================================
-- 4. JUGADORES — el centro del producto
-- =============================================================================

-- La ficha, SIN nada sensible. Lo sensible, en las tablas de §5.
create table if not exists sf_v3.players (
  id                   uuid primary key default gen_random_uuid(),
  academy_id           uuid not null references sf_v3.academies(id) on delete cascade,
  ficha                integer not null,           -- nº de ficha: correlativo, permanente, referencia de pago
  scoutflow_id         text,
  first_name           text not null,
  last_name            text,
  full_name            text generated always as (btrim(first_name || ' ' || coalesce(last_name, ''))) stored,
  birth_date           date,
  birth_year           smallint,
  gender               text,
  nationality          text[] not null default '{}',
  residence_country    text,
  city                 text,
  sport                text not null default 'baloncesto' references sf_v3.sports(key),
  primary_position     text,
  secondary_position   text,
  dorsal               text,
  team_id              uuid references sf_v3.teams(id) on delete set null,
  -- Medidas: la MEDIDA la pone el preparador; la ESTIMADA, el scout. No se mezclan.
  height_cm            numeric(5,1),
  height_est_cm        numeric(5,1),
  weight_kg            numeric(5,1),
  wingspan_cm          numeric(5,1),
  dominant_hand        text,
  uses_both_hands      text,
  -- Deportivo
  club                 text,
  league               text,
  category             text,
  start_age            smallint,
  -- Académico
  school               text,
  course               text,
  gpa                  numeric(4,2),
  english              text,
  other_languages      text,
  graduation_date      date,
  university_interest  text,
  -- Captación y seguimiento
  status               text not null default 'Nuevo',
  channel              text,
  capture_date         date,
  objective            text,
  responsible_staff_id uuid references sf_v3.staff(id) on delete set null,
  scout_id             uuid references sf_v3.staff(id) on delete set null,
  next_action          text,
  next_action_date     date,
  instagram            text,
  photo_path           text,                       -- ruta en Storage, nunca el archivo (F3-02)
  family_active        boolean not null default false,
  created_by_staff_id  uuid references sf_v3.staff(id) on delete set null,
  created_at           timestamptz not null default now(),
  updated_at           timestamptz not null default now(),
  -- Papelera (F0-08): una baja no borra; se recupera quitando estas tres.
  deleted_at           timestamptz,
  deleted_by           text,
  deleted_reason       text,
  unique (academy_id, ficha)
);
create index if not exists ix_players_academy on sf_v3.players (academy_id) where deleted_at is null;
create index if not exists ix_players_team on sf_v3.players (team_id);
create index if not exists ix_players_birth_year on sf_v3.players (academy_id, birth_year);
create index if not exists ix_players_scout on sf_v3.players (scout_id);
create index if not exists ix_players_responsible on sf_v3.players (responsible_staff_id);
create index if not exists ix_players_created_by on sf_v3.players (created_by_staff_id);

-- Trayectoria: un club y una temporada por fila.
create table if not exists sf_v3.career_history (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  player_id    uuid not null references sf_v3.players(id) on delete cascade,
  club         text not null,
  season       text not null,
  category     text,
  competition  text,
  finish       text,
  ord          smallint not null default 0
);
create index if not exists ix_career_player on sf_v3.career_history (player_id);
create index if not exists ix_career_academy on sf_v3.career_history (academy_id);

create table if not exists sf_v3.player_selections (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  level       text not null check (level in ('local', 'provincial', 'regional', 'national')),
  value       text,
  primary key (player_id, level)
);
create index if not exists ix_selections_academy on sf_v3.player_selections (academy_id);

create table if not exists sf_v3.player_competitions (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  happened_on text,                                -- '2025-02' o fecha
  name        text not null,
  place       text,
  ranking     text,
  result      text
);
create index if not exists ix_player_competitions_player on sf_v3.player_competitions (player_id);
create index if not exists ix_player_competitions_academy on sf_v3.player_competitions (academy_id);

-- Seguimiento: los pasos del embudo y la línea temporal.
create table if not exists sf_v3.tracking_steps (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  step        text not null,                       -- 'Entrevista', 'Oferta enviada'...
  done        boolean not null default false,
  done_on     date,
  by_name     text,
  note        text,
  primary key (player_id, step)
);
create index if not exists ix_tracking_steps_academy on sf_v3.tracking_steps (academy_id);

create table if not exists sf_v3.tracking_log (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  at          timestamptz not null default now(),
  by_name     text,
  body        text not null
);
create index if not exists ix_tracking_log_player on sf_v3.tracking_log (player_id, at desc);
create index if not exists ix_tracking_log_academy on sf_v3.tracking_log (academy_id);

-- EVALUACIONES: de aquí, y solo de aquí, sale el Scout Score.
create table if not exists sf_v3.evaluations (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid not null references sf_v3.players(id) on delete cascade,
  season        text not null,
  evaluated_on  date not null default current_date,
  by_staff_id   uuid references sf_v3.staff(id) on delete set null,
  by_name       text,
  by_role       text,
  created_at    timestamptz not null default now()
);
create index if not exists ix_evaluations_player on sf_v3.evaluations (player_id, evaluated_on desc);
create index if not exists ix_evaluations_academy on sf_v3.evaluations (academy_id);
create index if not exists ix_evaluations_by on sf_v3.evaluations (by_staff_id);

create table if not exists sf_v3.evaluation_scores (
  academy_id     uuid not null references sf_v3.academies(id) on delete cascade,
  evaluation_id  uuid not null references sf_v3.evaluations(id) on delete cascade,
  skill          text not null,
  value          numeric(4,1) not null check (value >= 0 and value <= 10),
  primary key (evaluation_id, skill)
);
create index if not exists ix_evaluation_scores_academy on sf_v3.evaluation_scores (academy_id);

-- Tests físicos del preparador (los ~20 campos que usa hoy).
create table if not exists sf_v3.measurements (
  id                  uuid primary key default gen_random_uuid(),
  academy_id          uuid not null references sf_v3.academies(id) on delete cascade,
  player_id           uuid not null references sf_v3.players(id) on delete cascade,
  measured_on         date not null default current_date,
  season              text,
  by_staff_id         uuid references sf_v3.staff(id) on delete set null,
  height_cm           numeric(5,1),
  weight_kg           numeric(5,1),
  wingspan_cm         numeric(5,1),
  torso_height_cm     numeric(5,1),
  foot_length_cm      numeric(4,1),
  hand_length_cm      numeric(4,1),
  vertical_reach_stand numeric(5,1),
  vertical_reach_run  numeric(5,1),
  long_jump_stand_cm  numeric(5,1),
  long_jump_run_cm    numeric(5,1),
  cmj_cm              numeric(5,1),
  jump_single_l_cm    numeric(5,1),
  jump_single_r_cm    numeric(5,1),
  dropjump_rsi        numeric(5,2),
  sprint20_s          numeric(5,2),
  cod_s               numeric(5,2),
  decel_s             numeric(5,2),
  nordic_n            numeric(6,1),
  ankle_rom_deg       numeric(5,1),
  measured_with       text,
  created_at          timestamptz not null default now()
);
create index if not exists ix_measurements_player on sf_v3.measurements (player_id, measured_on desc);
create index if not exists ix_measurements_academy on sf_v3.measurements (academy_id);
create index if not exists ix_measurements_by on sf_v3.measurements (by_staff_id);

-- Documentos: el estado y la ruta. El archivo, en Storage.
create table if not exists sf_v3.documents (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references sf_v3.academies(id) on delete cascade,
  player_id      uuid not null references sf_v3.players(id) on delete cascade,
  doc_type       text not null,                    -- 'pasaporte' | 'dni' | 'expediente' | 'seguro_medico' ...
  status         text not null default 'pendiente'
                 check (status in ('pendiente', 'recibido', 'validado', 'rechazado')),
  file_path      text,
  expires_on     date,
  validated_by   uuid references sf_v3.staff(id) on delete set null,
  validated_at   timestamptz,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now(),
  unique (player_id, doc_type)
);
create index if not exists ix_documents_academy on sf_v3.documents (academy_id, status);
create index if not exists ix_documents_validated_by on sf_v3.documents (validated_by);

-- Informes: solo llegan a la familia si una persona los publica.
create table if not exists sf_v3.reports (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references sf_v3.academies(id) on delete cascade,
  player_id      uuid not null references sf_v3.players(id) on delete cascade,
  kind           text not null default 'manual' check (kind in ('manual', 'ia', 'reglas', 'video')),
  ai_assisted    boolean not null default false,   -- marca de IA visible (F2-12)
  model          text,
  body           jsonb not null default '{}',
  clips_used     integer,
  published      boolean not null default false,
  published_by   uuid references sf_v3.staff(id) on delete set null,
  published_at   timestamptz,
  created_by     uuid references sf_v3.staff(id) on delete set null,
  created_at     timestamptz not null default now(),
  check (not published or published_by is not null)
);
create index if not exists ix_reports_player on sf_v3.reports (player_id, created_at desc);
create index if not exists ix_reports_academy on sf_v3.reports (academy_id);
create index if not exists ix_reports_published_by on sf_v3.reports (published_by);
create index if not exists ix_reports_created_by on sf_v3.reports (created_by);

create table if not exists sf_v3.interviews (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  on_date     date not null,
  at_time     time,
  with_name   text,
  notes       text,
  done        boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists ix_interviews_player on sf_v3.interviews (player_id);
create index if not exists ix_interviews_academy on sf_v3.interviews (academy_id, on_date);

-- Mayoría de edad: a los 18 el acceso cambia de manos.
create table if not exists sf_v3.majority_transitions (
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid primary key references sf_v3.players(id) on delete cascade,
  turns_18_on   date not null,
  notified_at   timestamptz,
  accepted_at   timestamptz
);
create index if not exists ix_majority_academy on sf_v3.majority_transitions (academy_id, turns_18_on);


-- =============================================================================
-- 5. LO SENSIBLE — tablas aparte, con reglas más estrictas (§14)
-- =============================================================================

-- Notas internas, presupuesto por jugador, beca posible y Scout Score en caché.
-- Solo dirección con `canSeeNotes` (notas) o `canSeeScore` (Score).
create table if not exists sf_v3.player_private (
  academy_id        uuid not null references sf_v3.academies(id) on delete cascade,
  player_id         uuid primary key references sf_v3.players(id) on delete cascade,
  notes_internal    text,
  economic_notes    text,                          -- situación económica: NUNCA entra en el Score
  budget            numeric(10,2),
  scholarship       text,
  scout_score       smallint check (scout_score between 0 and 100),   -- caché; se recalcula de evaluations
  score_coverage    smallint,
  updated_at        timestamptz not null default now()
);
create index if not exists ix_player_private_academy on sf_v3.player_private (academy_id);

-- Contacto del jugador: no sale del club ni viaja a la IA.
create table if not exists sf_v3.player_contact (
  academy_id       uuid not null references sf_v3.academies(id) on delete cascade,
  player_id        uuid primary key references sf_v3.players(id) on delete cascade,
  phone            text,
  email            text,
  dni              text,
  address          text,
  emergency_phone  text,
  updated_at       timestamptz not null default now()
);
create index if not exists ix_player_contact_academy on sf_v3.player_contact (academy_id);

-- Salud: lo que el club necesita (apto, antecedentes declarados por la
-- familia). Nunca el diagnóstico de un fisioterapeuta: eso no es del club.
create table if not exists sf_v3.player_medical (
  academy_id        uuid not null references sf_v3.academies(id) on delete cascade,
  player_id         uuid not null references sf_v3.players(id) on delete cascade,
  season            text not null,
  checkup_date      date,
  fit               boolean,
  congenital        text,
  surgeries         text,
  injuries          text,
  cardio_resp       text,
  blood_type        text,
  allergies         text,
  correctors        text,
  vaccination       text,
  notes             text,
  updated_by        uuid references sf_v3.staff(id) on delete set null,
  updated_at        timestamptz not null default now(),
  primary key (player_id, season)
);
create index if not exists ix_player_medical_academy on sf_v3.player_medical (academy_id);
create index if not exists ix_player_medical_by on sf_v3.player_medical (updated_by);

-- Disponibilidad: si puede jugar y qué NO puede hacer, en términos deportivos.
-- Sin diagnóstico. Aun así es dato de salud: no viaja a la IA (F0-17).
create table if not exists sf_v3.availability (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  estado      text not null default 'disponible' check (estado in ('disponible', 'limitada', 'no')),
  limitacion  text,
  carga       text,
  desde       date,
  hasta       date,
  nota        text,
  by_staff_id uuid references sf_v3.staff(id) on delete set null,
  by_role     text,
  at          timestamptz not null default now(),
  is_current  boolean not null default true
);
create unique index if not exists ux_availability_current on sf_v3.availability (player_id) where is_current;
create index if not exists ix_availability_academy on sf_v3.availability (academy_id);
create index if not exists ix_availability_by on sf_v3.availability (by_staff_id);

-- Citas con fisioterapia o bienestar mental (hoy `citas`).
create table if not exists sf_v3.appointments (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  player_id    uuid not null references sf_v3.players(id) on delete cascade,
  team_id      uuid references sf_v3.teams(id) on delete set null,
  with_role    text not null check (with_role in ('fisio', 'psicologo')),
  kind         text,
  reason       text,
  detail       text,
  estado       text not null default 'pedida',
  on_date      date,
  at_time      time,
  note         text,
  requested_by uuid references sf_v3.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists ix_appointments_academy on sf_v3.appointments (academy_id, on_date);
create index if not exists ix_appointments_player on sf_v3.appointments (player_id);
create index if not exists ix_appointments_team on sf_v3.appointments (team_id);
create index if not exists ix_appointments_by on sf_v3.appointments (requested_by);

-- Familias: cada tutor es una persona, con su cuenta para el Portal Family.
create table if not exists sf_v3.guardians (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  full_name   text not null,
  phone       text,
  email       text,
  user_id     uuid references auth.users(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_guardians_academy on sf_v3.guardians (academy_id);
create index if not exists ix_guardians_user on sf_v3.guardians (user_id);

create table if not exists sf_v3.player_guardians (
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  player_id    uuid not null references sf_v3.players(id) on delete cascade,
  guardian_id  uuid not null references sf_v3.guardians(id) on delete cascade,
  relation     text,                              -- 'madre' | 'padre' | 'tutor' ...
  is_primary   boolean not null default false,
  legal_guardian boolean not null default true,
  primary key (player_id, guardian_id)
);
create index if not exists ix_player_guardians_guardian on sf_v3.player_guardians (guardian_id);
create index if not exists ix_player_guardians_academy on sf_v3.player_guardians (academy_id);

-- Consentimientos: NUNCA se actualizan; se inserta una fila nueva.
create table if not exists sf_v3.consents (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid not null references sf_v3.players(id) on delete cascade,
  consent_type  text not null,                     -- 'imagen' | 'datos' | 'ia' | 'salida' ...
  granted       boolean not null,
  guardian_id   uuid references sf_v3.guardians(id) on delete set null,
  text_version  text not null,
  at            timestamptz not null default now()
);
create index if not exists ix_consents_player on sf_v3.consents (player_id, consent_type, at desc);
create index if not exists ix_consents_academy on sf_v3.consents (academy_id);
create index if not exists ix_consents_guardian on sf_v3.consents (guardian_id);

-- Cuenta para domiciliar (hoy `bank`). Solo administración y dirección.
create table if not exists sf_v3.billing_accounts (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid not null references sf_v3.players(id) on delete cascade,
  guardian_id   uuid references sf_v3.guardians(id) on delete set null,
  holder        text,
  iban          text,
  method        text,                              -- 'domiciliacion' | 'transferencia' | 'tarjeta' ...
  sepa_mandate  text,
  mandate_date  date,
  updated_at    timestamptz not null default now()
);
create index if not exists ix_billing_player on sf_v3.billing_accounts (player_id);
create index if not exists ix_billing_academy on sf_v3.billing_accounts (academy_id);
create index if not exists ix_billing_guardian on sf_v3.billing_accounts (guardian_id);


-- =============================================================================
-- 6. STAFF: TITULACIONES, LICENCIAS, CERTIFICADO Y SUELDOS
-- =============================================================================

create table if not exists sf_v3.staff_qualifications (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  title       text not null,
  entity      text,
  year        smallint,
  number      text
);
create index if not exists ix_staff_qual_staff on sf_v3.staff_qualifications (staff_id);
create index if not exists ix_staff_qual_academy on sf_v3.staff_qualifications (academy_id);

-- Licencia federativa POR TEMPORADA: renovar no borra la del año pasado.
create table if not exists sf_v3.staff_licences (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id     uuid not null references sf_v3.staff(id) on delete cascade,
  season       text not null,
  number       text,
  category     text,
  valid_until  date,
  status       text not null default 'pendiente'
               check (status in ('pendiente', 'vigente', 'caducada', 'no_aplica')),
  unique (staff_id, season)
);
create index if not exists ix_staff_licences_academy on sf_v3.staff_licences (academy_id);

-- Certificado de delitos sexuales: que se COMPROBÓ, quién y cuándo. Nunca el
-- documento, que custodia administración fuera de la app.
create table if not exists sf_v3.staff_clearance (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  season      text not null,
  cleared     boolean not null,
  checked_on  date not null,
  checked_by  text not null,
  unique (staff_id, season)
);
create index if not exists ix_staff_clearance_academy on sf_v3.staff_clearance (academy_id);

create table if not exists sf_v3.staff_experience (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  club        text not null,
  role        text,
  from_year   smallint,
  to_year     smallint
);
create index if not exists ix_staff_exp_staff on sf_v3.staff_experience (staff_id);
create index if not exists ix_staff_exp_academy on sf_v3.staff_experience (academy_id);

create table if not exists sf_v3.staff_training (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  course      text not null,
  entity      text,
  year        smallint
);
create index if not exists ix_staff_training_staff on sf_v3.staff_training (staff_id);
create index if not exists ix_staff_training_academy on sf_v3.staff_training (academy_id);

-- Quién tocó qué en la ficha de staff.
create table if not exists sf_v3.staff_history (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id    uuid not null references sf_v3.staff(id) on delete cascade,
  at          timestamptz not null default now(),
  by_name     text,
  change      jsonb not null default '{}'
);
create index if not exists ix_staff_history_staff on sf_v3.staff_history (staff_id, at desc);
create index if not exists ix_staff_history_academy on sf_v3.staff_history (academy_id);

-- Sueldos: cada concepto, su importe y su periodicidad. Solo `canSeeSalaries`.
create table if not exists sf_v3.salaries (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  staff_id     uuid not null references sf_v3.staff(id) on delete cascade,
  season       text,
  kind         text not null default 'otro',
  label        text not null,
  amount       numeric(10,2) not null check (amount >= 0),
  periodicity  text not null default 'mensual' check (periodicity in ('mensual', 'trimestral', 'anual', 'unico')),
  months       smallint not null default 12,
  destino      text,                               -- partida del presupuesto
  created_at   timestamptz not null default now()
);
create index if not exists ix_salaries_staff on sf_v3.salaries (staff_id);
create index if not exists ix_salaries_academy on sf_v3.salaries (academy_id);

-- Personal adjunto (colaboradores que no son staff: árbitros, monitores de campus...).
create table if not exists sf_v3.attached_people (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  full_name   text not null,
  role        text,
  phone       text,
  email       text,
  notes       text,
  created_at  timestamptz not null default now()
);
create index if not exists ix_attached_academy on sf_v3.attached_people (academy_id);


-- =============================================================================
-- 7. CAPTACIÓN: OJEOS Y VIAJES DEL SCOUT
-- =============================================================================

create table if not exists sf_v3.trips (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  scout_id     uuid references sf_v3.staff(id) on delete set null,
  name         text not null,
  scope        text,
  competition  text,
  from_date    date,
  to_date      date,
  city         text,
  country      text,
  venue        text,
  categories   text[] not null default '{}',
  notes        text,
  created_at   timestamptz not null default now()
);
create index if not exists ix_trips_academy on sf_v3.trips (academy_id);
create index if not exists ix_trips_scout on sf_v3.trips (scout_id);

create table if not exists sf_v3.scoutings (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  scout_id     uuid references sf_v3.staff(id) on delete set null,
  trip_id      uuid references sf_v3.trips(id) on delete set null,
  on_date      date not null,
  at_time      time,
  kind         text,
  competition  text,
  home         text,
  away         text,
  place        text,
  city         text,
  objective    text,
  estado       text not null default 'previsto',
  report       text,
  created_at   timestamptz not null default now()
);
create index if not exists ix_scoutings_academy on sf_v3.scoutings (academy_id, on_date);
create index if not exists ix_scoutings_scout on sf_v3.scoutings (scout_id);
create index if not exists ix_scoutings_trip on sf_v3.scoutings (trip_id);

create table if not exists sf_v3.scouting_players (
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  scouting_id  uuid not null references sf_v3.scoutings(id) on delete cascade,
  player_id    uuid not null references sf_v3.players(id) on delete cascade,
  primary key (scouting_id, player_id)
);
create index if not exists ix_scouting_players_player on sf_v3.scouting_players (player_id);
create index if not exists ix_scouting_players_academy on sf_v3.scouting_players (academy_id);

create table if not exists sf_v3.trip_players (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  trip_id     uuid not null references sf_v3.trips(id) on delete cascade,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  primary key (trip_id, player_id)
);
create index if not exists ix_trip_players_player on sf_v3.trip_players (player_id);
create index if not exists ix_trip_players_academy on sf_v3.trip_players (academy_id);


-- =============================================================================
-- 8. ENTRENAMIENTO: EJERCICIOS, SESIONES Y ASISTENCIA
-- =============================================================================

-- Biblioteca de ejercicios. `academy_id` NULL = catálogo de fábrica, que ven
-- todos los clubes; con club = los suyos (o su copia editada).
create table if not exists sf_v3.exercises (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid references sf_v3.academies(id) on delete cascade,
  sport        text not null default 'baloncesto' references sf_v3.sports(key),
  name         text not null,
  level        text,
  objective    text,
  moment       text,
  minutes      smallint,
  players_txt  text,
  min_players  smallint,
  max_players  smallint,
  material     text,
  description  text,
  keys         text,
  author       text,
  folder       text,
  section      text,
  stage        text,
  format       text,
  practice     text,
  family       text,
  step         text,
  not_yet      text,
  created_at   timestamptz not null default now()
);
create index if not exists ix_exercises_academy on sf_v3.exercises (academy_id);

-- El paso a paso, con su dibujo de pizarra.
create table if not exists sf_v3.exercise_steps (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid references sf_v3.academies(id) on delete cascade,
  exercise_id  uuid not null references sf_v3.exercises(id) on delete cascade,
  ord          smallint not null default 0,
  body         text,
  drawing      jsonb
);
create index if not exists ix_exercise_steps_exercise on sf_v3.exercise_steps (exercise_id, ord);
create index if not exists ix_exercise_steps_academy on sf_v3.exercise_steps (academy_id);

-- Lo planificado para una sesión concreta (equipo + día).
create table if not exists sf_v3.session_plans (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid not null references sf_v3.teams(id) on delete cascade,
  on_date     date not null,
  notes       text,
  created_by  uuid references sf_v3.staff(id) on delete set null,
  created_at  timestamptz not null default now(),
  unique (team_id, on_date)
);
create index if not exists ix_session_plans_academy on sf_v3.session_plans (academy_id, on_date);
create index if not exists ix_session_plans_by on sf_v3.session_plans (created_by);

create table if not exists sf_v3.session_plan_items (
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  plan_id      uuid not null references sf_v3.session_plans(id) on delete cascade,
  exercise_id  uuid not null references sf_v3.exercises(id) on delete restrict,
  ord          smallint not null default 0,
  minutes      smallint,
  primary key (plan_id, ord)
);
create index if not exists ix_session_items_exercise on sf_v3.session_plan_items (exercise_id);
create index if not exists ix_session_items_academy on sf_v3.session_plan_items (academy_id);

-- Asistencia a entrenamientos (hoy `asistencias`).
create table if not exists sf_v3.attendance (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  team_id     uuid not null references sf_v3.teams(id) on delete cascade,
  on_date     date not null,
  player_id   uuid not null references sf_v3.players(id) on delete cascade,
  status      text not null check (status in ('presente', 'ausente', 'justificada', 'tarde', 'lesion')),
  note        text,
  marked_by   uuid references sf_v3.staff(id) on delete set null,
  marked_at   timestamptz not null default now(),
  primary key (team_id, on_date, player_id)
);
create index if not exists ix_attendance_player on sf_v3.attendance (player_id, on_date);
create index if not exists ix_attendance_academy on sf_v3.attendance (academy_id, on_date);
create index if not exists ix_attendance_by on sf_v3.attendance (marked_by);


-- =============================================================================
-- 9. VÍDEO Y CORTES
-- =============================================================================

create table if not exists sf_v3.videos (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  team_id      uuid references sf_v3.teams(id) on delete set null,
  url          text not null,
  title        text,
  kind         text,                               -- 'partido' | 'entrenamiento' | 'highlights' ...
  played_on    date,
  rival        text,
  competition  text,
  kit_home     text,
  kit_away     text,
  created_by   uuid references sf_v3.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists ix_videos_academy on sf_v3.videos (academy_id);
create index if not exists ix_videos_team on sf_v3.videos (team_id);
create index if not exists ix_videos_by on sf_v3.videos (created_by);

create table if not exists sf_v3.video_clips (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  video_id    uuid not null references sf_v3.videos(id) on delete cascade,
  player_id   uuid references sf_v3.players(id) on delete set null,
  t_seconds   integer not null check (t_seconds >= 0),
  title       text,
  label       text,
  sign        text,                                -- acierto / error corregible ...
  con_balon   text,
  sin_balon   text,
  resultado   text,
  note        text,
  by_ia       boolean not null default false,      -- lo propuso la IA y lo aceptó una persona
  created_by  uuid references sf_v3.staff(id) on delete set null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_video_clips_video on sf_v3.video_clips (video_id, t_seconds);
create index if not exists ix_video_clips_player on sf_v3.video_clips (player_id);
create index if not exists ix_video_clips_academy on sf_v3.video_clips (academy_id);
create index if not exists ix_video_clips_by on sf_v3.video_clips (created_by);


-- =============================================================================
-- 10. COMUNICACIÓN Y PROTECCIÓN DEL MENOR
-- =============================================================================

-- Comunicados del club, con su público y quién los revisó.
create table if not exists sf_v3.announcements (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  title        text not null,
  body         text not null,
  audience     jsonb not null default '{}',        -- {"grupos":[...], "equipos":[...]}
  created_by   uuid references sf_v3.staff(id) on delete set null,
  reviewed_by  uuid references sf_v3.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists ix_announcements_academy on sf_v3.announcements (academy_id, created_at desc);
create index if not exists ix_announcements_by on sf_v3.announcements (created_by);
create index if not exists ix_announcements_reviewed on sf_v3.announcements (reviewed_by);

create table if not exists sf_v3.announcement_reads (
  academy_id       uuid not null references sf_v3.academies(id) on delete cascade,
  announcement_id  uuid not null references sf_v3.announcements(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  read_at          timestamptz not null default now(),
  primary key (announcement_id, user_id)
);
create index if not exists ix_announcement_reads_user on sf_v3.announcement_reads (user_id);
create index if not exists ix_announcement_reads_academy on sf_v3.announcement_reads (academy_id);

-- Conversaciones con respuesta. Regla de oro: un adulto del club NO tiene
-- canal privado con un menor. Con menores de 14 la conversación es con la
-- familia; de 14 a 17, la familia está siempre dentro (`family_copied`).
create table if not exists sf_v3.conversations (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references sf_v3.academies(id) on delete cascade,
  subject        text,
  player_id      uuid references sf_v3.players(id) on delete set null,   -- de quién se habla
  family_copied  boolean not null default true,
  created_by     uuid references auth.users(id) on delete set null,
  created_at     timestamptz not null default now()
);
create index if not exists ix_conversations_academy on sf_v3.conversations (academy_id);
create index if not exists ix_conversations_player on sf_v3.conversations (player_id);

create table if not exists sf_v3.conversation_participants (
  academy_id       uuid not null references sf_v3.academies(id) on delete cascade,
  conversation_id  uuid not null references sf_v3.conversations(id) on delete cascade,
  user_id          uuid not null references auth.users(id) on delete cascade,
  role             text,
  primary key (conversation_id, user_id)
);
create index if not exists ix_conv_participants_user on sf_v3.conversation_participants (user_id);
create index if not exists ix_conv_participants_academy on sf_v3.conversation_participants (academy_id);

create table if not exists sf_v3.messages (
  id               uuid primary key default gen_random_uuid(),
  academy_id       uuid not null references sf_v3.academies(id) on delete cascade,
  conversation_id  uuid not null references sf_v3.conversations(id) on delete cascade,
  author_id        uuid references auth.users(id) on delete set null,
  body             text not null,
  at               timestamptz not null default now()
);
create index if not exists ix_messages_conversation on sf_v3.messages (conversation_id, at);
create index if not exists ix_messages_academy on sf_v3.messages (academy_id);

-- Registro de comunicaciones con familias y menores (LOPIVI): qué, cuándo,
-- por qué canal. Solo se inserta.
create table if not exists sf_v3.comms_log (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  player_id   uuid references sf_v3.players(id) on delete set null,
  channel     text not null,
  from_name   text,
  to_name     text,
  summary     text,
  at          timestamptz not null default now()
);
create index if not exists ix_comms_log_academy on sf_v3.comms_log (academy_id, at desc);
create index if not exists ix_comms_log_player on sf_v3.comms_log (player_id);

-- Canal para que un menor o su familia escriba a la persona delegada de
-- protección (LOPIVI art. 48; tarea F2-11). Solo lo leen ella y dirección.
create table if not exists sf_v3.safeguarding_reports (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid references sf_v3.players(id) on delete set null,
  reporter_kind text not null check (reporter_kind in ('menor', 'familia', 'staff', 'otro')),
  body          text not null,
  estado        text not null default 'recibido',
  handled_by    uuid references sf_v3.staff(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists ix_safeguarding_academy on sf_v3.safeguarding_reports (academy_id, created_at desc);
create index if not exists ix_safeguarding_player on sf_v3.safeguarding_reports (player_id);
create index if not exists ix_safeguarding_handled on sf_v3.safeguarding_reports (handled_by);

-- Tablón del club (partidos del finde, quién entrena hoy, avisos revisados).
create table if not exists sf_v3.board_posts (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  kind          text not null default 'aviso',
  title         text,
  body          text,
  visible_from  date,
  visible_until date,
  reviewed_by   uuid references sf_v3.staff(id) on delete set null,
  created_by    uuid references sf_v3.staff(id) on delete set null,
  created_at    timestamptz not null default now()
);
create index if not exists ix_board_academy on sf_v3.board_posts (academy_id, visible_from);
create index if not exists ix_board_reviewed on sf_v3.board_posts (reviewed_by);
create index if not exists ix_board_created on sf_v3.board_posts (created_by);

-- Buzón de avisos de cada persona.
create table if not exists sf_v3.notifications (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  user_id      uuid not null references auth.users(id) on delete cascade,
  kind         text not null,
  body         text not null,
  link         text,
  supervisor   text,
  created_at   timestamptz not null default now(),
  read_at      timestamptz
);
create index if not exists ix_notifications_user on sf_v3.notifications (user_id, created_at desc) where read_at is null;
create index if not exists ix_notifications_academy on sf_v3.notifications (academy_id);

create table if not exists sf_v3.push_subscriptions (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  endpoint    text not null unique,
  keys        jsonb not null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_push_user on sf_v3.push_subscriptions (user_id);
create index if not exists ix_push_academy on sf_v3.push_subscriptions (academy_id);

create table if not exists sf_v3.notification_prefs (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  user_id     uuid not null references auth.users(id) on delete cascade,
  kind        text not null,
  push        boolean not null default true,
  email       boolean not null default false,
  primary key (user_id, kind)
);
create index if not exists ix_notification_prefs_academy on sf_v3.notification_prefs (academy_id);


-- =============================================================================
-- 11. TRÁMITES, TIENDA Y ALMACÉN
-- =============================================================================

-- Los trámites del club: cada enlace, solo a quien le toca.
create table if not exists sf_v3.procedures (
  id             uuid primary key default gen_random_uuid(),
  academy_id     uuid not null references sf_v3.academies(id) on delete cascade,
  ord            smallint not null default 0,
  family         text,
  title          text not null,
  destination    text,                             -- URL
  secret         text,                             -- código o contraseña del trámite
  secret_label   text,
  audience       text[] not null default '{}',     -- roles que lo ven
  season         text,
  ack_required   boolean not null default false,
  note           text
);
create index if not exists ix_procedures_academy on sf_v3.procedures (academy_id);

create table if not exists sf_v3.procedure_done (
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  procedure_id  uuid not null references sf_v3.procedures(id) on delete cascade,
  user_id       uuid not null references auth.users(id) on delete cascade,
  done_at       timestamptz not null default now(),
  primary key (procedure_id, user_id)
);
create index if not exists ix_procedure_done_user on sf_v3.procedure_done (user_id);
create index if not exists ix_procedure_done_academy on sf_v3.procedure_done (academy_id);

-- La ropa del club, prenda a prenda.
create table if not exists sf_v3.store_items (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  label       text not null,
  category    text,
  sizes       text[] not null default '{}',
  price       numeric(8,2),
  supplier_ref text,
  active      boolean not null default true
);
create index if not exists ix_store_items_academy on sf_v3.store_items (academy_id);

create table if not exists sf_v3.kit_packs (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  name        text not null,
  price       numeric(8,2),
  for_role    text                                 -- 'jugador' | 'staff'
);
create index if not exists ix_kit_packs_academy on sf_v3.kit_packs (academy_id);

create table if not exists sf_v3.kit_pack_items (
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  pack_id     uuid not null references sf_v3.kit_packs(id) on delete cascade,
  item_id     uuid not null references sf_v3.store_items(id) on delete restrict,
  qty         smallint not null default 1 check (qty > 0),
  primary key (pack_id, item_id)
);
create index if not exists ix_kit_pack_items_item on sf_v3.kit_pack_items (item_id);
create index if not exists ix_kit_pack_items_academy on sf_v3.kit_pack_items (academy_id);

-- Pedidos de ropa: de un jugador o de alguien del staff.
create table if not exists sf_v3.kit_orders (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid references sf_v3.players(id) on delete cascade,
  staff_id      uuid references sf_v3.staff(id) on delete cascade,
  pack_id       uuid references sf_v3.kit_packs(id) on delete set null,
  sizes         jsonb not null default '{}',
  print_name    text,
  print_number  text,
  status        text not null default 'pedido',    -- 'pedido' | 'en_almacen' | 'entregado'
  requested_at  timestamptz not null default now(),
  delivered_at  timestamptz,
  check ((player_id is null) <> (staff_id is null))
);
create index if not exists ix_kit_orders_academy on sf_v3.kit_orders (academy_id, status);
create index if not exists ix_kit_orders_player on sf_v3.kit_orders (player_id);
create index if not exists ix_kit_orders_staff on sf_v3.kit_orders (staff_id);
create index if not exists ix_kit_orders_pack on sf_v3.kit_orders (pack_id);

-- Movimientos de almacén: entrada por albarán, salida por entrega.
create table if not exists sf_v3.stock_movements (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  item_id      uuid not null references sf_v3.store_items(id) on delete restrict,
  size         text,
  qty          integer not null check (qty <> 0),  -- positivo entra, negativo sale
  moved_on     date not null default current_date,
  delivery_ref text,                               -- nº de albarán
  order_id     uuid references sf_v3.kit_orders(id) on delete set null,
  by_staff_id  uuid references sf_v3.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists ix_stock_item on sf_v3.stock_movements (item_id, size);
create index if not exists ix_stock_academy on sf_v3.stock_movements (academy_id, moved_on);
create index if not exists ix_stock_order on sf_v3.stock_movements (order_id);
create index if not exists ix_stock_by on sf_v3.stock_movements (by_staff_id);


-- =============================================================================
-- 12. DINERO: PLANES, CARGOS, RECIBOS, GASTOS Y PRESUPUESTO
-- =============================================================================

-- Plan de pago por temporada, CON VERSIÓN: cambiar un precio es crear la
-- versión siguiente, para que los recibos ya emitidos sigan cuadrando.
create table if not exists sf_v3.payment_plans (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  season      text not null,
  name        text not null,
  version     smallint not null default 1,
  programa    text not null default 'federado'
              check (programa in ('federado', 'escuela', 'academia', 'campus')),
  active      boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (academy_id, season, name, version)
);
create index if not exists ix_payment_plans_academy on sf_v3.payment_plans (academy_id);

-- Una fila puede describir «7 cuotas de septiembre a marzo».
create table if not exists sf_v3.plan_items (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  plan_id     uuid not null references sf_v3.payment_plans(id) on delete cascade,
  kind        text not null check (kind in ('inscripcion', 'cuota', 'equipacion', 'torneo', 'seguro', 'otro')),
  label       text not null,
  amount      numeric(8,2) not null check (amount >= 0),
  count       smallint not null default 1 check (count > 0),
  from_month  text,
  to_month    text,
  ord         smallint not null default 0
);
create index if not exists ix_plan_items_plan on sf_v3.plan_items (plan_id);
create index if not exists ix_plan_items_academy on sf_v3.plan_items (academy_id);

create table if not exists sf_v3.plan_discounts (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  plan_id     uuid not null references sf_v3.payment_plans(id) on delete cascade,
  kind        text not null default 'hermanos',
  rule        jsonb not null default '{}'          -- {"2º": 10, "3º": 20} en %
);
create index if not exists ix_plan_discounts_plan on sf_v3.plan_discounts (plan_id);
create index if not exists ix_plan_discounts_academy on sf_v3.plan_discounts (academy_id);

-- Plan especial de un jugador (beca, descuento propio). Lo aprueba una persona.
create table if not exists sf_v3.player_plan_overrides (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  player_id    uuid not null references sf_v3.players(id) on delete cascade,
  plan_id      uuid references sf_v3.payment_plans(id) on delete set null,
  discount_pct numeric(5,2) check (discount_pct between 0 and 100),
  note         text,
  approved_by  uuid references sf_v3.staff(id) on delete set null,
  created_at   timestamptz not null default now()
);
create index if not exists ix_plan_overrides_player on sf_v3.player_plan_overrides (player_id);
create index if not exists ix_plan_overrides_academy on sf_v3.player_plan_overrides (academy_id);
create index if not exists ix_plan_overrides_plan on sf_v3.player_plan_overrides (plan_id);
create index if not exists ix_plan_overrides_approved on sf_v3.player_plan_overrides (approved_by);

-- Cada cargo sabe de qué plan salió (`plan_id`) o si se puso a mano (`manual`).
create table if not exists sf_v3.finance_items (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references sf_v3.academies(id) on delete cascade,
  player_id     uuid not null references sf_v3.players(id) on delete restrict,
  plan_id       uuid references sf_v3.payment_plans(id) on delete set null,
  manual        boolean not null default false,
  concept       text not null,
  amount        numeric(8,2) not null,
  due_on        date,
  status        text not null default 'pendiente'
                check (status in ('pendiente', 'cobrado', 'cobrado_firme', 'devuelto', 'anulado')),
  paid_on       date,
  method        text,
  remittance    text,                              -- remesa SEPA (F4-03)
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);
create index if not exists ix_finance_player on sf_v3.finance_items (player_id);
create index if not exists ix_finance_academy_status on sf_v3.finance_items (academy_id, status);
create index if not exists ix_finance_plan on sf_v3.finance_items (plan_id);

-- Recibos, no facturas: el club no factura a las familias (Verifactu, F4-04).
create table if not exists sf_v3.receipts (
  id               uuid primary key default gen_random_uuid(),
  academy_id       uuid not null references sf_v3.academies(id) on delete cascade,
  finance_item_id  uuid not null references sf_v3.finance_items(id) on delete restrict,
  number           text not null,
  issued_at        timestamptz not null default now(),
  pdf_path         text,
  unique (academy_id, number)
);
create index if not exists ix_receipts_item on sf_v3.receipts (finance_item_id);

-- Gastos del club (hoy `expenses`), con su ticket en Storage.
create table if not exists sf_v3.expenses (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references sf_v3.academies(id) on delete cascade,
  spent_on     date not null,
  concept      text not null,
  category     text,
  amount       numeric(10,2) not null check (amount >= 0),
  by_name      text,
  by_role      text,
  status       text not null default 'pendiente' check (status in ('pendiente', 'aprobado', 'pagado', 'rechazado')),
  paid_on      date,
  note         text,
  ticket_path  text,
  created_at   timestamptz not null default now()
);
create index if not exists ix_expenses_academy on sf_v3.expenses (academy_id, spent_on);

-- Presupuesto de la temporada, partida a partida.
create table if not exists sf_v3.budget_lines (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  season      text not null,
  kind        text not null check (kind in ('ingreso', 'gasto')),
  category    text not null,
  label       text,
  amount      numeric(10,2) not null,
  ord         smallint not null default 0
);
create index if not exists ix_budget_academy on sf_v3.budget_lines (academy_id, season);


-- =============================================================================
-- 13. DATOS DEL CLUB: IMPORTACIÓN Y COPIAS
-- =============================================================================

-- Cómo se escribe cada cosa en las hojas del club ("Miguel" = tal persona).
create table if not exists sf_v3.import_aliases (
  id          uuid primary key default gen_random_uuid(),
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  kind        text not null,                       -- 'equipo' | 'preparador' | 'pabellon'
  alias       text not null,
  target_id   uuid not null,
  unique (academy_id, kind, alias)
);

-- Foto del club entero, una al día (hoy academy_data_historial).
create table if not exists sf_v3.data_snapshots (
  id          bigint generated always as identity primary key,
  academy_id  uuid not null references sf_v3.academies(id) on delete cascade,
  taken_at    timestamptz not null default now(),
  taken_by    uuid references auth.users(id) on delete set null,
  payload     jsonb not null
);
create index if not exists ix_snapshots_academy on sf_v3.data_snapshots (academy_id, taken_at desc);


-- -----------------------------------------------------------------------------
-- §12b. Claves foráneas hacia tablas creadas más abajo. Van al final para que
-- el archivo corra de una pasada sin ordenar por dependencias.
-- -----------------------------------------------------------------------------
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'fk_teams_plan') then
    alter table sf_v3.teams
      add constraint fk_teams_plan foreign key (plan_id) references sf_v3.payment_plans(id) on delete set null;
  end if;
end;
$$;
create index if not exists ix_teams_plan on sf_v3.teams (plan_id);


-- =============================================================================
-- 14. REGLAS DE ACCESO (RLS)
-- =============================================================================
--
-- Tres capas, de más general a más estricta:
--
--   1. BASE, en TODA tabla con `academy_id`: se ve y se toca solo lo del club
--      propio. La crea el bucle de abajo, así ninguna tabla nueva se queda sin
--      regla por olvido.
--   2. ESTRICTAS (`as restrictive`), en las tablas sensibles: además de ser
--      del club, hay que tener la capacidad. Una regla restrictiva se suma a
--      la base con un Y; no la sustituye.
--   3. FAMILIAS Y JUGADORES: solo lo suyo (F1-06). Se escribe tabla a tabla
--      al migrar cada módulo; aquí va el modelo en `players`.
--
-- No hay DELETE para nadie salvo lo indicado: un club no se vacía desde la app.
-- -----------------------------------------------------------------------------

-- Club de quien llama.
create or replace function sf_v3.app_academy()
returns uuid
language sql stable security definer
set search_path = ''
as $$
  select m.academy_id from sf_v3.members m
   where m.user_id = (select auth.uid()) and m.active
   limit 1
$$;

create or replace function sf_v3.app_role()
returns text
language sql stable security definer
set search_path = ''
as $$
  select m.role from sf_v3.members m
   where m.user_id = (select auth.uid()) and m.active
   limit 1
$$;

-- ¿Tiene quien llama esta capacidad? Rol del club + excepciones vigentes.
create or replace function sf_v3.app_can(p_cap text)
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce((
    select m.role = 'director'
        or coalesce((rs.caps ->> p_cap)::boolean, false)
        or exists (select 1 from sf_v3.user_permissions up
                    where up.staff_id = m.staff_id and up.perm = p_cap
                      and (up.expires_at is null or up.expires_at > now()))
      from sf_v3.members m
      left join sf_v3.role_settings rs on rs.academy_id = m.academy_id and rs.role = m.role
     where m.user_id = (select auth.uid()) and m.active
     limit 1), false)
$$;

-- Quién manda: invita, cambia roles, gestiona fichas y papelera.
create or replace function sf_v3.app_manda()
returns boolean
language sql stable security definer
set search_path = ''
as $$
  select coalesce(sf_v3.app_role() in ('director', 'dt_general', 'administrativo'), false)
$$;

-- Jugadores que un padre o un jugador pueden ver: los suyos.
create or replace function sf_v3.app_mis_jugadores()
returns setof uuid
language sql stable security definer
set search_path = ''
as $$
  select pg.player_id
    from sf_v3.player_guardians pg
    join sf_v3.guardians g on g.id = pg.guardian_id
   where g.user_id = (select auth.uid())
$$;

revoke all on function sf_v3.app_academy() from public;
revoke all on function sf_v3.app_role() from public;
revoke all on function sf_v3.app_can(text) from public;
revoke all on function sf_v3.app_manda() from public;
revoke all on function sf_v3.app_mis_jugadores() from public;
grant execute on function sf_v3.app_academy() to authenticated;
grant execute on function sf_v3.app_role() to authenticated;
grant execute on function sf_v3.app_can(text) to authenticated;
grant execute on function sf_v3.app_manda() to authenticated;
grant execute on function sf_v3.app_mis_jugadores() to authenticated;

grant usage on schema sf_v3 to authenticated;

-- 1. BASE: toda tabla con academy_id.
do $$
declare
  t record;
begin
  for t in
    select c.table_name
      from information_schema.columns c
      join information_schema.tables tb
        on tb.table_schema = c.table_schema and tb.table_name = c.table_name and tb.table_type = 'BASE TABLE'
     where c.table_schema = 'sf_v3' and c.column_name = 'academy_id'
  loop
    execute format('alter table sf_v3.%I enable row level security', t.table_name);
    execute format('grant select, insert, update on sf_v3.%I to authenticated', t.table_name);
    execute format('drop policy if exists base_select on sf_v3.%I', t.table_name);
    execute format('drop policy if exists base_insert on sf_v3.%I', t.table_name);
    execute format('drop policy if exists base_update on sf_v3.%I', t.table_name);
    execute format('create policy base_select on sf_v3.%I for select to authenticated using (academy_id = (select sf_v3.app_academy()))', t.table_name);
    execute format('create policy base_insert on sf_v3.%I for insert to authenticated with check (academy_id = (select sf_v3.app_academy()))', t.table_name);
    execute format('create policy base_update on sf_v3.%I for update to authenticated using (academy_id = (select sf_v3.app_academy())) with check (academy_id = (select sf_v3.app_academy()))', t.table_name);
  end loop;
end;
$$;

-- La tabla de clubes se mira por su `id`, no por `academy_id`.
alter table sf_v3.academies enable row level security;
grant select, update on sf_v3.academies to authenticated;
drop policy if exists ac_select on sf_v3.academies;
drop policy if exists ac_update on sf_v3.academies;
create policy ac_select on sf_v3.academies for select to authenticated using (id = (select sf_v3.app_academy()));
create policy ac_update on sf_v3.academies for update to authenticated using (id = (select sf_v3.app_academy()) and (select sf_v3.app_manda()));

-- El catálogo de fábrica de ejercicios (academy_id NULL) lo ve todo el mundo.
drop policy if exists base_select on sf_v3.exercises;
create policy base_select on sf_v3.exercises for select to authenticated
  using (academy_id is null or academy_id = (select sf_v3.app_academy()));
drop policy if exists base_select on sf_v3.exercise_steps;
create policy base_select on sf_v3.exercise_steps for select to authenticated
  using (academy_id is null or academy_id = (select sf_v3.app_academy()));

-- Catálogos comunes: solo lectura.
alter table sf_v3.sports enable row level security;
alter table sf_v3.sport_skills enable row level security;
grant select on sf_v3.sports, sf_v3.sport_skills to authenticated;
drop policy if exists cat_select on sf_v3.sports;
drop policy if exists cat_select on sf_v3.sport_skills;
create policy cat_select on sf_v3.sports for select to authenticated using (true);
create policy cat_select on sf_v3.sport_skills for select to authenticated using (true);

-- 2. ESTRICTAS. Nombre fijo `solo_*`; se rehacen enteras en cada ejecución.
do $$
declare
  r record;
begin
  for r in
    select * from (values
      -- tabla,               capacidad que hace falta
      ('player_private',      'canSeeNotes'),
      ('player_medical',      'canSeeMedical'),
      ('appointments',        'canSeeMedical'),
      ('salaries',            'canSeeSalaries'),
      ('billing_accounts',    'canManageFinance'),
      ('finance_items',       'canSeeFinance'),
      ('receipts',            'canSeeFinance'),
      ('budget_lines',        'canSeeFinance'),
      ('expenses',            'canSeeFinance'),
      ('player_plan_overrides','canSeeFinance'),
      ('safeguarding_reports','canHandleSafeguarding'),
      ('audit_log',           'canManagePerms'),
      ('user_permissions',    'canManagePerms')
    ) as v(tabla, cap)
  loop
    execute format('drop policy if exists solo_select on sf_v3.%I', r.tabla);
    execute format('drop policy if exists solo_insert on sf_v3.%I', r.tabla);
    execute format('drop policy if exists solo_update on sf_v3.%I', r.tabla);
    execute format('create policy solo_select on sf_v3.%I as restrictive for select to authenticated using (sf_v3.app_can(%L))', r.tabla, r.cap);
    execute format('create policy solo_insert on sf_v3.%I as restrictive for insert to authenticated with check (sf_v3.app_can(%L))', r.tabla, r.cap);
    execute format('create policy solo_update on sf_v3.%I as restrictive for update to authenticated using (sf_v3.app_can(%L))', r.tabla, r.cap);
  end loop;
end;
$$;

-- El registro de auditoría solo se INSERTA (lo hace el servidor) y se lee con
-- permiso; nadie lo cambia.
revoke update on sf_v3.audit_log from authenticated;
revoke update on sf_v3.comms_log from authenticated;
revoke update on sf_v3.consents from authenticated;

-- El Scout Score y las notas viven en la misma fila privada: quien tiene
-- `canSeeScore` pero no `canSeeNotes` (un DT) lo leerá por una vista que solo
-- saca el Score, cuando se migre ese módulo. Hasta entonces, solo notas.

-- 3. FAMILIAS Y JUGADORES: solo los suyos. En `players`, además de la base,
-- una regla restrictiva: si el rol es de familia, solo sus jugadores.
drop policy if exists solo_familia on sf_v3.players;
create policy solo_familia on sf_v3.players as restrictive for select to authenticated
  using (
    coalesce(sf_v3.app_role(), '') not in ('padre', 'jugador')
    or id in (select sf_v3.app_mis_jugadores())
  );

-- Informes: la familia solo ve los PUBLICADOS de sus hijos.
drop policy if exists solo_publicados on sf_v3.reports;
create policy solo_publicados on sf_v3.reports as restrictive for select to authenticated
  using (
    coalesce(sf_v3.app_role(), '') not in ('padre', 'jugador')
    or (published and player_id in (select sf_v3.app_mis_jugadores()))
  );

-- Papelera: el borrado DEFINITIVO de un jugador, solo quien manda.
grant delete on sf_v3.players to authenticated;
drop policy if exists solo_manda_borra on sf_v3.players;
create policy solo_manda_borra on sf_v3.players for delete to authenticated
  using (academy_id = (select sf_v3.app_academy()) and (select sf_v3.app_manda()) and deleted_at is not null);

-- Miembros: se ve a los del club; cambiar roles, solo quien manda.
drop policy if exists base_update on sf_v3.members;
create policy base_update on sf_v3.members for update to authenticated
  using (academy_id = (select sf_v3.app_academy()) and (select sf_v3.app_manda()));
drop policy if exists base_insert on sf_v3.members;   -- se entra con una invitación, por función del servidor


-- =============================================================================
-- 15. updated_at automático
-- =============================================================================
do $$
declare
  t record;
begin
  for t in
    select c.table_name from information_schema.columns c
     where c.table_schema = 'sf_v3' and c.column_name = 'updated_at'
  loop
    execute format('drop trigger if exists tg_updated_at on sf_v3.%I', t.table_name);
    execute format('create trigger tg_updated_at before update on sf_v3.%I for each row execute function sf_v3.tg_updated_at()', t.table_name);
  end loop;
end;
$$;


-- =============================================================================
-- 16. CATÁLOGO INICIAL DE DEPORTES (multi-deporte desde el principio)
-- =============================================================================
insert into sf_v3.sports (key, label, positions) values
  ('baloncesto', 'Baloncesto', array['Base', 'Escolta', 'Alero', 'Ala-pívot', 'Pívot']),
  ('futbol',     'Fútbol',     array['Portero', 'Defensa', 'Centrocampista', 'Delantero']),
  ('voley',      'Vóley',      array['Colocador', 'Opuesto', 'Central', 'Receptor', 'Líbero']),
  ('hockey',     'Hockey',     array[]::text[]),
  ('rugby',      'Rugby',      array[]::text[]),
  ('tenis',      'Tenis',      array[]::text[]),
  ('otro',       'Otro',       array[]::text[])
on conflict (key) do nothing;


-- =============================================================================
-- 17. COMPROBACIÓN
-- =============================================================================
-- Debe salir (25/09/2026): 91 tablas, las 91 con RLS, 219 claves foráneas.
-- Si sale una tabla sin RLS, esa tabla está abierta: no se sigue.
select
  (select count(*) from information_schema.tables where table_schema = 'sf_v3' and table_type = 'BASE TABLE') as tablas,
  (select count(*) from pg_tables where schemaname = 'sf_v3' and rowsecurity) as con_rls,
  (select count(*) from pg_constraint c join pg_namespace n on n.oid = c.connamespace
    where n.nspname = 'sf_v3' and c.contype = 'f') as claves_foraneas,
  (select count(*) from pg_policies where schemaname = 'sf_v3') as reglas;
