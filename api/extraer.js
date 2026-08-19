/* ============================================================================
   ScoutFlow Academy · Extraer datos de un texto con IA
   ----------------------------------------------------------------------------
   POR QUÉ ESTO VIVE AQUÍ Y NO EN LA APP:
   la clave de OpenAI NO puede estar en el index.html. Cualquiera que abra la
   página podría leerla y gastar el crédito de Jorge. Aquí se ejecuta en el
   servidor de Vercel, y la clave vive en una variable de entorno que solo
   conoce él.

   PARA QUE FUNCIONE, en Vercel → Settings → Environment Variables:
     OPENAI_API_KEY   ← la clave (secreta, no la comparte con nadie)
     OPENAI_MODEL     ← opcional. Por defecto gpt-4o-mini

   Si no hay clave, no falla: contesta que no está configurada y la app tira
   del lector de siempre.
   ========================================================================== */

const CAMPOS = {
  first_name: 'Nombre de pila',
  last_name: 'Apellidos',
  birth_date: 'Fecha de nacimiento en formato AAAA-MM-DD',
  birth_year: 'Año de nacimiento, número de 4 cifras',
  primary_position: 'Posición principal. Solo una de: Base, Escolta, Alero, Ala-pívot, Pívot',
  secondary_position: 'Posición secundaria, misma lista',
  height_cm: 'Altura en centímetros, número entero',
  weight_kg: 'Peso en kilos, número',
  nationality: 'Lista de nacionalidades, en español y con mayúscula inicial',
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
  family_relation: 'Relación: Padre, Madre, Tutor',
  family_phone: 'Teléfono de contacto de la familia',
  family_email: 'Correo de la familia',
  objective: 'Qué busca el jugador o la familia'
};

function esquema() {
  const props = {};
  Object.keys(CAMPOS).forEach(k => {
    if (k === 'nationality') props[k] = { type: ['array', 'null'], items: { type: 'string' }, description: CAMPOS[k] };
    else if (k === 'height_cm' || k === 'weight_kg' || k === 'birth_year') props[k] = { type: ['number', 'null'], description: CAMPOS[k] };
    else props[k] = { type: ['string', 'null'], description: CAMPOS[k] };
  });
  props.resumen = { type: ['string', 'null'], description: 'Una frase con lo que cuenta el texto, en español' };
  props.sin_datos = { type: 'boolean', description: 'true si el texto no habla de ningún jugador' };
  return {
    type: 'object',
    properties: props,
    required: Object.keys(props),
    additionalProperties: false
  };
}

const INSTRUCCIONES = [
  'Eres el asistente de una academia de baloncesto. Te van a pegar mensajes de WhatsApp,',
  'correos o notas sueltas sobre un jugador, escritos de forma informal y con faltas.',
  'Tu tarea es extraer los datos que REALMENTE aparecen en el texto.',
  '',
  'REGLAS INNEGOCIABLES:',
  '1. Si un dato no está en el texto, devuelve null. NO lo deduzcas, NO lo inventes,',
  '   NO lo rellenes con lo que suele ser habitual. Es preferible un hueco vacío a un',
  '   dato inventado: esto es la ficha de un menor.',
  '2. No conviertas ni calcules cosas que no están dichas. Si dicen la edad pero no la',
  '   fecha de nacimiento, deja la fecha en null.',
  '3. Si dicen la altura como "1.90" o "190" o "un noventa", devuelve 190.',
  '4. "Base", "uno", "1" o "point guard" es Base. "Cuatro" es Ala-pívot. "Cinco" o',
  '   "pívot" es Pívot. "Dos" es Escolta. "Tres" es Alero.',
  '5. Si el texto no habla de ningún jugador, pon sin_datos en true.',
  '6. Nunca opines sobre el jugador ni valores su nivel. Solo extraes datos.'
].join('\n');

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });

  const key = process.env.OPENAI_API_KEY;
  if (!key) {
    /* No es un error: es que aún no está configurada. La app lo entiende. */
    return res.status(200).json({ ok: false, motivo: 'sin_clave' });
  }

  const texto = (req.body && req.body.texto ? String(req.body.texto) : '').slice(0, 8000);
  if (!texto.trim()) return res.status(200).json({ ok: false, motivo: 'sin_texto' });

  try {
    const r = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + key },
      body: JSON.stringify({
        model: process.env.OPENAI_MODEL || 'gpt-4o-mini',
        temperature: 0,
        messages: [
          { role: 'system', content: INSTRUCCIONES },
          { role: 'user', content: texto }
        ],
        /* Modo estricto: la respuesta viene obligatoriamente con esta forma,
           así que la app no tiene que adivinar ni parsear texto libre. */
        response_format: {
          type: 'json_schema',
          json_schema: { name: 'ficha_jugador', strict: true, schema: esquema() }
        }
      })
    });

    if (!r.ok) {
      const detalle = await r.text();
      return res.status(200).json({ ok: false, motivo: 'openai', codigo: r.status, detalle: detalle.slice(0, 300) });
    }

    const data = await r.json();
    const bruto = data.choices && data.choices[0] && data.choices[0].message;
    if (bruto && bruto.refusal) return res.status(200).json({ ok: false, motivo: 'rechazado', detalle: bruto.refusal });

    let campos;
    try { campos = JSON.parse(bruto.content); }
    catch (e) { return res.status(200).json({ ok: false, motivo: 'respuesta_ilegible' }); }

    /* Limpieza defensiva: aunque el modo estricto garantiza la forma, no
       garantiza el sentido. Descartamos lo que no tenga pinta de válido. */
    if (campos.height_cm && (campos.height_cm < 100 || campos.height_cm > 250)) campos.height_cm = null;
    if (campos.weight_kg && (campos.weight_kg < 20 || campos.weight_kg > 200)) campos.weight_kg = null;
    if (campos.birth_year && (campos.birth_year < 1950 || campos.birth_year > new Date().getFullYear())) campos.birth_year = null;
    if (campos.birth_date && !/^\d{4}-\d{2}-\d{2}$/.test(campos.birth_date)) campos.birth_date = null;

    return res.status(200).json({
      ok: true,
      campos: campos,
      modelo: data.model,
      gasto: data.usage || null
    });
  } catch (e) {
    return res.status(200).json({ ok: false, motivo: 'error', detalle: String(e).slice(0, 200) });
  }
}
