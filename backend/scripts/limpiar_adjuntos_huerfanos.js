// Limpieza de evidencias huérfanas en uploads/control y uploads/calidad_faret.
//   node scripts/limpiar_adjuntos_huerfanos.js            -> solo LISTA (dry-run, no borra nada)
//   node scripts/limpiar_adjuntos_huerfanos.js --borrar   -> borra lo listado
//   --horas=24 (por defecto): solo considera archivos más antiguos que eso, para no tocar subidas en curso.
// Huérfano = (a) temporal ".upload" que nunca terminó de procesarse, o
//            (b) en calidad_faret, archivo que ninguna fila de registro_calidad_faret_adjuntos referencia.
// En uploads/control solo se aplica (a): la cuenta de la app no tiene SELECT sobre registro_adjuntos.
const fs = require('fs');
const path = require('path');

const listarHuerfanos = ({ dir, referenciados, ahora = Date.now(), horas = 24 }) => {
    if (!fs.existsSync(dir)) return [];
    const limite = ahora - horas * 3600 * 1000;
    return fs.readdirSync(dir)
        .map((nombre) => ({ nombre, ruta: path.join(dir, nombre), stat: fs.statSync(path.join(dir, nombre)) }))
        .filter((f) => f.stat.isFile() && f.stat.mtimeMs < limite)
        .filter((f) => f.nombre.endsWith('.upload') || (referenciados && !referenciados.has(f.nombre)))
        .map((f) => ({ ruta: f.ruta, bytes: f.stat.size, motivo: f.nombre.endsWith('.upload') ? 'temporal sin procesar' : 'sin registro asociado' }));
};

module.exports = { listarHuerfanos };

if (require.main === module) {
    (async () => {
        require('dotenv').config({ path: path.join(__dirname, '../.env') });
        const { getCalidadSqlServerPool } = require('../src/config/calidadSqlServerPool');
        const borrar = process.argv.includes('--borrar');
        const horas = Number((process.argv.find((a) => a.startsWith('--horas=')) || '--horas=24').split('=')[1]);

        const pool = await getCalidadSqlServerPool();
        const faret = await pool.request().query('SELECT nombre_archivo FROM registro_calidad_faret_adjuntos');
        const referenciadosFaret = new Set(faret.recordset.map((r) => r.nombre_archivo));

        const uploads = path.join(__dirname, '../uploads');
        const huerfanos = [
            ...listarHuerfanos({ dir: path.join(uploads, 'control'), referenciados: null, horas }),
            ...listarHuerfanos({ dir: path.join(uploads, 'calidad_faret'), referenciados: referenciadosFaret, horas }),
        ];

        for (const h of huerfanos) {
            console.log(`${borrar ? 'BORRA' : 'huérfano'}  ${h.ruta}  (${h.bytes} bytes, ${h.motivo})`);
            if (borrar) fs.unlinkSync(h.ruta);
        }
        console.log(`${huerfanos.length} archivo(s) ${borrar ? 'borrados' : 'detectados (dry-run; use --borrar para eliminarlos)'}`);
        await pool.close();
    })().catch((e) => { console.error('Error:', e.message); process.exit(1); });
}
