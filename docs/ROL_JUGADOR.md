# Rol **Jugador** — especificación funcional y técnica

> **Cómo leer este documento.** Igual que `ROL_FAMILIA.md`: cada bloque en cristiano para que lo valides tú, y debajo la parte técnica para quien programe. Este documento **depende** del de Familia; léelos juntos.

**Proyecto:** ScoutFlow Academy · **Rol:** `jugador` · **Versión:** 2026-08-02
**Relacionado:** `docs/ROL_FAMILIA.md` · `database/auth_schema.sql`

---

## 0. Resumen en una página

El jugador es el **centro del producto** pero el **último en tener cuenta**. Durante toda la fase actual la app funciona sin que ningún jugador entre: sus datos los gestiona el staff y los ve su familia.

Cuando entra, lo hace de una de dos formas radicalmente distintas, y **la app decide sola cuál** a partir de su fecha de nacimiento:

| | **Menor de 18** | **Mayor de 18** |
|---|---|---|
| Qué ve | Calendario, convocatorias y mensajes. Poco más | Todo lo suyo: pagos, documentación, informes, autorizaciones |
| Equivale a | Una versión reducida y protegida | El rol Familia, pero sobre sí mismo |
| Sus tutores | Ven todo y reciben copia de sus mensajes | Solo si él lo confirma |
| Quién firma | Los tutores | Él |

Tres ideas gobiernan el diseño:

1. **La edad no se guarda, se calcula.** Nadie marca una casilla de "es mayor". Sale de `birth_date` y cambia sola el día del cumpleaños.
2. **Ningún adulto del club habla a solas con un menor.** Todo mensaje a un menor llega también a sus tutores. Sin excepciones ni configuración que lo desactive.
3. **Al menor no se le enseña su expediente.** No por ocultismo: porque leer "poca competitividad" o "situación económica familiar" a solas en el móvil a los quince años no ayuda a nadie.

---

## 1. Tres edades, no dos

Tú planteaste el corte en los 18. Hay que meter uno más, porque en España existe y afecta.

| Tramo | Qué significa |
|---|---|
| **Hasta 13** | No puede consentir sobre sus datos: firman los tutores. Tiene cuenta solo si el club activa las de su equipo |
| **14 a 17** | Puede consentir sobre el tratamiento de sus datos, pero sigue siendo menor a efectos de protección: sus tutores ven todo y reciben copia de sus mensajes |
| **18 en adelante** | Titular pleno de sus datos. Sus padres pierden el acceso salvo que él lo mantenga |

El corte de los 14 sale de la LOPDGDD. En CBJA vas a tener los tres tramos conviviendo el mismo día, así que el sistema tiene que resolverlo solo.

> **Decisión (2026-08-02):** las cuentas de jugador **las activa el club por equipo o categoría**. No hay edad mínima fija en el producto: la dirección decide en qué equipos existen. Así un club puede darlas solo en cadete y junior, y otro en todos.

**Consecuencia que hay que asumir:** si un club activa las cuentas en minis, estará dando acceso a la app a niños de nueve años. El producto lo permite, pero la pantalla de configuración debe **avisarlo explícitamente** al activarlo, y las reglas de mensajería del punto 5 aplican igual y sin excepción.

---

## 2. Cómo se activa la cuenta

### En cristiano

1. La dirección activa las cuentas de jugador **para un equipo** desde Configuración.
2. A partir de ahí, administración puede invitar a los jugadores de ese equipo. Mismo sistema que las familias: correo con enlace de un solo uso, sin contraseñas.
3. Para un menor, la invitación **se envía a sus tutores**, no directamente al menor. Son ellos quienes deciden si su hijo tiene cuenta y quienes le pasan el acceso.
4. Un jugador sin correo propio, sencillamente, no tiene cuenta. No pasa nada: su familia sí la tiene.

### Técnico

```sql
alter table teams add column if not exists player_accounts_enabled boolean default false;
```

| Paso | Tabla / función |
|---|---|
| Activar por equipo | `teams.player_accounts_enabled` |
| Invitar | `invitations` con `role='jugador'`, `player_id` |
| Aceptar | `app_accept_invitation()` → fila en `player_access` con `relation='Jugador'` |

> **Cuidado con `app_is_guardian`.** Hoy devuelve `true` para cualquier fila de `player_access`. Si el jugador se enlaza por esa misma tabla, **se convertiría en tutor de sí mismo** y heredaría permisos que no le tocan (por ejemplo, `finance_select`). Hay que corregirla:
>
> ```sql
> create or replace function app_is_guardian(pid uuid) returns boolean language sql stable as
> $$ select exists (select 1 from player_access pa
>      where pa.player_id = pid and pa.user_id = auth.uid()
>        and pa.relation in ('Padre','Madre','Tutor')) $$;
>
> create or replace function app_is_self(pid uuid) returns boolean language sql stable as
> $$ select exists (select 1 from player_access pa
>      where pa.player_id = pid and pa.user_id = auth.uid()
>        and pa.relation = 'Jugador') $$;
> ```

---

## 3. La edad se calcula, no se guarda

### En cristiano

Nadie marca "este es mayor de edad". La app lo sabe por su fecha de nacimiento y **cambia sola** el día que cumple 18, sin que nadie haga nada.

Guardar un `es_mayor = true` sería un error clásico: alguien tendría que acordarse de actualizarlo, y con mil jugadores no se acuerda nadie.

### Técnico

```sql
create or replace function app_player_age(pid uuid) returns int language sql stable as
$$ select extract(year from age(current_date,
     (select birth_date from players where id = pid)))::int $$;

create or replace function app_player_is_adult(pid uuid) returns boolean language sql stable as
$$ select coalesce(app_player_age(pid) >= 18, false) $$;
```

Las políticas RLS se ramifican sobre `app_player_is_adult()`. Nada que mantener a mano.

> Si `birth_date` está vacío, la función devuelve `false`: **se trata como menor**. Ante la duda, la opción protectora.

---

## 4. Qué ve cada uno

### 4.1 Jugador **menor**

**En cristiano.** Una app corta y útil, no un expediente. Ve lo que necesita para ir a entrenar y jugar:

```
┌─────────────────────────────┐
│  ScoutFlow                  │
├─────────────────────────────┤
│  Su foto · nombre · dorsal  │
│  Su equipo                   │
├─────────────────────────────┤
│  Próximas citas             │
│  Convocatorias              │
│  Mensajes del equipo        │
│  Mensajes para mí           │
└─────────────────────────────┘
```

**Y ya está.** No ve pagos, ni documentación, ni informes, ni su valoración, ni sus medidas físicas, ni por supuesto nada de otros jugadores.

**Por qué no ve su ficha completa.** Tenías razón en que no es relevante, pero el motivo de fondo es otro: un chaval de quince años leyendo a solas en el móvil que su Scout Score es 58, que su entrenador anotó "le falta carácter" o que en notas internas figura la situación económica de su casa, es un daño gratuito. Esa información existe para que el club trabaje, no para que el jugador la consuma sin contexto.

Los informes van a los tutores, que deciden cómo y cuándo hablarlo con su hijo.

### 4.2 Jugador **mayor de edad**

**En cristiano.** Exactamente el portal de Familia, pero sobre sí mismo. Ve y gestiona:

- Sus pagos y cómo pagarlos, y se descarga sus recibos
- Su checklist de documentación: qué ha entregado y qué le falta
- Su revisión médica y su apto
- Los informes que el club publique sobre él
- Sus autorizaciones, que ahora **firma él**: imagen, datos, comunicaciones
- Sus datos bancarios
- Su equipación
- Calendario, convocatorias y mensajes

Es el mismo código del portal Family, cambiando quién es el titular. No hay que construir dos veces.

**Lo que sigue sin ver, tenga la edad que tenga:** notas internas, presupuesto, Scout Score y evaluaciones técnicas del cuerpo técnico.

> **Tensión legal que conviene conocer.** Bajo el RGPD, un mayor de edad tiene **derecho de acceso** a los datos personales que el club guarda sobre él, y eso incluye evaluaciones y valoraciones internas. Que no aparezcan en la app es una decisión de producto legítima; que el club se niegue a facilitarlas ante una solicitud formal, no lo es.
>
> Traducción práctica: mantenlas fuera de la interfaz, pero ten un procedimiento para responder a quien las pida por escrito. Y díselo a los entrenadores: **lo que escriben puede acabar leyéndolo el jugador.** Suele mejorar la calidad de lo que se escribe.

---

## 5. Avisos: sacar al club de WhatsApp

> **Decisión (2026-08-02): esto NO es un chat.** Es un **tablón de avisos en un solo sentido**. El club informa: entrenamientos, horarios, partidos, convocatorias. Los jugadores no escriben, no se ven entre sí y no existe ninguna conversación entre ellos.

Esta es la parte importante del documento.

### En cristiano

Hoy los entrenadores avisan por WhatsApp. Eso significa: el club no tiene registro de nada, los números de teléfono de menores circulan entre adultos, y si un día hay un problema, no hay forma de reconstruir qué se dijo.

La app lo sustituye con cuatro reglas:

**1 · Va en un solo sentido.** El cuerpo técnico envía; el jugador y su familia reciben. No hay hilos, no hay grupo, no hay conversación. Quien necesite hablar, que llame o quede: la app registra avisos, no charlas.

**2 · Nadie ve a nadie.** Un jugador no ve a los demás destinatarios de un aviso, ni sus nombres, ni si lo han leído. Recibe su mensaje y punto. Ni copia oculta ni lista de destinatarios: cada uno recibe lo suyo por separado.

**3 · Ningún adulto del club avisa a solas a un menor.** Un aviso dirigido a un jugador menor llega **siempre** también a sus tutores. No es configurable, no se puede desactivar, y el entrenador lo ve al escribir: *"Este aviso también lo recibirán sus tutores"*.

Esto protege al menor y **protege al entrenador**, que es la mitad que nadie menciona. Un técnico que solo se comunica por un canal registrado y con los padres en copia no puede ser acusado de nada.

**4 · Nada se borra y todo queda en el club.** Un aviso se puede retirar, pero permanece en el registro con su autor y su hora. Si un entrenador se marcha, su historial sigue ahí: lo tiene el club, no un móvil particular.

### A quién se envía

El entrenador elige el destinatario al escribir. Tres formas, y el detalle completo irá en `ROL_ENTRENADOR.md`:

| Envío | Uso típico |
|---|---|
| **A todo el equipo** | "El sábado el partido se adelanta a las 10:00" |
| **A los que marque** | Una convocatoria: solo los doce citados |
| **A uno solo** | "Mañana no hace falta que traigas la equipación de juego" |

En los tres casos, cada destinatario recibe **su** aviso. Aunque el entrenador lo mande a doce, se generan doce envíos independientes. Nadie sabe a quién más ha ido.

### Lo que desaparece

Esto **cambia el "muro del equipo"** que existe hoy en la app. Un muro es un espacio compartido donde todos leen lo mismo y ven quién ha escrito. Pasa a ser un **tablón de avisos**: lista de mensajes recibidos, en solo lectura, sin autoría visible más allá de "el club" o el nombre del entrenador, y sin nada de otros destinatarios.

También desaparecen del diseño anterior: las respuestas, los hilos, el `parent_id` y la mensajería entre jugador y técnico.

### Lo único que vuelve hacia atrás

> **Decisión (2026-08-02): aprobadas.** Son las dos únicas cosas que van del destinatario al club. Respuestas **cerradas**, sin texto libre. No son un chat.

Un aviso sin retorno deja al entrenador a ciegas, y es justo lo que le devuelve a WhatsApp para preguntar "¿lo habéis visto?".

**1 · Visto o no visto.** Cuando alguien abre el aviso, queda marcado. El entrenador ve la lista: quién lo ha visto y quién no. Le sirve para saber a quién llamar por teléfono cuando el cambio de horario es urgente.

**2 · Confirmación de asistencia.** Si el aviso lo pide, aparecen dos botones: **Iré** / **No puedo**. El entrenador ve la lista de confirmados. Para una convocatoria, esto ahorra treinta mensajes.

#### Dos detalles que hay que resolver bien

**Con un menor, ¿quién cuenta como "visto"?** Un aviso a un jugador de doce años llega a él y a sus dos padres. Si lo abre la madre y el chaval no, ¿está visto?

La respuesta correcta es **mostrarlo por separado**, no fusionarlo en un solo indicador:

```
Convocatoria sábado 10:00 — Cadete Masculino A

Martín Ríos          jugador ✓ visto     tutores ✓ visto      Iré
Diego Romero         jugador — sin ver   tutores ✓ visto      Iré
Sofía Méndez         jugador ✓ visto     tutores — sin ver    No puedo
Lucas García         jugador — sin ver   tutores — sin ver    sin responder
```

Así el entrenador sabe exactamente a quién llamar. Un "visto" agregado escondería que el jugador no se ha enterado.

**¿Quién confirma la asistencia?** Cualquiera de los dos: el jugador o un tutor. Pero **queda registrado quién lo hizo**, porque no es lo mismo que lo confirme el chaval de quince que su padre. La última respuesta manda, y el histórico se conserva.

Para los menores de 14 tiene más sentido que confirme el tutor —es quien lo lleva al partido—, pero no lo bloqueo por edad: sería una regla más que mantener a cambio de poco.

#### Lo que sigue sin existir

Ni texto libre, ni "gracias", ni emojis, ni adjuntos de vuelta. Dos botones y nada más. En cuanto se abre un hueco para escribir, aparece el primer hilo de conversación y a los quince días tienes un WhatsApp dentro de tu app, con la diferencia de que ahora eres tú quien responde de él.

### La advertencia honesta

Esto solo funciona si la app es **más rápida que WhatsApp**. Si un entrenador tiene que abrir el navegador, esperar y buscar el equipo para avisar de que el partido se retrasa media hora, va a coger el móvil y escribir al grupo. Siempre.

Dos cosas hacen falta y ninguna es opcional:

- **Notificaciones push que lleguen de verdad**, con el problema de iPhone que ya conoces. Sin esto, nadie confía en que el mensaje se ha leído y todos vuelven a WhatsApp.
- **Una norma del club**, escrita y firmada por los técnicos: la comunicación oficial va por la app. La tecnología sola no cambia una costumbre.

### Técnico

El modelo tiene **dos tablas**: el aviso que se escribe una vez, y un envío por cada destinatario. Esa separación es lo que garantiza que nadie vea a nadie.

```sql
-- El aviso, escrito una sola vez
create table if not exists announcements (
  id           uuid primary key default gen_random_uuid(),
  academy_id   uuid not null references academies(id) on delete cascade,
  team_id      uuid references teams(id) on delete set null,
  author_id    uuid not null references users_profile(id),
  kind         text not null default 'aviso',  -- aviso | convocatoria | horario | partido
  title        text not null,
  body         text not null,
  needs_rsvp   boolean default false,          -- pide confirmar asistencia
  event_id     uuid references team_events(id) on delete set null,
  created_at   timestamptz default now(),
  retracted_at timestamptz,                    -- retirado, NUNCA borrado
  retracted_by uuid references users_profile(id)
);

-- Un envío por destinatario. Aquí vive TODO lo que ve cada uno.
create table if not exists announcement_targets (
  announcement_id uuid not null references announcements(id) on delete cascade,
  user_id         uuid not null references users_profile(id) on delete cascade,
  player_id       uuid references players(id) on delete cascade,  -- a qué jugador se refiere
  as_role         text not null,          -- jugador | tutor
  read_at         timestamptz,
  rsvp            text,                   -- ire | no_puedo | null
  rsvp_at         timestamptz,
  rsvp_by         uuid references users_profile(id),  -- quién confirmó: el jugador o un tutor
  primary key (announcement_id, user_id, player_id)
);
create index on announcement_targets (user_id, read_at);
create index on announcement_targets (announcement_id, player_id);

-- Solo se pueden tocar estas cuatro columnas. Sin esto, la política de
-- update dejaría a un usuario cambiarse el player_id o el as_role.
revoke update on announcement_targets from authenticated;
grant  update (read_at, rsvp, rsvp_at, rsvp_by) on announcement_targets to authenticated;
```

**Por qué dos tablas.** Con una sola, la fila del aviso tendría que llevar la lista de destinatarios, y cualquier consulta que la leyera revelaría a quién más se envió. Con `announcement_targets`, cada usuario **solo puede leer su propia fila**: no existe consulta legítima que le devuelva las de otros.

> **Por qué la clave primaria incluye `player_id`.** Un padre con **dos hijos en el mismo equipo** recibe un aviso de equipo dos veces, una por cada hijo — y tiene que poder confirmar la asistencia de cada uno por separado. Con la clave en `(announcement_id, user_id)` solo se guardaría una fila y el segundo hijo desaparecería del reparto. Es un caso que en un club pasa el primer mes.

**La política que lo garantiza:**

```sql
alter table announcement_targets enable row level security;

create policy at_select_own on announcement_targets for select
  using ( user_id = auth.uid() );          -- solo lo tuyo, nunca lo de otro

create policy at_select_staff on announcement_targets for select
  using ( app_is_staff() and app_can_see_player(player_id) );

create policy at_rsvp on announcement_targets for update
  using ( user_id = auth.uid() )
  with check ( user_id = auth.uid() );     -- solo puede tocar read_at y rsvp
```

**Regla de protección del menor, blindada en la base de datos y no en la app:**

```sql
-- Al crear los envíos de un aviso dirigido a un jugador MENOR,
-- se generan también los envíos a todos sus tutores. Siempre.
create or replace function app_fanout_guardians() returns trigger language plpgsql as $$
begin
  if new.player_id is not null
     and new.as_role = 'jugador'
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

create trigger announcement_guardian_fanout
  after insert on announcement_targets
  for each row execute function app_fanout_guardians();
```

Aunque alguien llame a la API saltándose la interfaz, el aviso a un menor acaba en el buzón de sus tutores. La protección no depende de que la pantalla esté bien programada.

**Prohibir el borrado de verdad:**

```sql
revoke delete on announcements, announcement_targets from authenticated;
```

Retirar un aviso es un `update` de `retracted_at`, y solo lo puede hacer el autor o la dirección.

**Lo que ve cada uno del aviso en sí:**

| Quién | Ve |
|---|---|
| Jugador o tutor | El aviso al que tiene fila en `announcement_targets`. **Nunca** la lista de destinatarios |
| Cuerpo técnico | Sus avisos y los de sus equipos, con el recuento de leídos y las confirmaciones |
| Dirección | Todo el club |

### Reparto de avisos

Cada fila de `announcement_targets` genera **su** notificación. Un aviso a un menor produce como mínimo tres: la suya, la de su padre y la de su madre.

```sql
create table if not exists notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references users_profile(id) on delete cascade,
  player_id    uuid references players(id) on delete cascade,
  source       text not null,      -- aviso | pago | documento | medico | calendario
  source_id    uuid,
  read_at      timestamptz,
  created_at   timestamptz default now()
);
```

El disparo se hace con un *trigger* sobre `announcement_targets`. Así el aviso sale igual venga de la app del entrenador, del portal o de un proceso automático.

Y el push que sale al móvil dice **siempre "Notificación del club"**, con el identificador dentro y nada más — la regla ya fijada en `ROL_FAMILIA.md`.

---

## 6. El cumpleaños de los 18

> **Decisión (2026-08-02):** al cumplir 18, el acceso de los tutores **continúa solo si el jugador lo confirma**.

### Qué pasa exactamente

**Un mes antes.** Aviso al jugador y a sus tutores: *"El 14 de marzo cumples 18. A partir de esa fecha decides tú quién puede ver tus datos."*

**El día del cumpleaños.** Su perfil pasa automáticamente al modo adulto: gana acceso a pagos, documentación, informes y autorizaciones sobre sí mismo. El acceso de los tutores queda **en suspenso**, no retirado: siguen viendo lo que ya veían durante 30 días de cortesía, pero con un aviso visible de que caduca.

**Al entrar por primera vez como adulto**, se le pregunta una sola cosa:

```
Ya eres mayor de edad. Tus datos son tuyos.

¿Quieres que [nombre del tutor] siga teniendo acceso
a tu ficha, tus pagos y tus documentos?

  ( ) Sí, mantener el acceso
  ( ) Sí, pero solo a los pagos
  ( ) No, retirar el acceso
```

**A los 30 días sin respuesta**, el acceso de los tutores se retira. El silencio no vale como sí.

**Quien paga.** Es el conflicto práctico: los padres siguen pagando la cuota de un chaval de 18 y ya no ven las facturas. Por eso está la opción intermedia — mantener solo la parte de finanzas — que se implementa con el `can_pay` que ya existe en `player_access`, dejando la fila viva pero con acceso limitado a `finance` y `family_billing`.

**Las autorizaciones caducan.** Las que firmaron los tutores dejan de valer: el titular ha cambiado. Hay que volver a preguntarle a él, en particular la de imagen. Técnicamente: las filas de `consents` firmadas por un tutor se marcan caducadas al cumplir 18 y se piden de nuevo.

### Técnico

Todo esto lo dispara un proceso diario, no un *trigger*: hay que actuar en fechas, no en cambios de fila.

```sql
create table if not exists majority_transitions (
  player_id     uuid primary key references players(id) on delete cascade,
  turns_18_on   date not null,
  notified_at   timestamptz,
  decided_at    timestamptz,
  decision      text,        -- mantener | solo_pagos | retirar
  grace_ends_on date
);
```

Una tarea programada diaria: avisar a los que cumplen en 30 días, cambiar de modo a los que cumplen hoy, y retirar accesos a los que agotaron la cortesía sin decidir.

---

## 7. Lo que ningún jugador ve

| No ve | Menor | Mayor |
|---|---|---|
| Notas internas y presupuesto | ❌ | ❌ |
| Scout Score | ❌ | ❌ en la app (ver 4.2 sobre derecho de acceso) |
| Evaluaciones técnicas del cuerpo técnico | ❌ | ❌ en la app |
| Datos de cualquier otro jugador | ❌ | ❌ |
| **A los demás jugadores de su equipo** — nombres, fotos, dorsales | ❌ | ❌ |
| **A quién más se ha enviado un aviso** | ❌ | ❌ |
| Avisos dirigidos solo a su familia | ❌ | ❌ |
| Sus pagos y documentación | ❌ | ✅ |
| Informes publicados | ❌ | ✅ |
| Sus medidas físicas | ❌ | ✅ (son suyas) |

---

## 8. Qué falta hoy

Todo. En la app actual el rol Jugador está marcado como "futuro/opcional" y no existe ninguna pantalla.

| Pieza | Estado |
|---|---|
| Rol `jugador` en el modelo | ❌ |
| Interruptor por equipo | ❌ |
| Funciones de edad | ❌ |
| `app_is_guardian` corregida | ❌ — **y hoy es un fallo latente** |
| `announcements` + `announcement_targets` + trigger de copia a tutores | ❌ |
| Convertir el **muro del equipo** actual en tablón de avisos | ❌ — hay que quitar lo compartido |
| `notifications` y reparto | ❌ |
| Portal del jugador menor | ❌ |
| Portal del jugador mayor (= reusar Family) | ❌ |
| Transición a los 18 | ❌ |

---

## 9. Orden de implementación

Va **después** de que Familia funcione. Sin familias dentro, las cuentas de jugador no sirven de nada.

1. **Corregir `app_is_guardian`** para que distinga tutor de jugador. Es un arreglo de cinco líneas que hay que hacer **antes** de crear ninguna cuenta de jugador, o el primero que entre será tutor de sí mismo.
2. **Funciones de edad** y el interruptor por equipo.
3. **`announcements` + `announcement_targets`**, con el reparto a tutores y el borrado prohibido. Es el corazón del rol y lo que sustituye a WhatsApp.
4. **Reparto de notificaciones** a jugador y tutores.
5. **Portal del jugador menor** — es corto, cuatro bloques.
6. **Portal del jugador mayor** — reutilizar el de Familia cambiando el titular.
7. **Transición de los 18**, con su tarea diaria.

---

## 10. Decisiones abiertas

1. **¿Qué pasa si un tutor no quiere que su hijo tenga cuenta** aunque el club las haya activado para ese equipo? Hace falta poder bloquearlo por jugador.
2. **¿Los mayores de edad ven su Scout Score?** Hoy digo que no en la app. Merece una decisión consciente, no por omisión.
3. **¿La familia puede escribir texto libre a un aviso?** Con la regla de "no es un chat" y con los botones ya aprobados, diría que no. Confírmame que lo ves igual.

**Ya decidido (2026-08-02):**

- ✅ **No es un chat.** Tablón de avisos en un solo sentido: entrenamientos, horarios, partidos, convocatorias.
- ✅ **Los jugadores no se ven entre sí**, ni en listados ni como destinatarios de un aviso.
- ✅ El entrenador envía **a todos, a los que marque, o a uno solo**.
- ✅ Las cuentas de jugador **las activa el club por equipo**.
- ✅ Al cumplir 18, el acceso de los tutores **sigue solo si el jugador lo confirma**.
- ✅ El jugador menor **no ve los informes**: van a sus tutores.
- ✅ **Visto / no visto** y **Iré / No puedo**. Respuestas cerradas, sin texto libre.
- ✅ Con menores, el "visto" se muestra **separado**: jugador y tutores por su lado.

---

_Documento vivo. Depende de `ROL_FAMILIA.md`. Siguiente rol a especificar: Entrenador._
