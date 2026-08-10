const express = require('express');

const router = express.Router();

const { obtenerOrdenFabricacion } = require('../controllers/ordenFabricacion.controller');

router.get('/:np', obtenerOrdenFabricacion);

module.exports = router;
