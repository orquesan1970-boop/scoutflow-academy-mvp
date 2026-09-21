/* ============================================================================
   ScoutFlow Academy · Leer la factura o el albarán del proveedor
   ----------------------------------------------------------------------------
   QUÉ HACE: recibe la factura de un pedido —PDF, foto del albarán o texto
   pegado— y devuelve sus líneas ya emparejadas con el catálogo del club:
   artículo, talla y cantidad. Meter una caja de 300 prendas a mano son
   trescientos clics; esto lo deja en una pantalla de repaso.

   LO QUE NO HACE, Y ES LO MÁS IMPORTANTE: **no toca el almacén**. Devuelve una
   propuesta. El almacén solo se mueve cuando una persona repasa las líneas y
   pulsa el botón. Un albarán mal leído que entra solo son existencias falsas,
   y unas existencias falsas se descubren en junio, cuando ya no se puede
   arreglar.

   EL EMPAREJADO es el trabajo de verdad: el proveedor escribe «CAMISETA JUEGO
   MOR. M/C TALLA 12» y nosotros tenemos «1ª equipación morada · camiseta».
   Por eso se le manda NUESTRO catálogo con sus ids y sus tallas, y se le
   obliga a elegir un id de esa lista o ninguno. Inventarse un artículo sería
   crear estantería fantasma.

   PDF y FOTO necesitan Gemini (GEMINI_API_KEY): es el único de los tres
   proveedores que mira el documento. El texto pegado lo lee cualquiera.
   ========================================================================== */

import { mismaCasa, fueraDeCasa } from './_origen.js';

export const config = { maxDuration: 60 };

function instrucciones(catalogo) {
  return [
    'Eres el ayudante de almacén de un club deportivo. Te dan la factura o el albarán',
    'de un pedido de ropa y material. Devuelve UNA LÍNEA POR ARTÍCULO Y TALLA.',
    '',
    'ESTE ES EL CATÁLOGO DEL CLUB. El `art_id` tiene que salir de aquí, sin excepción:',
    catalogo.map(function (a) {
      return '- ' + a.id + ' = "' + a.label + '"' + (a.tallas ? ' · tallas: ' + a.tallas.join(', ') : '');
    }).join('\n'),
    '',
    'REGLAS INNEGOCIABLES:',
    '1. Si una línea de la factura no encaja con ningún artículo del catálogo, pon',
    '   `art_id` a null y copia el texto en `texto`. NO te inventes un id ni fuerces',
    '   el que más se parezca: es preferible que lo empareje una persona.',
    '2. Copia SIEMPRE el texto original de la línea en `texto`. Es lo que permite a',
    '   quien repasa comprobar sin abrir el PDF.',
    '3. Una línea con varias tallas ("M: 6, L: 4") son DOS líneas de salida.',
    '4. `cantidad` son UNIDADES. Si la factura habla de packs o de docenas y dice',
    '   cuántas unidades lleva cada uno, multiplica; si no lo dice, deja la cantidad',
    '   tal cual y avisa en `dudoso`.',
    '5. Las tallas, tal como las escriba el proveedor: "12", "XS", "M", "única".',
    '   Si no pone talla, déjala vacía.',
    '6. NO son artículos: portes, transporte, serigrafía, descuentos, IVA, bases',
    '   imponibles ni totales. Fuera de la lista.',
    '7. Si algo no se lee con seguridad —una foto torcida, un número borroso—,',
    '   ponlo en `dudoso` diciendo qué. Nunca rellenes un hueco a ojo.',
    '8. `precio_unit` solo si la factura lo dice por unidad, sin IVA. Si no, null.',
    '9. Responde en español de España.'
  ].join('\n');
}

function esquemaGemini() {
  return {
    type: 'OBJECT',
    properties: {
      proveedor: { type: 'STRING', nullable: true },
      numero: { type: 'STRING', nullable: true, description: 'Número de factura o albarán' },
      fecha: { type: 'STRING', nullable: true, description: 'Fecha del documento, AAAA-MM-DD' },
      lineas: {
        type: 'ARRAY',
        items: {
          type: 'OBJECT',
          properties: {
            art_id: { type: 'STRING', nullable: true, description: 'Id del catálogo, o null' },
            texto: { type: 'STRING', description: 'La línea tal como viene en la factura' },
            talla: { type: 'STRING', nullable: true },
            cantidad: { type: 'NUMBER', nullable: true },
            precio_unit: { type: 'NUMBER', nullable: true },
            dudoso: { type: 'STRING', nullable: true }
          }
        }
      }
    }
  };
}

function esquemaJSON() {
  return {
    type: 'object',
    properties: {
      proveedor: { type: ['string', 'null'] },
      numero: { type: ['string', 'null'] },
      fecha: { type: ['string', 'null'] },
      lineas: {
        type: 'array',
        items: {
          type: 'object',
          properties: {
            art_id: { type: ['string', 'null'] },
            texto: { type: 'string' },
            talla: { type: ['string', 'null'] },
            cantidad: { type: ['number', 'null'] },
            precio_unit: { type: ['number', 'null'] },
            dudoso: { type: ['string', 'null'] }
          },
          required: ['texto']
        }
      }
    },
    required: ['lineas']
  };
}

async function conGemini(partes, sistema, key) {
  const modelo = process.env.GEMINI_MODEL || 'gemini-2.0-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      systemInstruction: { parts: [{ text: sistema }] },
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

async function conClaude(texto, sistema, key) {
  const modelo = process.env.ANTHROPIC_MODEL || 'claude-haiku-4-5-20251001';
  const r = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'x-api-key': key, 'anthropic-version': '2023-06-01' },
    body: JSON.stringify({
      model: modelo, max_tokens: 4096, temperature: 0, system: sistema,
      messages: [{ role: 'user', content: texto }],
      tools: [{ name: 'factura', description: 'Las líneas del albarán', input_schema: esquemaJSON() }],
      tool_choice: { type: 'tool', name: 'factura' }
    })
  });
  if (!r.ok) throw new Error('claude ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const uso = (data.content || []).filter(c => c.type === 'tool_use')[0];
  if (!uso) throw new Error('claude: no usó la herramienta');
  return { datos: uso.input, modelo: modelo };
}

async function conOpenAI(texto, sistema, key) {
  const modelo = process.env.OPENAI_MODEL || 'gpt-4o-mini';
  const r = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
    body: JSON.stringify({
      model: modelo, temperature: 0,
      messages: [{ role: 'system', content: sistema },
                 { role: 'user', content: texto + '\n\nDevuelve un JSON {"proveedor":..,"numero":..,"fecha":..,"lineas":[..]}.' }],
      response_format: { type: 'json_object' }
    })
  });
  if (!r.ok) throw new Error('openai ' + r.status + ' ' + (await r.text()).slice(0, 200));
  const data = await r.json();
  const msg = data.choices && data.choices[0] && data.choices[0].message;
  if (msg && msg.refusal) throw new Error('openai rechazó: ' + msg.refusal);
  return { datos: JSON.parse(msg.content), modelo: modelo };
}

/* La aduana. Lo que devuelve la IA se comprueba contra el catálogo de verdad:
   un id que no existe se convierte en línea sin emparejar, no en un movimiento
   a un artículo fantasma. */
function limpia(datos, catalogo) {
  const ids = {};
  catalogo.forEach(a => { ids[a.id] = a; });
  const lineas = Array.isArray(datos && datos.lineas) ? datos.lineas : [];
  return lineas.map(l => {
    const texto = String(l.texto || '').trim().slice(0, 200);
    let n = Math.round(+l.cantidad || 0);
    if (n < 0 || n > 5000) n = 0;
    const art = l.art_id && ids[String(l.art_id)] ? String(l.art_id) : null;
    let talla = String(l.talla == null ? '' : l.talla).trim().slice(0, 12);
    /* Si el artículo tiene lista de tallas y la que viene no está, se deja
       marcada: la elige una persona. Meter una "XXL" en un artículo que solo
       tiene hasta XL crea una casilla que nadie va a mirar nunca más. */
    let talla_rara = false;
    if (art && talla && ids[art].tallas && ids[art].tallas.indexOf(talla) < 0) talla_rara = true;
    if (!texto && !art) return null;
    return {
      art_id: art, texto: texto, talla: talla, cantidad: n,
      precio_unit: (l.precio_unit > 0 && l.precio_unit < 10000) ? +l.precio_unit : null,
      dudoso: String(l.dudoso || '').trim().slice(0, 200),
      talla_rara: talla_rara
    };
  }).filter(Boolean).slice(0, 300);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });
  if (!mismaCasa(req)) return fueraDeCasa(res);

  const gem = process.env.GEMINI_API_KEY;
  const ant = process.env.ANTHROPIC_API_KEY;
  const oai = process.env.OPENAI_API_KEY;
  if (!gem && !ant && !oai) return res.status(200).json({ ok: false, motivo: 'sin_clave' });

  const b = req.body || {};
  const catalogo = (Array.isArray(b.catalogo) ? b.catalogo : []).slice(0, 200).map(a => ({
    id: String(a.id || '').slice(0, 30),
    label: String(a.label || '').slice(0, 120),
    tallas: Array.isArray(a.tallas) ? a.tallas.slice(0, 30).map(t => String(t).slice(0, 12)) : null
  })).filter(a => a.id && a.label);
  if (!catalogo.length) return res.status(200).json({ ok: false, motivo: 'sin_catalogo' });

  const sistema = instrucciones(catalogo);
  const mime = String(b.mime || '');
  let texto = String(b.texto || '');
  let partes = null;

  if (b.archivo) {
    const bytes = Math.floor(String(b.archivo).length * 0.75);
    if (bytes > 12 * 1024 * 1024) return res.status(200).json({ ok: false, motivo: 'muy_grande' });
    if (/^application\/pdf/.test(mime) || /^image\//.test(mime)) {
      if (!gem) return res.status(200).json({ ok: false, motivo: 'sin_gemini' });
      partes = [
        { inlineData: { mimeType: mime.split(';')[0], data: String(b.archivo) } },
        { text: 'Saca las líneas de este albarán o factura.' }
      ];
    } else {
      try { texto = Buffer.from(String(b.archivo), 'base64').toString('utf8'); }
      catch (e) { return res.status(200).json({ ok: false, motivo: 'archivo' }); }
    }
  }

  if (!partes) {
    texto = texto.slice(0, 24000);
    if (!texto.trim()) return res.status(200).json({ ok: false, motivo: 'sin_texto' });
    partes = [{ text: 'Factura o albarán:\n\n' + texto }];
  }

  try {
    let r;
    if (gem) r = await conGemini(partes, sistema, gem);
    else if (ant) r = await conClaude(texto, sistema, ant);
    else r = await conOpenAI(texto, sistema, oai);

    const lineas = limpia(r.datos, catalogo);
    if (!lineas.length) return res.status(200).json({ ok: false, motivo: 'sin_lineas' });
    const d = r.datos || {};
    return res.status(200).json({
      ok: true, modelo: r.modelo,
      proveedor: String(d.proveedor || '').slice(0, 120),
      numero: String(d.numero || '').slice(0, 60),
      fecha: /^\d{4}-\d{2}-\d{2}$/.test(String(d.fecha || '')) ? d.fecha : null,
      lineas: lineas
    });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: String(e.message || e).slice(0, 300) });
  }
}
