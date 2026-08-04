# Repaso — roles Familia y Jugador

**Fecha:** 2026-08-02 · **Auditado contra:** `ROL_FAMILIA.md`, `ROL_JUGADOR.md`, `auth_schema.sql`, `AUTENTICACION_Y_PERMISOS.md` y el portal actual de la app.

> Este documento es una revisión crítica, no un resumen. Está para encontrar fallos, no para tranquilizar.

---

## 1. Dónde estamos

Dos roles especificados de once. Cero líneas de código escritas. Eso está bien: el plano va delante.

Lo que **sí** está sólido y no hace falta volver a discutir:

- El modelo de identidad / rol / alcance / permisos está bien separado y aguanta.
- La decisión de no guardar documentos quita de encima el mayor riesgo del producto.
- El tablón de avisos en dos tablas resuelve de raíz el "que nadie vea a nadie".
- La edad calculada y no almacenada evita el error clásico de mantener un `es_mayor` a mano.
- La copia obligatoria a tutores está blindada en la base de datos, no en la pantalla.

---

## 2. Decisiones cerradas

| # | Decisión | Fecha |
|---|---|---|
| 1 | La app **no guarda documentos**. Solo entregado / pendiente | 02-08 |
| 2 | De salud, solo **fecha de revisión y apto**. Caduca por temporada | 02-08 |
| 3 | Datos sensibles de custodia, **fuera de la app** | 02-08 |
| 4 | La **foto del jugador** sí se sube desde la cámara. Única subida que queda | 02-08 |
| 5 | El estado de entrega lo marca **solo el club** | 02-08 |
| 6 | Notificación al móvil: **siempre "Notificación del club"** | 02-08 |
| 7 | **Una sola autorización de imagen** (web + redes + prensa) | 02-08 |
| 8 | Responder es obligatorio; **aceptar no**. El "no" no bloquea la inscripción | 02-08 |
| 9 | Cuentas de jugador: **las activa el club por equipo** | 02-08 |
| 10 | A los 18, el acceso de los tutores **sigue solo si el jugador lo confirma** | 02-08 |
| 11 | El jugador menor **no ve informes** | 02-08 |
| 12 | **No es un chat.** Tablón de avisos en un sentido | 02-08 |
| 13 | Los jugadores **no se ven entre sí** | 02-08 |
| 14 | **Visto / no visto** y **Iré / No puedo**. Sin texto libre | 02-08 |

Catorce decisiones cerradas en una sesión. Eso es mucho terreno ganado, y también el motivo de que haya contradicciones que limpiar: los documentos se escribieron mientras las decisiones cambiaban.

---

## 3. Errores encontrados

### 3.1 Graves — en el esquema que YA existe

> **Estado: corregidos en `SUPABASE_auth_v2.sql`.** Ese archivo sustituye a `auth_schema.sql` y a `auth_schema_fixes.sql`. Es el único que hay que ejecutar. Pendiente de aplicar en Supabase.
>
> **E7 · Escalada de privilegios (el más grave de todos).** La política `profile_update_self` de v1 era `for update using (id = auth.uid())`, sin restricción de columnas. Cualquier padre podía ejecutar `update users_profile set role = 'director'` y **convertirse en director del club**: ver notas internas, presupuestos, economía y las fichas de los mil jugadores. Corregido con un *trigger* que bloquea el cambio de rol, academia y segmento a quien no sea director.
>
> **E6 · Un jugador invitado no vería nada.** `app_accept_invitation` metía el rol `jugador` por la rama de staff: le asignaba el rol pero nunca creaba su fila en `player_access`. Entraría a una app vacía, sin ningún error visible que explicara por qué.
>
> **E8 · Fuga entre academias.** El `with check` de `finance_write` no comprobaba el alcance: alguien con `manage_finance` podía insertar cuotas de un jugador de **otra academia**. En un SaaS multi-club, eso es cruzar datos entre clientes.
>
> **E9 · Cualquiera escribía en el muro de cualquier equipo.** `team_messages_insert` solo comprobaba `author_id = auth.uid()`, sin mirar el equipo.

Estos están hoy en `auth_schema.sql` y romperían el portal el día que se conecte Supabase.

**E0 · El jugador sería personal del club.** *(descubierto al escribir el parche)*
`app_is_staff()` está definida como `app_role() <> 'padre'`. En cuanto exista el rol `jugador`, **cualquier jugador pasaría el filtro de staff**: podría editar fichas, ver medidas físicas de otros y colarse por todas las políticas que solo comprueban "es personal". Es más grave que E1 y estaba oculto a plena vista.
*Arreglo: `app_role() not in ('padre','jugador')`.*

**E1 · El jugador sería tutor de sí mismo.**
`app_is_guardian(pid)` devuelve `true` para cualquier fila de `player_access`. Si el jugador se enlaza por esa tabla, hereda permisos de tutor — entre ellos `finance_select`. Un menor de catorce vería sus cuotas y su deuda.
*Arreglo: filtrar por `relation in ('Padre','Madre','Tutor')` y añadir `app_is_self()`. Cinco líneas. Debe hacerse **antes** de crear la primera cuenta de jugador.*

**E2 · La familia no puede guardar su IBAN.**
`players_update` exige `app_is_staff()`. La app le enseña el formulario, la base de datos rechaza el guardado. Fallo silencioso y desconcertante para el usuario.

**E3 · Una familia puede autovalidarse los documentos.**
`documents_rw` es un `for all` que solo comprueba el alcance. Un padre podría marcar su propio pasaporte como validado, o borrar filas.

**E4 · El calendario del equipo no tiene RLS.**
`team_messages` está protegido; `team_events` no. Queda abierto.

**E5 · Datos bancarios y de salud dentro de `players`.**
Todo el cuerpo técnico lee `players`. Hoy un entrenador de minis vería el IBAN de sus familias. Hay que sacarlos a `family_billing` y `player_medical`.

### 3.2 Graves — errores míos, ya corregidos

Los pongo porque conviene que quede constancia de que el plano también se revisa.

**E6 · Un padre con dos hijos en el mismo equipo perdía uno.**
La clave primaria de `announcement_targets` era `(announcement_id, user_id)`. Un aviso al equipo genera una fila por hijo, y con esa clave la segunda chocaba y se descartaba. El padre habría visto un solo aviso y solo habría podido confirmar la asistencia de un hijo. En un club con hermanos, esto pasa el primer mes.
*Corregido: la clave incluye `player_id`.*

**E7 · Un usuario podía reasignarse un aviso.**
La política de `update` sobre `announcement_targets` comprobaba `user_id = auth.uid()`, pero no restringía **qué columnas** se pueden tocar. Alguien podría haberse cambiado el `player_id` o el `as_role` de 'tutor' a 'jugador'.
*Corregido: `revoke update` general y `grant update` solo sobre las cuatro columnas de respuesta.*

### 3.3 Contradicciones entre documentos — ya corregidas

**E8 · `ROL_FAMILIA.md` seguía describiendo mensajería con respuestas.**
El bloque "Comunicaciones" describía una tabla `communications` con `audience` y `visible_to_family`, y decía que la familia podía responder. Quedó obsoleto en cuanto decidiste que no era un chat, pero seguía escrito en cuatro sitios: el mapa de pantallas, el bloque 4.9, la tabla de huecos y el orden de implementación.
*Corregido en los cuatro. El diseño de `communications` queda anulado.*

### 3.4 Medios — sin resolver

| # | Qué | Dónde |
|---|---|---|
| **E9** | `consents` dice "nunca se actualiza" pero no se revocan los privilegios `update`/`delete`. Una regla escrita que nadie hace cumplir | FAMILIA §2.1 |
| **E10** | `player_medical` no tiene clave primaria definida. Debe ser `(player_id, season)`, o habrá dos aptos de la misma temporada | FAMILIA §4.4 |
| **E11** | **Quién firma entre los 14 y los 17.** El documento explica que a los 14 el menor ya puede consentir, pero no dice quién firma en la práctica: ¿el tutor, el menor, los dos? Es un hueco real de diseño | FAMILIA §2.1 |
| **E12** | Las autorizaciones firmadas por un tutor **caducan a los 18**, pero la tabla `consents` no tiene mecanismo para marcarlas caducadas | JUGADOR §6 |
| **E13** | La política de `player_medical` contempla "staff o tutor". Falta el **jugador mayor de edad** viendo lo suyo, que sí debe poder | FAMILIA §4.4 |
| **E14** | En `family_todo`, "autorización sin firmar" no distingue **"no ha contestado"** de **"ha contestado que no"**. El segundo no es una tarea pendiente | FAMILIA §4.2 |
| **E15** | No está escrito **cómo se generan los destinatarios de un aviso de equipo cuando un jugador no tiene cuenta.** Deben crearse solo las filas de sus tutores. Obvio, pero sin escribir no se implementa | JUGADOR §5 |

---

## 4. Huecos: lo que ni siquiera hemos tocado

Esto es lo que más me preocupa del repaso. No son errores; son temas enteros que no aparecen en ningún documento.

### 4.1 Conservación y borrado de datos

**Ningún documento dice qué pasa cuando un jugador deja el club.** ¿Se borra su ficha? ¿Se conserva? ¿Cuánto? ¿Y sus fotos, sus avisos, sus consentimientos?

El RGPD obliga a tener una política de conservación: no puedes guardar datos de un menor indefinidamente porque sí. Y a la vez hay obligaciones fiscales que te obligan a conservar los pagos varios años. Son plazos distintos para datos distintos, y eso hay que diseñarlo.

**Es el hueco más grande que tenemos.**

### 4.2 Derechos del interesado

Acceso, rectificación, supresión, oposición, portabilidad. Una familia tiene derecho a pedir todo lo que el club guarda de su hijo, en formato legible, y el club tiene un plazo para responder.

No hay ni pantalla, ni procedimiento, ni siquiera una mención. Y ya salió de refilón con el Scout Score: un jugador mayor de edad puede pedir por escrito sus evaluaciones internas.

### 4.3 Brecha de seguridad

Si un día se filtran datos, hay 72 horas para notificar a la AEPD. Sin procedimiento escrito, ese plazo se pasa. Es organizativo más que técnico, pero forma parte de lo que un club te va a preguntar.

### 4.4 Idioma

En tus propios datos de prueba hay jugadores de Colombia, Argentina y México, y el producto nace con vocación internacional. **Los dos documentos asumen que todo el mundo lee español.** Con familias extranjeras, el portal en un solo idioma es una barrera real — y las autorizaciones firmadas en un idioma que no entiendes son jurídicamente flojas.

### 4.5 Auditoría de accesos

Con datos de menores conviene registrar **quién ha consultado qué**. Hoy no hay ninguna tabla de log. Si un día hay una denuncia sobre el uso indebido de datos de un menor, la única respuesta posible es "no lo sé".

### 4.6 Impago

¿Qué pasa con el acceso de una familia que deja de pagar? ¿Se le corta el portal? ¿Ve solo la deuda? Es una decisión de producto con consecuencias legales — cortarle el acceso a sus propios datos por impago es discutible.

### 4.7 Multi-club

El producto nace para venderse a varios clubes. No hemos pensado: una familia con hijos en **dos clubes distintos** del mismo SaaS, o un jugador que **cambia de club**. Con el modelo actual, `users_profile.academy_id` es único: esa familia necesitaría dos cuentas.

### 4.8 Plan de pruebas de RLS — ✅ RESUELTO

Escrito en `PRUEBAS_RLS.sql`. Once pruebas, cada una atada a un fallo real encontrado hoy: el padre que no debe ver al hijo de otro, el jugador que no debe ser staff, el padre que no debe poder ascenderse a director, el aviso a un menor que debe copiarse a sus tutores, el hermano que no debe perderse.

Se ejecuta entero en el editor SQL de Supabase, va dentro de una transacción que se deshace al final —no deja datos de prueba— y termina diciendo `=== TODAS LAS PRUEBAS PASAN ===` o se para en la primera que falle.

### 4.9 Familias sin app

Pregunta abierta desde el primer documento y sin responder. Existen, y más de lo que parece.

---

## 5. Documentos del proyecto que han quedado desactualizados

| Documento | Qué dice que ya no vale |
|---|---|
| `MAPA_DEL_PROYECTO.md` | "Documentos: subida real pendiente" · "muro de comunicación" del equipo |
| `AUTENTICACION_Y_PERMISOS.md` | No menciona el rol `jugador`, ni el fallo de `app_is_guardian`, ni el nuevo permiso `manage_medical` |
| `auth_schema.sql` | La semilla de `role_permissions` no incluye `jugador` ni `manage_medical` |
| **Instrucciones del proyecto** | Sección 13: "cámara integrada obligatoria para pasaporte, DNI, documentos y certificados" — **revertido**. Sección 12: la matriz de roles no tiene Jugador ni las reglas de menor/mayor |

> Las instrucciones del proyecto son la fuente de verdad del sistema. Conviene actualizarlas tú, o dentro de dos sesiones alguien construirá la cámara de documentos que acabamos de eliminar.

---

## 6. Decisiones abiertas, consolidadas

De los dos documentos, ordenadas por lo que bloquean.

| # | Decisión | Bloquea |
|---|---|---|
| 1 | **¿Quién firma los consentimientos entre 14 y 17 años?** | La tabla `consents` |
| 2 | **¿Firma de ambos progenitores** para imagen pública, o basta con uno? | La pantalla de inscripción |
| 3 | **Política de conservación:** ¿cuánto se guarda tras la baja de un jugador? | Todo el modelo de datos |
| 4 | **PWA o app nativa** | La arquitectura del portal |
| 5 | **`can_pay`:** ¿pagan padre y madre indistintamente? | Finanzas y la transición a los 18 |
| 6 | **¿La inscripción la rellena la familia** o la carga administración? | El formulario público |
| 7 | **Familias sin app:** ¿qué vía alternativa? | El diseño del proceso |
| 8 | **¿Se corta el acceso por impago?** | Reglas de negocio |
| 9 | **¿El jugador mayor de edad ve su Scout Score?** | La ficha del jugador |
| 10 | **¿Bloquear cuenta de jugador a petición del tutor?** | El interruptor por equipo |
| 11 | **¿Política de privacidad y contrato de encargado redactados?** | Vender a cualquier club |

---

## 7. Qué haría ahora, por orden

1. **Arreglar E1–E5 en `auth_schema.sql`.** Son cinco parches sobre lo ya escrito y desbloquean todo lo demás. Ninguno cuesta más de veinte líneas.
2. **Cerrar las decisiones 1, 3 y 5**, que son las que condicionan tablas.
3. **Escribir el guion de pruebas de RLS** antes que las tablas nuevas. Definir cómo se comprueba obliga a pensar los casos límite.
4. **Especificar el rol Entrenador**, que es quien escribe los avisos y sin el cual el tablón no tiene emisor.
5. **Actualizar las instrucciones del proyecto** con las catorce decisiones cerradas.

---

_Repaso cerrado el 2026-08-02. Siguiente: rol Entrenador._
