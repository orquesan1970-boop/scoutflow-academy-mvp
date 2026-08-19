/* ============================================================================
   ScoutFlow Academy · Leer un mensaje y sacar los datos de un jugador
   ----------------------------------------------------------------------------
   POR QUÉ ESTO VIVE EN EL SERVIDOR:
   la clave de la IA NO puede estar en el index.html. Cualquiera que abriera la
   página podría leerla y gastar el crédito. Aquí se ejecuta en Vercel y la
   clave vive en una variable de entorno.

   FUNCIONA CON TRES PROVEEDORES. Usa el primero que encuentre configurado:

     1) GEMINI_API_KEY      → Google Gemini   · TIENE CAPA GRATUITA
     2) ANTHROPIC_API_KEY   → Claude          · de pago, por uso
     3) OPENAI_API_KEY      → OpenAI          · de pago, por uso

   Se configuran en Vercel → Settings → Environment Variables.
   Opcionales: GEMINI_MODEL, ANTHROPIC_MODEL, OPENAI_MODEL.

   Cambiar de proveedor es cambiar una variable. No hay que tocar código.
   Si no hay ninguna clave, no falla: avisa y la app tira del lector básico.
   ========================================================================== */

const CAMPOS = {
  first_name: 'Nombre de pila',
  last_name: 'Apellidos',
  birth_date: 'Fecha de nacimiento, formato AAAA-MM-DD',
  birth_year: 'Año de nacimiento, 4 cifras',
  primary_position: 'Posición principal. Solo una de: Base, Escolta, Alero, Ala-pívot, Pívot',
  secondary_position: 'Posición secundaria, misma lista',
  height_cm: 'Altura en centímetros, entero',
  weight_kg: 'Peso en kilos',
  nationality: 'Nacionalidades como NOMBRE DE PAÍS en español: "Serbia", "España", "Argentina". NUNCA el gentilicio ("serbio", "español")',
  city: 'Ciudad de residencia',
  residence_country: 'País de residencia',
  phone: 'Teléfono del jugador',
  email: 'Correo del jugador',
  club: 'Club en el que juega ahora',
  league: 'Liga o competición',
  category: 'Categoría: Mini, Infantil, Cadete, Junior...',
  school: 'Centro de estudios',
  course: 'Curso escolar',
  family_contact: 'Nombre del padre, madre o tutor',
  family_relation: 'Relación: Padre, Madre o Tutor',
  family_phone: 'Teléfono de la familia',
  family_email: 'Correo de la familia',
  objective: 'Qué busca el jugador o la familia',
  resumen: 'Una frase en español con lo que cuenta el mensaje'
};
const NUMERICOS = ['birth_year', 'height_cm', 'weight_kg'];
const CLAVES = Object.keys(CAMPOS);

const INSTRUCCIONES = [
  'Eres el asistente de una academia de baloncesto. Te van a pegar mensajes de WhatsApp,',
  'correos o notas sobre un jugador, escritos de forma informal y con faltas.',
  'Extrae SOLO los datos que aparecen de verdad en el texto.',
  '',
  'REGLAS INNEGOCIABLES:',
  '1. Si un dato no está, devuélvelo vacío o nulo. NO lo deduzcas ni lo inventes.',
  '   Es preferible un hueco a un dato inventado: esto es la ficha de un menor.',
  '2. No calcules lo que no está dicho. Si dan la edad pero no la fecha de nacimiento,',
  '   deja la fecha vacía.',
  '3. Alturas: "1.90", "190" o "un noventa" son 190.',
  '4. Posiciones: "uno" o "point guard" = Base; "dos" = Escolta; "tres" = Alero;',
  '   "cuatro" = Ala-pívot; "cinco" o "pivot" = Pívot.',
  '5. Nacionalidad: siempre el PAÍS, nunca el gentilicio. "es serbio" → "Serbia";',
  '   "argentino y español" → ["Argentina", "España"]. Si no, luego no se puede',
  '   agrupar ni filtrar, porque el resto de la ficha usa nombres de país.',
  '6. Si te dan solo el año ("es del 2011"), rellena birth_year y deja',
  '   birth_date vacío. No te inventes el día.',
  '7. Si el texto no habla de ningún jugador, pon sin_datos = true.',
  '8. No opines sobre el jugador ni valores su nivel. Solo extraes datos.'
].join('\n');

/* --- Esquemas, uno por proveedor: cada uno los pide a su manera --- */
function esquemaOpenAI() {
  const props = {};
  CLAVES.forEach(k => {
    if (k === 'nationality') props[k] = { type: ['array', 'null'], items: { type: 'string' }, description: CAMPOS[k] };
    else if (NUMERICOS.indexOf(k) >= 0) props[k] = { type: ['number', 'null'], description: CAMPOS[k] };
    else props[k] = { type: ['string', 'null'], description: CAMPOS[k] };
  });
  props.sin_datos = { type: 'boolean', description: 'true si el texto no habla de ningún jugador' };
  return { type: 'object', properties: props, required: Object.keys(props), additionalProperties: false };
}
function esquemaGemini() {
  const props = {};
  CLAVES.forEach(k => {
    if (k === 'nationality') props[k] = { type: 'ARRAY', items: { type: 'STRING' }, nullable: true, description: CAMPOS[k] };
    else if (NUMERICOS.indexOf(k) >= 0) props[k] = { type: 'NUMBER', nullable: true, description: CAMPOS[k] };
    else props[k] = { type: 'STRING', nullable: true, description: CAMPOS[k] };
  });
  props.sin_datos = { type: 'BOOLEAN', description: 'true si el texto no habla de ningún jugador' };
  return { type: 'OBJECT', properties: props };
}
function esquemaClaude() {
  const props = {};
  CLAVES.forEach(k => {
    if (k === 'nationality') props[k] = { type: ['array', 'null'], items: { type: 'string' }, description: CAMPOS[k] };
    else if (NUMERICOS.indexOf(k) >= 0) props[k] = { type: ['number', 'null'], description: CAMPOS[k] };
    else props[k] = { type: ['string', 'null'], description: CAMPOS[k] };
  });
  props.sin_datos = { type: 'boolean', description: 'true si el texto no habla de ningún jugador' };
  return { type: 'object', properties: props, required: ['sin_datos'] };
}

/* --- Una llamada por proveedor. Todas devuelven { campos, modelo } o lanzan --- */
async function conGemini(texto, key) {
  const modelo = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: INSTRUCCIONES }] },
      contents: [{ role: 'user', parts: [{ text: texto }] }],
      generationConfig: { temperature: 0, responseMimeType: 'application/json', responseSchema: esquemaGemini() }
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
      model: modelo, max_tokens: 1024, temperature: 0, system: INSTRUCCIONES,
      messages: [{ role: 'user', content: texto }],
      /* Se le obliga a contestar con la herramienta, que es la forma de que
         la respuesta venga con la estructura exacta y no en texto libre. */
      tools: [{ name: 'ficha_jugador', description: 'Devuelve los datos encontrados', input_schema: esquemaClaude() }],
      tool_choice: { type: 'tool', name: 'ficha_jugador' }
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
      model: modelo, temperature: 0,
      messages: [{ role: 'system', content: INSTRUCCIONES }, { role: 'user', content: texto }],
      response_format: { type: 'json_schema', json_schema: { name: 'ficha_jugador', strict: true, schema: esquemaOpenAI() } }
    })
  });
  if (!r.ok) throw new Error('openai ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (msg && msg.refusal) throw new Error('openai rechazó: ' + msg.refusal);
  return { campos: JSON.parse(msg.content), modelo: modelo };
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const texto = (req.body && req.body.texto ? String(req.body.texto) : '').slice(0, 8000);
  if (!texto.trim()) return res.status(200).json({ ok: false, motivo: 'sin_texto' });

  try {
    let r;
    if (gem) r = await conGemini(texto, gem);
    else if (ant) r = await conClaude(texto, ant);
    else r = await conOpenAI(texto, oai);

    const c = r.campos || {};
    /* Limpieza defensiva: la estructura viene garantizada, el sentido no. */
    if (c.height_cm && (c.height_cm < 100 || c.height_cm > 250)) c.height_cm = null;
    if (c.weight_kg && (c.weight_kg < 20 || c.weight_kg > 200)) c.weight_kg = null;
    if (c.birth_year && (c.birth_year < 1950 || c.birth_year > new Date().getFullYear())) c.birth_year = null;
    if (c.birth_date && !/^\d{4}-\d{2}-\d{2}$/.test(c.birth_date)) c.birth_date = null;
    if (c.nationality && !Array.isArray(c.nationality)) c.nationality = [String(c.nationality)];

    return res.status(200).json({ ok: true, campos: c, modelo: r.modelo });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
