# Autenticación, roles y permisos — plan de fase real

Este documento explica cómo se da acceso a cada persona, cómo se le asignan sus
permisos y cómo incorporarlo **a escala** (miles de jugadores, el doble de familias
porque entran padre y madre por separado, y decenas de entrenadores).

El esquema técnico está en `database/auth_schema.sql`. La conexión, en `js/supabaseClient.js`.

---

## 1. Cuatro cosas que no hay que confundir

| Concepto | Pregunta | Dónde vive |
|---|---|---|
| **Identidad** | ¿Quién eres? | Supabase Auth (correo + enlace mágico / código OTP) |
| **Rol** | ¿Qué eres en el club? | `users_profile.role` |
| **Alcance** | ¿Sobre quién? | `team_coaches` (entrenador), `player_access` (familia), `segment` (DT) |
| **Permisos** | ¿Qué puede tocar? | `role_permissions` + políticas **RLS** |

Regla de oro: **el usuario nunca elige su rol**. El selector de rol de la demo
desaparece en producción. El rol y el alcance los pone **quien invita** y vienen
ya pegados a la cuenta al entrar.

---

## 2. Cómo entra cada persona (tu "clave por correo")

1. El director o administración pulsa **Invitar**: escribe el correo, elige el
   **rol** y el **alcance** (equipo para un entrenador, hijo/a + relación para una familia).
2. Supabase envía un correo con un **enlace mágico** (un clic, un solo uso) o un
   **código de 6 dígitos** (OTP). Eso es la clave especial.
3. La persona descarga la app, mete su correo, abre el enlace (o teclea el código).
   Su cuenta se crea y, al aceptar, queda **enlazada al club con su rol y alcance**
   (función `app_accept_invitation`).
4. La app le muestra solo lo suyo: la familia, el portal de su hijo/a; el
   administrativo, finanzas; el entrenador, su equipo.

**Passwordless recomendado**: con miles de familias, gestionar contraseñas (y sus
"he olvidado la contraseña") es un problema. El enlace mágico / OTP evita todo eso:
cada acceso es un correo. Quien quiera, puede fijar contraseña; no es obligatorio.

---

## 3. Permisos reales: por qué RLS y no solo la interfaz

Hoy, en la demo, los permisos se aplican **ocultando botones**. Eso es comodidad,
no seguridad: alguien con conocimientos podría pedir datos que no le tocan.

En fase real, las **políticas RLS** (Row Level Security) viven en la base de datos
y deciden, fila por fila, qué puede ver o tocar cada usuario. Así:

- Una familia **no puede** acceder a los datos de otro niño aunque manipule la app.
- Finanzas solo la edita quien tiene `can_manage_finance`.
- Las notas internas, el presupuesto y el Scout Score viven en una tabla aparte
  (`player_private`) que solo ve quien tiene `can_see_notes`.

La matriz `role_permissions` es **editable** (espeja la pantalla de Permisos), así
que el director puede cambiar qué hace cada rol sin tocar código.

---

## 4. Escala: miles de familias, decenas de entrenadores

El cuello de botella nunca es la base de datos (con sus índices aguanta de sobra),
sino el **alta de tanta gente**. La clave es que las altas sean **masivas y
automáticas**, no de una en una.

**Jugadores y familias (alta masiva):**
- Importas los jugadores por **CSV** (o se crean al inscribirse). En la misma
  operación se generan las **invitaciones** a los correos de los progenitores.
- **Padre y madre**: dos correos por jugador → **dos invitaciones**, cada una crea
  su propia cuenta y ambas quedan enlazadas al mismo hijo/a en `player_access`.
  Por eso puede haber el doble de cuentas de familia que de jugadores.
- Lo ideal: que la **inscripción la haga la propia familia** (formulario del club).
  Al enviarla, se crea el jugador y se dispara la invitación automáticamente. Cero
  trabajo manual de administración.

**Entrenadores (decenas):**
- La dirección técnica los invita (o se importan por CSV) y se les **asigna a sus
  equipos** (`team_coaches`). Un entrenador puede llevar varios equipos; un equipo,
  varios técnicos.
- El alcance es automático: cada entrenador solo ve los jugadores de sus equipos.

**Buenas prácticas a esa escala:**
- Invitaciones **idempotentes** (reinvitar no duplica) y con **caducidad** (14 días).
- **Revocar** un acceso = marcar la invitación/quitar la fila de acceso; el usuario
  deja de ver datos al instante (lo hace RLS).
- Índices ya previstos en `player_access(player_id)`, `invitations(email)`, etc.

---

## 5. Plan de incorporación por fases (de la demo a producción)

1. **Activar Supabase Auth** con correo (enlace mágico / OTP).
2. **Aplicar** `database/schema.sql` y luego `database/auth_schema.sql` (tablas + RLS).
3. **Sembrar** la academia y el primer usuario **director** (y su fila en `role_permissions`).
4. **Conectar la app** a `js/supabaseClient.js`. Aquí se nota el diseño actual: toda
   la app habla con `SF.store` (una única capa de datos). Cambiar
   *localStorage → Supabase* se hace dentro de `SF.store`, **sin reescribir las
   pantallas**. Es el gran ahorro de haberlo construido así.
5. **Quitar** el selector de rol de la demo; el rol pasa a salir del perfil real.
6. **Pantalla de Usuarios/Invitaciones**: la de Permisos pasa de informativa a
   operativa (invitar, ver pendientes/activos, revocar, cambiar rol, reasignar familia).
7. **Importar** jugadores por CSV y **auto-invitar** a las familias (padre y madre).
8. **Invitar** entrenadores y **asignarlos** a sus equipos.

---

## 6. Quién puede invitar

| Rol | Puede invitar |
|---|---|
| Director | A cualquiera (staff y familias) |
| Administrativo | Familias y staff administrativo |
| Dirección Técnica | Entrenadores de su ámbito (opcional) |
| Resto (entrenador, scout, preparador físico, familia) | No invita |

---

## 7. Estado actual

- **Hecho:** el modelo de roles, alcance y la matriz de permisos (ya funciona en la app).
- **Preparado (este documento + `auth_schema.sql`):** identidad real, invitaciones por
  correo y permisos blindados con RLS.
- **Pendiente (v0.3):** activar Supabase, conectar `SF.store`, y montar la pantalla
  operativa de Usuarios/Invitaciones.
