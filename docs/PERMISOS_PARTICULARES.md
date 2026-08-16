# Permisos: por defecto, y las excepciones

**Fecha:** 2026-08-16 · **Estado:** funcionando en la app (pantalla *Permisos*)

---

## 1. El problema

Hasta ahora los permisos eran solo el rol: eras entrenador y veías lo que ve un entrenador. Punto.

Pero la realidad del club no es tan limpia:

- Carlos es entrenador **y además lleva la caja de su equipo**. Necesita ver finanzas. No es administrativo.
- El scout que prepara la incorporación de Pablo necesita **reclamar documentos**. No es administración.
- La psicóloga necesita el Scout Score **este año**, porque está haciendo un trabajo concreto.

Dos salidas malas:

| Salida mala | Por qué es mala |
|---|---|
| Darle a Carlos el rol de administrativo | Le das *todo* lo de administración. Ve las finanzas de todos los jugadores del club, no las de su equipo |
| Añadir finanzas al rol "entrenador" | Se lo das a **todos** los entrenadores para siempre |

La salida buena: **el rol sigue siendo el valor por defecto, y encima se conceden excepciones concretas.**

---

## 2. Los cuatro candados

Un sistema de excepciones sin frenos acaba, a los dos años, en que todo el mundo lo ve todo y nadie sabe por qué. Estos cuatro candados están para que eso no pase. No son opcionales: están metidos en el código.

### Candado 1 · Solo suma, nunca resta

Los permisos efectivos son **los del rol MÁS las excepciones**. No existe "el rol menos algo".

Si a alguien le sobra un permiso, **el rol está mal definido** y hay que arreglar el rol. Poner un parche para quitar sería empezar a tener dos sistemas contradictorios, y llegaría el día en que nadie sabría cuál manda.

### Candado 2 · Caduca siempre

Toda excepción lleva fecha de fin. Por defecto, el final de la temporada.

Es el candado más importante de los cuatro, y el más aburrido. Es lo único que impide que la lista crezca para siempre. **Un permiso caducado deja de aplicar solo**, sin que nadie tenga que acordarse de quitarlo — que es exactamente de lo que nadie se acuerda.

En la pantalla, lo que caduca en menos de 30 días sale marcado en naranja.

### Candado 3 · Motivo obligatorio

Una frase. "Lleva la caja de su equipo".

No es burocracia: es para que dentro de año y medio, cuando alguien revise la lista, pueda decidir si eso sigue teniendo sentido. Sin el motivo, la única opción realista es dejarlo como está por si acaso.

### Candado 4 · Hay dos que no se delegan nunca

| No delegable | Por qué |
|---|---|
| **Ver notas internas** | Incluye el presupuesto y la situación económica de la familia. Eso se decide en el organigrama, no con una excepción |
| **Gestionar permisos** | Quien lo recibiera podría dárselo todo a sí mismo. Un sistema de permisos que se puede regalar no es un sistema de permisos |

Están bloqueados en el código (`SF.PERM_NUNCA`), no solo escondidos de la pantalla.

---

## 3. Qué se puede conceder

| Permiso | Efecto |
|---|---|
| Ver finanzas de sus jugadores | Ve el estado de pago |
| Gestionar cobros y planes de pago | Abre la sección Finanzas |
| Ver el Scout Score | Ve la valoración interna |
| Evaluar jugadores | Puede cargar evaluaciones |
| Tomar y editar medidas físicas | Altura, peso, envergadura |
| Crear y gestionar equipos | Plantillas y convocatorias |
| Gestionar documentación y enviar recordatorios | Abre Documentos y puede reclamar |
| Enviar comunicados del club | Abre Comunicados |
| Importar datos de partido | Abre Importar datos |
| Ver el listado de staff | Abre Staff |

---

## 4. Cómo funciona por dentro

Todos los permisos de la app pasan por una sola función, `role()`. Ahí es donde se juntan el rol y las excepciones:

```js
function role() {
  var base  = SF.ROLES[SF.store.role()];   // lo que da el rol
  var extra = SF.store.userPermsActive(me.id);  // las excepciones VIGENTES
  // ... merged[permiso] = true  →  es un OR, nunca resta
}
```

Que sea un único punto de paso importa: significa que **la delegación funciona en todas las pantallas a la vez**, sin haber tocado ninguna. Si mañana se añade una pantalla nueva y usa `role()`, hereda esto solo.

`userPermsActive()` filtra por fecha, así que la caducidad no depende de que nadie haga nada.

**Datos que se guardan de cada excepción:** a quién · qué permiso · motivo · hasta cuándo · quién lo concedió · cuándo · si se retiró y cuándo. Retirar **no borra**: marca. El registro de quién tuvo acceso a qué se conserva.

---

## 5. Las tres cosas que se ven en pantalla

En **Permisos** (solo el director puede conceder):

1. **Por defecto, según el rol** — la matriz de siempre.
2. **Permisos particulares** — quién tiene qué, por qué, hasta cuándo, y quién se lo dio. Con botón de retirar.
3. **¿Quién puede hacer cada cosa?** — la misma información **al revés**.

El tercero es el que de verdad se va a usar. "¿Quién puede ver las finanzas?" es la pregunta que hace un auditor, o un padre que pregunta quién tiene acceso a sus datos. Con la matriz por roles sola, **esa pregunta no se puede responder** sin repasar la lista entera a mano.

Y en la **ficha de cada persona** salen sus propios permisos extra: nadie debería tener un permiso sin saber que lo tiene ni hasta cuándo.

---

## 6. Cuando llegue Supabase

Esto vive hoy en el navegador. En la base de datos será una tabla, y lo importante es que **la comprobación tiene que estar en el servidor, no en la app**:

```sql
create table user_permissions (
  id uuid primary key default gen_random_uuid(),
  academy_id uuid references academies(id),
  staff_id   uuid references users_profile(id) not null,
  perm       text not null,
  reason     text not null,               -- candado 3
  until      date not null,               -- candado 2
  granted_by uuid references users_profile(id) not null,
  granted_at timestamptz default now(),
  revoked_at timestamptz,
  constraint no_delegables check (perm not in ('canSeeNotes','canManagePermissions'))
);
```

El `check` es el candado 4 puesto donde no se puede saltar: aunque alguien llame a la API directamente, la base de datos lo rechaza.

Y una función que las políticas RLS puedan usar:

```sql
create or replace function has_perm(p text) returns boolean as $$
  select exists (
    select 1 from user_permissions
    where staff_id = auth.uid() and perm = p
      and revoked_at is null and until >= current_date
  );
$$ language sql stable security definer;
```

> **Ojo con esto:** hoy la app esconde botones. Eso está bien para que la pantalla sea clara, pero **no es seguridad**: cualquiera con conocimientos puede saltárselo desde el navegador. La seguridad de verdad empieza el día que RLS compruebe esto en el servidor. Hasta entonces, la app es una demo con buenas costumbres.

---

## 7. Pendiente

- Aviso a la dirección cuando queden 15 días para que caduque un permiso
- Revisión de junio: listar todo lo vigente al acabar la temporada y obligar a renovar o dejar caducar
- Que las excepciones queden también en el historial de la ficha de la persona (hoy se ven, pero no como evento fechado)
- **Lo importante:** llevar los cuatro candados a RLS cuando exista Supabase

---

_Documento vivo._
