// Si la petición fue autenticada (req.auth), las rutas /uploads/... que aparezcan en la respuesta JSON se devuelven como
// URLs absolutas firmadas y de corta vida. Los clientes que aún no mandan token siguen recibiendo la ruta relativa de siempre.
const { rutaSegura, urlFirmada } = require('../utils/urlsFirmadas');

const firmarValor = (v) => {
    if (typeof v === 'string') {
        const ruta = v.startsWith('/uploads/') ? rutaSegura(v) : null;
        return ruta ? urlFirmada(ruta) : v;
    }
    if (Array.isArray(v)) return v.map(firmarValor);
    if (v && typeof v === 'object' && !(v instanceof Date)) {
        const salida = {};
        for (const [k, x] of Object.entries(v)) salida[k] = firmarValor(x);
        return salida;
    }
    return v;
};

const firmarRespuesta = (req, res, next) => {
    if (!req.auth) return next();
    const original = res.json.bind(res);
    res.json = (cuerpo) => original(firmarValor(cuerpo));
    return next();
};

module.exports = { firmarRespuesta, firmarValor };
