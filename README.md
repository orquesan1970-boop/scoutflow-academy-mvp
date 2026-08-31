# ScoutFlow Academy

CRM deportivo para academias y clubes de formación. Gestiona el jugador de
principio a fin: captación, admisión, seguimiento deportivo, documentación,
familias, personal y dinero.

**From Prospect to Player**

- Aplicación: <https://app.scoutflow-academy.com> · desplegada por Vercel desde
  este repositorio, rama `main`
- Academia piloto: CBJA Academy — 277 jugadores, 27 equipos
- Product Owner: Jorge Andrés

---

## Estado real, sin adornos

| Pieza | Estado |
|---|---|
| Aplicación | **Funcionando.** ~20 secciones, 17 roles |
| Acceso | **Real.** Correo y contraseña (Supabase Auth) |
| Base de datos | **Real.** Supabase, servidor de Frankfurt (UE) |
| Guardado en la nube | **Real.** Automático, con respaldo local si se cae la red |
| IA (leer mensajes, analizar fichas, leer cuadrantes) | **Real.** Gemini / Claude / OpenAI, la que esté configurada |
| Historial de versiones | **Real**, si se ejecuta `database/nube.sql` |
| Varios usuarios en un mismo club | **No.** Una cuenta = un club (Paso 2, pendiente) |
| Permisos en el servidor | **No.** Los roles se aplican en el navegador |
| Pagos online | **No.** Stripe está previsto, no conectado |
| Subida de archivos a la nube | **No.** Los documentos se registran, no se almacenan |

### Lo que hay que saber antes de tocar nada

**La aplicación entera es `index.html`.** Un solo archivo, sin paso de
compilación: se edita y se sube. Las carpetas `css/`, `js/` y `data/` son de la
primera versión y **la aplicación no las usa** — están para no romper enlaces
antiguos. Si editas ahí, no cambia nada. Se irán retirando.

**Una cuenta = un club.** Cada correo registrado tiene su propio club. Si entra
otra persona con otro correo, no ve este club: ve uno vacío.

**El rol se elige en un desplegable**, no viene del servidor. Sirve para probar
y para el piloto; **no es seguridad**. Hasta que los permisos vivan en Supabase
(RLS), esto es un piloto de una persona, no una aplicación para todo el club.

---

## Estructura

```text
index.html            LA APLICACIÓN ENTERA (~18.000 líneas)
api/                  Funciones de servidor (Vercel)
  extraer.js            lee un mensaje y saca los datos del jugador
  analizar.js           analiza una ficha y propone el siguiente paso
  cuadrante.js          lee un cuadrante de preparación física (foto o Excel)
middleware.js         Contraseña de acceso a todo el dominio (ver abajo)
database/
  nube.sql              LAS TABLAS QUE USA LA APP HOY. Empieza por aquí
  schema_completo.sql   El modelo relacional al que se quiere llegar
  SUPABASE_auth_v2.sql  Autenticación y permisos por fila (Paso 2)
  PRUEBAS_RLS.sql       Comprobaciones de que los permisos aíslan de verdad
docs/                 Documentación por temas: roles, permisos, familia, menores
web/                  Borrador de la web comercial (aparte de la aplicación)
css/ js/ data/        De la primera versión. LA APP NO LOS USA
```

## Trabajar en local

Doble clic en `index.html` y funciona: los datos se guardan en el navegador
(`localStorage`) y no tocan la nube. Es el sitio para trastear sin miedo.

Con servidor local, que es lo recomendable:

```bash
python3 -m http.server 8899   # y abrir http://localhost:8899
```

Las funciones de `api/` **no funcionan en local** (necesitan Vercel). Sin ellas,
la aplicación no se cae: avisa y tira del lector básico.

## Publicar

Subir `index.html` a la rama `main` y Vercel despliega solo, en un par de
minutos. Después conviene comprobar que lo subido es lo que se quería:

```bash
git fetch origin main
git show origin/main:index.html | cmp - index.html && echo "idéntico"
```

## Variables de entorno (Vercel → Settings → Environment Variables)

| Variable | Para qué |
|---|---|
| `SF_PASS` | Contraseña de acceso a todo el dominio, **incluidas las funciones de IA**. Mientras exista, nadie entra sin ella. Es lo único que hoy impide que alguien de fuera gaste las claves de IA |
| `SF_USER` | Usuario de esa contraseña (por defecto `cbja`) |
| `GEMINI_API_KEY` | IA de Google. Tiene capa gratuita — es la primera que se busca |
| `ANTHROPIC_API_KEY` | IA de Anthropic (de pago por uso) |
| `OPENAI_API_KEY` | IA de OpenAI (de pago por uso) |

Se usa la primera clave de IA que esté configurada. Cambiar de proveedor es
cambiar una variable: no hay que tocar código.

> **Antes de quitar `SF_PASS`** para abrir la aplicación a familias y personal,
> hay que proteger las funciones de `api/` con la sesión de Supabase y un límite
> por usuario. Hoy están abiertas: lo único que las tapa es esa contraseña.

## Copias de seguridad

Supabase, en el plan contratado, **no hace copias** ("Last backup: No backups"),
y el club se guarda como una sola fila que se pisa en cada guardado.

- **Configuración → Copias de seguridad** descarga el club entero con la fecha
  en el nombre, y avisa cuando hace más de 14 días de la última.
- Restaurar **exige** descargar antes lo que hay, revisa el archivo y dice qué
  trae antes de tocar nada.
- Ejecutando `database/nube.sql` se activa el historial: una versión al día,
  las diez últimas, y volver atrás desde la propia aplicación.

## Qué falta para dejar de ser un piloto

1. Academias compartidas: varias personas en un mismo club, con invitaciones.
2. Que el rol venga del perfil del usuario y desaparezca el desplegable.
3. Permisos aplicados en el servidor (RLS), no solo escondiendo botones.
4. Migrar el JSON único al modelo relacional de `schema_completo.sql`.
5. Proteger las funciones de IA con sesión y límites de uso.
6. Pruebas automáticas de acceso, permisos, guardado, importación y finanzas.
