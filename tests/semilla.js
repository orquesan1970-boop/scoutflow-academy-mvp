/* ============================================================================
   ScoutFlow Academy · Semilla sin datos reales, sin tocar al club real (F0-05)
   ----------------------------------------------------------------------------
   Lo que no debe pasar:
     1. Que en el repositorio haya nombres de personas reales. Los nombres que
        se buscan van codificados aquí (base64) para que este mismo archivo no
        cuente como positivo.
     2. Que un club NUEVO reciba esas personas en su semilla.
     3. Que un club que YA tiene sus datos (guardados con la versión anterior)
        vea cambiados sus jugadores o su staff al abrir la versión nueva.
        Para esto se usa el index.html del commit anterior sacado de git; si no
        hay git, esa parte se salta y se dice.

   Uso: node tests/semilla.js
   ========================================================================== */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const { execSync } = require('child_process');
const C = require('./_comun');

const REALES = ['UGFibG8gSWduYWNpbw==', 'QW5kcsOpcyBTdcOhcmV6', 'QW5kcmVzIFN1YXJleg==', 'VG9sw6k=', 'QWFyw7Nu', 'TWlndWVsIMOBbmdlbA==']
  .map(b => Buffer.from(b, 'base64').toString('utf8'));
const COMMIT_ANTERIOR = process.env.COMMIT_ANTERIOR || 'f58b03b';
const KEY = 'scoutflow:db:v2';

function archivos(dir, out) {
  for (const n of fs.readdirSync(dir)) {
    if (n === '.git' || n === 'node_modules') continue;
    const f = path.join(dir, n);
    const st = fs.statSync(f);
    if (st.isDirectory()) archivos(f, out);
    else if (st.size < 5e6 && /\.(html|js|json|md|sql|css|txt|yml)$/i.test(n)) out.push(f);
  }
  return out;
}

(async () => {
  const m = C.marcador('Semilla anónima');

  /* 1. Ningún nombre real en el repositorio */
  for (const f of archivos(C.ROOT, [])) {
    const t = fs.readFileSync(f, 'utf8');
    REALES.forEach(n => m.ok(t.indexOf(n) < 0, path.relative(C.ROOT, f) + ' contiene un nombre real (' + n.slice(0, 3) + '…)'));
  }

  const browser = await C.navegador();

  /* 2. Un club nuevo recibe solo gente inventada */
  const srv = await C.servidor();
  const nuevo = await C.abrirComo(browser, srv.base, 'director', 'desk');
  const semilla = await nuevo.page.evaluate(() => ({
    p1: (SF.store.get('p1') || {}).full_name,
    staff: SF.store.staff().filter(s => ['s4', 's23', 's25'].indexOf(s.id) >= 0).map(s => s.full_name),
    criterios: JSON.stringify(SF.store.academy().pf_criterios || [])
  }));
  m.ok(semilla.p1 === 'Lucas Ferreyra Gil', 'la ficha p1 de un club nuevo es «' + semilla.p1 + '»');
  REALES.forEach(n => {
    m.ok(semilla.staff.join('|').indexOf(n) < 0, 'el staff de un club nuevo lleva un nombre real');
    m.ok(semilla.criterios.indexOf(n) < 0, 'los criterios del cuadrante de un club nuevo llevan un nombre real');
  });
  m.ok(semilla.staff.length === 3, 'faltan preparadores en la semilla: ' + semilla.staff.join(', '));
  nuevo.errores.forEach(e => m.ok(false, 'error de JavaScript en club nuevo: ' + e.msg));
  await nuevo.ctx.close();

  /* 3. Un club con datos de la versión anterior no cambia */
  let viejo = null;
  try { viejo = execSync('git show ' + COMMIT_ANTERIOR + ':index.html', { cwd: C.ROOT, maxBuffer: 64e6 }); } catch (e) { viejo = null; }
  if (!viejo) {
    console.log('  (sin git: se salta la prueba del club con datos de la versión anterior)');
  } else {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'sf-anterior-'));
    fs.writeFileSync(path.join(dir, 'index.html'), viejo);
    const srvViejo = await C.servidor(dir);
    const a = await C.abrirComo(browser, srvViejo.base, 'director', 'desk');
    const guardado = await a.page.evaluate(k => localStorage.getItem(k), KEY);
    const antes = await a.page.evaluate(() => ({
      p1: (SF.store.get('p1') || {}).full_name,
      staff: SF.store.staff().filter(s => ['s4', 's23', 's25'].indexOf(s.id) >= 0).map(s => s.id + ':' + s.full_name).sort(),
      n: SF.store.players().length
    }));
    await a.ctx.close(); await srvViejo.cerrar();

    const ctx = await browser.newContext({ viewport: { width: 1366, height: 900 }, timezoneId: 'Europe/Madrid', locale: 'es-ES' });
    await ctx.addInitScript(([k, v]) => { if (!sessionStorage.getItem('__sf_prueba')) { localStorage.setItem(k, v); sessionStorage.setItem('__sf_prueba', '1'); } }, [KEY, guardado]);
    const page = await ctx.newPage();
    await page.route('**/cdn.jsdelivr.net/**', r => r.abort());
    const errs = [];
    page.on('pageerror', e => errs.push(String(e.message)));
    await page.goto(srv.base, { waitUntil: 'load' });
    await page.waitForFunction(() => window.SF && SF.store && document.getElementById('view'), null, { timeout: 30000 });
    const despues = await page.evaluate(() => ({
      p1: (SF.store.get('p1') || {}).full_name,
      staff: SF.store.staff().filter(s => ['s4', 's23', 's25'].indexOf(s.id) >= 0).map(s => s.id + ':' + s.full_name).sort(),
      n: SF.store.players().length
    }));
    m.ok(despues.p1 === antes.p1, 'la versión nueva ha cambiado la ficha p1 de un club con datos: «' + antes.p1 + '» → «' + despues.p1 + '»');
    m.ok(JSON.stringify(despues.staff) === JSON.stringify(antes.staff), 'la versión nueva ha cambiado el staff de un club con datos');
    m.ok(despues.n === antes.n, 'la versión nueva ha cambiado el número de jugadores: ' + antes.n + ' → ' + despues.n);
    errs.forEach(e => m.ok(false, 'error de JavaScript al abrir datos anteriores: ' + e));
    await ctx.close();
  }

  m.fin();
  await browser.close();
  await srv.cerrar();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
