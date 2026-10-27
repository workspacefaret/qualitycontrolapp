// Límite de envíos (POST) por IP para los formularios públicos, sin dependencias ni login. Ventana fija en memoria.
// Umbral alto a propósito: la planta puede compartir una sola IP (NAT) entre muchos inspectores. Frena ráfagas/abuso, no el uso normal.
// Variables: LIMITE_POST_POR_MIN (def. 240; 0 = desactivado).
const VENTANA_MS = 60 * 1000;
const contadores = new Map();

const limite = () => {
    const v = parseInt(process.env.LIMITE_POST_POR_MIN, 10);
    return Number.isFinite(v) ? v : 240;
};

const limitarSolicitudes = (req, res, next) => {
    const max = limite();
    if (max <= 0) return next();

    const ahora = Date.now();
    const ip = req.ip || 'desconocida';
    // Si el proxy (IIS/ARR) no entrega la IP real del cliente, todos los envíos parecerían venir de 127.0.0.1: no se limita
    // (un contador compartido bloquearía a toda la planta). Verificar que ARR envíe X-Forwarded-For antes de confiar en este límite.
    if (/^(::1|127\.0\.0\.1|::ffff:127\.0\.0\.1)$/.test(ip)) return next();
    let c = contadores.get(ip);
    if (!c || ahora - c.inicio >= VENTANA_MS) {
        c = { inicio: ahora, n: 0 };
        contadores.set(ip, c);
    }
    c.n += 1;

    if (contadores.size > 5000) {
        for (const [k, v] of contadores) if (ahora - v.inicio >= VENTANA_MS) contadores.delete(k);
    }

    if (c.n > max) {
        res.set('Retry-After', String(Math.ceil((VENTANA_MS - (ahora - c.inicio)) / 1000)));
        console.log(JSON.stringify({ t: new Date().toISOString(), evento: 'limite_solicitudes', ip, metodo: req.method }));
        return res.status(429).json({ ok: false, message: 'Demasiadas solicitudes. Intente nuevamente en un momento.' });
    }
    return next();
};

const _reiniciar = () => contadores.clear();

module.exports = { limitarSolicitudes, _reiniciar };
