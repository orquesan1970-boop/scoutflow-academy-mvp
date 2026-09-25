/* ============================================================================
   ScoutFlow Academy · Lo que sale del club al pedir «Analizar con IA» (F0-17)
   ----------------------------------------------------------------------------
   Abre la app como dirección, pide el análisis de un jugador evaluado y con
   una limitación puesta, y mira QUÉ manda el navegador a /api/analizar. La
   llamada se intercepta: no llega a ninguna IA.

   Lo que no debe pasar:
     · que el envío lleve el Scout Score (ni como campo ni dentro de la
       evolución),
     · que lleve la disponibilidad (dato de salud),
     · que el informe por reglas —el que sale cuando no hay IA y que también
       se puede enseñar a la familia— diga el Score.

   Uso: node tests/ia-ficha.js
   ========================================================================== */
'use strict';
const C = require('./_comun');

(async () => {
  const srv = await C.servidor();
  const browser = await C.navegador();
  const m = C.marcador('Ficha que se envía a la IA');

  for (const modo of ['ia', 'reglas']) {
    const { ctx, page, errores } = await C.abrirComo(browser, srv.base, 'director', 'desk');
    let enviado = null;
    await page.route('**/api/analizar', async r => {
      enviado = JSON.parse(r.request().postData() || '{}');
      const cuerpo = modo === 'ia'
        ? { ok: true, modelo: 'modelo-de-prueba', enviado: Object.keys(enviado.ficha || {}),
            informe: { resumen: 'Resumen de prueba.', fuerte: ['Uno'], mejorar: ['Dos'], faltan: [], siguiente: 'Tres' } }
        : { ok: false, motivo: 'sin_clave' };
      await r.fulfill({ status: 200, contentType: 'application/json', body: JSON.stringify(cuerpo) });
    });

    /* Un jugador con evaluaciones (tiene Score) y con una limitación puesta. */
    const jugador = await page.evaluate(() => {
      const p = SF.store.players().filter(x => SF.scoutScore(x) && (SF.evolucion(x) || []).length > 1)[0]
        || SF.store.players().filter(x => SF.scoutScore(x))[0];
      SF.store.update(p.id, { availability: Object.assign({}, p.availability || {}, {
        estado: 'limitada', limitacion: 'Sin saltos', desde: SF.hoyISO(), hasta: '', by: 'Prueba', role: 'fisio', at: new Date().toISOString() }) });
      return { id: p.id, nombre: p.full_name, score: SF.scoutScore(p).score };
    });

    await page.evaluate(() => { location.hash = '#/informes'; });
    await page.waitForTimeout(300);
    const pulsado = await page.evaluate(nombre => {
      const fila = Array.from(document.querySelectorAll('.att')).find(x => (x.querySelector('.att-name') || {}).textContent === nombre);
      if (!fila) return false;
      fila.querySelector('button').click();
      return true;
    }, jugador.nombre);
    m.ok(pulsado, 'no se encontró a ' + jugador.nombre + ' en Informes');
    await page.waitForTimeout(800);

    m.ok(!!enviado, modo + ': el navegador no llegó a llamar a /api/analizar');
    if (enviado) {
      const f = enviado.ficha || {};
      const texto = JSON.stringify(f);
      m.ok(!('score' in f) && !('score_cobertura' in f), modo + ': el envío lleva el campo score');
      m.ok(!/score/i.test(texto), modo + ': el envío menciona el Score: ' + texto.slice(0, 160));
      m.ok(!('disponibilidad' in f) && !/sin saltos/i.test(texto), modo + ': el envío lleva la disponibilidad (dato de salud)');
      m.ok(!!f.nombre && !!f.evaluacion, modo + ': el envío debería seguir llevando nombre y notas de evaluación');
    }
    const informe = await page.evaluate(() => (document.querySelector('#sf-modal') || {}).innerText || '');
    if (modo === 'reglas') {
      m.ok(/hecho por reglas/i.test(informe), 'reglas: no salió el informe por reglas');
      m.ok(!/score/i.test(informe.replace(/Asignar Scout Score/g, '')), 'reglas: el informe por reglas dice el Score');
      m.ok(informe.indexOf(String(jugador.score) + ' sobre 100') < 0, 'reglas: el informe por reglas lleva «' + jugador.score + ' sobre 100»');
    }
    errores.forEach(e => m.ok(false, modo + ': error de JavaScript: ' + e.msg));
    await ctx.close();
  }

  m.fin();
  await browser.close();
  await srv.cerrar();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
