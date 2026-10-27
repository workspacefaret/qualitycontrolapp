const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload, limitarPeticion, MAX_BYTES } = require('../utils/uploads');

const router = express.Router();

const {
    getContextoPorQr,
    crearRegistroControl,
} = require('../controllers/control.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/control'));

router.get('/contexto/:codigoQr', getContextoPorQr);
router.post('/registros', limitarPeticion(MAX_BYTES + 1024 * 1024), upload.single('archivo'), validarContenido, crearRegistroControl);

router.use(manejarErroresUpload);

module.exports = router;
