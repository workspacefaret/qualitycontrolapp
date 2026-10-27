// Verifica el endurecimiento de /uploads de server.js sin levantar la BD: se extrae el bloque del middleware.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const express = require('express');

const fuente = fs.readFileSync(path.join(__dirname, '../server.js'), 'utf8');
const bloque = fuente.match(/app\.use\('\/uploads'[\s\S]*?\}, express\.static\([^\n]*\)\);/);

test('/uploads sirve imágenes/PDF con cabeceras seguras y rechaza el resto', async () => {
    assert.ok(bloque, 'no se encontró el bloque de /uploads en server.js');
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'upl-'));
    fs.mkdirSync(path.join(dir, 'uploads/control'), { recursive: true });
    const f = (n, c) => fs.writeFileSync(path.join(dir, 'uploads/control', n), c);
    f('a.jpg', Buffer.from([0xff, 0xd8, 0xff, 0xd9])); f('b.PNG', 'x'); f('c.pdf', '%PDF-'); f('x.html', '<script>1</script>'); f('y.svg', '<svg/>'); f('.env', 'S=1');

    const cwd = process.cwd(); process.chdir(dir);
    const app = express(); eval(bloque[0]);
    const srv = app.listen(0); const base = `http://127.0.0.1:${srv.address().port}`;
    try {
        for (const n of ['a.jpg', 'b.PNG', 'c.pdf']) {
            const r = await fetch(`${base}/uploads/control/${n}`);
            assert.strictEqual(r.status, 200, n);
            assert.strictEqual(r.headers.get('x-content-type-options'), 'nosniff');
            assert.match(r.headers.get('content-security-policy'), /sandbox/);
        }
        for (const n of ['x.html', 'y.svg', '.env', 'noexiste.jpg']) {
            assert.strictEqual((await fetch(`${base}/uploads/control/${n}`)).status, 404, n);
        }
        assert.strictEqual((await fetch(`${base}/uploads/control/`)).status, 404);
    } finally { srv.close(); process.chdir(cwd); fs.rmSync(dir, { recursive: true, force: true }); }
});
