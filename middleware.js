/* ============================================================================
   ScoutFlow Academy — Puerta de acceso
   ----------------------------------------------------------------------------
   Mientras la plataforma está en construcción, la web pide usuario y
   contraseña antes de mostrar nada. Se ejecuta en Vercel ANTES de servir la
   página, así que quien no tenga la clave no llega a descargar la app.

   LA CONTRASEÑA NO ESTÁ EN ESTE ARCHIVO, y es a propósito: el repositorio es
   público y cualquiera podría leerla. Se configura en Vercel como variable de
   entorno, donde solo la ves tú.

   Cómo activarla (en vercel.com, dentro del proyecto):
     Settings → Environment Variables → Add
        Name:  SF_PASS      Value: (la contraseña que elijas)
        Name:  SF_USER      Value: (opcional; si no, el usuario es "cbja")
     Después: Deployments → ... → Redeploy

   MIENTRAS NO EXISTA SF_PASS, ESTO NO BLOQUEA NADA. Así, si algo fallara,
   la web sigue funcionando en vez de quedarse inaccesible.

   Para quitar la protección: borra la variable SF_PASS y vuelve a desplegar.
   ========================================================================== */

export const config = {
  // Se protege todo menos el icono de la pestaña y los archivos internos
  matcher: '/((?!favicon.ico|_vercel).*)'
};

export default function middleware(request) {
  const PASS = process.env.SF_PASS;

  // Sin contraseña configurada -> no se bloquea nada
  if (!PASS) return;

  const USER = process.env.SF_USER || 'cbja';
  const auth = request.headers.get('authorization') || '';

  if (auth.startsWith('Basic ')) {
    try {
      const decoded = atob(auth.slice(6));
      const i = decoded.indexOf(':');
      const u = decoded.slice(0, i);
      const p = decoded.slice(i + 1);
      if (u === USER && p === PASS) return;   // credenciales correctas: pasa
    } catch (e) { /* cabecera mal formada: se pide de nuevo */ }
  }

  return new Response(
    'ScoutFlow Academy — acceso restringido.\n\nEsta plataforma está en construcción.',
    {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="ScoutFlow Academy", charset="UTF-8"',
        'Content-Type': 'text/plain; charset=utf-8'
      }
    }
  );
}
