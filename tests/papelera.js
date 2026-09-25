/* ============================================================================
   ScoutFlow Academy · Editar, dar de baja y recuperar una ficha (F0-08)
   ----------------------------------------------------------------------------
   Lo que no debe pasar:
     · que un rol que no es dirección vea «Editar perfil» o «Dar de baja» en
       una ficha que no dio de alta él,
     · que dar de baja borre la ficha: tiene que poder recuperarse entera,
     · que la papelera se vea desde un rol que no tiene nada en ella,
     · que el borrado definitivo salga de un solo clic.

   Uso: node tests/papelera.js
   ========================================================================== */
'use strict';
const C = require('./_comun');

async function ficha(page, id) {
  await page.evaluate(x => { location.hash = '#/jugador/' + x; }, id);
  await page.waitForTimeout(200);
  return page.evaluate(() => ({ ed: !!document.querySelector('#view #ed'), del: !!document.querySelector('#view #del') }));
}

(async () => {
  const srv = await C.servidor();
  const browser = await C.navegador();
  const m = C.marcador('Bajas y papelera');

  /* --- Dirección: baja y recuperación --- */
  {
    const { ctx, page, errores } = await C.abrirComo(browser, srv.base, 'director', 'desk');
    const id = 'p2';
    const antes = await page.evaluate(x => ({ n: SF.store.players().length, p: JSON.stringify(SF.store.get(x)) }), id);
    const b = await ficha(page, id);
    m.ok(b.ed && b.del, 'dirección debería ver Editar y Dar de baja');
    await page.click('#view #del');
    await page.waitForTimeout(150);
    m.ok(await page.evaluate(() => !!document.querySelector('#sf-modal #bmot')), 'dar de baja debería pedir confirmación con motivo, sin confirm()');
    await page.fill('#sf-modal #bmot', 'Deja el club (prueba)');
    await page.click('#sf-modal [data-si]');
    await page.waitForTimeout(250);
    const tras = await page.evaluate(x => ({ n: SF.store.players().length, esta: !!SF.store.get(x), pap: SF.store.papelera().map(p => p.id),
      motivo: (SF.store.papelera()[0] || {}).baja && SF.store.papelera()[0].baja.motivo, hash: location.hash,
      boton: (document.querySelector('#papel') || {}).textContent || '' }), id);
    m.ok(tras.n === antes.n - 1 && !tras.esta, 'tras la baja la ficha no debería estar en la lista');
    m.ok(tras.pap.indexOf(id) >= 0, 'la ficha dada de baja debería estar en la papelera');
    m.ok(tras.motivo === 'Deja el club (prueba)', 'la baja debería guardar el motivo');
    m.ok(/Papelera \(1\)/.test(tras.boton), 'Jugadores debería enseñar «Papelera (1)» y enseña «' + tras.boton + '»');

    /* Sobrevive a una recarga (queda guardado, no solo en memoria) */
    await page.reload({ waitUntil: 'load' });
    await page.waitForFunction(() => window.SF && SF.store && document.getElementById('view'), null, { timeout: 30000 });
    m.ok(await page.evaluate(x => SF.store.papelera().some(p => p.id === x), id), 'la papelera debería seguir ahí tras recargar');

    await page.evaluate(() => { location.hash = '#/jugadores'; });
    await page.waitForTimeout(250);
    await page.click('#papel');
    await page.waitForTimeout(150);
    await page.click('#sf-modal [data-rec]');
    await page.waitForTimeout(200);
    const vuelta = await page.evaluate(x => { const p = SF.store.get(x); if (!p) return null; const c = Object.assign({}, p); delete c.bajas_previas;
      return { n: SF.store.players().length, p: JSON.stringify(c), previas: (p.bajas_previas || []).length, pos: SF.store.players().map(y => y.id).indexOf(x) }; }, id);
    m.ok(!!vuelta, 'la ficha recuperada debería volver a la lista');
    if (vuelta) {
      m.ok(vuelta.n === antes.n, 'tras recuperar debería haber los mismos jugadores que antes');
      m.ok(vuelta.p === antes.p, 'la ficha recuperada debería ser idéntica a la de antes');
      m.ok(vuelta.previas === 1, 'la ficha recuperada debería recordar su baja anterior');
      m.ok(vuelta.pos === 1, 'la ficha recuperada debería volver a su sitio (posición 1) y está en ' + vuelta.pos);
    }

    /* Borrado definitivo: dos clics */
    await page.evaluate(() => SF.ui.closeModal());
    await page.evaluate(x => SF.store.darDeBaja(x, { name: 'Prueba' }, 'para borrar'), 'p3');
    await page.evaluate(() => { location.hash = '#/jugadores'; SF.router.render(); });
    await page.waitForTimeout(200);
    await page.click('#papel');
    await page.waitForTimeout(150);
    await page.click('#sf-modal [data-borra]');
    m.ok(await page.evaluate(() => SF.store.papelera().some(p => p.id === 'p3')), 'un solo clic no debería borrar para siempre');
    await page.click('#sf-modal [data-borra]');
    await page.waitForTimeout(150);
    m.ok(await page.evaluate(() => !SF.store.papelera().some(p => p.id === 'p3') && !SF.store.get('p3')), 'el segundo clic debería borrar para siempre');
    errores.forEach(e => m.ok(false, 'director: error de JavaScript: ' + e.msg));
    await ctx.close();
  }

  /* --- Roles que no son dirección --- */
  for (const rol of ['entrenador', 'preparador_fisico', 'coord_pf', 'fisio', 'psicologo', 'administrativo', 'scout']) {
    const { ctx, page, errores } = await C.abrirComo(browser, srv.base, rol, 'desk');
    const ids = await page.evaluate(() => { const c = document.querySelector('.pcard'); return c ? [c.dataset.id] : []; });
    await page.evaluate(() => { location.hash = '#/jugadores'; });
    await page.waitForTimeout(200);
    const primero = await page.evaluate(() => { const c = document.querySelector('.pcard'); return c ? c.dataset.id : null; });
    if (primero) {
      const b = await ficha(page, primero);
      m.ok(!b.ed && !b.del, rol + ' no debería ver Editar ni Dar de baja en una ficha que no dio de alta');
    }
    m.ok(await page.evaluate(() => { location.hash = '#/jugadores'; return true; }) && !(await page.evaluate(() => !!document.querySelector('#papel'))), rol + ' no debería ver la papelera vacía');

    /* Quien puede dar de alta, gestiona lo que da de alta él */
    const puedeAlta = await page.evaluate(() => !!SF.perms().canCreatePlayers);
    if (puedeAlta) {
      const nuevo = await page.evaluate(() => SF.store.create({ first_name: 'Prueba', last_name: 'Alta Propia', birth_year: 2012, sport: 'baloncesto', status: 'Nuevo' }).id);
      const b = await ficha(page, nuevo);
      m.ok(b.ed && b.del, rol + ' debería poder editar y dar de baja la ficha que acaba de dar de alta');
    }
    errores.forEach(e => m.ok(false, rol + ': error de JavaScript: ' + e.msg));
    void ids;
    await ctx.close();
  }

  m.fin();
  await browser.close();
  await srv.cerrar();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
