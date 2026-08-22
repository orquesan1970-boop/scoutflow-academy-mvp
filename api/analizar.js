/* ============================================================================
   ScoutFlow Academy · Resumen de un jugador escrito por la IA
   ----------------------------------------------------------------------------
   HERMANA DE extraer.js. Aquella LEE un mensaje y saca datos; esta COGE los
   datos que ya tenemos y escribe el resumen que un director lee antes de
   llamar a una familia.

   LO QUE NO LLEGA AQUÍ, Y POR QUÉ:
   el navegador compone el envío campo a campo y deja fuera las notas
   internas, la situación económica de la familia, los antecedentes médicos y
   los datos de contacto. No hace falta ninguno para escribir un resumen
   deportivo, y son justo los que no deben salir del club.

   Aun así, este archivo NO se fía: vuelve a filtrar por su cuenta (ver
   LIMPIAR). Dos cierres valen más que uno, porque el día que alguien toque el
   navegador y se olvide, aquí sigue puesto.

   Mismos proveedores y mismas variables de entorno que extraer.js.
   ========================================================================== */

/* Campos que este endpoint acepta. Cualquier otra cosa que llegue se tira
   antes de mandarla a ningún sitio. */
const PERMITIDOS = [
  'nombre', 'anio', 'edad', 'posicion', 'posicion_2', 'altura_cm', 'peso_kg',
  'envergadura_cm', 'mano', 'usa_dos_manos', 'equipo', 'categoria', 'club',
  'liga', 'estado', 'anios_en_el_club', 'score', 'score_cobertura',
  'evaluacion', 'evolucion', 'documentos_pendientes', 'disponibilidad',
  'nacionalidades', 'curso', 'idioma_ingles', 'objetivo', 'edad_de_inicio',
  'trayectoria', 'selecciones', 'proxima_cita'
];

/* Palabras que delatan que alguien ha metido donde no debía. Si aparecen en
   una clave, ese campo no sale del servidor. */
const PROHIBIDO = /nota|interna|econom|beca|presupuesto|salud|medic|lesion|diagn|alerg|sangre|telefono|movil|email|correo|dni|direccion|iban|banco|tutor|padre|madre|familia/i;

function limpiar(ficha) {
  const out = {};
  Object.keys(ficha || {}).forEach(k => {
    if (PERMITIDOS.indexOf(k) < 0) return;
    if (PROHIBIDO.test(k)) return;
    const v = ficha[k];
    if (v === null || v === undefined || v === '') return;
    /* Nada de objetos anidados con sorpresas: solo texto, números y listas
       de texto. Un objeto puede traer dentro cualquier cosa. */
    if (typeof v === 'object' && !Array.isArray(v)) return;
    if (Array.isArray(v)) out[k] = v.slice(0, 40).map(x => String(x).slice(0, 200));
    else out[k] = String(v).slice(0, 400);
  });
  return out;
}

const INSTRUCCIONES = [
  'Eres el analista de una academia de baloncesto de formación. Te dan la ficha',
  'deportiva de un jugador y escribes un resumen breve para su director o su',
  'entrenador, que lo va a leer antes de una reunión o de llamar a la familia.',
  '',
  'REGLAS:',
  '1. Habla SOLO de lo que hay en la ficha. No inventes ni supongas nada.',
  '   Si un dato no está, no lo menciones ni digas que falta salvo en el',
  '   apartado de datos que faltan.',
  '2. Es un menor en formación. Nada de sentencias sobre su techo, su futuro',
  '   profesional ni comparaciones con jugadores reales. No eres un ojeador de',
  '   la NBA: eres alguien que ayuda a un club a trabajar mejor con un chaval.',
  '3. Las notas de la evaluación van de 0 a 10 y están puestas comparándolo',
  '   con SU categoría y SU año, no con el baloncesto en general. Un 6 en',
  '   cadete no es "mediocre": es lo esperable para su edad.',
  '4. Si ha subido de categoría manteniendo la nota, eso es mejorar, y merece',
  '   decirse.',
  '5. No hables de dinero, de salud, ni de la situación de la familia. Si',
  '   aparecieran, ignóralos.',
  '6. Tono sobrio y en español de España. Frases cortas. Nada de superlativos',
  '   ni de lenguaje de folleto.',
  '7. Cada apartado, como mucho tres puntos. Prefiere decir menos y mejor.'
].join('\n');

function esquemaGemini() {
  return {
    type: 'OBJECT',
    properties: {
      resumen: { type: 'STRING', description: 'Dos o tres frases: quién es y por dónde va.' },
      fuerte: { type: 'ARRAY', items: { type: 'STRING' }, description: 'En qué destaca, según sus notas y datos.' },
      mejorar: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Qué le toca trabajar, en términos deportivos.' },
      faltan: { type: 'ARRAY', items: { type: 'STRING' }, description: 'Datos o papeles que faltan en la ficha.' },
      siguiente: { type: 'STRING', description: 'Una acción concreta para esta semana.' }
    }
  };
}
function esquemaJSON() {
  return {
    type: 'object',
    properties: {
      resumen: { type: 'string' },
      fuerte: { type: 'array', items: { type: 'string' } },
      mejorar: { type: 'array', items: { type: 'string' } },
      faltan: { type: 'array', items: { type: 'string' } },
      siguiente: { type: 'string' }
    },
    required: ['resumen', 'fuerte', 'mejorar', 'faltan', 'siguiente'],
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
      model: modelo, max_tokens: 1200, temperature: 0.2, system: INSTRUCCIONES,
      messages: [{ role: 'user', content: texto }],
      tools: [{ name: 'informe', description: 'Devuelve el resumen', input_schema: esquemaJSON() }],
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

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const ficha = limpiar(req.body && req.body.ficha);
  if (!Object.keys(ficha).length) return res.status(200).json({ ok: false, motivo: 'sin_datos' });

  /* Se manda como lista de "campo: valor", no como JSON crudo: se lee mejor y
     no invita al modelo a devolver la misma estructura de vuelta. */
  const texto = Object.keys(ficha).map(k => {
    const v = ficha[k];
    return k.replace(/_/g, ' ') + ': ' + (Array.isArray(v) ? v.join(' · ') : v);
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
        fuerte: lista(c.fuerte),
        mejorar: lista(c.mejorar),
        faltan: lista(c.faltan),
        siguiente: String(c.siguiente || '').slice(0, 400)
      },
      modelo: r.modelo,
      /* Se devuelve qué se envió para poder enseñárselo a quien pregunte.
         Un club tiene derecho a saber qué ha salido de su casa. */
      enviado: Object.keys(ficha)
    });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
