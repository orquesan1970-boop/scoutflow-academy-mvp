# Pruebas automáticas de ScoutFlow Academy

Estas pruebas comprueban, sobre todo, **lo que no debe pasar**: que un rol vea lo que no le toca,
que un dato sensible salga hacia la IA, que una función gaste cuota a petición de cualquiera o que
un cambio rompa una pantalla. Cada tarea de la salida a producción deja aquí su prueba.

No tocan Supabase ni ninguna IA. La app se abre en **modo local** (se bloquea el CDN de
`supabase-js`) y siembra sus datos de ejemplo, que son todos inventados. Las llamadas a `api/`
se hacen en Node con un `fetch` falso que no sale a internet.

## Cómo se ejecutan

Hace falta Node 18 o superior. La primera vez:

```bash
cd tests
npm install
npx playwright install chromium
cd ..
```

Y luego, desde la raíz del repositorio:

```bash
node tests/todas.js        # todas (unos 4 minutos)
node tests/recorrido.js    # solo el recorrido de roles
VP=desk ROLES=director,entrenador node tests/recorrido.js   # un trozo
```

Si ya tienes un Chromium instalado, `CHROMIUM_PATH=/ruta/a/chrome` evita descargarlo.

## Qué hay

| Archivo | Qué comprueba | Tarea |
|---|---|---|
| `api.js` | Las 7 funciones de IA devuelven 403 a quien no es la app; usan un modelo vigente aunque falte o esté mal `GEMINI_MODEL`; el Score y la disponibilidad no llegan al proveedor | F0-01, F0-02, F0-17 |
| `semilla.js` | Ningún nombre real en el repositorio; un club nuevo recibe solo gente inventada; un club con datos de la versión anterior no ve cambiado nada | F0-05 |
| `ia-ficha.js` | Lo que manda el navegador al pulsar «Analizar» no lleva Score ni disponibilidad, y el informe por reglas no dice el Score | F0-17 |
| `papelera.js` | Solo dirección y quien dio de alta ven «Editar perfil» y «Dar de baja»; la baja se recupera entera; el borrado definitivo pide dos pasos | F0-08 |
| `recorrido.js` | Los 17 roles por todas sus pantallas en 1366×900 y 390×844: 0 errores de JavaScript, ninguna puerta cerrada, 0 Scores para quien no tiene permiso, botones de la ficha según permiso, ningún desborde nuevo en móvil | F0-07, F0-08, F0-09 |
| `_comun.js` | Servidor local, arranque del navegador y marcador de resultados | — |

## Reglas

- **Una prueba nueva tiene que fallar con el código anterior y pasar con el nuevo.** Si pasa en los
  dos, no está probando el cambio.
- Los desbordes en móvil que ya se conocen (Family, Documentos y la ficha del scout, tarea F3-07)
  se informan pero no rompen la prueba. Uno nuevo, sí.
- Nada de datos reales aquí dentro. Si una prueba necesita buscar un nombre real, va codificado
  (ver `semilla.js`).
- Estas pruebas no se publican con la app: `.vercelignore` deja fuera la carpeta `tests/`.

## Lo que todavía no prueban

Las reglas de acceso **en Supabase** (que un entrenador no pueda leer notas internas desde la
consola). Hoy los permisos se deciden en el navegador; cuando la Fase 1 los lleve al servidor,
la tarea F1-12 añade aquí esas pruebas con una cuenta por rol.
