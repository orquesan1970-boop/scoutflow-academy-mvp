-- ============================================================================
-- ScoutFlow Academy — PRUEBAS DE SEGURIDAD (RLS)
-- ----------------------------------------------------------------------------
-- Ruta en el repo:  database/pruebas_rls.sql
-- Versión: 2026-08-02
--
-- QUÉ ES ESTO
--   No comprueba que el SQL "corra". Comprueba lo único que importa:
--   que un padre NO pueda ver al hijo de otro, que un jugador NO sea staff,
--   y que nadie pueda ascenderse a director.
--
--   Cada prueba corresponde a un fallo real encontrado el 2026-08-02.
--   Si alguna falla, el script se PARA con el motivo.
--
-- CÓMO SE EJECUTA
--   1. Aplica primero schema.sql y SUPABASE_auth_v2.sql
--   2. Pega este archivo entero en el editor SQL de Supabase y ejecútalo
--   3. Debe terminar con:  === TODAS LAS PRUEBAS PASAN ===
--
--   Todo ocurre dentro de una transacción que se DESHACE al final:
--   no deja ni un dato de prueba en tu base.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Utilidad: ponerse en la piel de un usuario (como hace Supabase con el JWT)
-- ---------------------------------------------------------------------------
create or replace function t_login(u uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims',
                     json_build_object('sub', u, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create or replace function t_admin() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', '', true);
end $$;

create or replace function t_ok(cond boolean, msg text) returns void language plpgsql as $$
begin
  if cond then raise notice '  OK   %', msg;
  else raise exception 'FALLA: %', msg; end if;
end $$;


-- ###########################################################################
-- DATOS DE PRUEBA
--   Academia con 2 equipos.
--   - Martín (menor, 2012) y Sara (menor, 2014): HERMANOS, mismo equipo.
--   - Diego (mayor, 2006): otro jugador del mismo equipo.
--   - Ana (menor, 2013): equipo distinto, familia distinta.
--   Padres: Pedro (padre de Martín y Sara), Lucía (madre de Ana).
--   Staff: Carlos (entrenador del equipo A), Marta (administrativa).
-- ###########################################################################

select t_admin();

do $$
declare
  ac uuid := gen_random_uuid();
  eqA uuid := gen_random_uuid();  eqB uuid := gen_random_uuid();
  jMartin uuid := gen_random_uuid(); jSara uuid := gen_random_uuid();
  jDiego  uuid := gen_random_uuid(); jAna  uuid := gen_random_uuid();
  uPedro  uuid := gen_random_uuid(); uLucia uuid := gen_random_uuid();
  uCarlos uuid := gen_random_uuid(); uMarta uuid := gen_random_uuid();
  uDiego  uuid := gen_random_uuid(); uMartin uuid := gen_random_uuid();
begin
  insert into academies (id, name) values (ac, 'CBJA Test');

  insert into teams (id, academy_id, name) values
    (eqA, ac, 'Cadete A'), (eqB, ac, 'Infantil B');

  insert into players (id, academy_id, full_name, birth_date, team_id) values
    (jMartin, ac, 'Martin Test', '2012-03-01', eqA),
    (jSara,   ac, 'Sara Test',   '2014-05-10', eqA),
    (jDiego,  ac, 'Diego Test',  '2006-01-20', eqA),
    (jAna,    ac, 'Ana Test',    '2013-09-09', eqB);

  -- auth.users primero (users_profile depende de ella)
  insert into auth.users (id, email) values
    (uPedro,'pedro@test.com'), (uLucia,'lucia@test.com'),
    (uCarlos,'carlos@test.com'), (uMarta,'marta@test.com'),
    (uDiego,'diego@test.com'), (uMartin,'martin@test.com')
  on conflict do nothing;

  insert into users_profile (id, academy_id, full_name, email, role) values
    (uPedro,  ac, 'Pedro',  'pedro@test.com',  'padre'),
    (uLucia,  ac, 'Lucia',  'lucia@test.com',  'padre'),
    (uCarlos, ac, 'Carlos', 'carlos@test.com', 'entrenador'),
    (uMarta,  ac, 'Marta',  'marta@test.com',  'administrativo'),
    (uDiego,  ac, 'Diego',  'diego@test.com',  'jugador'),
    (uMartin, ac, 'Martin', 'martin@test.com', 'jugador')
  on conflict (id) do update set role = excluded.role, academy_id = excluded.academy_id;

  -- Alcance
  insert into player_access (user_id, player_id, relation) values
    (uPedro, jMartin, 'Padre'), (uPedro, jSara, 'Padre'),
    (uLucia, jAna, 'Madre'),
    (uDiego, jDiego, 'Jugador'), (uMartin, jMartin, 'Jugador');

  insert into team_coaches (user_id, team_id) values (uCarlos, eqA);

  insert into role_permissions (academy_id, role, can_see_finance, can_manage_finance,
                                can_see_notes, can_evaluate, can_manage_medical) values
    (ac,'entrenador',    false,false,false,true, false),
    (ac,'administrativo',true, true, false,false,true),
    (ac,'padre',         true, false,false,false,false),
    (ac,'jugador',       false,false,false,false,false)
  on conflict do nothing;

  insert into finance (player_id, concept, amount, status) values
    (jMartin,'Cuota octubre', 90, 'pendiente'),
    (jAna,   'Cuota octubre', 90, 'pendiente');

  insert into documents (player_id, type) values (jMartin,'dni'), (jAna,'dni');

  -- Guardar los ids para las pruebas
  create temp table t_ids as select ac academia, eqA equipoA, eqB equipoB,
    jMartin p_martin, jSara p_sara, jDiego p_diego, jAna p_ana,
    uPedro u_pedro, uLucia u_lucia, uCarlos u_carlos, uMarta u_marta,
    uDiego u_diego, uMartin u_martin;
end $$;


-- ###########################################################################
-- PRUEBAS
-- ###########################################################################

-- ---------------------------------------------------------------------------
-- T1 · LA PRUEBA QUE IMPORTA
--      Un padre NO puede ver al hijo de otra familia.
-- ---------------------------------------------------------------------------
do $$ declare n int; i record;
begin
  select * into i from t_ids;
  perform t_login(i.u_pedro);
  select count(*) into n from players where id = i.p_ana;
  perform t_ok(n = 0, 'T1 · Pedro NO ve a Ana (hija de otra familia)');

  select count(*) into n from players;
  perform t_ok(n = 2, 'T1b · Pedro ve exactamente a sus 2 hijos');

  select count(*) into n from finance where player_id = i.p_ana;
  perform t_ok(n = 0, 'T1c · Pedro NO ve las cuotas de Ana');
end $$;

-- ---------------------------------------------------------------------------
-- T2 · E0 — Un jugador NO es personal del club.
--      En v1, app_is_staff() = rol <> 'padre': todo jugador pasaba por staff.
-- ---------------------------------------------------------------------------
do $$ declare i record; b boolean;
begin
  select * into i from t_ids;
  perform t_login(i.u_diego);
  select app_is_staff() into b;
  perform t_ok(b = false, 'T2 · Un jugador NO es staff (E0)');
end $$;

-- ---------------------------------------------------------------------------
-- T3 · E1 — El jugador NO es tutor de sí mismo.
--      Si lo fuera, un menor vería sus cuotas y su deuda.
-- ---------------------------------------------------------------------------
do $$ declare i record; b boolean; n int;
begin
  select * into i from t_ids;
  perform t_login(i.u_martin);
  select app_is_guardian(i.p_martin) into b;
  perform t_ok(b = false, 'T3 · Martin NO es tutor de si mismo (E1)');

  select count(*) into n from finance where player_id = i.p_martin;
  perform t_ok(n = 0, 'T3b · Un jugador MENOR no ve sus finanzas');
end $$;

-- ---------------------------------------------------------------------------
-- T4 · E7 — ESCALADA DE PRIVILEGIOS.
--      En v1, cualquiera podía hacerse director de su propio club.
-- ---------------------------------------------------------------------------
do $$ declare i record; subio boolean := false;
begin
  select * into i from t_ids;
  perform t_login(i.u_pedro);
  begin
    update users_profile set role = 'director' where id = i.u_pedro;
    subio := true;   -- si llega aquí, el agujero sigue abierto
  exception when others then
    subio := false;  -- el trigger lo ha bloqueado: correcto
  end;
  perform t_ok(subio = false, 'T4 · Un padre NO puede ascenderse a director (E7)');
end $$;

-- ---------------------------------------------------------------------------
-- T5 · E3 — Una familia NO puede marcar sus documentos como entregados.
-- ---------------------------------------------------------------------------
do $$ declare i record; pudo boolean := false; n int;
begin
  select * into i from t_ids;
  perform t_login(i.u_pedro);
  update documents set delivered = true where player_id = i.p_martin;
  get diagnostics n = row_count;
  perform t_ok(n = 0, 'T5 · La familia NO marca documentos como entregados (E3)');

  select count(*) into n from documents where player_id = i.p_martin;
  perform t_ok(n = 1, 'T5b · Pero SI ve su checklist');
end $$;

-- ---------------------------------------------------------------------------
-- T6 · Un entrenador solo ve a los jugadores de SU equipo.
-- ---------------------------------------------------------------------------
do $$ declare i record; n int;
begin
  select * into i from t_ids;
  perform t_login(i.u_carlos);
  select count(*) into n from players where id = i.p_ana;
  perform t_ok(n = 0, 'T6 · Carlos NO ve a Ana (equipo distinto)');

  select count(*) into n from players;
  perform t_ok(n = 3, 'T6b · Carlos ve a los 3 de su equipo');

  select count(*) into n from finance;
  perform t_ok(n = 0, 'T6c · Un entrenador NO ve finanzas');
end $$;

-- ---------------------------------------------------------------------------
-- T7 · Un aviso a un MENOR llega SIEMPRE a sus tutores.
--      Se comprueba el trigger, no la pantalla.
-- ---------------------------------------------------------------------------
do $$ declare i record; av uuid; n int;
begin
  select * into i from t_ids;
  perform t_admin();

  insert into announcements (academy_id, team_id, author_id, title, body)
  values (i.academia, i.equipoA, i.u_carlos, 'Entrenamiento', 'Mañana a las 18:00')
  returning id into av;

  -- Se inserta SOLO el destino del jugador menor
  insert into announcement_targets (announcement_id, user_id, player_id, as_role)
  values (av, i.u_martin, i.p_martin, 'jugador');

  select count(*) into n from announcement_targets
   where announcement_id = av and user_id = i.u_pedro;
  perform t_ok(n = 1, 'T7 · El aviso a un menor se copia a su tutor (automatico)');
end $$;

-- ---------------------------------------------------------------------------
-- T8 · E6(mio) — Un padre con DOS hijos en el mismo equipo
--      recibe DOS filas, no una. Con la clave antigua se perdía un hijo.
-- ---------------------------------------------------------------------------
do $$ declare i record; av uuid; n int;
begin
  select * into i from t_ids;
  perform t_admin();

  insert into announcements (academy_id, team_id, author_id, title, body, needs_rsvp)
  values (i.academia, i.equipoA, i.u_carlos, 'Convocatoria', 'Sabado 10:00', true)
  returning id into av;

  insert into announcement_targets (announcement_id, user_id, player_id, as_role) values
    (av, i.u_pedro, i.p_martin, 'tutor'),
    (av, i.u_pedro, i.p_sara,   'tutor');

  select count(*) into n from announcement_targets
   where announcement_id = av and user_id = i.u_pedro;
  perform t_ok(n = 2, 'T8 · Padre con 2 hijos en el mismo equipo recibe 2 filas');
end $$;

-- ---------------------------------------------------------------------------
-- T9 · Nadie sabe a quién más se envió un aviso.
-- ---------------------------------------------------------------------------
do $$ declare i record; n int;
begin
  select * into i from t_ids;
  perform t_login(i.u_pedro);
  select count(*) into n from announcement_targets where user_id <> i.u_pedro;
  perform t_ok(n = 0, 'T9 · Pedro NO ve los destinos de otros usuarios');
end $$;

-- ---------------------------------------------------------------------------
-- T10 · Un jugador MAYOR de edad sí ve lo suyo.
-- ---------------------------------------------------------------------------
do $$ declare i record; n int; b boolean;
begin
  select * into i from t_ids;
  perform t_login(i.u_diego);
  select app_player_is_adult(i.p_diego) into b;
  perform t_ok(b = true, 'T10 · Diego (2006) se calcula como mayor de edad');

  select count(*) into n from players;
  perform t_ok(n = 1, 'T10b · Diego solo se ve a si mismo');

  select count(*) into n from players where id = i.p_martin;
  perform t_ok(n = 0, 'T10c · Diego NO ve a sus companeros de equipo');
end $$;

-- ---------------------------------------------------------------------------
-- T11 · Las notas internas no las ve nadie sin permiso.
-- ---------------------------------------------------------------------------
do $$ declare i record; n int;
begin
  select * into i from t_ids;
  perform t_admin();
  insert into player_private (player_id, notes_internal, scout_score, budget)
  values (i.p_martin, 'Situacion economica delicada', 62, 3000);

  perform t_login(i.u_pedro);
  select count(*) into n from player_private;
  perform t_ok(n = 0, 'T11 · La familia NO ve notas internas ni Scout Score');

  perform t_login(i.u_carlos);
  select count(*) into n from player_private;
  perform t_ok(n = 0, 'T11b · El entrenador tampoco (sin see_notes)');
end $$;


-- ###########################################################################
-- RESULTADO
-- ###########################################################################

select t_admin();
do $$ begin raise notice ' '; raise notice '=== TODAS LAS PRUEBAS PASAN ==='; end $$;

-- Nada de esto queda en tu base de datos.
rollback;
