const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload, limitarPeticion } = require('../utils/uploads');

const router = express.Router();

const {
    getContextoPorQr,
    crearRegistroControl,
} = require('../controllers/control.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/control'));

// 'archivo' = evidencia de la inspección (como siempre). 'fotosPallet' = fotos opcionales de la clasificación de pallets
// (hasta 30, una por pallet). Los clientes antiguos solo envían 'archivo' y siguen funcionando igual.
const MAX_FOTOS_PALLET = 30;
const subida = upload.fields([{ name: 'archivo', maxCount: 1 }, { name: 'fotosPallet', maxCount: MAX_FOTOS_PALLET }]);

// multer.fields() entrega un objeto por campo: se restablece req.file (evidencia) y req.files como lista plana,
// que es lo que usan validarContenido, borrarArchivos y el controlador.
const adaptarArchivos = (req, res, next) => {
    const porCampo = req.files && !Array.isArray(req.files) ? req.files : {};
    const evidencia = porCampo.archivo || [];
    req.file = evidencia[0];
    req.fotosPallet = porCampo.fotosPallet || [];
    req.files = [...evidencia, ...req.fotosPallet];
    next();
};

router.get('/contexto/:codigoQr', getContextoPorQr);
// 150 MB por petición: mismo tope que IIS para este servicio; cada archivo sigue limitado a 25 MB por multer.
router.post('/registros', limitarPeticion(150 * 1024 * 1024), subida, adaptarArchivos, validarContenido, crearRegistroControl);

router.use(manejarErroresUpload);

module.exports = router;
