/* ============================================================================
   ScoutFlow Academy · Leer un cuadrante de preparación física
   ----------------------------------------------------------------------------
   Hermano de /api/extraer, pero en vez de un jugador lee una PARRILLA: la hoja
   semanal de preparación física que el club ya tiene hecha, venga como foto de
   WhatsApp, como Excel o como PDF.

   MISMA REGLA QUE ALLÍ: la clave de la IA vive en Vercel, nunca en el
   index.html, y funciona con el primer proveedor configurado:

     1) GEMINI_API_KEY      → Google Gemini   · lee imágenes y PDF
     2) ANTHROPIC_API_KEY   → Claude          · lee imágenes y PDF
     3) OPENAI_API_KEY      → OpenAI          · lee imágenes; PDF no

   LO QUE ESTE ENDPOINT NO HACE, Y ES A PROPÓSITO: no escribe nada. Devuelve lo
   que ha entendido y ya está. Quién es cada equipo, quién es cada preparador y
   si eso entra o no en el cuadrante lo decide una persona en la pantalla de
   revisión. Una hora mal leída en un cuadrante de PF es un equipo esperando en
   la pista con nadie delante, y eso no lo arregla ningún porcentaje de acierto.
   ========================================================================== */

const INSTRUCCIONES = [
  'Eres el asistente de un club de baloncesto. Te van a dar la hoja semanal de',
  'PREPARACIÓN FÍSICA: una parrilla con los días de la semana, las horas, el equipo',
  'y el preparador físico que se la da. Puede llegarte como foto de un papel, como',
  'captura de WhatsApp, como hoja de cálculo o como PDF.',
  '',
  'Devuelve UNA FILA POR SESIÓN. Nada más.',
  '',
  'REGLAS INNEGOCIABLES:',
  '1. Copia lo que pone. No deduzcas, no completes, no ordenes. Si una celda está',
  '   vacía, devuélvela nula. Un hueco se ve y se corrige; un dato inventado, no.',
  '2. Horas en formato 24 h "HH:MM". "19h", "7 de la tarde" o "19.00" son "19:00".',
  '   Si solo hay hora de inicio, deja hora_fin nula. No estimes la duración.',
  '3. hora_pista es la hora a la que el equipo SALTA A PISTA después de la',
  '   preparación física, si la hoja la trae en una columna aparte. Si no está,',
  '   nula. No la confundas con hora_ini ni con hora_fin.',
  '4. El nombre del equipo, TAL CUAL está escrito en la hoja, aunque venga',
  '   abreviado ("Cad Masc A", "INF FEM"). No lo traduzcas ni lo desarrolles: en',
  '   la app ya se empareja después con los equipos de verdad.',
  '5. El preparador, tal cual. Si la hoja usa COLORES por preparador y trae una',
  '   leyenda que dice qué color es cada uno, puedes usarla. Si no hay leyenda,',
  '   no adivines por el color: deja el preparador nulo.',
  '6. Días: "Lunes", "Martes", "Miércoles", "Jueves", "Viernes", "Sábado",',
  '   "Domingo". Si la hoja los agrupa y solo escribe el día en la primera fila,',
  '   repite ese día en las siguientes hasta que cambie.',
  '7. No metas filas que no sean sesiones: títulos, leyendas, totales, notas al',
  '   pie o celdas vacías no son sesiones.',
  '8. Si el documento no es un cuadrante de preparación física, pon sin_datos = true',
  '   y devuelve la lista vacía.'
].join('\n');

const CAMPOS = {
  dia: 'Día de la semana en español: Lunes, Martes, Miércoles, Jueves, Viernes, Sábado o Domingo',
  hora_ini: 'Hora de inicio de la preparación física, formato HH:MM en 24 h',
  hora_fin: 'Hora de fin de la preparación física, formato HH:MM en 24 h',
  hora_pista: 'Hora a la que el equipo salta a pista después, formato HH:MM, si la hoja la trae',
  equipo: 'Nombre del equipo tal cual está escrito en la hoja',
  preparador: 'Nombre del preparador físico tal cual está escrito, o nulo',
  pabellon: 'Pabellón o instalación, si aparece',
  pista: 'Pista o sala, si aparece',
  nota: 'Cualquier apunte de esa fila (contenido de la sesión, observación), si lo hay'
};
const CLAVES = Object.keys(CAMPOS);

/* --- Esquemas: una lista de sesiones, cada proveedor a su manera --- */
function esquemaOpenAI() {
  const props = {};
  CLAVES.forEach(k => { props[k] = { type: ['string', 'null'], description: CAMPOS[k] }; });
  return {
    type: 'object',
    properties: {
      sesiones: { type: 'array', items: { type: 'object', properties: props, required: CLAVES, additionalProperties: false } },
      sin_datos: { type: 'boolean', description: 'true si el documento no es un cuadrante de preparación física' }
    },
    required: ['sesiones', 'sin_datos'], additionalProperties: false
  };
}
function esquemaGemini() {
  const props = {};
  CLAVES.forEach(k => { props[k] = { type: 'STRING', nullable: true, description: CAMPOS[k] }; });
  return {
    type: 'OBJECT',
    properties: {
      sesiones: { type: 'ARRAY', items: { type: 'OBJECT', properties: props } },
      sin_datos: { type: 'BOOLEAN', description: 'true si el documento no es un cuadrante de preparación física' }
    }
  };
}
function esquemaClaude() {
  const props = {};
  CLAVES.forEach(k => { props[k] = { type: ['string', 'null'], description: CAMPOS[k] }; });
  return {
    type: 'object',
    properties: {
      sesiones: { type: 'array', items: { type: 'object', properties: props } },
      sin_datos: { type: 'boolean', description: 'true si el documento no es un cuadrante de preparación física' }
    },
    required: ['sesiones', 'sin_datos']
  };
}

/* El contenido llega de una de dos formas: texto (hoja de cálculo ya convertida
   en el navegador) o archivo en base64 (foto o PDF). */
function pideTexto(e) { return e.tipo === 'texto'; }

async function conGemini(e, key) {
  const modelo = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const parts = pideTexto(e)
    ? [{ text: e.texto }]
    : [{ inline_data: { mime_type: e.mime, data: e.datos } }, { text: 'Lee el cuadrante de preparación física de este documento.' }];
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: INSTRUCCIONES }] },
      contents: [{ role: 'user', parts: parts }],
      generationConfig: { temperature: 0, responseMimeType: 'application/json', responseSchema: esquemaGemini() }
    })
  });
  if (!r.ok) throw new Error('gemini ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const t = data.candidates && data.candidates[0] && data.candidates[0].content
    && data.candidates[0].content.parts && data.candidates[0].content.parts[0].text;
  if (!t) throw new Error('gemini: respuesta vacía');
  return { datos: JSON.parse(t), modelo: modelo };
}

async function conClaude(e, key) {
  const modelo = process.env.ANTHROPIC_MODEL || 'claude-haiku-4-5-20251001';
  let contenido;
  if (pideTexto(e)) contenido = e.texto;
  else if (e.mime === 'application/pdf') contenido = [
    { type: 'document', source: { type: 'base64', media_type: 'application/pdf', data: e.datos } },
    { type: 'text', text: 'Lee el cuadrante de preparación física de este documento.' }];
  else contenido = [
    { type: 'image', source: { type: 'base64', media_type: e.mime, data: e.datos } },
    { type: 'text', text: 'Lee el cuadrante de preparación física de esta imagen.' }];
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model: modelo, max_tokens: 4096, temperature: 0, system: INSTRUCCIONES,
      messages: [{ role: 'user', content: contenido }],
      tools: [{ name: 'cuadrante_pf', description: 'Devuelve las sesiones leídas', input_schema: esquemaClaude() }],
      tool_choice: { type: 'tool', name: 'cuadrante_pf' }
    })
  });
  if (!r.ok) throw new Error('claude ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const uso = (data.content || []).filter(c => c.type === 'tool_use')[0];
  if (!uso) throw new Error('claude: no usó la herramienta');
  return { datos: uso.input, modelo: modelo };
}

async function conOpenAI(e, key) {
  const modelo = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  if (!pideTexto(e) && e.mime === 'application/pdf') {
    throw new Error('Con OpenAI no se puede leer un PDF directamente. Sube una foto de la hoja, o pásalo a Excel.');
  }
  const contenido = pideTexto(e)
    ? e.texto
    : [{ type: 'text', text: 'Lee el cuadrante de preparación física de esta imagen.' },
       { type: 'image_url', image_url: { url: 'data:' + e.mime + ';base64,' + e.datos } }];
  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
    body: JSON.stringify({
      model: modelo, temperature: 0,
      messages: [{ role: 'system', content: INSTRUCCIONES }, { role: 'user', content: contenido }],
      response_format: { type: 'json_schema', json_schema: { name: 'cuadrante_pf', strict: true, schema: esquemaOpenAI() } }
    })
  });
  if (!r.ok) throw new Error('openai ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (msg && msg.refusal) throw new Error('openai rechazó: ' + msg.refusal);
  return { datos: JSON.parse(msg.content), modelo: modelo };
}

/* --- Limpieza. La estructura la garantiza el esquema; el sentido, no. --- */
const DIAS = ['lunes', 'martes', 'miercoles', 'jueves', 'viernes', 'sabado', 'domingo'];
function sinTildes(s) { return String(s || '').toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').trim(); }
function hora(h) {
  if (!h) return null;
  const m = String(h).match(/(\d{1,2})\s*[:.hH]\s*(\d{2})?/);
  if (!m) return null;
  const hh = +m[1], mm = +(m[2] || 0);
  if (hh > 23 || mm > 59) return null;
  return String(hh).padStart(2, '0') + ':' + String(mm).padStart(2, '0');
}
function limpia(s) {
  const dia = DIAS.indexOf(sinTildes(s.dia));
  const ini = hora(s.hora_ini), fin = hora(s.hora_fin);
  return {
    dia: dia >= 0 ? dia : null,
    dia_txt: s.dia || '',
    hora_ini: ini, hora_fin: fin, hora_pista: hora(s.hora_pista),
    equipo: (s.equipo || '').toString().trim(),
    preparador: (s.preparador || '').toString().trim(),
    pabellon: (s.pabellon || '').toString().trim(),
    pista: (s.pista || '').toString().trim(),
    nota: (s.nota || '').toString().trim()
  };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const b = req.body || {};
  const entrada = b.tipo === 'texto'
    ? { tipo: 'texto', texto: String(b.texto || '').slice(0, 40000) }
    : { tipo: 'archivo', mime: String(b.mime || ''), datos: String(b.datos || '') };

  if (entrada.tipo === 'texto' && !entrada.texto.trim()) return res.status(200).json({ ok: false, motivo: 'sin_texto' });
  if (entrada.tipo === 'archivo' && !entrada.datos) return res.status(200).json({ ok: false, motivo: 'sin_texto' });

  try {
    let r;
    if (gem) r = await conGemini(entrada, gem);
    else if (ant) r = await conClaude(entrada, ant);
    else r = await conOpenAI(entrada, oai);

    const d = r.datos || {};
    if (d.sin_datos) return res.status(200).json({ ok: true, sin_datos: true, sesiones: [], modelo: r.modelo });

    /* Una sesión sin equipo o sin hora de inicio no es una sesión: es una fila
       de adorno que se ha colado. Se cae aquí y no llega a la revisión. */
    const sesiones = (d.sesiones || []).map(limpia)
      .filter(s => s.equipo && s.hora_ini && s.dia !== null);

    return res.status(200).json({ ok: true, sesiones: sesiones, modelo: r.modelo, leidas: (d.sesiones || []).length });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
