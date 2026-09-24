/* ============================================================================
   ScoutFlow Academy · Qué modelo de IA usa cada proveedor
   ----------------------------------------------------------------------------
   Los archivos que empiezan por "_" NO son rutas: Vercel no los publica.

   POR QUÉ EXISTE. Hasta el 25/09/2026 cada una de las siete funciones llevaba
   su propio modelo escrito a mano, y seis de ellas decían `gemini-2.0-flash`,
   que Google apagó el 1 de junio de 2026 (hallazgo C3 de la auditoría). Sin
   la variable GEMINI_MODEL puesta en Vercel, toda la IA de la app fallaba.

   AHORA el modelo vive aquí, en un solo sitio. Cambiarlo es cambiar una línea.

   CÓMO SE ELIGE, de más a menos prioridad:
     1. La variable de Vercel (GEMINI_MODEL, ANTHROPIC_MODEL, OPENAI_MODEL,
        y GEMINI_VIDEO_MODEL solo para la IA que mira vídeo).
     2. Si no está puesta, o si dice un modelo que ya está retirado, el de
        POR_DEFECTO. Un nombre retirado no se usa nunca: es la forma de que un
        olvido en el panel de Vercel no vuelva a tumbar la IA entera.

   REVISIÓN MENSUAL (claude_02, §9). Mirar estas tres páginas y, si alguno de
   los modelos de abajo tiene fecha de apagado, cambiarlo aquí y en REVISADO:
     · https://ai.google.dev/gemini-api/docs/deprecations
     · https://platform.claude.com/docs/en/about-claude/model-deprecations
     · https://developers.openai.com/api/docs/deprecations
   ========================================================================== */

/* Día en que se comprobó por última vez que estos modelos siguen vivos. */
export const REVISADO = '2026-09-25';

export const POR_DEFECTO = {
  /* Sustituto oficial de gemini-2.0-flash según Google. Estable, con capa
     gratuita. Sin fecha de apagado anunciada a 25/09/2026. */
  gemini: 'gemini-3.6-flash',
  /* La IA que mira un tramo de YouTube (api/video-ia). Se queda en el modelo
     con el que se probó en producción el 13/09/2026: sin fecha de apagado
     anunciada, y es el que mejor conocemos leyendo vídeo por tramos. */
  geminiVideo: 'gemini-2.5-flash',
  /* Activo; retirada «no antes del 15/10/2026». Revisar en octubre. */
  claude: 'claude-haiku-4-5-20251001',
  /* Activo, sin fecha de retirada a 25/09/2026. */
  openai: 'gpt-4o-mini'
};

/* Familias ya apagadas. Si alguien las deja puestas en Vercel, se ignoran. */
const RETIRADOS = [
  /^gemini-1\.0/, /^gemini-1\.5/, /^gemini-2\.0/, /^gemini-pro$/, /^gemini-pro-vision$/,
  /^claude-(instant|2)/, /^claude-3-/,
  /^gpt-3\.5/, /^gpt-4-(0314|0613|32k)/
];

export function retirado(nombre) {
  return RETIRADOS.some(r => r.test(String(nombre || '').trim()));
}

function elige(valor, porDefecto) {
  const v = String(valor || '').trim();
  if (!v) return porDefecto;
  if (retirado(v)) {
    console.warn('[ScoutFlow] El modelo «' + v + '» está retirado; se usa ' + porDefecto + '. Cámbialo en Vercel.');
    return porDefecto;
  }
  return v;
}

export function modeloGemini() { return elige(process.env.GEMINI_MODEL, POR_DEFECTO.gemini); }
export function modeloClaude() { return elige(process.env.ANTHROPIC_MODEL, POR_DEFECTO.claude); }
export function modeloOpenAI() { return elige(process.env.OPENAI_MODEL, POR_DEFECTO.openai); }

/* El de vídeo mantiene el orden de siempre: su variable propia, si no la
   general, y si no el suyo por defecto. Así no cambia lo que hoy funciona. */
export function modeloGeminiVideo() {
  const propio = String(process.env.GEMINI_VIDEO_MODEL || '').trim();
  if (propio && !retirado(propio)) return propio;
  const general = String(process.env.GEMINI_MODEL || '').trim();
  if (general && !retirado(general)) return general;
  return POR_DEFECTO.geminiVideo;
}
