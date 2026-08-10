const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');

const router = express.Router();

const {
    getContextoPorQr,
    crearRegistroControl,
} = require('../controllers/control.controller');

const uploadDir = path.join(__dirname, '../../uploads/control');

if (!fs.existsSync(uploadDir)) {
    fs.mkdirSync(uploadDir, { recursive: true });
}

const storage = multer.diskStorage({
    destination: (req, file, cb) => {
        cb(null, uploadDir);
    },
    filename: (req, file, cb) => {
        const ext = path.extname(file.originalname);
        const uniqueName = `${Date.now()}-${Math.round(Math.random() * 1E9)}${ext}`;
        cb(null, uniqueName);
    },
});

const upload = multer({
    storage,
    limits: {
        fileSize: 10 * 1024 * 1024,
    },
});

router.get('/contexto/:codigoQr', getContextoPorQr);
router.post('/registros', upload.single('archivo'), crearRegistroControl);

module.exports = router;
