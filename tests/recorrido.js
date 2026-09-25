/* ============================================================================
   ScoutFlow Academy · Recorrido de los 17 roles
   ----------------------------------------------------------------------------
   Abre la app como cada rol y entra en todas las pantallas que ese rol puede
   abrir, en escritorio (1366×900) y en móvil (390×844). Es la versión guardada
   del recorrido de la auditoría del 23/09/2026 (claude_08), convertida en
   prueba: si algo de lo que NO debe pasar pasa, sale con código 1.

   Comprueba:
     · 0 errores de JavaScript en consola.
     · Ningún rol aterriza en «tu rol no tiene acceso».
     · Scout Score: ni tarjetas, ni tabla, ni cabecera, ni historial para
       quien no tiene `canSeeScore` (F0-07).
     · «Editar perfil» y «Dar de baja»: solo dirección y quien dio de alta esa
       ficha (F0-08).
     · Desbordes horizontales nuevos en 390 px (los conocidos, F3-07, se
       informan pero no fallan).

   Uso:
     cd tests && npm install && npx playwright install chromium && cd ..
     node tests/recorrido.js                     # los 17 roles, escritorio y móvil
     VP=desk ROLES=director,entrenador node tests/recorrido.js
   ========================================================================== */
'use strict';
const fs = require('fs');
const os = require('os');
const path = require('path');
const C = require('./_comun');

const ROLES = process.env.ROLES ? process.env.ROLES.split(',') : C.ROLES;
const VISTAS = process.env.VP ? process.env.VP.split(',') : ['desk', 'mob'];
const DIRECCION = ['director', 'dt_general', 'dt_femenino', 'dt_masculino', 'dt_escuelas', 'dt_minis'];

/* Desbordes en móvil que ya se conocen y tienen su tarea (F3-07). Se
   informan, pero no rompen la prueba: lo que la rompe es uno NUEVO. */
const DESBORDES_CONOCIDOS = { family: true, documentos: true, licencias: true };
const DESBORDES_FICHA_CONOCIDOS = { scout: true };

(async () => {
  const srv = await C.servidor();
  const browser = await C.navegador();
  const m = C.marcador('Recorrido de roles');
  const salida = [];
  let pantallas = 0;

  for (const vista of VISTAS) {
    for (const rol of ROLES) {
      const { ctx, page, errores } = await C.abrirComo(browser, srv.base, rol, vista);
      const rec = { rol, vista, rutas: {}, desbordes: [] };

      const aterriza = await page.evaluate(() => ({
        hash: location.hash,
        cerrada: /no tiene acceso/i.test(document.getElementById('view').innerText)
      }));
      rec.aterriza = aterriza.hash;
      m.ok(!aterriza.cerrada, rol + ' (' + vista + ') aterriza en una puerta cerrada: ' + aterriza.hash);

      for (const rt of C.RUTAS) {
        const puede = await page.evaluate(x => SF.router.puede(x), rt);
        if (!puede) continue;
        await page.evaluate(x => { location.hash = '#/' + x; }, rt);
        await page.waitForTimeout(100);
        const info = await page.evaluate(() => {
          const v = document.getElementById('view');
          return { len: v.innerText.length, sinAcceso: /no tiene acceso/i.test(v.innerText),
            over: Math.max(0, document.documentElement.scrollWidth - window.innerWidth) };
        });
        pantallas++;
        rec.rutas[rt] = info;
        m.ok(!info.sinAcceso, rol + ' puede abrir #/' + rt + ' pero sale «no tiene acceso»');
        if (vista === 'mob' && info.over > 2) {
          rec.desbordes.push(rt + ' +' + info.over);
          m.ok(!!DESBORDES_CONOCIDOS[rt], rol + ' (móvil) desborda ' + info.over + ' px en #/' + rt + ' (nuevo)');
        }
      }

      /* ---- Jugadores: el Scout Score solo para quien puede verlo ---- */
      if (await page.evaluate(() => SF.router.puede('jugadores'))) {
        await page.evaluate(() => { location.hash = '#/jugadores'; });
        await page.waitForTimeout(200);
        const tarjetas = await page.evaluate(() => {
          const cs = Array.from(document.querySelectorAll('.pcard'));
          return { n: cs.length, conScore: cs.filter(c => /\d/.test((c.querySelector('.pcard-score') || {}).innerText || '')).length,
            puede: !!SF.perms().canSeeScore };
        });
        rec.tarjetas = tarjetas;
        if (!tarjetas.puede) m.ok(tarjetas.conScore === 0, rol + ' no tiene canSeeScore y ve el Score en ' + tarjetas.conScore + ' tarjetas');

        /* Vista de tabla */
        const tabla = await page.evaluate(() => {
          const b = document.getElementById('vt'); if (!b) return null;
          b.click();
          const th = Array.from(document.querySelectorAll('table.tbl th')).map(x => x.textContent.trim().toLowerCase());
          const celdas = Array.from(document.querySelectorAll('table.tbl tbody td:last-child')).filter(td => /^\d+$/.test(td.textContent.trim())).length;
          const ok = { columna: th.indexOf('score') >= 0, celdas: celdas };
          document.getElementById('vg').click();
          return ok;
        });
        if (tabla && !tarjetas.puede) m.ok(!tabla.columna, rol + ' no tiene canSeeScore y la tabla tiene columna Score (' + tabla.celdas + ' valores)');

        /* ---- Ficha del primer jugador visible ---- */
        const primero = await page.evaluate(() => { const c = document.querySelector('.pcard'); return c ? c.dataset.id : null; });
        if (primero) {
          await page.evaluate(id => { location.hash = '#/jugador/' + id; }, primero);
          await page.waitForTimeout(250);
          const ficha = await page.evaluate(({ id, direccion }) => {
            const v = document.getElementById('view');
            const p = SF.store.get(id);
            const r = SF.perms();
            const me = SF.store.staffMe();
            return {
              editar: !!v.querySelector('#ed'), baja: !!v.querySelector('#del'),
              scoreCabecera: /Score/.test((v.querySelector('.fh-tags') || {}).innerText || ''),
              puedeScore: !!r.canSeeScore,
              esperaBotones: direccion.indexOf(SF.store.role()) >= 0 ||
                (!!r.canCreatePlayers && !!me && p.created_by_staff_id === me.id)
            };
          }, { id: primero, direccion: DIRECCION });
          rec.ficha = ficha;
          m.ok(ficha.editar === ficha.esperaBotones, rol + ': «Editar perfil» ' + (ficha.editar ? 'visible' : 'oculto') + ' y debería estar ' + (ficha.esperaBotones ? 'visible' : 'oculto'));
          m.ok(ficha.baja === ficha.esperaBotones, rol + ': «Dar de baja» ' + (ficha.baja ? 'visible' : 'oculto') + ' y debería estar ' + (ficha.esperaBotones ? 'visible' : 'oculto'));
          if (!ficha.puedeScore) m.ok(!ficha.scoreCabecera, rol + ' ve el Score en la cabecera de la ficha');

          const ntabs = await page.evaluate(() => document.querySelectorAll('.tabs .tab').length);
          for (let i = 0; i < ntabs; i++) {
            const t = await page.evaluate(i => {
              const b = document.querySelectorAll('.tabs .tab')[i]; b.click();
              return b.innerText.trim();
            }, i);
            await page.waitForTimeout(60);
            const pest = await page.evaluate(() => {
              const body = document.querySelector('.tab-body');
              return { score: /\bScore\s+\d|Scout Score\s*\d|\d+\s*\/\s*100/.test(body ? body.innerText : ''),
                over: Math.max(0, document.documentElement.scrollWidth - window.innerWidth) };
            });
            pantallas++;
            if (!ficha.puedeScore) m.ok(!pest.score, rol + ' ve un Score en la pestaña ' + t);
            if (vista === 'mob' && pest.over > 2) {
              rec.desbordes.push('ficha/' + t + ' +' + pest.over);
              m.ok(!!DESBORDES_FICHA_CONOCIDOS[rol], rol + ' (móvil) desborda ' + pest.over + ' px en la pestaña ' + t + ' (nuevo)');
            }
          }
        }
      }

      rec.errores = errores;
      errores.forEach(e => m.ok(false, rol + ' (' + vista + ') error de JavaScript en #' + e.ruta + ': ' + e.msg));
      salida.push(rec);
      console.log(vista + ' · ' + rol + ': ' + Object.keys(rec.rutas).length + ' rutas, ' + errores.length + ' errores' +
        (rec.tarjetas ? ', ' + rec.tarjetas.n + ' tarjetas (' + rec.tarjetas.conScore + ' con Score)' : '') +
        (rec.desbordes.length ? ', desbordes: ' + rec.desbordes.join(' ') : ''));
      await ctx.close();
    }
  }

  const f = path.join(os.tmpdir(), 'scoutflow-recorrido-' + VISTAS.join('-') + '.json');
  fs.writeFileSync(f, JSON.stringify(salida, null, 1));
  console.log(pantallas + ' pantallas. Detalle en ' + f);
  m.fin();
  await browser.close();
  await srv.cerrar();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
