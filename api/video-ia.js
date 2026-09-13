/* ============================================================================
   ScoutFlow Academy · La IA MIRA el vídeo (un tramo de él)
   ----------------------------------------------------------------------------
   ESTE ES DISTINTO DE api/video.js, y conviene no confundirlos:

     · api/video.js    lee los CORTES ESCRITOS por el cuerpo técnico y los
                       ordena. No ve nada.
     · api/video-ia.js manda un TRAMO DEL VÍDEO a Gemini y le pregunta qué
                       pasa ahí. Sí ve, dentro de lo que se explica abajo.

   POR QUÉ ESTO SÍ SE PUEDE (y antes dijimos que no). La API de Gemini acepta
   una URL de YouTube directamente y procesa el vídeo en el servidor. El
   navegador no puede tocar los píxeles de un iframe; nuestro backend no los
   necesita: le pasa la URL a Google y Google mira.

   LO QUE SIGUE SIN PODERSE, y por eso este archivo no lo pide:
   Gemini muestrea FOTOGRAMAS -1 por segundo por defecto, aquí subimos a 2 o 3
   porque el baloncesto va rápido-. Con eso se describe muy bien una jugada y
   se dice en qué minuto pasa. NO se mide un "release de 0,41 s" (el gesto
   entero cabe entre dos fotogramas), ni un ángulo de codo desde un plano de
   grada, ni un PPP, que exige contar todas las posesiones sin fallar una. Y
   la documentación de Google no habla de seguimiento de personas: con diez
   chavales de la misma equipación, confundir al 4 con el 14 es lo normal.

   Así que el esquema de salida NO TIENE NINGÚN NÚMERO. Describe y sitúa; no
   mide. Y lo que devuelve entra en la app como BORRADOR de un corte, para que
   lo firme una persona.

   EL TRAMO ES LA CLAVE. Analizar 40 segundos alrededor de una jugada marcada
   es preciso, barato y rápido. Analizar hora y media de golpe es caro, lento
   y devuelve un resumen que nadie puede verificar. Por eso el modo normal de
   este endpoint es "un corte", no "un partido".

   REQUISITOS: GEMINI_API_KEY. Los otros proveedores no aceptan una URL de
   YouTube, así que aquí no hay alternativa: se dice y punto.
   El vídeo tiene que ser PÚBLICO en YouTube. Los "no listados" los rechaza
   Google aunque el enlace funcione en un navegador.
   ========================================================================== */

const MAX_TRAMO = 240;   // segundos. Más que esto ya no es "una jugada".

function seg(v) {
  const n = Math.max(0, Math.floor(Number(v) || 0));
  return n;
}

/* LA URL, LIMPIA. Esto costó un error en producción y merece quedar escrito.
   Gemini devolvía:
       "Unsupported MIME type: text/html; charset=utf-8" · INVALID_ARGUMENT
   ...que no dice nada hasta que se entiende qué pasó: al no reconocer la URL
   como YouTube, Google intentó DESCARGARLA como si fuera un archivo suelto y
   recibió una página web.

   ¿Por qué no la reconocía? Porque se le mandaba tal cual la había pegado el
   club, y la de un partido suele venir con cosas detrás: `&t=114s` del minuto,
   `&list=` de una lista, `?si=` de un enlace compartido desde el móvil. Con
   eso el patrón de YouTube falla.

   Así que aquí se extrae el ID de vídeo -once caracteres- y se reconstruye la
   URL canónica. Lo que pegue el club da igual; lo que sale de aquí siempre
   tiene la misma forma. */
function idYouTube(url) {
  var m = String(url || '').match(
    /(?:youtube\.com\/(?:watch\?(?:[^#]*&)?v=|embed\/|shorts\/|live\/|v\/)|youtu\.be\/)([\w-]{11})/i);
  return m ? m[1] : null;
}
function urlCanonica(url) {
  var id = idYouTube(url);
  return id ? 'https://www.youtube.com/watch?v=' + id : null;
}

/* Las reglas van en el system prompt Y repetidas en el user prompt, a
   propósito: con entrada de vídeo el modelo se entusiasma, y la instrucción
   que más se salta es justo la de no inventar cifras. */
const REGLAS = [
  'Eres el analista de vídeo de una academia de baloncesto de FORMACIÓN.',
  'Ves un tramo corto de un partido y describes lo que ocurre para que un',
  'entrenador lo use el martes siguiente.',
  '',
  'REGLAS INNEGOCIABLES:',
  '1. Describe SOLO lo que se ve en las imágenes. Si algo no se distingue',
  '   -el dorsal, quién toca el balón, si entra o no- DILO. "No se distingue"',
  '   es una respuesta correcta y útil; inventarlo no.',
  '2. PROHIBIDO DAR NÚMEROS que no se puedan contar en las imágenes: nada de',
  '   notas sobre 10 o sobre 100, porcentajes, puntos por posesión, ratings,',
  '   ángulos, velocidades ni tiempos de lanzamiento. No tienes con qué',
  '   medirlos y una cifra inventada con decimales parece medida.',
  '3. No identifiques a nadie por su cara ni por su nombre. Si te dan un',
  '   dorsal, úsalo solo si LO VES en la camiseta; si no lo ves, habla del',
  '   jugador por su posición en la pista ("el base con camiseta clara").',
  '3b. Te pueden dar pistas del club: el color de la equipación, el del rival,',
  '   dónde está la cámara o hacia qué canasta se ataca. ÚSALAS PARA MIRAR,',
  '   no como hechos dados: si la pista dice "camiseta roja" y en el tramo que',
  '   ves no hay nadie de rojo, eso es lo que tienes que contestar. Fíjate en',
  '   el color de la equipación antes que en nada: es lo único que a esta',
  '   resolución distingue a un equipo del otro con fiabilidad.',
  '4. Son menores. Nada de juicios sobre su futuro, su techo ni comparaciones',
  '   con jugadores profesionales. Describe la jugada, no al chaval.',
  '5. Español de España, sobrio, frases cortas. Vocabulario de baloncesto de',
  '   formación: bloqueo directo, continuación, ayuda, rotación, cierre de',
  '   rebote, transición, spacing.'
].join('\n');

const ESQUEMA_CORTE = `Responde SOLO con un objeto JSON con estas claves:
{
  "titulo": "una línea de 4 a 9 palabras que nombre la jugada",
  "con_balon": "qué hace el jugador cuando tiene el balón, o '' si no lo tiene",
  "sin_balon": "cómo se mueve, cómo defiende, qué lee sin balón",
  "resultado": "en qué acaba la jugada",
  "etiqueta": "una de: Ataque posicional, Transición, Contraataque, Bloqueo directo, Defensa individual, Defensa zonal, Rebote, Saque de banda o fondo, Tiro, Pérdida, Acierto, Error corregible, Actitud",
  "confianza": "alta, media o baja: lo segura que es tu lectura con la calidad de imagen que tienes",
  "no_visible": "qué NO has podido distinguir. Cadena vacía si lo has visto todo con claridad"
}`;

const ESQUEMA_PROPUESTA = `Responde SOLO con un objeto JSON:
{
  "momentos": [
    { "t": "MM:SS o HH:MM:SS, el minuto DEL VÍDEO donde empieza la jugada",
      "titulo": "una línea que nombre la jugada",
      "por_que": "por qué merece enseñarse a un equipo de formación",
      "etiqueta": "una de la lista de etiquetas" }
  ],
  "no_visible": "lo que la calidad del vídeo no te deja ver"
}
Máximo 8 momentos, los más útiles para entrenar. Si el tramo no da para tanto, devuelve menos.`;

async function pideAGemini(key, payload) {
  const modelo = process.env.GEMINI_VIDEO_MODEL || process.env.GEMINI_MODEL || 'gemini-2.5-flash';
  const url = 'https://generativelanguage.googleapis.com/v1beta/models/' + modelo + ':generateContent?key=' + key;
  const r = await fetch(url, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
  });
  const txt = await r.text();
  if (!r.ok) {
    const e = new Error('gemini ' + r.status + ' ' + txt.slice(0, 400));
    e.status = r.status; e.cuerpo = txt;
    throw e;
  }
  const data = JSON.parse(txt);
  const t = data.candidates && data.candidates[0] && data.candidates[0].content
    && data.candidates[0].content.parts && data.candidates[0].content.parts
      .map(p => p.text || '').join('').trim();
  if (!t) throw new Error('gemini: respuesta vacía');
  return { texto: t, modelo: modelo };
}

/* El modelo devuelve JSON, pero a veces lo envuelve en ```json. Se limpia
   antes de parsear: fallar por tres comillas sería tonto. */
function parseaJSON(t) {
  let s = String(t || '').trim();
  s = s.replace(/^```(?:json)?\s*/i, '').replace(/\s*```$/, '').trim();
  const i = s.indexOf('{'), j = s.lastIndexOf('}');
  if (i >= 0 && j > i) s = s.slice(i, j + 1);
  return JSON.parse(s);
}

function limpia(v, max) {
  return String(v == null ? '' : v).replace(/\s+/g, ' ').trim().slice(0, max || 300);
}

export default async function handler(req, res) {
  if (req.method !== 'POST') return res.status(405).json({ ok: false, motivo: 'metodo' });

  const key = process.env.GEMINI_API_KEY;
  /* Aquí NO valen Claude ni OpenAI: ninguno acepta una URL de YouTube. Se
     dice con su nombre en vez de un "error de proveedor" genérico. */
  if (!key) return res.status(200).json({ ok: false, motivo: 'sin_gemini' });

  const b = req.body || {};
  const url = urlCanonica(b.url);
  if (!url) return res.status(200).json({ ok: false, motivo: 'no_youtube' });

  const modo = (b.modo === 'propuesta') ? 'propuesta' : 'corte';
  let desde = seg(b.desde);
  let hasta = seg(b.hasta);
  if (hasta <= desde) hasta = desde + (modo === 'corte' ? 40 : 600);
  if (hasta - desde > MAX_TRAMO && modo === 'corte') hasta = desde + MAX_TRAMO;

  /* Fotogramas por segundo. El baloncesto a 1 fps se pierde la mitad de las
     acciones; a 3 el coste se dispara sin ganar mucho. 2 es el punto donde
     una continuación de bloqueo directo se ve entera. */
  const fps = modo === 'corte' ? 2 : 1;

  /* LAS PISTAS. A uno o dos fotogramas por segundo, y con un plano general
     desde la grada, la diferencia entre "el chaval de rojo con el 4" y "un
     jugador" es enorme. Estos datos los escribe el club UNA VEZ al dar de alta
     el vídeo, no en cada corte: son del partido, no de la jugada.

     Y se dicen como pistas para MIRAR, no como hechos: si el modelo no ve el
     dorsal, tiene que decirlo, no dárselo por bueno porque se lo hemos puesto
     en el prompt. Esa es la diferencia entre ayudarle a mirar y decirle lo que
     tiene que encontrar. */
  const pistas = [];
  if (b.equipacion) pistas.push('EQUIPACIÓN DE NUESTRO EQUIPO: ' + limpia(b.equipacion, 140) +
    '. Es lo que hay que mirar para saber quiénes son los nuestros.');
  if (b.equipacion_rival) pistas.push('Equipación del rival: ' + limpia(b.equipacion_rival, 140) + '.');
  if (b.dorsal) pistas.push('El jugador que interesa lleva el dorsal ' + limpia(b.dorsal, 6) +
    '. Búscalo, pero úsalo SOLO si lo ves de verdad en la camiseta; si no lo distingues, dilo.');
  if (b.contexto) pistas.push('Contexto del vídeo que da el club: ' + limpia(b.contexto, 600));
  if (b.categoria) pistas.push('Categoría: ' + limpia(b.categoria, 60) + '. Es formación, no profesional.');

  const instruccion = modo === 'corte'
    ? ['Mira este tramo del partido y descríbeme la jugada principal.', ...pistas,
       'Recuerda: nada de números inventados, y di lo que no se distinga.', '', ESQUEMA_CORTE].join('\n')
    : ['Recórrete este tramo y propón los momentos que merece la pena enseñar a un equipo de formación.',
       ...pistas,
       'Los minutos que devuelvas son del VÍDEO, contando desde su principio (00:00), no del reloj del partido.',
       'Recuerda: nada de números inventados, y di lo que no se distinga.', '', ESQUEMA_PROPUESTA].join('\n');

  const payload = {
    systemInstruction: { parts: [{ text: REGLAS }] },
    contents: [{
      role: 'user',
      parts: [
        { fileData: { fileUri: url },
          videoMetadata: { startOffset: desde + 's', endOffset: hasta + 's', fps: fps } },
        { text: instruccion }
      ]
    }],
    generationConfig: { temperature: 0.15, responseMimeType: 'application/json' }
  };

  try {
    const r = await pideAGemini(key, payload);
    let c;
    try { c = parseaJSON(r.texto); }
    catch (e) { return res.status(200).json({ ok: false, motivo: 'respuesta_rara', detalle: r.texto.slice(0, 300) }); }

    if (modo === 'corte') {
      return res.status(200).json({
        ok: true, modo: 'corte', modelo: r.modelo, tramo: { desde, hasta, fps },
        corte: {
          titulo: limpia(c.titulo, 120),
          con_balon: limpia(c.con_balon, 400),
          sin_balon: limpia(c.sin_balon, 400),
          resultado: limpia(c.resultado, 400),
          etiqueta: limpia(c.etiqueta, 60),
          confianza: (['alta', 'media', 'baja'].indexOf(String(c.confianza || '').toLowerCase()) >= 0)
            ? String(c.confianza).toLowerCase() : 'media',
          no_visible: limpia(c.no_visible, 300)
        }
      });
    }
    const momentos = (Array.isArray(c.momentos) ? c.momentos : []).slice(0, 8).map(m => ({
      t: limpia(m.t, 12), titulo: limpia(m.titulo, 120),
      por_que: limpia(m.por_que, 300), etiqueta: limpia(m.etiqueta, 60)
    })).filter(m => m.t && m.titulo);
    return res.status(200).json({
      ok: true, modo: 'propuesta', modelo: r.modelo, tramo: { desde, hasta, fps },
      momentos: momentos, no_visible: limpia(c.no_visible, 300)
    });

  } catch (e) {
    const cuerpo = String(e.cuerpo || e.message || '');
    /* El error que más va a salir en un club: el vídeo está como "no listado"
       para proteger a los chavales, y Google solo acepta públicos. Merece un
       motivo propio porque la solución es distinta y no es un fallo de nadie. */
    if (/not.*public|private|unlisted|PERMISSION_DENIED|FAILED_PRECONDITION|cannot access/i.test(cuerpo)) {
      return res.status(200).json({ ok: false, motivo: 'video_no_publico', detalle: cuerpo.slice(0, 200) });
    }
    /* Si aun con la URL canónica Google contesta que el MIME es text/html, es
       que no ha podido acceder al vídeo: casi siempre porque no es público.
       Se dice eso y no el error crudo, que no le sirve a nadie. */
    if (/Unsupported MIME type|text\/html/i.test(cuerpo)) {
      return res.status(200).json({ ok: false, motivo: 'video_no_publico', detalle: cuerpo.slice(0, 200) });
    }
    if (/quota|RESOURCE_EXHAUSTED|rate/i.test(cuerpo)) {
      return res.status(200).json({ ok: false, motivo: 'cuota', detalle: cuerpo.slice(0, 200) });
    }
    return res.status(200).json({ ok: false, motivo: 'proveedor', detalle: cuerpo.slice(0, 300) });
  }
}
