const express = require('express');

const router = express.Router();

const {
    getUsuarios,
    getProcesos,
    getMaquinas,
    getParametrosVisuales,
    getOrigenesProblema,
    getCatalogoOffline,
} = require('../controllers/catalogos.controller');

router.get('/usuarios', getUsuarios);

router.get('/offline', getCatalogoOffline);

router.get('/procesos', getProcesos);

router.get('/maquinas', getMaquinas);

router.get('/parametros-visuales/:procesoId', getParametrosVisuales);

router.get('/origenes-problema/:procesoId', getOrigenesProblema);

module.exports = router;