# Pruebas del esquema v3 (`database/schema_v3.sql`)

Comprueban que el esquema de destino corre limpio en PostgreSQL y que sus reglas de acceso
(RLS) hacen lo que dicen. No tocan el Supabase real: se usan en un Postgres de pruebas.

```bash
createdb v3
psql -v ON_ERROR_STOP=1 -d v3 -f tests/esquema/auth_simulado.sql   # lo que Supabase ya trae
psql -v ON_ERROR_STOP=1 -d v3 -f database/schema_v3.sql            # 1.ª pasada
psql -v ON_ERROR_STOP=1 -d v3 -f database/schema_v3.sql            # 2.ª pasada: no debe romper nada
psql -v ON_ERROR_STOP=1 -d v3 -f tests/esquema/pruebas_rls.sql     # reglas de acceso
```

La última línea debe decir «todas las comprobaciones pasan». Si una regla falla, psql se para
en ella y dice cuál (por ejemplo, «el entrenador ve notas internas y Scout Score»).

Qué se comprueba, con dos clubes y cuatro personas:

- Nadie ve nada de otro club, ni puede crear filas en él.
- El entrenador ve a los jugadores de su club, pero no las notas internas ni el Scout Score, no
  puede escribirlas y no puede borrar jugadores.
- La familia ve solo a su hijo y solo los informes publicados; un informe no se puede marcar como
  publicado sin decir quién lo publica.
- Sin sesión no se ve nada.

Probado el 25/09/2026 en PostgreSQL 16.13: 91 tablas, las 91 con RLS, 219 claves foráneas.
