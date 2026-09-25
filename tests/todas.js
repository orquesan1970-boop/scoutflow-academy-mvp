/* ============================================================================
   ScoutFlow Academy · Todas las pruebas, una detrás de otra
   ----------------------------------------------------------------------------
   Uso (desde la raíz del repositorio):
     node tests/todas.js
   Sale con código 1 si falla cualquiera. Tarda unos 4 minutos, casi todo en
   el recorrido de los 17 roles en escritorio y en móvil.
   ========================================================================== */
'use strict';
const { spawnSync } = require('child_process');
const path = require('path');

const PRUEBAS = [
  ['api.js', 'Funciones de servidor: origen, modelo de IA, qué sale hacia la IA'],
  ['semilla.js', 'Semilla sin datos reales y sin tocar al club real'],
  ['ia-ficha.js', 'Lo que manda el navegador al analizar un jugador'],
  ['papelera.js', 'Editar, dar de baja y recuperar una ficha'],
  ['recorrido.js', 'Los 17 roles por todas sus pantallas, escritorio y móvil']
];

let fallos = 0;
const t0 = Date.now();
for (const [archivo, que] of PRUEBAS) {
  console.log('\n── ' + archivo + ' · ' + que);
  const r = spawnSync(process.execPath, [path.join(__dirname, archivo)], { stdio: 'inherit', env: process.env });
  if (r.status !== 0) fallos++;
}
console.log('\n' + (fallos ? '✗ ' + fallos + ' de ' + PRUEBAS.length + ' pruebas fallan' : '✓ Las ' + PRUEBAS.length + ' pruebas pasan') +
  ' (' + Math.round((Date.now() - t0) / 1000) + ' s)');
process.exit(fallos ? 1 : 0);
