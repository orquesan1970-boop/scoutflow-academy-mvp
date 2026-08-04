# Rol **Familia** — especificación funcional y técnica

> **Cómo leer este documento.** Cada bloque tiene dos capas. La parte **"En cristiano"** la puedes validar tú: describe qué hace esa persona y si refleja cómo funciona tu club. La parte **"Técnico"** es para quien programe: dice qué tabla se toca, con qué permiso y qué política la protege. Si las dos capas no cuadran, manda la de arriba.

**Proyecto:** ScoutFlow Academy · **Rol:** `padre` (padre / madre / tutor legal) · **Versión:** 2026-08-02
**Base:** `database/auth_schema.sql` · `docs/AUTENTICACION_Y_PERMISOS.md` · portal actual en `js/pages.js`

---

## 0. Resumen en una página

La familia es el rol de **más volumen** del sistema: con 1.000 jugadores puede haber ~2.000 cuentas, porque padre y madre entran por separado. También es el **más sensible**: son datos de menores, con RGPD encima.

Su app es **una sola pantalla larga en el móvil**, sin menú lateral, sin buscador, sin tablas. Entra, ve a su hijo/a, y resuelve las tres cosas que el club necesita de ella: **subir documentos, pagar y responder**.

Regla que gobierna todo lo demás:

> La familia **solo** puede ver y tocar filas ligadas a un jugador con el que tenga una fila en `player_access`. No hay excepciones, y no se garantiza ocultando botones: lo impide la base de datos.

---

## 1. Quién es

| | |
|---|---|
| **Quién** | Padre, madre o tutor legal de un jugador del club |
| **Cuántos** | ~2 por jugador (padre y madre, cuentas separadas) |
| **Dispositivo** | Móvil, casi siempre. El diseño es *mobile-first*, no una web encogida |
| **Cuánto tiempo dedica** | Segundos. Entra porque le ha llegado un aviso, hace una cosa y se va |
| **Nivel técnico** | Cualquiera. Tiene que funcionar para quien no ha instalado una app en su vida |
| **Rol en BD** | `users_profile.role = 'padre'` |
| **Alcance** | Filas de `player_access` con su `user_id` |

**Consecuencia de diseño:** si una acción necesita más de dos toques o una explicación, está mal diseñada. La familia no va a leer instrucciones.

---

## 2. Cómo entra

### En cristiano

Nadie se registra por su cuenta. El club invita.

1. Administración (o el director) da de alta al jugador y escribe el correo del padre y el de la madre.
2. A cada uno le llega un correo con un **enlace de un solo uso**. No hay contraseña que inventar ni que olvidar.
3. Pincha el enlace, y ya está dentro, viendo a su hijo/a. Nunca elige su rol: se lo da la invitación.
4. Si el enlace caduca (14 días), se le reenvía. Reinvitar no duplica cuentas.

Esto es deliberado: con 2.000 familias, gestionar contraseñas y "he olvidado mi clave" sería un trabajo a tiempo completo.

### Técnico

| Paso | Tabla / función | Notas |
|---|---|---|
| Invitar | `insert into invitations` | `academy_id`, `email`, `role='padre'`, `player_id`, `relation`, `token`, `expires_at` |
| Enviar correo | Supabase Auth (magic link / OTP) | No se programa |
| Crear cuenta | trigger `on_auth_user_created` → `app_handle_new_user()` | Crea `users_profile` **sin** rol ni academia |
| Aceptar | `app_accept_invitation(p_token)` | Escribe `role`, `academy_id` en `users_profile` **y** crea la fila en `player_access` |
| Alcance | `player_access(user_id, player_id, relation, can_pay)` | Padre y madre = **dos filas** al mismo `player_id` |

**Pendiente de decidir:** ¿la inscripción la rellena la propia familia desde un formulario público? Si sí, la invitación se dispara sola al enviarlo y administración no toca nada. Es el camino que quita más trabajo manual, pero exige un formulario público con consentimiento y firma del tutor.

---

### 2.1 Consentimientos: lo que se firma al crear la ficha

> **Aviso.** No soy abogado y esto no es asesoramiento legal. Son los puntos que un club español que trata datos de menores tiene que cubrir, para que sepas qué preguntar. **Antes de vender esto a clubes, que lo revise un abogado especializado en protección de datos.** Estás tratando datos de salud de menores a escala: es el terreno con más riesgo de todo el producto.

#### En cristiano

Antes de que el club pueda usar nada, el tutor tiene que autorizar. Y no vale **una sola casilla** de "acepto todo": la ley exige que las autorizaciones sean **separadas**, para que se pueda decir sí a una cosa y no a otra. Un padre puede querer que su hijo juegue y no querer que su cara salga en Instagram, y eso tiene que ser posible.

Lo que se firma al crear la ficha, como mínimo:

| # | Autorización | ¿Obligatoria? |
|---|---|---|
| 1 | Tratamiento de datos del jugador para gestionar su participación en el club | Sí — sin esto no hay inscripción |
| 2 | **Revisión médica y apto** — solo fecha y sí/no, nada más | Sí, y con consentimiento explícito aparte |
| 3 | **Foto en la ficha interna** (para que el cuerpo técnico identifique al jugador) | Sí |
| 4 | **Difusión pública de imagen** — web del club, redes sociales y prensa, en una sola autorización | **Contestar, sí. Aceptar, no.** Ver 2.1.1 |
| 5 | Cesión de datos a la federación y organizadores de competiciones | Sí, si compite |
| 6 | Comunicaciones del club (avisos, convocatorias) | Sí |
| 7 | Desplazamientos y viajes del menor | Por evento, no de una vez |

**Las tres cosas que suelen fallar** y que hay que hacer bien desde el principio:

**Separar la foto interna de la foto pública.** Es el error más común en clubes. Que el entrenador vea la cara del niño en su ficha y que ese mismo niño aparezca en el Instagram del club son dos cosas distintas y necesitan dos permisos distintos. La foto de la ficha va con el consentimiento general de datos —es necesaria para prestar el servicio—; la difusión pública se pregunta aparte y se puede rechazar.

**Guardar la prueba, no solo el "sí".** De poco sirve un `true` en una casilla. Hay que registrar **quién** firmó, **cuándo**, y **qué texto exacto** firmó. Si dentro de dos años cambias la política de privacidad, tienes que poder demostrar qué versión aceptó cada familia. Por eso se versiona el texto.

**Retirar tiene que ser tan fácil como dar.** La ley lo exige. Si la familia autorizó por una casilla, tiene que poder desautorizar por otra casilla, sin llamar a nadie. Eso significa una pantalla **"Mis autorizaciones"** dentro del portal, siempre accesible.

Y la consecuencia que hay que programar: **si retiran el permiso de imagen, la foto tiene que dejar de usarse de verdad.** No basta con apuntarlo. La app debe marcar al jugador como "no publicable" y que eso se vea allí donde alguien vaya a sacar una foto para redes.

#### 2.1.1 Autorización de imagen: un solo documento, respuesta obligatoria

> **Decisión de producto (2026-08-02).** Una única autorización cubre **web del club, redes sociales y prensa**. No se desglosa por canal. Al firmar la inscripción hay que responder **sí o no**, y sin responder no se puede terminar. Pero **el "no" termina la inscripción exactamente igual que el "sí"**.

**Por qué se puede agrupar los tres canales.** El RGPD exige granularidad por **finalidad**, no por canal. Web, redes y prensa comparten finalidad —difundir la actividad del club—, así que caben en un solo consentimiento siempre que el texto diga con claridad los tres. Desglosar habría sido más garantista, pero también más farragoso de firmar y de gestionar, y no aporta nada legalmente.

**Por qué el "no" no puede bloquear.** Esto es lo único innegociable de todo el bloque. El artículo 7.4 del RGPD dice que un consentimiento no es libre si condicionas un servicio a aceptarlo cuando no es necesario para prestarlo. Jugar al baloncesto no requiere aparecer en Instagram.

Si negarse impidiera inscribirse, no solo sería inválido ese consentimiento: **serían inválidos todos**, incluidos los "sí", porque se habrían dado bajo presión. Es un riesgo desproporcionado a cambio de nada.

**Cómo tiene que verse en pantalla:**

```
Autorización de uso de imagen                        (obligatorio responder)

El club puede publicar imágenes y vídeos donde aparezca
[NOMBRE] en su página web, sus redes sociales y en medios
de comunicación, para difundir la actividad deportiva del club.

Puedes cambiar esta decisión cuando quieras desde
"Mis autorizaciones", sin dar explicaciones.

        ( ) SÍ, autorizo          ( ) NO autorizo

Tu respuesta no afecta a la inscripción ni a la participación
de tu hijo/a en ninguna actividad del club.
```

Reglas de implementación, todas obligatorias:

| Regla | Por qué |
|---|---|
| Ninguna opción premarcada | El RGPD prohíbe el consentimiento por defecto |
| No se puede continuar sin elegir una | Elección forzada: evita el "no me di cuenta" |
| El "no" avanza igual que el "sí" | Consentimiento libre (art. 7.4) |
| Se guarda la versión del texto firmado | Es la prueba |
| Revocable desde "Mis autorizaciones", en un clic | Retirar tan fácil como dar |
| Al revocar, el jugador pasa a "no publicable" **en la app** | El permiso tiene que tener efecto real |

**Lo que la app debe hacer con el "no".** No basta con guardarlo. El jugador queda marcado como no publicable y eso tiene que ser **visible allí donde alguien vaya a coger una foto** para redes: un distintivo en su ficha y en el listado del equipo. Si el community manager del club no lo ve al ir a publicar, la autorización no sirve de nada.

#### Edad: el corte está en los 14

En España, a partir de los **14 años** el menor puede consentir por sí mismo el tratamiento de sus datos. Por debajo, hace falta el consentimiento del tutor.

Esto tiene efecto directo en tu app: un jugador de 12 y uno de 16 **no se tratan igual**. Y como CBJA tiene desde minis hasta cadetes, vas a tener las dos situaciones a la vez. Para derechos de imagen la cosa es más matizada todavía, y es justo donde hace falta el abogado.

**Recomendación práctica:** para difusión pública de imagen de un menor, pedir la firma de **ambos progenitores**, no de uno. Es más trabajo y evita el conflicto clásico de "yo no autoricé esa foto".

#### Técnico

Tabla nueva. No es opcional: sin ella no hay forma de demostrar nada.

```sql
create table if not exists consents (
  id            uuid primary key default gen_random_uuid(),
  academy_id    uuid not null references academies(id) on delete cascade,
  player_id     uuid not null references players(id) on delete cascade,
  signed_by     uuid references users_profile(id),   -- qué cuenta firmó
  relation      text,                                -- Padre | Madre | Tutor | Jugador (14+)
  kind          text not null,                       -- datos | medico | imagen_publica | federacion | comunicaciones
  granted       boolean not null,                    -- imagen_publica admite false y NO bloquea la inscripción
  policy_version text not null,                      -- qué texto se firmó
  signed_at     timestamptz default now(),
  revoked_at    timestamptz,
  ip            inet,
  user_agent    text
);
create index on consents (player_id, kind);
```

| Acción | Permiso | Política RLS |
|---|---|---|
| Ver sus autorizaciones | `app_is_guardian(player_id)` | `select` para tutor y staff con alcance |
| Firmar / retirar | `app_is_guardian(player_id)` | `insert` propio; **nunca `update`** — se inserta una fila nueva |
| Consultar para publicar | staff | `select` |

> **Nunca se actualiza una fila de consentimiento, se inserta otra.** El historial es la prueba. Si sobrescribes, pierdes la evidencia de qué se autorizó antes.

Campos que hay que añadir en `players`:

- `publishable boolean generated` o vista derivada: ¿tiene consentimiento vigente de imagen pública?
- Los datos de salud deberían salir de `players` a una tabla `player_health` con RLS propia. Son **categoría especial**: no puede verlos el mismo grupo que ve el resto de la ficha.

#### Lo que esto significa para tu negocio

Cuando vendas ScoutFlow a un club, el club es el **responsable** de los datos y tú el **encargado del tratamiento**. Eso obliga a firmar un **contrato de encargado** (artículo 28 del RGPD) con cada cliente. No es papeleo opcional: sin él, ningún club medianamente asesorado te firmará.

Añádelo a la lista de cosas a preparar antes de comercializar, junto con la política de privacidad y el registro de actividades de tratamiento.

---

## 3. Mapa de la app para la familia

Una sola pantalla, en este orden (el orden importa: lo urgente arriba):

```
┌─────────────────────────────┐
│  ScoutFlow Family      [≡]  │
├─────────────────────────────┤
│  [Selector de hijo/a]       │  ← solo si tiene más de uno
│  Foto · Nombre · Año · Pos. │
├─────────────────────────────┤
│  ⚠ Lo que el club te pide   │  ← NUEVO: bandeja de tareas
│  Próximas citas             │
│  Documentos pendientes      │
│  Pagos                      │
│  Cómo pagar                 │
│  Equipación                 │
│  Datos bancarios            │
│  Informes                   │
│  Avisos del club            │  ← NUEVO
│  Mis autorizaciones         │  ← NUEVO (RGPD)
└─────────────────────────────┘
```

---

### 3.1 Móvil, instalación y avisos

#### En cristiano

La familia entra desde el móvil. Eso ya está resuelto en el diseño. Lo que **no** está resuelto es cómo le llegan los avisos, y ahí hay una decisión que cuesta dinero y tiempo según lo que elijas.

Hay tres caminos:

**A · Web normal + correo.** La familia abre un enlace en el navegador. Los avisos llegan por email. Cero fricción para entrar, pero los correos se pierden entre el resto y nadie los mira el mismo día.

**B · PWA — la web se añade a la pantalla de inicio.** Queda con su icono, como una app, y permite **notificaciones push** de verdad. En Android funciona directamente. **En iPhone solo funciona si la familia añade la web a la pantalla de inicio a mano**, con el botón Compartir → "Añadir a inicio". Ese paso lo va a completar bastante menos gente de la que crees, y en un club con muchos iPhone eso es medio censo sin avisos.

**C · App nativa en App Store y Google Play.** Notificaciones fiables en todos los móviles y presencia real en la tienda. Cuesta: cuenta de desarrollador de Apple (unos 99 € al año), de Google (unos 25 € una vez), pasar la revisión de Apple — que con apps de menores mira con lupa — y publicar cada actualización.

**Mi recomendación:** empezar por **B con correo de respaldo**, medir cuántas familias completan la instalación, y saltar a **C** cuando el club lo pida o cuando veas que en iPhone no llega. Ir directo a nativa ahora sería gastar semanas antes de saber si las familias siquiera entran.

#### El aviso no puede delatar

Una notificación se lee en la pantalla bloqueada, a la vista de cualquiera. Esto está mal:

> ❌ "Martín Ríos: cuota de octubre vencida — 90 €"

**Regla fijada:** el aviso que sale al móvil dice **siempre lo mismo**, sin excepciones y sin variantes por tipo:

> ✅ **Notificación del club**

El mensaje, dentro de la app y tras identificarse. Ni el nombre del jugador, ni el concepto, ni el importe, ni si es un pago o un documento. Nada que permita deducir algo desde una pantalla bloqueada.

Esto es innegociable en la implementación: la carga útil (`payload`) del push lleva solo el identificador del aviso; el contenido se pide al servidor una vez dentro. Si el texto viaja en el push, viaja al móvil aunque nadie abra la app.

#### Qué se avisa y qué no

Hay que separar dos tipos, porque legalmente no son lo mismo:

| Tipo | Ejemplos | ¿Puede desactivarlo la familia? |
|---|---|---|
| **De servicio** | Documento rechazado, cuota vencida, cambio de horario del partido | No del todo — es la relación con el club |
| **Informativo** | Noticias del club, campus de verano, promociones | Sí, siempre, y con un clic |

Mezclar los dos en un único interruptor es el error típico. Si la familia desactiva las notificaciones porque le cansa la publicidad, deja de enterarse de que su hijo tiene un partido.

#### Técnico

| Pieza | Qué hace falta |
|---|---|
| PWA | `manifest.json`, service worker, iconos, `display: standalone` |
| Push | Web Push API + VAPID; en iOS requiere iOS 16.4+ **y** estar añadida a inicio |
| Tabla `push_subscriptions` | `user_id`, `endpoint`, `keys`, `device`, `created_at`, `last_seen` |
| Tabla `notifications` | `user_id`, `player_id`, `kind`, `title`, `read_at`, `sent_at` |
| Preferencias | `notification_prefs(user_id, kind, enabled)` |
| Respaldo | Si no hay suscripción push activa a las X horas → enviar correo |

> El envío se dispara desde la base de datos: un *trigger* sobre `documents`, `finance` o `team_events` encola la notificación. Así el aviso sale aunque la acción venga de la app de administración, del portal o de un proceso automático.

---

## 4. Bloque por bloque

### 4.1 Cabecera — foto y datos del hijo/a

**En cristiano.** Lo primero que ve: la foto de su hijo, su nombre, año de nacimiento y posición. Si la foto no está, un botón grande para hacerla con la cámara del móvil. Es la forma más fácil de que el club consiga fotos sin perseguir a nadie.

Si tiene dos o tres hijos en el club, arriba hay un selector para cambiar entre ellos. Nunca ve a los dos a la vez mezclados.

**Técnico.**

| Acción | Tabla | Campos | Permiso | Política |
|---|---|---|---|---|
| Ver ficha básica | `players` | `full_name`, `birth_year`, `primary_position`, `photo_url` | alcance | `players_select` → `app_can_see_player(id)` |
| Subir foto | Storage `players/{id}/photo` + `players.photo_url` | — | `app_is_guardian(pid)` | **falta política de Storage** |
| Listar sus hijos | `player_access` | `where user_id = auth.uid()` | — | — |

> **Aviso.** La foto del menor es dato personal. Debe ir a un bucket **privado** con URLs firmadas de caducidad corta, nunca público.

---

### 4.2 Lo que el club te pide *(bloque nuevo)*

**En cristiano.** Una bandeja con lo que está pendiente **de ella**, no del club: "falta el pasaporte", "cuota de octubre vencida", "confirma la talla de la equipación", "rellena el número de la seguridad social". Cada línea lleva directa a resolverlo.

Hoy la familia tiene que adivinar qué falta recorriendo la pantalla. Esto lo pone arriba y lo cuenta.

**Técnico.** No es una tabla nueva: es una **vista calculada** al vuelo a partir de lo que ya existe.

| Origen de la tarea | Consulta |
|---|---|
| Documento sin entregar | `documents` con `delivered = false` |
| Revisión médica caducada o sin hacer | `player_medical` sin fila de la temporada actual, o `fit = false` |
| Pago vencido | `finance` con `status='vencido'` |
| Pedido de ropa sin hacer | `kit_orders` inexistente o `status is null` |
| Foto del jugador sin subir | `players.photo_url is null` |
| Dato del perfil vacío | campos requeridos nulos en `players` |
| Datos bancarios sin poner | `family_billing` vacío y hay cuotas domiciliadas |
| Autorización sin firmar | falta fila vigente en `consents` para un `kind` obligatorio |

Recomendación: encapsularlo en una **vista SQL** `family_todo` con RLS heredada, para no repetir la lógica en la app.

---

### 4.3 Próximas citas

**En cristiano.** El próximo partido y el próximo entrenamiento de su equipo: día, hora, sitio y rival. Nada más. La familia no necesita el calendario entero, necesita saber dónde llevar al niño el sábado.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver próximas citas | `team_events` (vía `players.team_id`) | alcance | **falta** — hoy `team_events` no tiene RLS |

> **Hueco de seguridad a cerrar.** `auth_schema.sql` protege `team_messages` pero **no** `team_events`. Hay que añadir una política que permita leer eventos del equipo a: el cuerpo técnico de ese equipo, dirección, y las familias con un hijo en ese equipo. Escritura solo cuerpo técnico y dirección.

---

### 4.4 Documentación — checklist, no archivo

> **Decisión de producto (2026-08-02).** La app **no guarda documentos**. Solo lleva la cuenta de qué se ha entregado y qué falta. Los papeles viajan por correo electrónico o se entregan en mano, y los custodia el club fuera de la plataforma.
>
> Esto **revierte** la decisión anterior de "cámara integrada para pasaporte, DNI y certificados". La cámara se queda **solo para la foto del jugador**.

**Por qué es la decisión correcta.** Guardar copias de DNI y pasaportes de menores te convertía en custodio de documentos identificativos de mil familias: bucket cifrado, URLs firmadas, política de conservación, respuesta ante brecha de seguridad, y un incidente potencialmente grave si algo falla. A cambio de una comodidad. Con esto, la app hace lo único que el club necesita de verdad: **saber qué falta**.

#### En cristiano

La familia ve una lista de lo que el club le pide, con dos estados: **entregado** o **pendiente**. Nada más. Ni subir, ni validar, ni rechazar.

```
Documentación
  ✅ Ficha de inscripción firmada     entregado 12/09
  ✅ Autorización de imagen           entregado 12/09
  ⬜ Copia del DNI                    pendiente
  ⬜ Justificante del seguro          pendiente
```

Junto a los pendientes, una línea que diga cómo entregarlos: *"Envíalos a secretaria@cbja.es o tráelos al pabellón"*. La app orienta; el trámite ocurre fuera.

**Quién marca:** solo el club. Administración marca lo que ha recibido. La familia no puede declarar entregas por su cuenta, así que hay un único registro y no hay discusión sobre si se entregó o no.

#### Revisión médica

Dos datos, y solo dos:

| Campo | Qué es |
|---|---|
| **Fecha de la revisión** | Cuándo se hizo |
| **Apto** | Sí / No |

**Nada más.** Ni informe, ni diagnóstico, ni alergias, ni lesiones, ni el nombre del médico. Si el club necesita conocer una alergia, eso se trata por correo o en persona con el entrenador, fuera de la app.

Caduca **por temporada**. La app avisa sola cuando toca renovarla, igual que hacen las federaciones. El aviso llega a la familia con antelación y aparece en la bandeja de "lo que el club te pide".

> **Sigue siendo dato de salud.** Un "apto: no" revela estado de salud, así que el campo entra en categoría especial del RGPD aunque sea un sí/no. La diferencia con guardar un informe médico es abismal —esto es el mínimo imprescindible para que un menor compita, y se justifica solo—, pero exige igualmente: consentimiento explícito, acceso restringido a quien lo necesite, y no aparecer en listados generales.
>
> **Quién debe verlo:** dirección, administración, el entrenador de su equipo y el preparador físico. **No** el scout, ni la dirección técnica de otro segmento.

#### Datos sensibles de custodia

Fuera de la app, siempre. Situaciones de custodia, órdenes judiciales, restricciones entre progenitores: el club las gestiona por correo o presencialmente. La app no las almacena ni las muestra.

Lo único que refleja la app es el **efecto**: quién tiene acceso al portal del jugador (`player_access`) y quién puede pagar (`can_pay`). El motivo por el que un progenitor no tiene acceso no se escribe en ningún sitio.

#### Técnico

| Acción | Tabla | Campos | Permiso | Política |
|---|---|---|---|---|
| Ver checklist | `documents` | `type`, `delivered`, `delivered_at` | alcance | `documents_select` |
| Marcar entregado | `documents` | `delivered`, `delivered_at`, `marked_by` | staff con alcance | `documents_write` |
| Ver apto médico | `player_medical` | `checkup_date`, `fit`, `season` | staff autorizado o tutor | `medical_select` |
| Editar apto médico | `player_medical` | — | `manage_medical` (nuevo permiso) | `medical_write` |

Cambios respecto al esquema actual:

- **`documents` se simplifica.** Fuera `file_url`, `status` de cuatro valores y `reject_reason`. Entra `delivered boolean`, `delivered_at`, `marked_by`.
- **Se parte `documents_rw`.** Hoy es un `for all` que permitiría a una familia marcar sus propios documentos. Pasa a `select` con alcance y `write` solo para staff.
- **Nueva tabla `player_medical`** con `player_id`, `season`, `checkup_date`, `fit boolean`, `updated_by`, `updated_at`. Separada de `players` para poder restringirla aparte. Una fila por temporada: así queda el histórico y la caducidad es automática.
- **Sin Storage para documentos.** El único bucket que queda es el de fotos de jugador.

---

### 4.5 Pagos

**En cristiano.** Cuánto lleva pagado, cuánto debe, y el desglose: inscripción, cuota de cada mes, torneos, equipación. Cada línea con su estado. Si algo está pendiente, un botón para pagarlo.

Hoy el botón "Pagar" abre una ventana con los datos para hacer transferencia o Bizum: **la app no cobra, informa**. Eso está bien para arrancar, pero hay que decirlo claro en pantalla para que nadie crea que ya ha pagado.

Debe poder **descargarse el recibo** de lo pagado. Muchas familias lo necesitan para la empresa, para ayudas o para Hacienda.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver sus pagos | `finance` | `app_is_guardian(player_id)` | `finance_select` ✅ ya contempla a la familia |
| Marcar como pagado | `finance` | `manage_finance` (**staff**) | `finance_write` — la familia **no** puede |
| Descargar recibo | Storage `receipts/` | `app_is_guardian` | **falta** |

> El descuento por hermanos (2º hijo = 100 % de inscripción; 3º = 100 % + 50 % del resto) se calcula sobre **todos los `player_access` del mismo tutor**. Ojo: si padre y madre están separados y cada uno tiene acceso a hijos distintos, el descuento es del *jugador*, no del *usuario*. Debe calcularse por familia real, no por cuenta.

---

### 4.6 Equipación

**En cristiano.** El pack deportivo del club: sus 6 prendas, la talla de cada una, y si quiere el nombre y el dorsal serigrafiados. La familia elige tallas y envía el pedido. Después puede modificarlo mientras el club no lo haya cerrado.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver / crear / modificar pedido | `kit_orders` | `app_is_guardian` o `manage_finance` | `kit_write` ✅ ya lo contempla |

> **Falta un cierre.** Hoy la familia puede modificar el pedido siempre. Necesita un estado `cerrado` a partir del cual solo administración pueda tocarlo, o el club acabará con pedidos cambiados después de haberlos encargado al proveedor.

---

### 4.7 Datos bancarios

**En cristiano.** La familia mete su IBAN y elige forma de pago (recibo domiciliado o tarjeta). Lo puede actualizar cuando cambie de banco.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver / editar IBAN | hoy `players.bank` (JSON) | `app_is_guardian` | `players_update` — ⚠️ **hoy exige `app_is_staff()`, así que la familia NO puede** |

> **Esto está roto y hay que arreglarlo.** La política `players_update` requiere ser staff. Con el esquema actual, la familia no podría guardar su IBAN aunque la app le enseñe el botón.
>
> Además, el IBAN **no debe vivir en `players`**: es dato de la familia, no del jugador, y `players` lo lee todo el cuerpo técnico. Hay que sacarlo a una tabla `family_billing(player_id, iban, method, holder_name)` con RLS propia: solo la familia del jugador y quien tenga `manage_finance`. Un entrenador no tiene por qué ver el IBAN de nadie.

---

### 4.8 Informes

**En cristiano.** Los informes del club sobre su hijo: deportivos, académicos, de adaptación, trimestrales. **Solo los que el staff haya decidido publicar.** Un informe escrito por un entrenador no aparece hasta que alguien lo publica a propósito.

Esto es importante y es una decisión de producto ya tomada: el staff escribe con libertad, y publica lo que quiere que la familia lea.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver informes publicados | `reports` | alcance + `published = true` | **falta la tabla y la política** |
| Escribir informe | `reports` | `can_evaluate` | **falta** |
| Publicar informe | `reports.published` | staff con permiso | **falta** |

> `reports` no existe todavía en el esquema. La política de lectura para familia debe ser: `app_is_guardian(player_id) and published = true`. Para staff: `app_can_see_player(player_id)`.

---

### 4.9 Avisos del club *(bloque nuevo)*

> **Actualizado el 2026-08-02.** Este bloque se llamaba "Comunicaciones" y se diseñó como mensajería con respuestas. **Ya no.** Es un **tablón de avisos en un solo sentido**. La especificación completa está en `ROL_JUGADOR.md`, sección 5; aquí solo lo que ve la familia.
>
> El diseño anterior —tabla `communications` con `audience` y `visible_to_family`— **queda anulado** y sustituido por `announcements` + `announcement_targets`.

**En cristiano.** Avisos del club: entrenamientos, horarios, partidos, convocatorias. La familia los recibe, los lee y, cuando el aviso lo pida, confirma asistencia con dos botones. **No puede escribir.** Si necesita hablar con el entrenador, teléfono o en persona.

La familia recibe:

- Los avisos dirigidos a su hijo/a, **siempre**, aunque el jugador tenga cuenta propia y sea menor
- Los avisos dirigidos al equipo
- Los avisos dirigidos específicamente a las familias

Y **no ve** a los demás destinatarios: ni sus nombres, ni cuántos son, ni si lo han leído.

**Técnico.**

| Acción | Tabla | Permiso | Política |
|---|---|---|---|
| Ver sus avisos | `announcement_targets` + `announcements` | fila propia | `at_select_own` → `user_id = auth.uid()` |
| Marcar leído | `announcement_targets.read_at` | fila propia | `at_rsvp` |
| Confirmar asistencia | `announcement_targets.rsvp`, `rsvp_by` | fila propia | `at_rsvp` |
| Escribir | — | **no existe** | — |

---

## 5. Lo que la familia NO ve nunca

Esta lista no es una preferencia: es la frontera del rol, y debe estar garantizada por RLS, no por la interfaz.

| No ve | Dónde vive | Qué lo protege |
|---|---|---|
| Notas internas, presupuesto, situación económica | `player_private` | `private_select` → `app_perm('see_notes')` ✅ |
| Scout Score interno | `player_private` | ✅ |
| Evaluaciones técnicas y comentarios de entrenador | `evaluations` | **falta la tabla** |
| Medidas físicas | `measurements` | `measurements_select` exige `app_is_staff()` ✅ |
| El apto médico **de otro jugador** | `player_medical` | **falta** — política más estrecha que la de `players` |
| Cualquier dato de otro jugador | `players` | `players_select` → `app_can_see_player` ✅ |
| Otras familias, otros usuarios | `users_profile` | `profile_self` ✅ |
| Economía del club, watchlists, captación | varias | ✅ por rol |
| Informes no publicados | `reports` | **falta** |

**Prueba de fuego antes de dar esto por hecho:** entrar con una cuenta de familia real y pedir a mano el jugador de otra familia. Si devuelve datos, no está terminado. Ocultar el botón no es seguridad.

---

## 6. Casos reales que hay que resolver

Estos no son detalles: en un club de verdad aparecen todos el primer mes.

**Padre y madre.** Dos cuentas, dos filas en `player_access` al mismo jugador. Ya está contemplado. Falta decidir: ¿los dos pueden pagar? El campo `can_pay` existe pero nadie lo usa todavía.

**Varios hijos.** Un tutor con dos o tres hijos en el club. La base de datos lo soporta (varias filas en `player_access`), pero **el portal actual solo muestra un jugador**. Hay que añadir el selector.

**Separación y custodia.** El caso más delicado. Padres separados donde uno no debe ver ciertos datos, o donde solo uno paga. Se resuelve dando o quitando la fila de `player_access` y con `can_pay`. **Pero hace falta una decisión tuya:** ¿el club acepta órdenes judiciales de restricción de acceso? Si sí, necesitas un registro de quién cambió el acceso y cuándo.

**Revocar.** Un tutor que deja de serlo: se borra su fila de `player_access` y deja de ver los datos **al instante**, sin cerrar sesión, porque lo impide RLS.

**El jugador cumple 18.** ✅ **Resuelto** — el acceso de los tutores continúa solo si el jugador lo confirma, con 30 días de cortesía y opción intermedia de "solo pagos". Detalle completo en `ROL_JUGADOR.md`, sección 6.

**Familia sin correo o sin smartphone.** Existe, y más de lo que parece. Necesita una vía alternativa: que administración cargue los documentos y registre los pagos en su nombre. La app no puede ser el único camino o dejas gente fuera.

---

## 7. Distancia entre lo que hay hoy y este plano

| Bloque | Hoy en la app | Falta |
|---|---|---|
| Cabecera + foto | ✅ nombre, año, posición | Foto real con cámara; selector de varios hijos |
| Lo que el club te pide | ❌ no existe | Todo el bloque |
| Próximas citas | ✅ funciona | RLS en `team_events` |
| Documentación | ⚠️ lista con botón de subir | **Quitar la subida**; pasar a entregado/pendiente; marcado solo por el club |
| Revisión médica | ❌ no existe | Tabla `player_medical`, caducidad por temporada y aviso |
| Pagos | ✅ desglose y totales | Descarga de recibos; cobro real |
| Equipación | ✅ completo | Estado "cerrado" |
| Datos bancarios | ✅ formulario | Sacar el IBAN de `players`; arreglar la política que hoy lo impide |
| Informes | ⚠️ placeholder vacío | Tabla `reports` entera |
| Avisos del club | ⚠️ hay muro de equipo compartido | Convertirlo en tablón: `announcements` + `announcement_targets` |
| Mis autorizaciones | ❌ no existe | Tabla `consents` y la pantalla |
| Avisos | ❌ no existe | PWA, push con texto fijo, correo de respaldo |

En una frase: **las pantallas están; lo que falta es que guarden de verdad y que los permisos sean reales.**

> **Trabajo de quitar, no solo de añadir.** El portal actual tiene botones de "Subir" con cámara en la sección de documentos. Hay que retirarlos y sustituirlos por el checklist en solo lectura, o la familia intentará usarlos.

---

## 8. Cambios necesarios en la base de datos

Ordenados por urgencia, no por dificultad.

**Arreglos sobre lo ya escrito:**

1. `players_update` — permitir a la familia editar su parcela, o (mejor) sacar esos campos de `players`.
2. `documents_rw` — partirla en select / insert / update. Hoy la familia podría autovalidarse un documento.
3. `team_events` — no tiene RLS. Añadirla.

**Tablas nuevas:**

4. **`consents`** — autorizaciones firmadas, versionadas y con historial. **La más urgente de todas**: sin ella el club no puede demostrar que tiene permiso para nada.
5. **`player_medical`** — una fila por temporada: `checkup_date`, `fit`, nada más. Con RLS propia y más estrecha que la de `players`.
6. `family_billing` — IBAN y forma de pago, fuera de `players`.
7. `reports` — con `published boolean default false` y política de lectura para familia.
8. `announcements` + `announcement_targets` — el tablón de avisos. Definidas en `ROL_JUGADOR.md` §5.
9. `evaluations` — para que las valoraciones dejen de ser invisibles a la familia por omisión y lo sean por diseño.
10. `push_subscriptions`, `notifications`, `notification_prefs` — los avisos. Definidas en `ROL_JUGADOR.md` §5.

**Simplificaciones (quitar, no añadir):**

11. **`documents` adelgaza** — fuera `file_url`, `status` de cuatro valores y `reject_reason`. Entra `delivered`, `delivered_at`, `marked_by`.
12. **Sin Storage para documentos.** Único bucket que queda: fotos de jugador, privado y con URLs firmadas.
13. **Sin campos de salud en `players`.** Ni alergias, ni lesiones, ni informes.

**Campos que faltan:**

14. `kit_orders.locked`
15. `players` → indicador derivado **"publicable"** (¿hay consentimiento de imagen vigente?)
16. `role_permissions` → nuevo permiso `manage_medical`
17. Vista `family_todo`

---

## 9. Orden de implementación sugerido

1. **Simplificar `documents` y quitar los botones de subir.** Es lo más rápido y lo que menos código toca: quitar, no añadir.
2. **Arreglar las políticas rotas** (`players_update`, `documents_rw`, `team_events` sin RLS).
3. **`consents` + pantalla "Mis autorizaciones".** Mientras no exista, el club está usando fotos de menores sin poder demostrar que tiene permiso.
4. **`player_medical`** con caducidad por temporada y su aviso automático.
5. **Sacar el IBAN a `family_billing`.** Un entrenador no debe ver cuentas bancarias, y hoy las vería.
6. **Foto del jugador** desde la cámara, a bucket privado, condicionada al consentimiento de imagen.
7. **Selector de varios hijos.** Sin esto, una familia con dos hermanos no puede usar la app.
8. **PWA + push** con texto fijo y correo de respaldo. Sin avisos, el portal no se visita.
9. **Bandeja "lo que el club te pide".** Convierte el portal de escaparate en herramienta.
10. **`reports` + publicación.**
11. **Tablón de avisos.** Va con el rol Entrenador, que es quien los escribe.

---

## 10. Decisiones que necesito de ti

Antes de escribir SQL:

1. **¿La inscripción la rellena la familia** desde un formulario público, o siempre la carga administración?
2. **`can_pay`:** ¿pueden pagar padre y madre indistintamente, o se designa un pagador?
3. **Familias sin app:** ¿qué vía alternativa damos?
5. **¿Exigimos la firma de ambos progenitores** para difusión de imagen, o basta con uno?
6. **Notificaciones:** ¿arrancamos con PWA (barato, flojo en iPhone) o vamos directos a app nativa?
7. **¿Tienes ya política de privacidad y contrato de encargado de tratamiento?** Si no, hay que redactarlos antes de vender a ningún club.

**Ya decidido (2026-08-02):**

- ✅ La app **no guarda documentos**: solo entregado / pendiente. Los papeles, por correo o en mano.
- ✅ De salud, solo **fecha de revisión y apto**. Nada más.
- ✅ Los datos sensibles de custodia se gestionan **fuera de la app**.
- ✅ La foto del jugador **sí** se sube desde la cámara. Es la única subida que queda.
- ✅ El estado de entrega lo marca **solo el club**.
- ✅ El apto médico **caduca por temporada**, con aviso automático.
- ✅ La notificación al móvil dice **siempre "Notificación del club"**; el contenido, dentro.
- ✅ **Una sola autorización de imagen** para web, redes y prensa. Sin desglose por canal.
- ✅ Responder **es obligatorio** para terminar la inscripción; **aceptar no lo es**. El "no" avanza igual.

---

_Documento vivo. Cuando se implemente un bloque, se marca aquí. Siguiente rol a especificar: Entrenador o Administrativo._
