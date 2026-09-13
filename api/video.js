/* ============================================================================
   ScoutFlow Academy · Informe a partir de los CORTES de un vídeo
   ----------------------------------------------------------------------------
   HERMANA DE analizar.js. Aquella resume una ficha; esta lee los cortes que el
   cuerpo técnico ha marcado en un partido y los ordena.

   LO QUE ESTE ENDPOINT NO HACE, Y CONVIENE QUE QUEDE ESCRITO AQUÍ:
   no ve el vídeo. No recibe imágenes, no recibe la URL del partido y no podría
   hacer nada con ella. Recibe TEXTO: el minuto de cada corte, su título, su
   etiqueta y la nota que escribió una persona que sí estaba mirando.

   Por eso el esquema de respuesta no tiene ratings, ni notas sobre 100, ni
   nada con decimales. Un modelo de lenguaje al que le pides una "nota táctica"
   te la da —siempre te la da— y parece medida. Sobre un menor en formación,
   eso no es un adorno de pantalla: es una decisión tomada con un número que
   nadie ha medido. Si algún día hay visión por computador de verdad, será otro
   endpoint y se llamará de otra forma.

   Mismos proveedores y mismas variables de entorno que analizar.js:
   GEMINI_API_KEY · ANTHROPIC_API_KEY · OPENAI_API_KEY.
   ========================================================================== */

/* Igual que en analizar.js: lo que llega se filtra aquí también, aunque el
   navegador ya lo haya filtrado. Dos cierres valen más que uno. */
const PROHIBIDO = /nota_interna|interna|econom|beca|presupuesto|salud|medic|lesion|diagn|alerg|sangre|telefono|movil|email|correo|dni|direccion|iban|banco|tutor|padre|madre|familia/i;

function limpiaTexto(v, max) {
  return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max || 300);
}

function limpiaCortes(arr) {
  return (Array.isArray(arr) ? arr : []).slice(0, 60).map(c => {
    const o = {};
    Object.keys(c || {}).forEach(k => {
      if (PROHIBIDO.test(k)) return;
      if (['tiempo', 'titulo', 'etiqueta', 'nota', 'jugador', 'dorsal',
           'cuarto', 'signo', 'con_balon', 'sin_balon', 'resultado'].indexOf(k) < 0) return;
      o[k] = limpiaTexto(c[k], k === 'nota' ? 500 : 120);
    });
    return o;
  }).filter(c => c.titulo || c.nota);
}

const INSTRUCCIONES = [
  'Eres el analista de una academia de baloncesto de formación. El cuerpo técnico',
  'ha visto un partido y ha marcado momentos concretos con una nota escrita a mano.',
  'Tu trabajo es ORDENAR eso: encontrar lo que se repite y convertirlo en trabajo',
  'para la semana.',
  '',
  'REGLAS, y son estrictas:',
  '1. NO HAS VISTO EL VÍDEO. Solo tienes las notas de quien sí lo vio. No describas',
  '   jugadas que no estén en las notas, no añadas detalles de lo que "seguramente"',
  '   pasó, y no completes lo que falte. Si las notas no dan para un apartado, di',
  '   que no dan.',
  '2. Nada de números inventados. Ni notas sobre 10 o sobre 100, ni porcentajes, ni',
  '   ratings, ni estadísticas. No tienes con qué calcularlos. Puedes contar cuántos',
  '   cortes hablan de lo mismo, porque eso sí está delante de ti.',
  '3. Es un menor en formación. Nada de sentencias sobre su techo ni comparaciones',
  '   con jugadores profesionales.',
  '4. Habla de lo corregible: lo que se entrena el martes. "Mejorar la lectura" no',
  '   es una tarea; "repetir salidas de bloqueo leyendo al defensor del pasador" sí.',
  '5. Español de España, tono sobrio, frases cortas. Nada de lenguaje de folleto.',
  '6. Como mucho tres puntos por apartado. Menos y mejor.'
].join('\n');

function esquemaGemini() {
  return {
    type: 'OBJECT',
    properties: {
      resumen: { type: 'STRING', description: 'Dos o tres frases: qué cuentan estos cortes en conjunto.' },
      repetido: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Lo que aparece en varios cortes, diciendo en cuántos.' },
      bien: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Lo que las notas señalan como acierto.' },
      trabajar: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Tareas concretas de entrenamiento para esta semana.' },
      revisar: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Qué cortes conviene volver a ver con el jugador, por su minuto.' }
    }
  };
}
function esquemaJSON() {
  return {
    type: 'object',
    properties: {
      resumen: { type: 'string' },
      repetido: { type: 'array', items: { type: 'string' } },
      bien: { type: 'array', items: { type: 'string' } },
      trabajar: { type: 'array', items: { type: 'string' } },
      revisar: { type: 'array', items: { type: 'string' } }
    },
    required: ['resumen', 'repetido', 'bien', 'trabajar', 'revisar'],
    additionalProperties: false
  };
}

async function conGemini(texto, key) {
  const modelo = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: INSTRUCCIONES }] },
      contents: [{ role: 'user', parts: [{ text: texto }] }],
      generationConfig: { temperature: 0.2, responseMimeType: 'application/json', responseSchema: esquemaGemini() }
    })
  });
  if (!r.ok) throw new Error('gemini ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const t = data.candidates && data.candidates[0] && data.candidates[0].content
    && data.candidates[0].content.parts && data.candidates[0].content.parts[0].text;
  if (!t) throw new Error('gemini: respuesta vacía');
  return { campos: JSON.parse(t), modelo: modelo };
}

async function conClaude(texto, key) {
  const modelo = process.env.ANTHROPIC_MODEL || 'claude-haiku-4-5-20251001';
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model: modelo, max_tokens: 1400, temperature: 0.2, system: INSTRUCCIONES,
      messages: [{ role: 'user', content: texto }],
      tools: [{ name: 'informe', description: 'Devuelve el informe de los cortes', input_schema: esquemaJSON() }],
      tool_choice: { type: 'tool', name: 'informe' }
    })
  });
  if (!r.ok) throw new Error('claude ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const uso = (data.content || []).filter(c => c.type === 'tool_use')[0];
  if (!uso) throw new Error('claude: no usó la herramienta');
  return { campos: uso.input, modelo: modelo };
}

async function conOpenAI(texto, key) {
  const modelo = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
    body: JSON.stringify({
      model: modelo, temperature: 0.2,
      messages: [{ role: 'system', content: INSTRUCCIONES }, { role: 'user', content: texto }],
      response_format: { type: 'json_schema', json_schema: { name: 'informe', strict: true, schema: esquemaJSON() } }
    })
  });
  if (!r.ok) throw new Error('openai ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (msg && msg.refusal) throw new Error('openai rechazó: ' + msg.refusal);
  return { campos: JSON.parse(msg.content), modelo: modelo };
}

import { mismaCasa, fueraDeCasa } from './_origen.js';

/* CUÁNTO SE LE DEJA TARDAR. Por defecto Vercel corta una función a los 10
   segundos y devuelve un error que no explica nada. Proponer los cortes de un partido puede pasar de ahi.
   Si el plan de Vercel no permite este tope, el despliegue lo avisa. */
export const config = { maxDuration: 30 };

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });
  /* Solo responde a nuestra propia app: esto gasta cuota. */
  if (!mismaCasa(req)) return fueraDeCasa(res);

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const b = req.body || {};
  const cortes = limpiaCortes(b.cortes);
  if (cortes.length < 2) return res.status(200).json({ ok: false, motivo: 'sin_datos' });

  /* El contexto del partido: lo justo para que el informe se entienda. Nada
     de la URL del vídeo: no le sirve de nada y no tiene por qué salir. */
  const ctx = [
    b.titulo ? 'Partido o vídeo: ' + limpiaTexto(b.titulo, 200) : '',
    b.tipo ? 'Tipo: ' + limpiaTexto(b.tipo, 60) : '',
    b.fecha ? 'Fecha: ' + limpiaTexto(b.fecha, 20) : '',
    b.rival ? 'Rival: ' + limpiaTexto(b.rival, 120) : '',
    b.competicion ? 'Competición: ' + limpiaTexto(b.competicion, 120) : '',
    b.equipo ? 'Equipo: ' + limpiaTexto(b.equipo, 120) : '',
    b.jugador ? 'El informe es sobre: ' + limpiaTexto(b.jugador, 160) : ''
  ].filter(Boolean).join('\n');

  const texto = ctx + '\n\nCORTES MARCADOS POR EL CUERPO TÉCNICO (' + cortes.length + '):\n' +
    cortes.map((c, i) => {
      const partes = [(i + 1) + '.', '[' + (c.tiempo || '?') + (c.cuarto ? ' ' + c.cuarto : '') + ']'];
      if (c.jugador) partes.push(c.jugador + (c.dorsal ? ' (#' + c.dorsal + ')' : '') + ' —');
      if (c.titulo) partes.push(c.titulo);
      if (c.etiqueta) partes.push('{' + c.etiqueta + '}');
      if (c.signo) partes.push('(' + c.signo + ')');
      if (c.con_balon) partes.push('· Con balón: ' + c.con_balon);
      if (c.sin_balon) partes.push('· Sin balón: ' + c.sin_balon);
      if (c.resultado) partes.push('· Resultado: ' + c.resultado);
      if (c.nota) partes.push('· Nota: ' + c.nota);
      return partes.join(' ');
    }).join('\n');

  try {
    let r;
    if (gem) r = await conGemini(texto, gem);
    else if (ant) r = await conClaude(texto, ant);
    else r = await conOpenAI(texto, oai);

    const c = r.campos || {};
    const lista = x => (Array.isArray(x) ? x : []).filter(Boolean).map(s => String(s).slice(0, 300)).slice(0, 4);
    return res.status(200).json({
      ok: true,
      informe: {
        resumen: String(c.resumen || '').slice(0, 900),
        repetido: lista(c.repetido),
        bien: lista(c.bien),
        trabajar: lista(c.trabajar),
        revisar: lista(c.revisar)
      },
      modelo: r.modelo,
      cortes: cortes.length
    });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
