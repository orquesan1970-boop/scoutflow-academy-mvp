-- =============================================================================
-- ScoutFlow Academy · Paso 2 — El club es de todos, no de una cuenta
-- =============================================================================
--
-- QUÉ PROBLEMA RESUELVE
--
-- Hasta ahora `academy_data` guardaba un JSON entero por `owner_id`. Eso quiere
-- decir que si un entrenador se creaba una cuenta, NO veía el club: veía una
-- academia nueva sembrada desde cero. Los 17 roles de la aplicación eran un
-- selector de la pantalla, no personas de verdad.
--
-- Un producto que se vende a clubes no puede funcionar así: un club son varias
-- personas mirando los mismos jugadores.
--
--
-- POR QUÉ UNA FILA POR ENTIDAD Y NO CUARENTA TABLAS
--
-- Lo ortodoxo sería normalizar: una tabla `players`, otra `teams`, otra
-- `documents`... Se descartó a propósito. Normalizar obliga a reescribir los
-- ~100 métodos de `SF.store` como llamadas asíncronas, es decir, tocar todas
-- las pantallas de una aplicación que hoy funciona.
--
-- Partir el almacén en filas da el multiusuario real SIN tocar ni una pantalla:
-- `SF.store` sigue viendo un objeto y no se entera de nada. Cuando cada cosa
-- necesite sus propias reglas en el servidor, se normaliza por partes.
--
--
-- CÓMO SE EJECUTA
--
--   1. ANTES DE NADA: en la app, Configuración → Datos → Exportar JSON.
--      Esto no borra nada, pero una copia en el escritorio cuesta diez segundos.
--   2. Supabase → SQL Editor → pegar este archivo ENTERO → Run.
--   3. Al final del archivo hay una consulta de comprobación. Debe decir
--      cuántos jugadores, personal y equipos han viajado.
--
-- Se puede ejecutar DOS VECES seguidas sin romper nada: todo es `if not exists`
-- o `on conflict do nothing`, y la migración se marca para no repetirse.
--
-- NO BORRA `academy_data`. Se queda como red de seguridad. Cuando lleve unas
-- semanas funcionando, se podrá quitar a mano.
-- =============================================================================


-- -----------------------------------------------------------------------------
-- 1. LAS TABLAS
-- -----------------------------------------------------------------------------

-- El club. Todo lo demás cuelga de aquí.
create table if not exists academies (
  id         uuid primary key default gen_random_uuid(),
  nombre     text not null,
  deporte    text default 'baloncesto',
  creado_por uuid references auth.users(id) on delete set null,
  creado     timestamptz default now()
);

-- QUIÉN PERTENECE Y CON QUÉ ROL.
-- Esta tabla sustituye al selector de rol de la demo. A partir de aquí el rol
-- de una persona lo dice el SERVIDOR, no un desplegable de la pantalla: un
-- entrenador no puede ascenderse a director cambiando una opción.
create table if not exists members (
  user_id    uuid not null references auth.users(id) on delete cascade,
  academy_id uuid not null references academies(id) on delete cascade,
  role       text not null default 'entrenador',
  -- Con qué ficha de personal se corresponde. Es lo que permite que
  -- "mis equipos" signifique algo de verdad y no dependa del rol.
  staff_id   text,
  -- Jugadores asignados, para roles con alcance limitado (scout, padre).
  player_ids text[] default '{}',
  activo     boolean not null default true,
  creado     timestamptz default now(),
  primary key (user_id, academy_id)
);

create index if not exists idx_members_academy on members (academy_id) where activo;

-- INVITACIONES. Alta por código, porque mandar correos necesita configurar un
-- proveedor y eso es otra batalla. El código se pasa por WhatsApp y listo.
create table if not exists invitations (
  token      text primary key,
  academy_id uuid not null references academies(id) on delete cascade,
  correo     text,
  role       text not null default 'entrenador',
  staff_id   text,
  invita     uuid references auth.users(id) on delete set null,
  usado_por  uuid references auth.users(id) on delete set null,
  usado      timestamptz,
  caduca     timestamptz not null default (now() + interval '14 days'),
  creado     timestamptz default now()
);

create index if not exists idx_inv_academy on invitations (academy_id);

-- LOS DATOS. Un jugador = una fila.
--
--   col  = qué colección es ('players', 'staff', 'teams', 'videoteca'…)
--   item = su id dentro de la colección
--   ord  = EL ORDEN ORIGINAL. Sin esto las fichas bailarían de sitio en cada
--          recarga, porque Postgres no promete orden sin un ORDER BY.
--   data = el objeto tal cual
create table if not exists academy_docs (
  academy_id uuid not null references academies(id) on delete cascade,
  col        text not null,
  item       text not null,
  ord        int  not null default 0,
  data       jsonb not null,
  actualizado timestamptz default now(),
  primary key (academy_id, col, item)
);

create index if not exists idx_docs_col on academy_docs (academy_id, col, ord);


-- -----------------------------------------------------------------------------
-- 2. FUNCIONES DE APOYO
--
-- VAN EN `security definer` Y NO ES UN DETALLE. Si consultaran `members` con
-- los permisos de quien llama, la propia regla RLS de `members` volvería a
-- llamar a esta función para decidir si puede leer `members`, y Postgres
-- cortaría por recursión infinita. Con `security definer` se saltan la RLS al
-- consultar, que es exactamente lo que hace falta aquí.
--
-- `set search_path = public` va para que nadie pueda colar un esquema propio
-- delante y hacer que la función lea otra tabla.
-- -----------------------------------------------------------------------------

create or replace function app_academy()
returns uuid
language sql stable security definer set search_path = public as $$
  select academy_id from members
   where user_id = auth.uid() and activo
   limit 1
$$;

create or replace function app_role()
returns text
language sql stable security definer set search_path = public as $$
  select role from members
   where user_id = auth.uid() and activo
   limit 1
$$;

-- Quién puede invitar y cambiar a los demás.
create or replace function app_manda()
returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce(
    (select role in ('director', 'direccion_tecnica', 'administrador')
       from members where user_id = auth.uid() and activo limit 1),
    false)
$$;


-- -----------------------------------------------------------------------------
-- 3. LAS REGLAS (RLS)
--
-- Sin esto, cualquiera con una cuenta podría leer el club de otro. Es la única
-- parte de este archivo que de verdad protege algo.
-- -----------------------------------------------------------------------------

alter table academies    enable row level security;
alter table members      enable row level security;
alter table invitations  enable row level security;
alter table academy_docs enable row level security;

-- Los clubes: se ve el propio, y nada más.
drop policy if exists ac_select on academies;
create policy ac_select on academies
  for select using (id = app_academy());

drop policy if exists ac_update on academies;
create policy ac_update on academies
  for update using (id = app_academy() and app_manda());

-- Los miembros: se ven los del propio club. Solo quien manda puede cambiarlos.
drop policy if exists me_select on members;
create policy me_select on members
  for select using (academy_id = app_academy());

drop policy if exists me_update on members;
create policy me_update on members
  for update using (academy_id = app_academy() and app_manda());

drop policy if exists me_delete on members;
create policy me_delete on members
  for delete using (academy_id = app_academy() and app_manda());

-- Las invitaciones: solo quien manda las ve y las crea.
drop policy if exists inv_all on invitations;
create policy inv_all on invitations
  for all using (academy_id = app_academy() and app_manda())
  with check (academy_id = app_academy() and app_manda());

-- LOS DATOS: todo miembro activo del club lee y escribe.
--
-- HONESTIDAD SOBRE LO QUE ESTO NO HACE: el reparto fino por rol —que la familia
-- solo vea a su hijo, que las notas internas no salgan de dirección— sigue
-- viviendo en la interfaz, no aquí. Alguien con cuenta de entrenador y ganas de
-- abrir la consola podría leer más de lo que su pantalla le enseña.
--
-- Se blinda de verdad cuando cada cosa tenga su tabla. Mientras tanto conviene
-- saberlo y no venderlo como lo que no es.
drop policy if exists docs_all on academy_docs;
create policy docs_all on academy_docs
  for all using (academy_id = app_academy())
  with check (academy_id = app_academy());


-- -----------------------------------------------------------------------------
-- 4. LAS OPERACIONES
--
-- Van como funciones y no como escrituras sueltas desde el navegador porque
-- crean o cambian pertenencias: si la app pudiera insertar en `members`
-- directamente, cualquiera podría meterse en cualquier club.
-- -----------------------------------------------------------------------------

-- Crear el club. Quien lo crea queda de director.
create or replace function app_crear_club(p_nombre text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_id  uuid;
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'Hay que haber entrado con una cuenta.';
  end if;

  -- Si ya pertenece a un club, se devuelve ese. Llamar dos veces no crea dos
  -- clubes: es de los errores más fáciles de cometer desde el navegador.
  select academy_id into v_id from members where user_id = v_uid and activo limit 1;
  if v_id is not null then
    return v_id;
  end if;

  insert into academies (nombre, creado_por)
  values (coalesce(nullif(trim(p_nombre), ''), 'Mi club'), v_uid)
  returning id into v_id;

  insert into members (user_id, academy_id, role)
  values (v_uid, v_id, 'director');

  return v_id;
end;
$$;

-- Invitar. Devuelve el código que hay que pasarle a la persona.
create or replace function app_invitar(p_correo text, p_role text, p_staff_id text default null)
returns text
language plpgsql security definer set search_path = public as $$
declare
  v_ac  uuid := app_academy();
  v_tok text;
begin
  if v_ac is null or not app_manda() then
    raise exception 'No tienes permiso para invitar a nadie.';
  end if;

  -- Reinvitar al mismo correo NO crea un código nuevo: se refresca el que hay.
  -- Si no, una persona acaba con cuatro códigos y sin saber cuál vale.
  select token into v_tok
    from invitations
   where academy_id = v_ac
     and lower(coalesce(correo, '')) = lower(coalesce(trim(p_correo), ''))
     and usado is null
   limit 1;

  if v_tok is not null then
    update invitations
       set caduca = now() + interval '14 days', role = p_role, staff_id = p_staff_id
     where token = v_tok;
    return v_tok;
  end if;

  -- Código corto, en mayúsculas y sin caracteres que se confundan al dictarlo
  -- por teléfono (ni O ni 0, ni I ni 1).
  v_tok := upper(translate(substr(encode(gen_random_bytes(9), 'base64'), 1, 8),
                           'O0I1l+/=', 'XYZWVMNP'));

  insert into invitations (token, academy_id, correo, role, staff_id, invita)
  values (v_tok, v_ac, nullif(trim(p_correo), ''), coalesce(p_role, 'entrenador'), p_staff_id, auth.uid());

  return v_tok;
end;
$$;

-- Aceptar una invitación con el código.
create or replace function app_aceptar(p_token text)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_inv invitations%rowtype;
  v_uid uuid := auth.uid();
  v_ya  uuid;
begin
  if v_uid is null then
    raise exception 'Hay que haber entrado con una cuenta.';
  end if;

  select * into v_inv from invitations
   where token = upper(trim(p_token));

  if v_inv.token is null then
    raise exception 'Ese código no existe. Revisa que esté bien escrito.';
  end if;
  if v_inv.usado is not null then
    raise exception 'Ese código ya se ha usado.';
  end if;
  if v_inv.caduca < now() then
    raise exception 'Ese código ha caducado. Pide uno nuevo.';
  end if;

  select academy_id into v_ya from members where user_id = v_uid and activo limit 1;
  if v_ya is not null and v_ya <> v_inv.academy_id then
    raise exception 'Ya perteneces a otro club.';
  end if;

  insert into members (user_id, academy_id, role, staff_id)
  values (v_uid, v_inv.academy_id, v_inv.role, v_inv.staff_id)
  on conflict (user_id, academy_id) do update
    set activo = true, role = excluded.role, staff_id = excluded.staff_id;

  update invitations set usado = now(), usado_por = v_uid where token = v_inv.token;

  return v_inv.academy_id;
end;
$$;

-- Qué soy y dónde. Una sola llamada al entrar, en vez de tres consultas.
create or replace function app_quien_soy()
returns table (academy_id uuid, nombre text, role text, staff_id text, player_ids text[])
language sql stable security definer set search_path = public as $$
  select a.id, a.nombre, m.role, m.staff_id, m.player_ids
    from members m
    join academies a on a.id = m.academy_id
   where m.user_id = auth.uid() and m.activo
   limit 1
$$;

grant execute on function app_crear_club(text)  to authenticated;
grant execute on function app_invitar(text, text, text) to authenticated;
grant execute on function app_aceptar(text)     to authenticated;
grant execute on function app_quien_soy()       to authenticated;
grant execute on function app_academy()         to authenticated;
grant execute on function app_role()            to authenticated;
grant execute on function app_manda()           to authenticated;

-- `anon` no toca nada. Quien no ha entrado, no existe para esta base de datos.
revoke all on academies, members, invitations, academy_docs from anon;


-- -----------------------------------------------------------------------------
-- 5. TRAER LO QUE YA HAY
--
-- Coge cada fila de `academy_data` y la reparte en filas de `academy_docs`.
-- No borra el original. Es idempotente: se marca en `_meta` y no se repite.
-- -----------------------------------------------------------------------------

-- Las colecciones que se parten en filas. Son las tres que crecen: un club con
-- 277 jugadores, al cambiar un dorsal, sube UNA fila y no el club entero.
-- El resto de listas (cuadrante, ojeos, gastos…) viajan enteras porque son
-- pequeñas y partirlas no compensa la complejidad.
create or replace function app_migrar_una(p_owner uuid, p_data jsonb)
returns uuid
language plpgsql security definer set search_path = public as $$
declare
  v_ac     uuid;
  v_nombre text;
  v_col    text;
  v_item   jsonb;
  v_i      int;
  v_resto  jsonb := p_data;
  c_partir text[] := array['players', 'staff', 'teams'];
begin
  if p_data is null or p_data = 'null'::jsonb then
    return null;
  end if;

  -- ¿Ya tiene club esta cuenta? Si no, se le crea uno con el nombre que trae
  -- el propio JSON, para que no se llame "Mi club" teniendo nombre de verdad.
  select academy_id into v_ac from members where user_id = p_owner and activo limit 1;

  if v_ac is null then
    v_nombre := coalesce(nullif(trim(p_data #>> '{academy,name}'), ''), 'CBJA Academy');
    insert into academies (nombre, creado_por) values (v_nombre, p_owner) returning id into v_ac;
    insert into members (user_id, academy_id, role) values (p_owner, v_ac, 'director')
      on conflict (user_id, academy_id) do nothing;
  end if;

  -- Ya migrado: no se vuelve a hacer.
  if exists (select 1 from academy_docs where academy_id = v_ac and col = '_meta' and item = 'migracion') then
    return v_ac;
  end if;

  -- Las tres grandes, fila a fila, conservando el orden.
  foreach v_col in array c_partir loop
    if jsonb_typeof(p_data -> v_col) = 'array' then
      v_i := 0;
      for v_item in select * from jsonb_array_elements(p_data -> v_col) loop
        insert into academy_docs (academy_id, col, item, ord, data)
        values (v_ac, v_col,
                coalesce(nullif(v_item ->> 'id', ''), v_col || '_' || v_i),
                v_i, v_item)
        on conflict (academy_id, col, item) do update set data = excluded.data, ord = excluded.ord;
        v_i := v_i + 1;
      end loop;
      v_resto := v_resto - v_col;
    end if;
  end loop;

  -- Todo lo demás, entero, en una fila por clave.
  for v_col in select jsonb_object_keys(v_resto) loop
    insert into academy_docs (academy_id, col, item, ord, data)
    values (v_ac, '_todo', v_col, 0, jsonb_build_object('v', v_resto -> v_col))
    on conflict (academy_id, col, item) do update set data = excluded.data;
  end loop;

  insert into academy_docs (academy_id, col, item, ord, data)
  values (v_ac, '_meta', 'migracion', 0,
          jsonb_build_object('desde', 'academy_data', 'cuando', now()))
  on conflict (academy_id, col, item) do nothing;

  return v_ac;
end;
$$;

-- Se ejecuta para cada fila que haya en academy_data.
do $$
declare r record;
begin
  if to_regclass('public.academy_data') is null then
    raise notice 'No hay academy_data: nada que traer.';
    return;
  end if;
  for r in select owner_id, data from academy_data loop
    perform app_migrar_una(r.owner_id, r.data);
  end loop;
end $$;


-- -----------------------------------------------------------------------------
-- 6. LA MARCHA ATRÁS
--
-- ESTO EXISTE PARA QUE LA DECISIÓN NO SEA DE UN SOLO SENTIDO.
--
-- Volver atrás el mismo día es fácil: este archivo no borra `academy_data`, así
-- que basta con tirar las tablas nuevas y volver a publicar el index.html
-- anterior. El club sigue exactamente donde estaba.
--
-- El problema es volver atrás DESPUÉS. A las tres semanas, el trabajo nuevo
-- vive en `academy_docs` y `academy_data` se quedó congelado el día de la
-- migración: desandar el camino costaría esas tres semanas.
--
-- Esta función lo arregla. Recompone el JSON del club a partir de las filas y
-- lo devuelve a `academy_data`, con lo de hoy dentro. Después ya se pueden
-- tirar las tablas nuevas sin perder nada.
--
-- Cómo se usa, si algún día hace falta:
--     select app_volver_atras();
--     -- comprobar que el JSON tiene lo que debe:
--     select jsonb_array_length(data->'players') from academy_data;
--     -- y solo entonces, si se quiere limpiar:
--     -- drop table academy_docs, invitations, members, academies cascade;
-- -----------------------------------------------------------------------------

create or replace function app_volver_atras()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_ac    uuid;
  v_uid   uuid := auth.uid();
  v_out   jsonb := '{}'::jsonb;
  r       record;
begin
  select academy_id into v_ac from members where user_id = v_uid and activo limit 1;
  if v_ac is null then
    raise exception 'No perteneces a ningún club.';
  end if;

  -- Las listas que viajaron enteras, tal cual estaban.
  for r in select item, data from academy_docs where academy_id = v_ac and col = '_todo' loop
    v_out := v_out || jsonb_build_object(r.item, r.data -> 'v');
  end loop;

  -- Las tres que se partieron, recompuestas EN SU ORDEN. Sin el `order by ord`
  -- las fichas volverían barajadas, que es la forma más silenciosa de romper
  -- una restauración: no falla, simplemente queda mal.
  for r in select col, jsonb_agg(data order by ord) as arr
             from academy_docs
            where academy_id = v_ac and col in ('players', 'staff', 'teams')
            group by col loop
    v_out := v_out || jsonb_build_object(r.col, r.arr);
  end loop;

  -- Se devuelve al sitio de antes, pisando lo que hubiera.
  insert into academy_data (owner_id, data) values (v_uid, v_out)
  on conflict (owner_id) do update set data = excluded.data;

  return jsonb_build_object(
    'ok', true,
    'jugadores', coalesce(jsonb_array_length(v_out -> 'players'), 0),
    'personal',  coalesce(jsonb_array_length(v_out -> 'staff'), 0),
    'equipos',   coalesce(jsonb_array_length(v_out -> 'teams'), 0));
end;
$$;

grant execute on function app_volver_atras() to authenticated;


-- -----------------------------------------------------------------------------
-- 7. COMPROBACIÓN
--
-- Esto es lo que hay que mirar después de ejecutar. Debe salir una fila por
-- club, con cuántos jugadores, personal y equipos han viajado.
-- -----------------------------------------------------------------------------

select a.nombre                                                   as club,
       count(*) filter (where d.col = 'players')                   as jugadores,
       count(*) filter (where d.col = 'staff')                     as personal,
       count(*) filter (where d.col = 'teams')                     as equipos,
       count(*) filter (where d.col = '_todo')                     as otras_listas,
       (select count(*) from members m where m.academy_id = a.id)  as personas
  from academies a
  left join academy_docs d on d.academy_id = a.id
 group by a.id, a.nombre;
