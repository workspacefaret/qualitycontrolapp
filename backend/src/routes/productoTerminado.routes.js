const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload } = require('../utils/uploads');

const router = express.Router();

const {
    crearRegistroProductoTerminado,
    listarRegistrosProductoTerminado,
    obtenerRegistroProductoTerminado,
} = require('../controllers/productoTerminado.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/producto_terminado'));

router.post('/registros', upload.array('fotos', 100), validarContenido, crearRegistroProductoTerminado);
router.get('/registros', listarRegistrosProductoTerminado);
router.get('/registros/:id', obtenerRegistroProductoTerminado);

router.use(manejarErroresUpload);

module.exports = router;
