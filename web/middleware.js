/* ============================================================================
   ScoutFlow Academy — Web comercial · puerta de acceso
   ----------------------------------------------------------------------------
   Copia de la puerta que protege la app, para el proyecto de la web comercial.
   Se controla por separado: cada proyecto tiene sus propias variables.

   - Si en ESTE proyecto NO existe SF_PASS, la web comercial es pública.
   - Si la creas, pide usuario y contraseña igual que la app.

   Mientras la web esté en construcción, conviene ponerla. El día que quieras
   que los clubes la vean, basta con borrar SF_PASS y volver a desplegar.
   ========================================================================== */

export const config = {
  matcher: '/((?!favicon.ico|_vercel).*)'
};

export default function middleware(request) {
  const PASS = process.env.SF_PASS;
  if (!PASS) return;                       // sin contraseña -> web pública

  const USER = process.env.SF_USER || 'cbja';
  const auth = request.headers.get('authorization') || '';

  if (auth.startsWith('Basic ')) {
    try {
      const decoded = atob(auth.slice(6));
      const i = decoded.indexOf(':');
      if (decoded.slice(0, i) === USER && decoded.slice(i + 1) === PASS) return;
    } catch (e) { /* cabecera mal formada */ }
  }

  return new Response(
    'ScoutFlow Academy — web en construcción.',
    {
      status: 401,
      headers: {
        'WWW-Authenticate': 'Basic realm="ScoutFlow Academy", charset="UTF-8"',
        'Content-Type': 'text/plain; charset=utf-8'
      }
    }
  );
}
