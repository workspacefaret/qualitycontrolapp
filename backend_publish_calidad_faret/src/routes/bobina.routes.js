const express = require('express');

const router = express.Router();

const {
    obtenerBobinaPorLote,
    obtenerBobinasPorNp,
} = require('../controllers/bobina.controller');

router.get('/lote/:lote', obtenerBobinaPorLote);
router.get('/np/:np', obtenerBobinasPorNp);

module.exports = router;
