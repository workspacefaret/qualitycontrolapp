const { rutaSegura, verificar } = require('../utils/urlsFirmadas');
const { modo } = require('./auth');
const { ipCliente } = require('./limiteSolicitudes');

// Solo se sirven imágenes y PDF (todo el histórico es .jpg/.jpeg/.png); cualquier otra extensión (html, svg, js...) da 404
// y el navegador no puede reinterpretar el tipo ni ejecutar el contenido.
// Acceso: con ?exp&sig válidos (URL firmada emitida por este servidor tras validar una sesión) siempre; sin firma depende de
// UPLOADS_MODO: off/observar = se sirve como hasta ahora (compatibilidad con clientes antiguos; observar lo registra),
// exigir = 401. Una firma presente pero inválida o vencida se rechaza (403) en cualquier modo.
const uploadsAcceso = (req, res, next) => {
  if (!/\.(jpe?g|png|pdf)$/i.test(req.path)) return res.status(404).end();
  const ruta = rutaSegura('/uploads' + req.path);
  if (!ruta) return res.status(404).end();

  const estado = verificar(ruta, req.query.exp, req.query.sig);
  if (estado === 'invalida' || estado === 'expirada') {
    console.log(JSON.stringify({ t: new Date().toISOString(), evento: 'uploads_firma_' + estado, ruta, ip: ipCliente(req) }));
    return res.status(403).json({ ok: false, message: 'Enlace inválido o vencido.' });
  }
  if (estado === 'sin_firma') {
    const m = modo('UPLOADS_MODO');
    if (m === 'exigir') return res.status(401).json({ ok: false, message: 'Autenticación requerida.' });
    if (m === 'observar') console.log(JSON.stringify({ t: new Date().toISOString(), evento: 'uploads_sin_firma', ruta, ip: ipCliente(req) }));
  }
  res.set({
    'X-Content-Type-Options': 'nosniff',
    'Content-Security-Policy': "default-src 'none'; sandbox",
    'Cache-Control': 'private, max-age=0, no-store',
  });
  next();
};

module.exports = { uploadsAcceso };
