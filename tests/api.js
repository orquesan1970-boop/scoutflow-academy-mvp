/* ============================================================================
   ScoutFlow Academy · Pruebas de las funciones de servidor (api/)
   ----------------------------------------------------------------------------
   Se ejecutan en Node, sin Vercel y sin gastar ni una llamada de IA: `fetch`
   se sustituye por uno falso que apunta a qué URL y qué cuerpo se habría
   mandado al proveedor, y devuelve una respuesta vacía.

   Comprueba lo que NO debe pasar:
     F0-01  Ninguna de las siete funciones de IA responde a un POST que no
            venga de la propia app (403).
     F0-02  Sin GEMINI_MODEL puesta, las siete usan un modelo vigente; un
            nombre retirado puesto por error en Vercel no se usa.
     F0-17  Al analizar un jugador, ni el Scout Score ni la disponibilidad
            (dato de salud) llegan al proveedor, aunque el navegador los mande.

   Uso: node tests/api.js
   ========================================================================== */
'use strict';
const path = require('path');
const { pathToFileURL } = require('url');
const C = require('./_comun');

const HOST = 'app.scoutflow-academy.com';
const FUNCIONES = {
  extraer: { texto: 'Martín Ríos, del 2010, juega de alero, mide 1,92' },
  analizar: { ficha: { nombre: 'Jugador de prueba', posicion: 'Base', altura_cm: 186 } },
  video: { cortes: [{ t: 10, titulo: 'Bloqueo directo' }, { t: 40, titulo: 'Contraataque' }], titulo: 'Partido de prueba' },
  'video-ia': { url: 'https://www.youtube.com/watch?v=dQw4w9WgXcQ', desde: 0, hasta: 60, modo: 'corte' },
  cuadrante: { tipo: 'texto', texto: 'Lunes 18:00-18:50 Cadete Especial, preparador Diego' },
  factura: { catalogo: [{ id: 'a1', label: 'Polo de paseo', tallas: ['M'] }], texto: 'Polo de paseo talla M x 3' },
  hojas: { texto: 'Ejercicio 1: rueda de tiro, 10 minutos', nombre: 'hoja.txt', mime: 'text/plain' }
};

/* Lo que se habría mandado a la IA. */
let enviados = [];
global.fetch = async (url, opts) => {
  enviados.push({ url: String(url), cuerpo: opts && opts.body ? String(opts.body) : '' });
  const vacio = JSON.stringify({ candidates: [{ content: { parts: [{ text: '{}' }] } }] });
  return { ok: true, status: 200, text: async () => vacio, json: async () => JSON.parse(vacio) };
};

function peticion(cuerpo, cabeceras) {
  return { method: 'POST', headers: Object.assign({ host: HOST }, cabeceras || {}), body: cuerpo };
}
function respuesta() {
  const r = { code: 200, body: null };
  r.status = c => { r.code = c; return r; };
  r.json = b => { r.body = b; return r; };
  r.setHeader = () => r;
  return r;
}
async function llama(nombre, req) {
  const mod = await import(pathToFileURL(path.join(C.ROOT, 'api', nombre + '.js')).href + '?t=' + Date.now() + Math.random());
  const res = respuesta();
  await mod.default(req, res);
  return res;
}
function limpiaEntorno() {
  ['GEMINI_API_KEY', 'ANTHROPIC_API_KEY', 'OPENAI_API_KEY', 'GEMINI_MODEL', 'GEMINI_VIDEO_MODEL',
   'ANTHROPIC_MODEL', 'OPENAI_MODEL', 'SF_API_ABIERTA'].forEach(k => { delete process.env[k]; });
}
function modeloDe(url) { const m = url.match(/models\/([^:]+):/); return m ? m[1] : null; }

(async () => {
  const m = C.marcador('Funciones api/');

  /* ---------- F0-01: nadie de fuera gasta la cuota ---------- */
  limpiaEntorno();
  process.env.GEMINI_API_KEY = 'clave-falsa';
  for (const f of Object.keys(FUNCIONES)) {
    enviados = [];
    const sin = await llama(f, peticion(FUNCIONES[f]));
    m.ok(sin.code === 403, 'F0-01 · ' + f + ': un POST sin Origin devuelve ' + sin.code + ' y debería ser 403');
    const otra = await llama(f, peticion(FUNCIONES[f], { origin: 'https://otra-web.example' }));
    m.ok(otra.code === 403, 'F0-01 · ' + f + ': un POST desde otra web devuelve ' + otra.code + ' y debería ser 403');
    m.ok(enviados.length === 0, 'F0-01 · ' + f + ': una petición de fuera llegó a llamar al proveedor');
    const casa = await llama(f, peticion(FUNCIONES[f], { origin: 'https://' + HOST }));
    m.ok(casa.code !== 403, 'F0-01 · ' + f + ': un POST desde la propia app no debería devolver 403');
  }
  /* El GET de cuadrante sigue abierto: no llama a ningún modelo. */
  const get = await (async () => {
    const mod = await import(pathToFileURL(path.join(C.ROOT, 'api', 'cuadrante.js')).href + '?g=' + Date.now());
    const res = respuesta(); await mod.default({ method: 'GET', headers: { host: HOST } }, res); return res;
  })();
  m.ok(get.code === 200 && get.body && get.body.ok, 'F0-01 · el GET de cuadrante (comprobación de vida) debe seguir respondiendo');

  /* ---------- F0-02: modelo vigente sin GEMINI_MODEL ---------- */
  const modelos = await import(pathToFileURL(path.join(C.ROOT, 'api', '_modelo.js')).href).catch(() => null);
  m.ok(!!modelos, 'F0-02 · existe api/_modelo.js con los modelos en un solo sitio');
  const RETIRADOS = /^gemini-(1\.0|1\.5|2\.0)/;
  for (const conModelo of [null, 'gemini-2.0-flash', 'gemini-3.8-flash']) {
    limpiaEntorno();
    process.env.GEMINI_API_KEY = 'clave-falsa';
    if (conModelo) process.env.GEMINI_MODEL = conModelo;
    for (const f of Object.keys(FUNCIONES)) {
      enviados = [];
      await llama(f, peticion(FUNCIONES[f], { origin: 'https://' + HOST }));
      const usados = enviados.map(e => modeloDe(e.url)).filter(Boolean);
      const etiqueta = 'F0-02 · ' + f + (conModelo ? ' con GEMINI_MODEL=' + conModelo : ' sin GEMINI_MODEL');
      m.ok(usados.length > 0, etiqueta + ': no llegó a llamar a Gemini');
      usados.forEach(u => m.ok(!RETIRADOS.test(u), etiqueta + ': usa ' + u + ', que está retirado'));
      if (conModelo === 'gemini-3.8-flash' && f !== 'video-ia')
        usados.forEach(u => m.ok(u === 'gemini-3.8-flash', etiqueta + ': debería usar el modelo puesto en Vercel y usa ' + u));
    }
  }
  if (modelos) {
    m.ok(!RETIRADOS.test(modelos.POR_DEFECTO.gemini), 'F0-02 · el modelo por defecto de Gemini no puede estar retirado');
    m.ok(/^\d{4}-\d{2}-\d{2}$/.test(modelos.REVISADO || ''), 'F0-02 · _modelo.js dice cuándo se revisó la lista (REVISADO)');
  }
  /* El GET de cuadrante dice qué modelo se usaría (F0-03 se comprueba así). */
  limpiaEntorno(); process.env.GEMINI_API_KEY = 'clave-falsa';
  const get2 = await (async () => {
    const mod = await import(pathToFileURL(path.join(C.ROOT, 'api', 'cuadrante.js')).href + '?h=' + Date.now());
    const res = respuesta(); await mod.default({ method: 'GET', headers: { host: HOST } }, res); return res;
  })();
  m.ok(get2.body && get2.body.modelo && !RETIRADOS.test(get2.body.modelo), 'F0-02 · el GET de cuadrante dice qué modelo usa: ' + (get2.body && get2.body.modelo));

  /* ---------- F0-17: el Score y la salud no salen del club ---------- */
  limpiaEntorno(); process.env.GEMINI_API_KEY = 'clave-falsa';
  enviados = [];
  const ficha = { nombre: 'Jugador de prueba', posicion: 'Base', score: '91 sobre 100',
    score_cobertura: '20 de 22 apartados', disponibilidad: 'No disponible · Sin saltos',
    evolucion: ['2024/2025: 1.80 m, score 70', '2025/2026: 1.86 m, score 91'], scout_score: 91 };
  await llama('analizar', peticion({ ficha: ficha }, { origin: 'https://' + HOST }));
  const cuerpo = enviados.map(e => e.cuerpo).join('\n');
  m.ok(enviados.length === 1, 'F0-17 · analizar debería llamar una vez al proveedor');
  m.ok(!/score/i.test(cuerpo), 'F0-17 · el Scout Score ha llegado al proveedor');
  m.ok(!/\b91\b/.test(cuerpo), 'F0-17 · el valor del Score (91) ha llegado al proveedor');
  m.ok(!/disponib|sin saltos/i.test(cuerpo), 'F0-17 · la disponibilidad (dato de salud) ha llegado al proveedor');
  m.ok(/1\.86 m/.test(cuerpo), 'F0-17 · la evolución sin Score sí debe llegar (1.86 m)');

  limpiaEntorno();
  m.fin();
})().catch(e => { console.error('FATAL', e); process.exit(1); });
