# ScoutFlow Academy

CRM deportivo para academias y clubes de formación. Gestiona al jugador de
principio a fin: captación, admisión, seguimiento deportivo, documentación,
familias, personal y dinero.

**From Prospect to Player**

- Aplicación: <https://app.scoutflow-academy.com>, detrás de una contraseña
  (`SF_PASS`) mientras se construye. Vercel la publica sola desde la rama `main`.
- Web comercial: <https://scoutflow-academy.com> (carpeta `web/`, aparte de la app).
- Academia piloto: CBJA Academy · Product Owner: Jorge Andrés.

---

## Estado real, sin adornos (25/09/2026)

| Pieza | Estado |
|---|---|
| Aplicación | **Funciona.** 37 páginas, 17 roles, 22 capacidades, ficha de 14 pestañas. Recorrido automático: 714 pantallas, 0 errores |
| Acceso | **Real.** Correo y contraseña con Supabase Auth |
| Varios usuarios en un club | **Preparado** (Paso 2): el club es de sus miembros (`members`), se entra con un código de invitación y el rol lo dice el servidor. Falta confirmar que `paso2_multiusuario.sql` está ejecutado en el Supabase real (tarea F1-01) |
| Base de datos | **Real.** Supabase en Frankfurt. Una fila por jugador, persona del staff o equipo en `academy_docs`; el resto de listas, en bloque |
| Permisos | **Solo en el navegador.** En el servidor cualquier miembro puede todavía leer, cambiar y borrar todo el club. Lo cierra la Fase 1 |
| IA | **Real.** 7 funciones en `api/` con Gemini (alternativas: Claude y OpenAI). Solo responden a la propia app, pero todavía no saben quién llama ni tienen tope por usuario |
| Dónde corren las funciones | Frankfurt (`fra1`), igual que la base de datos |
| Fotos y archivos | **No.** Los documentos se registran, no se almacenan |
| Pagos online | **No.** Previsto, sin conectar |
| Correo y avisos al móvil | **No** |

El plan para llegar a producción, con sus 85 tareas, vive en el Project de
Claude («Estado de salida a producción»). Este README describe el código.

---

## Estructura

```text
index.html            LA APLICACIÓN ENTERA (~35.000 líneas, sin paso de compilación)
api/                  Funciones de servidor (Vercel), todas en Frankfurt
  _origen.js            valla: solo responde a peticiones de la propia app
  _modelo.js            qué modelo de IA usa cada proveedor, en un solo sitio
  extraer.js            lee un mensaje (WhatsApp, correo) y saca la ficha
  analizar.js           resumen de un jugador para dirección o su entrenador
  video.js              informe a partir de los cortes de vídeo marcados
  video-ia.js           la IA mira un tramo de un vídeo de YouTube
  cuadrante.js          lee un cuadrante de preparación física (foto, Excel, PDF)
  factura.js            lee un albarán y lo empareja con el catálogo de ropa
  hojas.js              lee la hoja de entrenamiento de un entrenador
database/             SQL de Supabase (ver abajo cuál manda)
tests/                Pruebas automáticas (no se publican: ver .vercelignore)
middleware.js         Puerta de contraseña de la web (deja fuera /api)
vercel.json           Región de las funciones (fra1) y caché
web/                  Web comercial, que se publica aparte
docs/                 Documentación por temas de agosto de 2026. Útil, pero
                      puede estar desfasada: el estado manda en el Project
```

Las carpetas `css/`, `js/`, `data/`, `config/`, `components/`, `pages/` y
`assets/` eran de la primera versión (junio) y **la app nunca las usó**. Se
retiraron el 25/09/2026 (tarea F0-11); una de ellas llevaba datos personales
reales.

### Dentro de `index.html`

| Bloque | Qué contiene |
|---|---|
| `<style>` | Todo el CSS y las variables de marca (morado `#6F5AEF`) |
| `js/data.js` | Semilla de ejemplo (todo inventado), 17 roles, 22 capacidades, ejercicios, planes, catálogos |
| `js/store.js` | `SF.store`: todas las operaciones sobre los datos y las migraciones (cada una con su bandera, corre una vez) |
| `js/ui.js` | Ventanas, avisos, iconos y la tarjeta de jugador |
| `js/pages.js` | Las 37 páginas |
| `js/router.js` | Menú, rutas por `#/` y control de acceso por rol |
| Nube | `SF.cloud`: login, partir y juntar filas, subida solo de lo que cambió, historial |
| `js/app.js` | Arranque: primero la nube, luego el router |

Los nombres `js/…` son etiquetas de bloque dentro del mismo archivo, no archivos.

### SQL: cuál manda

| Archivo | Qué es |
|---|---|
| `database/paso2_multiusuario.sql` | **El que manda hoy.** `academies`, `members`, `invitations`, `academy_docs`, sus reglas y funciones |
| `database/nube.sql` | Historial de versiones (`academy_data_historial`) |
| `database/schema_v3.sql` | El destino: el modelo por entidades (tarea F0-10). **No se ejecuta todavía** |
| `schema.sql`, `schema_completo.sql`, `SUPABASE_auth_v2.sql`, `PRUEBAS_RLS.sql` | Versiones anteriores, de referencia. No ejecutar |

---

## Trabajar en local

```bash
python3 -m http.server 8899   # y abrir http://localhost:8899
```

Sin conexión a Supabase la app entra en **modo local**: siembra sus datos de
ejemplo (todos inventados) y los guarda en el navegador. Se cambia de rol con
`SF.store.setRole('entrenador')` en la consola y recargando.

Las funciones de `api/` necesitan Vercel. Sin ellas la app no se cae: avisa y
usa el lector por reglas.

## Pruebas

```bash
cd tests && npm install && npx playwright install chromium && cd ..
node tests/todas.js
```

Qué comprueba cada una, en `tests/README.md`. **Un cambio no se publica si no
pasan**, y cada tarea añade su prueba de lo que no debe pasar.

## Publicar

**Nada va a `main` sin pasar antes por la rama `pruebas`** (tarea F0-14):

1. El cambio se sube a la rama **`pruebas`**. Vercel crea solo una **vista previa**
   con su propia dirección (la enlaza GitHub en el commit, en «Deployments»).
2. Se prueba en esa dirección: la app, el móvil y `/api/cuadrante`. La vista previa
   usa las mismas variables que producción solo si están marcadas también para
   *Preview* en Vercel.
3. Si está bien, **pull request de `pruebas` a `main`** y *Merge*. Vercel publica
   `main` en producción.

Después de publicar, se comprueba que lo publicado es exactamente lo probado,
**contra el commit**, no contra lo que dice la web:

```bash
git fetch origin main
git cat-file -p origin/main:index.html | cmp - index.html && echo "idéntico"
```

Y en el navegador, **Ctrl+F5**, porque sin eso sigue sirviendo la versión anterior.

Si algo sale mal, Vercel guarda los despliegues anteriores y deja volver a uno
con un clic (Deployments → el anterior → Promote to Production).

Comprobación rápida de que el servidor vive, sin gastar IA:
<https://app.scoutflow-academy.com/api/cuadrante> → `{"ok":true,"modelo":"…"}`.

## Variables de entorno (Vercel → Settings → Environment Variables)

| Variable | Para qué |
|---|---|
| `SF_PASS` / `SF_USER` | Contraseña de la web mientras se construye. **No tapa `/api/`**: las funciones se protegen solas con `api/_origen.js` |
| `GEMINI_API_KEY` | IA de Google. Es la primera que se busca, y la única que puede mirar vídeo |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | Alternativas para texto e imagen |
| `GEMINI_MODEL`, `GEMINI_VIDEO_MODEL`, `ANTHROPIC_MODEL`, `OPENAI_MODEL` | Opcionales. Si no están, manda `api/_modelo.js`. Un modelo retirado puesto aquí se ignora |
| `SF_API_ABIERTA=1` | Quita la valla de origen para probar con `curl`. Nunca en producción |

Los modelos se revisan cada mes contra las páginas de retiradas de cada
proveedor (enlaces en `api/_modelo.js`).

## Copias de seguridad

- **Configuración → Copias de seguridad** descarga el club entero con la fecha
  en el nombre, y avisa cuando hace más de 14 días de la última.
- Restaurar exige descargar antes lo que hay y dice qué trae antes de tocar nada.
- Con `database/nube.sql` ejecutado, la app guarda una versión al día (las diez
  últimas) y deja volver atrás.
- Las copias automáticas del propio Supabase llegan con su plan de pago (tarea F0-15).

## Lo que falta para producción

1. **Permisos en el servidor** (Fase 1): reglas por rol en Supabase para notas,
   sueldos, salud y familias; la sesión en cada llamada a `api/` y un tope de IA
   por usuario y club.
2. **Legal** (Fase 2): aviso legal, privacidad, encargo de tratamiento con el
   club, evaluación de impacto, delegado de protección del menor.
3. **Familias y móvil** (Fase 3): fotos y documentos en almacenamiento privado,
   correo, avisos al móvil.
4. **Cobro** (Fase 4) y **escala** (Fase 5).
