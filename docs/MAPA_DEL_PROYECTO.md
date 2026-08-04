# ScoutFlow Academy — Mapa del proyecto

_Documento para leer de un vistazo y compartir con quien te ayude. Explica qué hace la app hoy, qué ve cada rol, qué es real y qué falta._

**Producto:** ScoutFlow Academy · **Slogan:** From Prospect to Player · **Academia piloto:** CBJA (baloncesto, federación FBM)

---

## 1. Qué es, en una frase

Un **CRM deportivo** (una herramienta para gestionar jugadores) para academias y clubes: centraliza la **captación, admisión, seguimiento, familias, documentación, equipos, finanzas y economía del club** alrededor de la **ficha de cada jugador**. Nace multi‑deporte; el primer caso completo es baloncesto.

---

## 2. Cómo está montado hoy (en cristiano)

- La app **funciona en el navegador** (ordenador y móvil) y está publicada en internet (Vercel).
- Ahora mismo es una **demo funcional**: puedes crear, editar, pasar gastos, generar planes de pago, etc., y **todo se guarda en el propio navegador** (no se pierde al cerrar). Pero **aún no hay un servidor central**: cada dispositivo tiene sus datos.
- La **"fase real"** —entrar con usuario y contraseña, base de datos en la nube compartida, permisos de verdad, subir fotos/documentos, IA real y pagos— está **diseñada y preparada**, pero **todavía no conectada**. El motor previsto se llama **Supabase**.
- La **web comercial** (`scoutflow-academy.com`, para vender el producto) y la **app** (`app.scoutflow-academy.com`) son dos cosas **separadas**.

---

## 3. Qué hace la app, menú por menú

| Menú | Para qué sirve | Estado |
|---|---|---|
| **Inicio** | Resumen del club: nº de jugadores, en evaluación, datos incompletos, pagos pendientes, familias activas, últimos registrados. | Funciona |
| **Jugadores** | Vista principal en **tarjetas con foto**. Buscador y filtros. Se entra a la ficha de cada uno. | Funciona |
| **Equipos** | Cada equipo con su **plantilla** (con buscador para añadir jugadores que ya tienen ficha), **cuerpo técnico**, **familias**, **calendario** (entrenamientos y partidos con aviso automático) y **muro de comunicación**. | Funciona |
| **Importar con IA** | Pegar un texto y que "cree" una ficha. | **Simulado** (la IA aún no es real) |
| **Captación** | Embudo/pipeline: de "Nuevo" a "Inscrito". | Funciona |
| **Documentos** | Documentos del jugador (DNI, pasaporte, seguro, etc.) con estados. | Funciona (subida real = pendiente) |
| **Informes** | Informes deportivos/académicos; se publican a la familia solo si el staff quiere. | Base montada |
| **Family** | Acceso a la vista de las familias (portal del hijo/a). | Funciona |
| **Finanzas** | Plan de pago **por jugador**: inscripción, cuotas por mes, torneos, datos bancarios, descuento por hermanos, plan tipo FBM y pedido de equipación. | Funciona |
| **Economía** | Cuentas **del club**: cualquiera pasa **gastos con foto del ticket**, administración los aprueba, y se lleva la **contabilidad de la temporada** (saldo, ingresos, gastos, estadísticas). | Funciona |
| **Permisos** | Matriz de qué puede hacer cada rol. | Funciona (aplicado en pantalla) |
| **Configuración** | Ajustes de la academia y métodos de pago. | Base montada |

---

## 4. La ficha del jugador (el corazón de todo)

Tiene **12 pestañas**. Resumen de cada una:

1. **Perfil** — identidad, contacto, posición. (Primera pestaña siempre.)
2. **Deportivo** — club, liga, categoría, equipo, **Físico (medidas)** que toma el preparador físico (altura, peso, envergadura, alcances, mano dominante, usa las dos manos…), evaluación técnica/física/mental, trayectoria, selecciones y competiciones.
3. **Académico** — centro, curso, idiomas, notas.
4. **Familia** — padre, madre, tutor y contactos.
5. **Documentos** — DNI, pasaporte, seguro, expediente… con estado.
6. **Vídeos** — highlights, partidos, entrenamientos.
7. **Captación** — cómo y por quién llegó.
8. **Seguimiento** — **línea temporal interactiva**: cada hito (Nuevo → Datos incompletos → Evaluación → Entrevista → Oferta → Inscrito) se marca como completado, con fecha y **anotación**, más un registro de notas y la "próxima acción".
9. **Informes** — informes del jugador.
10. **Finanzas** — su plan de pago completo (ver menú Finanzas).
11. **Portal Family** — lo que ve su familia.
12. **Notas internas** — solo staff: situación económica, **presupuesto**, comentarios de scout/entrenador. **Nunca** lo ve la familia.

---

## 5. Los roles: quién ve qué

| Rol | Alcance | Qué hace |
|---|---|---|
| **Director** | Todo el club | Ve y edita todo, incluidas finanzas, economía, notas internas y permisos. Invita usuarios. |
| **Dirección Técnica General** | Todos los equipos | Gestiona equipos, evalúa, edita medidas físicas. Sin finanzas. |
| **Dirección Técnica (Femenino / Masculino / Escuelas / Minis)** | **Solo su segmento** | Igual que la general, pero limitada a su categoría. |
| **Preparador Físico** | Jugadores del club | Toma y edita las **medidas físicas** y evalúa la parte física. |
| **Scout** | Sus jugadores | Capta, evalúa inicial, hace seguimiento. |
| **Entrenador** | **Solo su equipo** | Ve a sus jugadores, evalúa, y gestiona el **calendario y la comunicación** de su equipo (no toca la plantilla de otros ni finanzas). |
| **Administrativo** | Asignado | Gestiona **finanzas** y **aprueba gastos** de economía. Sin evaluaciones deportivas. |
| **Familia (Padre/Madre/Tutor)** | **Solo su hijo/a** | Ve el portal del hijo: documentos, informes publicados, **plan de pagos**, **cómo pagar**, **pedido de equipación**, **próximas citas** del equipo. No ve nada de otros ni datos internos. |

> **Economía:** cualquiera del staff puede **pasar un gasto** (con foto del ticket); solo administración/dirección ve la contabilidad completa y aprueba.

---

## 6. Qué es real y qué está simulado (honesto)

| Real hoy | Simulado / de maqueta | Pendiente (fase real) |
|---|---|---|
| La app y todas las pantallas | La IA de "Importar" y "Analizar" | Login con usuario/contraseña |
| Guardado en el navegador | Las subidas de foto/documento (se registran, no se almacenan en la nube) | Base de datos en la nube (Supabase) |
| Todos los cálculos (finanzas, economía, contabilidad) | El pago (muestra los datos para transferencia/Bizum, no cobra solo) | Permisos aplicados en el servidor (RLS) |
| Roles y permisos en pantalla | | Pagos automáticos (Stripe/Bizum) |
| | | IA real · importación desde la federación |

---

## 7. Lo que hemos construido recientemente

- **Equipos** completos: plantilla con **buscador para añadir jugadores**, cuerpo técnico, familias, **calendario de entrenamientos y partidos** con **aviso automático** al muro, y comunicación.
- **Roles nuevos**: Dirección Técnica (general y por segmento), Preparador Físico.
- **Físico** movido a Deportivo (lo gestiona el preparador físico) + campo "usa las dos manos".
- **Finanzas** por jugador: plan de inscripción/cuotas/torneos, datos bancarios, **descuento por hermanos**, **plan tipo FBM**, y **pedido de equipación** (tallas + serigrafiado).
- **Economía del club**: gastos con **foto de ticket**, presupuesto, contabilidad de temporada y estadísticas.
- **Seguimiento** rehecho: línea temporal **interactiva** con anotaciones.
- **Blueprint de fase real (Supabase)**: esquema de autenticación, invitaciones por correo y permisos blindados (documentos `auth_schema.sql` y `AUTENTICACION_Y_PERMISOS.md`).
- **Usabilidad**: cada icono muestra su **nombre al pasar el cursor**.

---

## 8. Qué falta para ser un SaaS real (próximos pasos, en orden)

1. **Conectar Supabase** — login por correo, base de datos en la nube y **permisos de verdad** (ya está el plano hecho).
2. **Subidas reales** — fotos y documentos guardados en la nube (incluidas las fotos de tickets de gastos).
3. **Pantalla de Usuarios/Invitaciones** — para invitar a staff y familias por correo y gestionar accesos a escala.
4. **IA real** — importar de WhatsApp/PDF/email y el botón "Analizar con IA".
5. **Pagos reales** — cobro automático (Stripe, y luego Bizum/transferencia).
6. **Importación desde la federación** — que los partidos se rellenen solos en el calendario.
7. **Web comercial** (WordPress) y **comercialización** a clubes.

**Ajustes menores pendientes / ideas abiertas:** asistente de inscripción con firma del tutor y consentimiento del seguro; catálogo de equipación editable desde Configuración; rol "Jugador" (opcional).

---

## 9. Para quien nos ayude (orientación técnica rápida)

- **Qué es el código:** una app web hecha con HTML, CSS y JavaScript "a mano" (sin frameworks pesados ni pasos de compilación). Se abre y funciona.
- **Cómo se guarda:** todo pasa por una única capa de datos (`SF.store`). Hoy usa el almacenamiento del navegador; **cambiarla por Supabase es un cambio contenido** que no obliga a rehacer las pantallas.
- **Dónde está cada cosa** (repositorio en GitHub, se publica solo en Vercel):
  - `index.html` — arranque.
  - `css/styles.css` — estilos.
  - `js/data.js` — datos y modelo (roles, jugadores de prueba, catálogos).
  - `js/store.js` — la capa de datos (crear/editar/guardar).
  - `js/ui.js` — piezas de interfaz (iconos, tarjetas, ventanas).
  - `js/pages.js` — todas las pantallas.
  - `js/router.js` — el menú y la navegación.
  - `database/auth_schema.sql` + `docs/AUTENTICACION_Y_PERMISOS.md` — el plan de la fase real (Supabase).
- **Objetivo del salto:** de "demo que guarda en el navegador" a "SaaS con login, base de datos y permisos reales" con Supabase.

---

_Este mapa refleja el estado actual del desarrollo. Cuando avancemos, se actualiza._
