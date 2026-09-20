/* ============================================================================
   ScoutFlow Academy · Leer la hoja de entrenamiento de un entrenador
   ----------------------------------------------------------------------------
   QUÉ HACE: recibe una sesión escrita por un entrenador —en PDF, en una foto
   del papel, en Word, en Excel o pegada como texto— y devuelve los ejercicios
   que hay dentro, ya con la forma que usa la biblioteca: nombre, cómo se hace,
   claves, minutos, material, carpeta y edades.

   POR QUÉ VIVE EN EL SERVIDOR: la clave de la IA no puede estar en el
   index.html; cualquiera que abriera la página podría leerla y gastar el
   crédito. Aquí se ejecuta en Vercel y la clave vive en una variable.

   LO QUE NO HACE: no guarda nada. Devuelve una propuesta que el entrenador
   revisa ejercicio a ejercicio antes de que entre en la biblioteca. Una hoja
   mal leída que entra sola es peor que no tener importador.

   PDF y FOTO necesitan Gemini (GEMINI_API_KEY): es el único de los tres que
   mira el documento. Word, Excel y texto funcionan con cualquiera de los tres,
   porque el texto se saca aquí antes de preguntar.
   ========================================================================== */

import { inflateRawSync } from 'zlib';
import { mismaCasa, fueraDeCasa } from './_origen.js';

export const config = { maxDuration: 60 };

/* --- Los valores que la app entiende. Si la IA se sale de aquí, se descarta
   ese campo: es preferible un hueco que un ejercicio en una carpeta que no
   existe, porque eso lo hace invisible en la estantería. -------------------- */
const CARPETAS = ['calentamiento', 'pase', 'tiro', 'defensa', 's1c1', 's2c2',
  's3c3', 's4c4', 's5c5', 'superioridad', 'fisico', 'vuelta'];
const OBJETIVOS = ['calentamiento', 'tecnica', 'tiro', 'defensa', 'ataque',
  'transicion', 'juego', 'fisico', 'vuelta'];
const MOMENTOS = ['Calentamiento', 'Parte principal', 'Parte final', 'Vuelta a la calma'];
const FORMATOS = ['individual', 'parejas', 'grupo', 'equipo'];
const PRACTICAS = ['bloque', 'serie', 'aleatoria'];

const INSTRUCCIONES = [
  'Eres el ayudante de una academia de baloncesto. Te dan la hoja de entrenamiento',
  'de un entrenador: puede ser un PDF, la foto de un papel escrito a mano, una tabla',
  'o unas notas sueltas. Saca los EJERCICIOS que contiene, uno por uno.',
  '',
  'REGLAS INNEGOCIABLES:',
  '1. Copia lo que pone, con sus palabras. No reescribas el ejercicio a tu manera',
  '   ni lo "mejores": esa hoja es el trabajo del entrenador.',
  '2. Lo que no esté, va vacío. NO lo deduzcas. Un minutaje inventado descuadra',
  '   la sesión entera.',
  '3. Si algo no se lee bien en la foto, ponlo en `dudoso` con lo que creas que',
  '   pone. Quien revise lo verá marcado. Nunca rellenes un hueco a ojo.',
  '4. La cabecera de la sesión (fecha, equipo, objetivo del día) NO es un ejercicio.',
  '5. Un calentamiento y una vuelta a la calma SÍ son ejercicios.',
  '6. `claves` es lo que hay que corregir mientras se hace, no la descripción otra vez.',
  '   Si la hoja no dice ninguna, déjalo vacío.',
  '7. `carpeta` solo puede ser uno de estos valores: ' + CARPETAS.join(', ') + '.',
  '   Elige por el contenido: un 3x3 va en s3c3 aunque la hoja lo llame "juego".',
  '8. Las edades: `etapa_de` y `etapa_a` van de 1 a 5, donde 1 es escuela (6-9),',
  '   2 mini (10-11), 3 infantil (12-13), 4 cadete (14-15) y 5 júnior y sénior (16+).',
  '   Si la hoja dice el equipo ("infantil A"), úsalo. Si no dice nada, déjalo a 0.',
  '9. Responde en español de España.'
].join('\n');

function esquemaGemini() {
  return {
    type: 'OBJECT',
    properties: {
      sesion: { type: 'STRING', nullable: true, description: 'Equipo, fecha u objetivo del día si aparecen' },
      ejercicios: {
        type: 'ARRAY',
        items: {
          type: 'OBJECT',
          properties: {
            nombre: { type: 'STRING', description: 'Nombre corto del ejercicio' },
            descripcion: { type: 'STRING', nullable: true, description: 'Cómo se hace, con las palabras de la hoja' },
            claves: { type: 'STRING', nullable: true, description: 'Qué hay que corregir. Vacío si la hoja no lo dice' },
            minutos: { type: 'NUMBER', nullable: true },
            jugadores: { type: 'STRING', nullable: true, description: 'Cuántos hacen falta, tal como lo diga la hoja' },
            material: { type: 'STRING', nullable: true },
            carpeta: { type: 'STRING', nullable: true, description: 'Uno de: ' + CARPETAS.join(', ') },
            objetivo: { type: 'STRING', nullable: true, description: 'Uno de: ' + OBJETIVOS.join(', ') },
            momento: { type: 'STRING', nullable: true, description: 'Uno de: ' + MOMENTOS.join(', ') },
            formato: { type: 'STRING', nullable: true, description: 'Uno de: ' + FORMATOS.join(', ') },
            practica: { type: 'STRING', nullable: true, description: 'Uno de: ' + PRACTICAS.join(', ') },
            etapa_de: { type: 'NUMBER', nullable: true, description: '1 a 5, 0 si no se sabe' },
            etapa_a: { type: 'NUMBER', nullable: true, description: '1 a 5, 0 si no se sabe' },
            dudoso: { type: 'STRING', nullable: true, description: 'Lo que no se lee con seguridad' }
          }
        }
      }
    }
  };
}

/* --------------------------------------------------------------------------
   SACAR EL TEXTO DE UN WORD O UN EXCEL
   Los dos son un zip con XML dentro. Se lee el directorio central del zip y se
   descomprime solo el archivo que interesa. Son ochenta lineas y evitan meter
   una libreria entera para leer cuatro parrafos.
   -------------------------------------------------------------------------- */
function leerZip(buf) {
  let i = buf.length - 22;
  for (; i >= 0; i--) if (buf.readUInt32LE(i) === 0x06054b50) break;
  if (i < 0) throw new Error('El archivo no parece un Word ni un Excel.');
  const n = buf.readUInt16LE(i + 10);
  let p = buf.readUInt32LE(i + 16);
  const out = {};
  for (let k = 0; k < n; k++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) break;
    const metodo = buf.readUInt16LE(p + 10);
    const comp = buf.readUInt32LE(p + 20);
    const nl = buf.readUInt16LE(p + 28), el = buf.readUInt16LE(p + 30), cl = buf.readUInt16LE(p + 32);
    const lh = buf.readUInt32LE(p + 42);
    const nombre = buf.toString('utf8', p + 46, p + 46 + nl);
    if (lh + 30 <= buf.length) {
      const lnl = buf.readUInt16LE(lh + 26), lel = buf.readUInt16LE(lh + 28);
      const ini = lh + 30 + lnl + lel;
      const raw = buf.subarray(ini, ini + comp);
      try { out[nombre] = metodo === 8 ? inflateRawSync(raw) : Buffer.from(raw); } catch (e) {}
    }
    p += 46 + nl + el + cl;
  }
  return out;
}

function sinEtiquetas(xml, corta) {
  return String(xml)
    .replace(new RegExp(corta, 'g'), '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&amp;/g, '&')
    .replace(/&quot;/g, '"').replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, (m, d) => String.fromCharCode(+d))
    .replace(/&#x([0-9a-f]+);/gi, (m, h) => String.fromCharCode(parseInt(h, 16)))
    .replace(/\n{3,}/g, '\n\n').trim();
}

function textoDeWord(buf) {
  const z = leerZip(buf);
  const doc = z['word/document.xml'];
  if (!doc) throw new Error('El Word no trae texto legible.');
  /* Un salto por párrafo y otro por fila de tabla: sin esto, una hoja en
     tabla llega como un churro de una sola línea y la IA pierde el reparto. */
  const xml = doc.toString('utf8')
    .replace(/<\/w:tc>/g, '\u0001')     // fin de celda
    .replace(/<\/w:tr>/g, '\u0002');    // fin de fila
  return sinEtiquetas(xml, '</w:p>')
    .replace(/\n*\u0001\n*/g, ' · ')
    .replace(/( · )*\u0002\n*/g, '\n')
    .replace(/\n{3,}/g, '\n\n').trim();
}

function textoDeExcel(buf) {
  const z = leerZip(buf);
  let comp = [];
  const ss = z['xl/sharedStrings.xml'];
  if (ss) {
    const s = ss.toString('utf8');
    const trozos = s.split('<si>').slice(1);
    comp = trozos.map(t => sinEtiquetas(t.split('</si>')[0], '</t>').replace(/\n/g, ''));
  }
  const nombres = Object.keys(z).filter(k => /^xl\/worksheets\/sheet\d+\.xml$/.test(k)).sort();
  const lineas = [];
  nombres.forEach(nm => {
    const s = z[nm].toString('utf8');
    s.split('<row').slice(1).forEach(fila => {
      const celdas = [];
      fila.split('<c ').slice(1).forEach(c => {
        const esTexto = /t="s"/.test(c);
        const m = c.match(/<v>([^<]*)<\/v>/);
        let v = m ? m[1] : '';
        if (esTexto && v !== '') v = comp[+v] || '';
        if (!m) { const it = c.match(/<t[^>]*>([^<]*)<\/t>/); if (it) v = it[1]; }
        if (v !== '') celdas.push(sinEtiquetas(v, '\u0000'));
      });
      if (celdas.length) lineas.push(celdas.join(' · '));
    });
  });
  if (!lineas.length) throw new Error('La hoja de cálculo no trae texto legible.');
  return lineas.join('\n');
}

/* -------------------------------------------------------------------------- */
async function conGemini(partes, key) {
  const modelo = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: INSTRUCCIONES }] },
      contents: [{ role: 'user', parts: partes }],
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

async function conClaude(texto, key) {
  const modelo = process.env.ANTHROPIC_MODEL || 'claude-haiku-4-5-20251001';
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model: modelo, max_tokens: 4096, temperature: 0, system: INSTRUCCIONES,
      messages: [{ role: 'user', content: texto }],
      tools: [{ name: 'hoja', description: 'Los ejercicios de la hoja', input_schema: esquemaJSON() }],
      tool_choice: { type: 'tool', name: 'hoja' }
    })
  });
  if (!r.ok) throw new Error('claude ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const uso = (data.content || []).filter(c => c.type === 'tool_use')[0];
  if (!uso) throw new Error('claude: no usó la herramienta');
  return { datos: uso.input, modelo: modelo };
}

async function conOpenAI(texto, key) {
  const modelo = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
    body: JSON.stringify({
      model: modelo, temperature: 0,
      messages: [{ role: 'system', content: INSTRUCCIONES },
                 { role: 'user', content: texto + '\n\nDevuelve un JSON con {"sesion":"...","ejercicios":[...]}.' }],
      response_format: { type: 'json_object' }
    })
  });
  if (!r.ok) throw new Error('openai ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (msg && msg.refusal) throw new Error('openai rechazó: ' + msg.refusal);
  return { datos: JSON.parse(msg.content), modelo: modelo };
}

function esquemaJSON() {
  return {
    type: 'object',
    properties: {
      sesion: { type: ['string', 'null'] },
      ejercicios: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            nombre: { type: 'string' },
            descripcion: { type: ['string', 'null'] },
            claves: { type: ['string', 'null'] },
            minutos: { type: ['number', 'null'] },
            jugadores: { type: ['string', 'null'] },
            material: { type: ['string', 'null'] },
            carpeta: { type: ['string', 'null'] },
            objetivo: { type: ['string', 'null'] },
            momento: { type: ['string', 'null'] },
            formato: { type: ['string', 'null'] },
            practica: { type: ['string', 'null'] },
            etapa_de: { type: ['number', 'null'] },
            etapa_a: { type: ['number', 'null'] },
            dudoso: { type: ['string', 'null'] }
          },
          required: ['nombre']
        }
      }
    },
    required: ['ejercicios']
  };
}

/* Lo que llega de la IA se pasa por la aduana: valores fuera de catálogo se
   tiran, minutos imposibles se tiran, y un ejercicio sin nombre no es nada. */
function limpia(datos) {
  const lista = Array.isArray(datos && datos.ejercicios) ? datos.ejercicios : [];
  const enLista = (v, lista2) => (v && lista2.indexOf(String(v)) >= 0) ? String(v) : null;
  return lista.map(e => {
    const nombre = String(e.nombre || '').trim().slice(0, 120);
    if (!nombre) return null;
    let de = Math.round(+e.etapa_de || 0), a = Math.round(+e.etapa_a || 0);
    if (de < 1 || de > 5) de = 0;
    if (a < 1 || a > 5) a = 0;
    if (de && !a) a = de;
    if (a && !de) de = a;
    if (de && a && a < de) { const t = de; de = a; a = t; }
    let min = Math.round(+e.minutos || 0);
    if (min < 1 || min > 120) min = 0;
    return {
      nombre: nombre,
      descripcion: String(e.descripcion || '').trim().slice(0, 1200),
      claves: String(e.claves || '').trim().slice(0, 600),
      minutos: min,
      jugadores: String(e.jugadores || '').trim().slice(0, 40),
      material: String(e.material || '').trim().slice(0, 200),
      carpeta: enLista(e.carpeta, CARPETAS),
      objetivo: enLista(e.objetivo, OBJETIVOS),
      momento: enLista(e.momento, MOMENTOS),
      formato: enLista(e.formato, FORMATOS),
      practica: enLista(e.practica, PRACTICAS),
      etapa: de ? { de: de, a: a } : null,
      dudoso: String(e.dudoso || '').trim().slice(0, 300)
    };
  }).filter(Boolean).slice(0, 40);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });
  if (!mismaCasa(req)) return fueraDeCasa(res);

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const b = req.body || {};
  const mime = String(b.mime || '');
  const nombre = String(b.nombre || '');
  let texto = String(b.texto || '');
  let partes = null;

  try {
    if (b.archivo) {
      const buf = Buffer.from(String(b.archivo), 'base64');
      if (buf.length > 12 * 1024 * 1024) {
        return res.status(200).json({ ok: false, motivo: 'muy_grande' });
      }
      if (/^application\/pdf/.test(mime) || /^image\//.test(mime)) {
        /* PDF y foto van tal cual: es el único camino que MIRA el documento,
           y una hoja escrita a mano no se puede pasar a texto antes. */
        if (!gem) return res.status(200).json({ ok: false, motivo: 'sin_gemini' });
        partes = [
          { inlineData: { mimeType: mime.split(';')[0], data: String(b.archivo) } },
          { text: 'Saca los ejercicios de esta hoja de entrenamiento.' }
        ];
      } else if (/wordprocessingml/.test(mime) || /\.docx$/i.test(nombre)) {
        texto = textoDeWord(buf);
      } else if (/spreadsheetml/.test(mime) || /\.xlsx$/i.test(nombre)) {
        texto = textoDeExcel(buf);
      } else {
        texto = buf.toString('utf8');
      }
    }
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'archivo', detalle: String(e.message || e).slice(0, 200) });
  }

  if (!partes) {
    texto = texto.slice(0, 24000);
    if (!texto.trim()) return res.status(200).json({ ok: false, motivo: 'sin_texto' });
    partes = [{ text: 'Hoja de entrenamiento:\n\n' + texto }];
  }

  try {
    let r;
    if (gem) r = await conGemini(partes, gem);
    else if (ant) r = await conClaude(texto, ant);
    else r = await conOpenAI(texto, oai);
    const ejercicios = limpia(r.datos);
    if (!ejercicios.length) return res.status(200).json({ ok: false, motivo: 'sin_ejercicios' });
    return res.status(200).json({
      ok: true, modelo: r.modelo,
      sesion: String((r.datos || {}).sesion || '').slice(0, 200),
      ejercicios: ejercicios
    });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
