-- ============================================================================
-- ScoutFlow Academy · La nube (Supabase)
-- ----------------------------------------------------------------------------
-- POR QUÉ EXISTE ESTE ARCHIVO. La aplicación publicada ya guarda en Supabase,
-- en la tabla `academy_data`, pero esa tabla NO estaba escrita en ninguna parte
-- del repositorio: se creó a mano desde el editor SQL. Eso significa que la
-- infraestructura que está funcionando no se podía reconstruir desde el código,
-- y que nadie que abriera el proyecto podía saber qué forma tienen los datos.
-- Este archivo lo arregla.
--
-- OJO CON LO QUE ES Y LO QUE NO ES. Esto DOCUMENTA lo que hay desplegado; no es
-- lo que lo creó. Si algún detalle de la tabla real no coincide, manda la real:
-- compruébalo en Supabase → Table Editor antes de dar nada por hecho.
--
-- Se puede ejecutar entero y sin miedo: todo es `if not exists`, así que sobre
-- un proyecto que ya tiene las tablas no cambia nada.
--
-- Dónde: Supabase → SQL Editor → New query → pegar → Run.
-- ============================================================================


-- ---------------------------------------------------------------------------
-- 1. LOS DATOS DEL CLUB
-- ---------------------------------------------------------------------------
-- Hoy el club entero -jugadores, equipos, personal, finanzas- es UN SOLO
-- documento JSON por cuenta. Es lo que permitió subir todo a la nube sin
-- reescribir la aplicación: `SF.store` tenía una única puerta de lectura y
-- escritura, y esto se puso detrás.
--
-- SUS DOS LÍMITES, ESCRITOS AQUÍ PARA QUE NO SE OLVIDEN:
--   · Una cuenta = un club. Cada correo que se registra tiene su propio JSON.
--     Que varias personas compartan un club es el Paso 2, y todavía no está.
--   · Cada guardado pisa el anterior. De ahí la tabla de historial de abajo,
--     que es lo único que hoy hace que un error tenga marcha atrás.

create table if not exists academy_data (
  owner_id   uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null,
  updated_at timestamptz default now()
);

alter table academy_data enable row level security;

-- Cada uno solo ve y toca lo suyo. Sin esto, cualquiera con una cuenta podría
-- leer el club entero de otro club: nombres de menores, teléfonos de familias,
-- informes médicos y situación económica incluidos.
do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'academy_data' and policyname = 'propio_select') then
    create policy "propio_select" on academy_data for select using (auth.uid() = owner_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'academy_data' and policyname = 'propio_insert') then
    create policy "propio_insert" on academy_data for insert with check (auth.uid() = owner_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'academy_data' and policyname = 'propio_update') then
    create policy "propio_update" on academy_data for update using (auth.uid() = owner_id) with check (auth.uid() = owner_id);
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- 2. EL HISTORIAL DE VERSIONES
-- ---------------------------------------------------------------------------
-- El plan contratado de Supabase NO hace copias ("Last backup: No backups").
-- Súmalo a que el club es una fila que se pisa en cada guardado y sale esto:
-- si alguien borra media plantilla por error, lo guardado pasa a ser el club
-- sin esa media plantilla, y no hay ninguna versión de ayer a la que volver.
--
-- Esta tabla guarda una foto al día -y siempre antes de restaurar- y conserva
-- las diez últimas. No es un sistema de copias de nivel empresarial; es lo
-- suficiente para que ningún error de una tarde sea irreversible.
--
-- La aplicación funciona igual si esta tabla no existe: lo detecta, lo dice en
-- Configuración → Copias de seguridad y enseña este mismo SQL. Un club no se
-- puede quedar sin poder trabajar porque falte una tabla opcional.

create table if not exists academy_data_historial (
  id       uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  data     jsonb not null,
  motivo   text,
  creado   timestamptz default now()
);

create index if not exists idx_hist_owner on academy_data_historial (owner_id, creado desc);

alter table academy_data_historial enable row level security;

do $$ begin
  if not exists (select 1 from pg_policies where tablename = 'academy_data_historial' and policyname = 'propias_select') then
    create policy "propias_select" on academy_data_historial for select using (auth.uid() = owner_id);
  end if;
  if not exists (select 1 from pg_policies where tablename = 'academy_data_historial' and policyname = 'propias_insert') then
    create policy "propias_insert" on academy_data_historial for insert with check (auth.uid() = owner_id);
  end if;
  -- El borrado hace falta para conservar solo las diez últimas. Sin esta
  -- política la tabla crecería sin fin y el guardado empezaría a fallar.
  if not exists (select 1 from pg_policies where tablename = 'academy_data_historial' and policyname = 'propias_delete') then
    create policy "propias_delete" on academy_data_historial for delete using (auth.uid() = owner_id);
  end if;
end $$;


-- ---------------------------------------------------------------------------
-- COMPROBAR QUE HA IDO BIEN
-- ---------------------------------------------------------------------------
-- Las dos tablas deben salir con rowsecurity = true, y seis políticas en total.
--
--   select tablename, rowsecurity from pg_tables
--    where tablename in ('academy_data', 'academy_data_historial');
--
--   select tablename, policyname, cmd from pg_policies
--    where tablename in ('academy_data', 'academy_data_historial')
--    order by tablename, policyname;
