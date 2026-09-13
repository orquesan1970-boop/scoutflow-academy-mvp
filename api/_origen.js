/* ============================================================================
   ScoutFlow Academy · ¿Esta llamada viene de nuestra propia app?
   ----------------------------------------------------------------------------
   Los archivos que empiezan por "_" NO son rutas: Vercel no los publica. Este
   es código compartido por las funciones que gastan dinero.

   POR QUÉ EXISTE. La puerta de contraseña (middleware.js) dejó de tapar
   `/api/` porque tapándolo rompía las llamadas de la propia app. Pero una API
   que llama a Gemini y consume cuota no puede quedar abierta a cualquiera que
   sepa la URL.

   QUÉ COMPRUEBA. Que la petición llega desde el mismo sitio que la sirve:
   cabecera `Origin` (o `Referer` si no hay) contra el host del despliegue. Un
   navegador las pone siempre y no se pueden falsificar desde JavaScript de
   otra web; con curl sí, y por eso esto NO es autenticación: es la valla que
   evita que la URL corra por ahí y alguien se gaste la cuota del club por
   curiosidad. La autenticación de verdad llega con Supabase.

   Se puede desactivar poniendo SF_API_ABIERTA=1 en Vercel, para probar con
   curl desde fuera sin tener que tocar el código. */

export function mismaCasa(req) {
  if (process.env.SF_API_ABIERTA === '1') return true;

  const host = String(req.headers['x-forwarded-host'] || req.headers.host || '').toLowerCase();
  if (!host) return true;            // sin host no se puede comparar: no se bloquea

  const de = String(req.headers.origin || req.headers.referer || '');
  if (!de) return false;             // una llamada de navegador SIEMPRE trae una de las dos

  try {
    return new URL(de).host.toLowerCase() === host;
  } catch (e) {
    return false;
  }
}

/* Respuesta única para cuando no lo es, para que las cuatro funciones digan
   lo mismo y con el mismo motivo legible. */
export function fueraDeCasa(res) {
  return res.status(403).json({
    ok: false, motivo: 'otro_origen',
    detalle: 'Esta API solo responde a la aplicación de ScoutFlow. Para probarla desde fuera, ' +
             'pon SF_API_ABIERTA=1 en Vercel.'
  });
}
