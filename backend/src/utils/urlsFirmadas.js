// URLs temporales firmadas para /uploads. La firma se genera SOLO aquí (servidor); ningún cliente conoce el secreto.
// Formato: /uploads/<carpeta>/<archivo>?exp=<epoch segundos>&sig=<HMAC-SHA256 base64url de "<ruta>|<exp>">
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const CARPETAS = ['control', 'calidad_faret', 'producto_terminado'];
const TTL_SEGUNDOS = Math.min(Math.max(parseInt(process.env.UPLOADS_URL_TTL_SEG, 10) || 600, 30), 3600);
const BASE_PUBLICA = (process.env.UPLOADS_BASE_PUBLICA || 'https://api.faret.cl/calidad').replace(/\/+$/, '');
const UPLOADS_DIR = path.resolve(__dirname, '../../uploads');

// Sin UPLOADS_SECRET se usa uno aleatorio por proceso: las URLs firmadas dejan de valer al reiniciar (duran minutos).
const secreto = process.env.UPLOADS_SECRET || crypto.randomBytes(32).toString('hex');
if (!process.env.UPLOADS_SECRET) console.warn('[uploads] UPLOADS_SECRET no definido: se usa un secreto temporal por proceso');

const firma = (ruta, exp) => crypto.createHmac('sha256', secreto).update(`${ruta}|${exp}`).digest('base64url');

// Acepta solo /uploads/<carpeta permitida>/<archivo.jpg|jpeg|png|pdf> sin separadores ni '..'. Devuelve la ruta normalizada o null.
const rutaSegura = (entrada) => {
    if (typeof entrada !== 'string') return null;
    let ruta;
    try { ruta = new URL(entrada.trim(), 'http://x').pathname; } catch (_) { return null; }
    ruta = ruta.replace(/^\/calidad(?=\/uploads\/)/, '');
    const m = /^\/uploads\/([a-z_]+)\/([A-Za-z0-9._-]+\.(?:jpe?g|png|pdf))$/i.exec(ruta);
    if (!m || !CARPETAS.includes(m[1]) || m[2].includes('..')) return null;
    return `/uploads/${m[1]}/${m[2]}`;
};

const existe = (ruta) => {
    const fisica = path.resolve(UPLOADS_DIR, ruta.slice('/uploads/'.length));
    return fisica.startsWith(UPLOADS_DIR + path.sep) && fs.existsSync(fisica);
};

const firmarRuta = (ruta, ahora = Date.now()) => {
    const exp = Math.floor(ahora / 1000) + TTL_SEGUNDOS;
    return { exp, sig: firma(ruta, exp) };
};

const urlFirmada = (ruta, ahora) => {
    const { exp, sig } = firmarRuta(ruta, ahora);
    return `${BASE_PUBLICA}${ruta}?exp=${exp}&sig=${sig}`;
};

// 'ok' | 'sin_firma' | 'expirada' | 'invalida'
const verificar = (ruta, exp, sig, ahora = Date.now()) => {
    if (!exp && !sig) return 'sin_firma';
    const e = Number(exp);
    if (!Number.isInteger(e) || typeof sig !== 'string') return 'invalida';
    const esperada = Buffer.from(firma(ruta, e));
    const recibida = Buffer.from(sig);
    if (esperada.length !== recibida.length || !crypto.timingSafeEqual(esperada, recibida)) return 'invalida';
    return e * 1000 < ahora ? 'expirada' : 'ok';
};

module.exports = { TTL_SEGUNDOS, CARPETAS, rutaSegura, existe, urlFirmada, verificar, firmarRuta };
