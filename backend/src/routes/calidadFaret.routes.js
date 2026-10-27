const express = require('express');
const path = require('path');

const { crearUpload, validarContenido, manejarErroresUpload } = require('../utils/uploads');

const router = express.Router();

const {
    crearRegistroCalidadFaret,
    listarRegistrosCalidadFaret,
    obtenerResumenCalidadFaret,
    obtenerResumenMaquinasCalidadFaret,
    listarAdjuntosRegistroCalidadFaret,
    eliminarRegistroCalidadFaret,
} = require('../controllers/calidadFaret.controller');

const upload = crearUpload(path.join(__dirname, '../../uploads/calidad_faret'));

router.post('/registros', upload.array('archivos', 5), validarContenido, crearRegistroCalidadFaret);
router.get('/registros', listarRegistrosCalidadFaret);
router.get('/resumen', obtenerResumenCalidadFaret);
router.get('/maquinas/resumen', obtenerResumenMaquinasCalidadFaret);
router.get('/registros/:id/adjuntos', listarAdjuntosRegistroCalidadFaret);
router.delete('/registros/:id', eliminarRegistroCalidadFaret);

router.use(manejarErroresUpload);

module.exports = router;
