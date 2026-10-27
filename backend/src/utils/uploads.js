// Utilidades de subida de evidencias (fotos/PDF) para los flujos control (QR INNPACK) y calidad-faret.
// Sin dependencias nuevas: valida el CONTENIDO real (firma de archivo), no el nombre ni el mimetype
// que declara el cliente (la app envía application/octet-stream).
const fs = require('fs');
const path = require('path');
const multer = require('multer');

const MAX_BYTES = 10 * 1024 * 1024;

// tipo de contenido real -> extensión canónica con la que se guarda (la extensión del cliente no se usa)
const EXTENSION_POR_TIPO = { jpeg: '.jpg', png: '.png', pdf: '.pdf' };

const detectarTipo = (cabecera) => {
    if (cabecera.length >= 3 && cabecera[0] === 0xff && cabecera[1] === 0xd8 && cabecera[2] === 0xff) return 'jpeg';
    if (cabecera.length >= 8 && cabecera.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'png';
    if (cabecera.length >= 5 && cabecera.subarray(0, 5).toString('latin1') === '%PDF-') return 'pdf';
    return null;
};

const archivosDe = (req) => {
    if (Array.isArray(req.files)) return req.files;
    return req.file ? [req.file] : [];
};

const borrarArchivos = (req) => {
    for (const archivo of archivosDe(req)) {
        try { fs.unlinkSync(archivo.path); } catch (_) { }
    }
};

// Crea el middleware multer: nombre generado por el servidor y tope de tamaño. La extensión definitiva
// se decide en validarContenido a partir del contenido real.
const crearUpload = (uploadDir) => {
    fs.mkdirSync(uploadDir, { recursive: true });

    return multer({
        storage: multer.diskStorage({
            destination: (req, file, cb) => cb(null, uploadDir),
            filename: (req, file, cb) => cb(null, `${Date.now()}-${Math.round(Math.random() * 1E9)}.upload`),
        }),
        limits: { fileSize: MAX_BYTES },
    });
};

// Después de multer: el contenido debe ser JPG, PNG o PDF reales; el archivo se renombra con la extensión
// que le corresponde. Si algo no cumple, se descartan TODOS los archivos de la petición.
const validarContenido = (req, res, next) => {
    try {
        for (const archivo of archivosDe(req)) {
            const fd = fs.openSync(archivo.path, 'r');
            const cabecera = Buffer.alloc(8);
            const leidos = fs.readSync(fd, cabecera, 0, 8, 0);
            fs.closeSync(fd);

            const tipo = detectarTipo(cabecera.subarray(0, leidos));
            if (!tipo) {
                borrarArchivos(req);
                return res.status(400).json({
                    ok: false,
                    message: `El archivo "${archivo.originalname}" no es una imagen JPG/PNG ni un PDF válido.`,
                });
            }

            const nombreFinal = archivo.filename.replace(/\.upload$/, EXTENSION_POR_TIPO[tipo]);
            const rutaFinal = path.join(path.dirname(archivo.path), nombreFinal);
            fs.renameSync(archivo.path, rutaFinal);
            archivo.filename = nombreFinal;
            archivo.path = rutaFinal;
            archivo.mimetype = { jpeg: 'image/jpeg', png: 'image/png', pdf: 'application/pdf' }[tipo];
        }
        next();
    } catch (error) {
        borrarArchivos(req);
        next(error);
    }
};

// Va al final del router: traduce errores de subida a respuestas JSON claras.
const manejarErroresUpload = (err, req, res, next) => {
    if (err instanceof multer.MulterError) {
        const mensajes = {
            LIMIT_FILE_SIZE: 'El archivo supera el máximo de 10 MB.',
            LIMIT_UNEXPECTED_FILE: 'Se enviaron más archivos de los permitidos.',
            LIMIT_FILE_COUNT: 'Se enviaron más archivos de los permitidos.',
        };
        return res.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ ok: false, message: mensajes[err.code] || 'Error al subir el archivo.' });
    }
    next(err);
};

// Identificador generado por la app para que un reintento no duplique el registro.
const normalizarClientId = (valor) => {
    const texto = typeof valor === 'string' ? valor.trim() : '';
    return /^[A-Za-z0-9-]{8,36}$/.test(texto) ? texto : null;
};

module.exports = { MAX_BYTES, crearUpload, validarContenido, manejarErroresUpload, borrarArchivos, normalizarClientId, detectarTipo };
