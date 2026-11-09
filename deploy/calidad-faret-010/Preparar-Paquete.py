"""Herramienta del DESARROLLADOR (no viaja al servidor): sincroniza sql/ desde backend/migrations, valida contra el Excel
y regenera MANIFEST.sha256.   python -I Preparar-Paquete.py [--verificar]"""
import hashlib, shutil, subprocess, sys
from pathlib import Path

PKG = Path(__file__).resolve().parent
RAIZ = PKG.parent.parent
MIG = RAIZ / "backend" / "migrations"
SQLS = ["010_catalogo_eventos_calidad_faret.sql", "010_catalogo_eventos_calidad_faret_rollback.sql"]
EXCLUIR_DIRS = {"salida", "logs"}
EXCLUIR = {"MANIFEST.sha256", "Preparar-Paquete.py"}

def archivos():
    for p in sorted(PKG.rglob("*")):
        rel = p.relative_to(PKG)
        if p.is_dir() or rel.parts[0] in EXCLUIR_DIRS or rel.name in EXCLUIR or rel.name == ".gitattributes":
            continue
        yield rel

def manifiesto():
    lin = ["# SHA-256 de los archivos del paquete calidad-faret-010 (generado por Preparar-Paquete.py)"]
    for rel in archivos():
        lin.append(f"{hashlib.sha256((PKG / rel).read_bytes()).hexdigest()}  {rel.as_posix()}")
    return "\n".join(lin) + "\n"

verificar = "--verificar" in sys.argv
r = subprocess.run([sys.executable, "-I", str(RAIZ / "tools" / "generar_catalogo_eventos_calidad_faret.py"), "--verificar"], capture_output=True, text=True)
if r.returncode != 0:
    print(r.stdout, r.stderr); sys.exit("La migración NO coincide con el Excel.")
for s in SQLS:
    orig, copia = MIG / s, PKG / "sql" / s
    if verificar:
        if orig.read_bytes() != copia.read_bytes():
            sys.exit(f"sql/{s} difiere de backend/migrations/{s}")
    else:
        copia.parent.mkdir(exist_ok=True); shutil.copyfile(orig, copia)
nuevo = manifiesto()
man = PKG / "MANIFEST.sha256"
if verificar:
    if not man.exists() or man.read_text(encoding="utf-8") != nuevo:
        sys.exit("MANIFEST.sha256 desactualizado: ejecute Preparar-Paquete.py sin --verificar")
    print("OK: paquete y manifiesto al día")
else:
    man.write_text(nuevo, encoding="utf-8", newline="\n")
    print(f"MANIFEST.sha256 escrito ({nuevo.count(chr(10)) - 1} archivos)")
