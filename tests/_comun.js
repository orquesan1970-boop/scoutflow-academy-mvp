/* ============================================================================
   ScoutFlow Academy · Piezas comunes de las pruebas
   ----------------------------------------------------------------------------
   Un servidor estático mínimo (sirve el index.html del repositorio) y el
   arranque del navegador. Las pruebas NO tocan Supabase ni ninguna IA: se
   bloquea el CDN de supabase-js y la app entra en MODO LOCAL, sembrando sus
   datos de ejemplo. Así se puede probar todo sin claves y sin datos reales.

   Chromium: el de Playwright (`npx playwright install chromium`) o el que se
   indique en CHROMIUM_PATH.
   ========================================================================== */
'use strict';
const fs = require('fs');
const http = require('http');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');

const ROLES = ['director', 'dt_general', 'dt_femenino', 'dt_masculino', 'dt_escuelas', 'dt_minis',
  'coord_pf', 'entrenador', 'preparador_fisico', 'delegado_equipo', 'delegado_campo', 'fisio',
  'psicologo', 'scout', 'administrativo', 'padre', 'jugador'];

const RUTAS = ['inicio', 'tablon', 'agenda', 'mi-equipo', 'jugadores', 'equipos', 'horarios',
  'calendario', 'sesiones', 'captacion', 'importar', 'importar-datos', 'informes', 'video',
  'documentos', 'licencias', 'tramites', 'tienda', 'staff', 'adjuntos', 'family', 'comunicados',
  'finanzas', 'presupuesto', 'economia', 'sueldos', 'permisos', 'config', 'mis-avisos', 'mi-ficha',
  'portal-family', 'portal-jugador', 'buscar', 'inscripcion'];

function servidor(raiz) {
  const BASE_DIR = raiz || ROOT;
  const tipos = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.json': 'application/json',
    '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png' };
  const srv = http.createServer((q, r) => {
    let p = decodeURIComponent(q.url.split('?')[0]);
    if (p === '/') p = '/index.html';
    const f = path.join(BASE_DIR, p);
    if (!f.startsWith(BASE_DIR)) { r.writeHead(403); r.end(); return; }
    fs.readFile(f, (e, d) => {
      if (e) { r.writeHead(404); r.end(); return; }
      r.writeHead(200, { 'Content-Type': tipos[path.extname(f)] || 'application/octet-stream' });
      r.end(d);
    });
  });
  return new Promise(res => srv.listen(0, '127.0.0.1', () => {
    res({ base: 'http://127.0.0.1:' + srv.address().port + '/', cerrar: () => new Promise(ok => srv.close(ok)) });
  }));
}

async function navegador() {
  const { chromium } = require('playwright');
  const opts = {};
  if (process.env.CHROMIUM_PATH) opts.executablePath = process.env.CHROMIUM_PATH;
  return chromium.launch(opts);
}

/* Abre la app como un rol, en modo local, y devuelve la página y sus errores. */
async function abrirComo(browser, base, rol, vista) {
  const size = vista === 'mob' ? { width: 390, height: 844 } : { width: 1366, height: 900 };
  const ctx = await browser.newContext({ viewport: size, timezoneId: process.env.TZ_PRUEBA || 'Europe/Madrid', locale: 'es-ES' });
  const page = await ctx.newPage();
  await page.route('**/cdn.jsdelivr.net/**', r => r.abort());
  await page.route(/youtube|ytimg|googleapis|gstatic/, r => r.abort());
  const errores = [];
  page.on('pageerror', e => errores.push({ ruta: page.url().split('#')[1] || '', msg: String(e.message).slice(0, 200) }));
  page.on('console', m => {
    if (m.type() === 'error' && !/jsdelivr|favicon|ERR_FAILED|net::|Failed to load resource/.test(m.text()))
      errores.push({ ruta: page.url().split('#')[1] || '', msg: m.text().slice(0, 200) });
  });
  await page.goto(base, { waitUntil: 'load' });
  await page.waitForFunction(() => window.SF && SF.store && document.getElementById('view'), null, { timeout: 30000 });
  await page.evaluate(r => { SF.store.setRole(r); }, rol);
  await page.goto(base + '?r=' + rol, { waitUntil: 'load' });
  await page.waitForFunction(() => document.getElementById('view') && document.getElementById('view').innerText.length > 0, null, { timeout: 30000 });
  await page.keyboard.press('Escape');
  await page.waitForTimeout(200);
  await page.evaluate(() => document.querySelectorAll('.modal-back,.modal-bg').forEach(x => x.remove()));
  return { ctx, page, errores };
}

/* Resultado de una prueba: se acumulan los fallos y se sale con código 1 si hay alguno. */
function marcador(nombre) {
  const fallos = [];
  let n = 0;
  return {
    ok(cond, texto) { n++; if (!cond) fallos.push(texto); },
    fin() {
      if (fallos.length) {
        console.log('\n✗ ' + nombre + ': ' + fallos.length + ' de ' + n + ' comprobaciones fallan');
        fallos.slice(0, 60).forEach(f => console.log('  - ' + f));
        process.exitCode = 1;
      } else {
        console.log('✓ ' + nombre + ': ' + n + ' comprobaciones');
      }
      return fallos.length;
    }
  };
}

module.exports = { ROOT, ROLES, RUTAS, servidor, navegador, abrirComo, marcador };
