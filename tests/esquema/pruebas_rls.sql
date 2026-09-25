-- =============================================================================
-- Pruebas de las reglas de acceso de database/schema_v3.sql (tarea F0-10).
-- Se ejecuta DESPUÉS de auth_simulado.sql y schema_v3.sql, en un Postgres de
-- pruebas. Cada comprobación que falla corta la ejecución con su motivo.
--   psql -v ON_ERROR_STOP=1 -f tests/esquema/pruebas_rls.sql
-- =============================================================================

-- Dos clubes, cuatro personas.
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-00000000000a', 'director@club-a.test'),
  ('00000000-0000-0000-0000-00000000000b', 'entrenador@club-a.test'),
  ('00000000-0000-0000-0000-00000000000c', 'familia@club-a.test'),
  ('00000000-0000-0000-0000-00000000000d', 'director@club-b.test')
on conflict do nothing;

insert into sf_v3.academies (id, name) values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'Club A de prueba'),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'Club B de prueba')
on conflict do nothing;

insert into sf_v3.members (user_id, academy_id, role) values
  ('00000000-0000-0000-0000-00000000000a', 'aaaaaaaa-0000-0000-0000-000000000001', 'director'),
  ('00000000-0000-0000-0000-00000000000b', 'aaaaaaaa-0000-0000-0000-000000000001', 'entrenador'),
  ('00000000-0000-0000-0000-00000000000c', 'aaaaaaaa-0000-0000-0000-000000000001', 'padre'),
  ('00000000-0000-0000-0000-00000000000d', 'bbbbbbbb-0000-0000-0000-000000000002', 'director')
on conflict do nothing;

insert into sf_v3.players (id, academy_id, ficha, first_name, last_name, birth_year) values
  ('11111111-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 1, 'Hijo', 'De Prueba', 2012),
  ('11111111-0000-0000-0000-000000000002', 'aaaaaaaa-0000-0000-0000-000000000001', 2, 'Otro', 'Jugador', 2012),
  ('22222222-0000-0000-0000-000000000001', 'bbbbbbbb-0000-0000-0000-000000000002', 1, 'Jugador', 'Club B', 2011)
on conflict do nothing;

insert into sf_v3.player_private (academy_id, player_id, notes_internal, scout_score) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'nota interna', 80)
on conflict do nothing;

insert into sf_v3.guardians (id, academy_id, full_name, user_id) values
  ('33333333-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Familia de prueba', '00000000-0000-0000-0000-00000000000c')
on conflict do nothing;
insert into sf_v3.player_guardians (academy_id, player_id, guardian_id, relation) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', '33333333-0000-0000-0000-000000000001', 'madre')
on conflict do nothing;

insert into sf_v3.reports (academy_id, player_id, kind, published, published_by) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000001', 'manual', false, null);

-- ---------- Director del club A ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000a', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.players) = 2, 'el director de A debería ver sus 2 jugadores';
  assert (select count(*) from sf_v3.players where academy_id = 'bbbbbbbb-0000-0000-0000-000000000002') = 0, 'el director de A ve jugadores del club B';
  assert (select count(*) from sf_v3.player_private) = 1, 'el director debería ver las notas internas';
end $$;
reset role;

-- ---------- Entrenador del club A ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000b', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.players) = 2, 'el entrenador debería ver los jugadores de su club';
  assert (select count(*) from sf_v3.player_private) = 0, 'el entrenador ve notas internas y Scout Score';
end $$;
do $$ begin
  begin
    insert into sf_v3.player_private (academy_id, player_id, notes_internal)
    values ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-0000-0000-0000-000000000002', 'intento');
    raise exception 'el entrenador ha podido escribir notas internas';
  exception when insufficient_privilege then null;
  end;
  begin
    delete from sf_v3.players where id = '11111111-0000-0000-0000-000000000002';
    assert not found, 'el entrenador ha podido borrar un jugador';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ---------- Familia del club A ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.players) = 1, 'la familia debería ver solo a su hijo';
  assert (select count(*) from sf_v3.players where id = '11111111-0000-0000-0000-000000000002') = 0, 'la familia ve a otro jugador';
  assert (select count(*) from sf_v3.reports) = 0, 'la familia ve un informe sin publicar';
  assert (select count(*) from sf_v3.player_private) = 0, 'la familia ve notas internas';
end $$;
reset role;

-- Un informe no se puede marcar como publicado sin decir quién lo publica.
do $$ begin
  begin
    update sf_v3.reports set published = true where player_id = '11111111-0000-0000-0000-000000000001';
    raise exception 'se ha podido publicar un informe sin decir quién';
  exception when check_violation then null;
  end;
end $$;
-- El director (con su ficha de staff) lo publica; ahora la familia sí lo ve.
insert into sf_v3.staff (id, academy_id, full_name, role) values
  ('44444444-0000-0000-0000-000000000001', 'aaaaaaaa-0000-0000-0000-000000000001', 'Dirección de prueba', 'director')
on conflict do nothing;
update sf_v3.reports set published = true, published_by = '44444444-0000-0000-0000-000000000001', published_at = now()
 where player_id = '11111111-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000c', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.reports) = 1, 'la familia debería ver el informe publicado de su hijo';
end $$;
reset role;

-- ---------- Director del club B ----------
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-00000000000d', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.players) = 1, 'el director de B debería ver solo su jugador';
  assert (select count(*) from sf_v3.player_private) = 0, 'el director de B ve notas del club A';
  begin
    insert into sf_v3.players (academy_id, ficha, first_name) values ('aaaaaaaa-0000-0000-0000-000000000001', 99, 'Colado');
    raise exception 'el director de B ha podido crear un jugador en el club A';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- ---------- Sin sesión ----------
select set_config('request.jwt.claim.sub', '', false);
set role authenticated;
do $$ begin
  assert (select count(*) from sf_v3.players) = 0, 'sin sesión se ven jugadores';
end $$;
reset role;

select 'Reglas de acceso del esquema v3: todas las comprobaciones pasan' as resultado;
