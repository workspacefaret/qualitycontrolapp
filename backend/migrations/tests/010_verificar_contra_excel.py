#!/usr/bin/env python3
"""Verificación INDEPENDIENTE del seed: compara lo que quedó en la base de pruebas (volcado de sqlcmd) contra el Excel original,
campo por campo (ID, área, texto del defecto, criticidad, estado de origen, observación, texto original), sin pasar por el generador.

Uso: python -I 010_verificar_contra_excel.py <volcado_eventos.tsv> <volcado_areas.tsv> [ruta_xlsx]
Cada línea del volcado: columnas separadas por TAB (sqlcmd -s $'\t' -W -h -1 -y 0).
"""
import sys
from pathlib import Path

import openpyxl

RAIZ = Path(__file__).resolve().parents[3]
xlsx = Path(sys.argv[3]) if len(sys.argv) > 3 else RAIZ / 'docs' / 'Catalogo_maestro_eventos_calidad.xlsx'


def leer(ruta):
    return [l.rstrip('\r\n').split('\t') for l in Path(ruta).read_text(encoding='utf-8-sig').splitlines() if l.strip()]


wb = openpyxl.load_workbook(xlsx)
excel = {str(r[0]).strip(): r for r in list(wb['Catalogo eventos'].iter_rows(values_only=True))[1:] if r[0]}
areas_excel = {str(r[0]).strip(): str(r[1]).strip() for r in list(wb['Areas'].iter_rows(values_only=True))[1:] if r[0]}

db = {f[0]: f for f in leer(sys.argv[1])}
db_areas = {f[0]: f for f in leer(sys.argv[2])}
errores = []

if set(db) != set(excel):
    errores.append(f'IDs distintos. Solo en BD: {sorted(set(db) - set(excel))}; solo en Excel: {sorted(set(excel) - set(db))}')
for id_, r in excel.items():
    f = db.get(id_)
    if not f:
        continue
    # columnas: id, cod_area, defecto_origen, criticidad_origen, estado_origen, observacion_origen, texto_documento, estado, aprobacion
    esperado = [str(r[0]).strip(), str(r[1]).strip(), str(r[4]), str(r[5]).strip(), str(r[6]).strip(),
                '' if r[7] is None else str(r[7]), str(r[8])]
    real = f[:7]
    real[5] = '' if real[5] == 'NULL' else real[5]
    for nombre, e, a in zip(['id', 'cod_area', 'defecto_origen', 'criticidad_origen', 'estado_origen', 'observacion_origen', 'texto_documento'], esperado, real):
        if e != a:
            errores.append(f'{id_}.{nombre}: Excel={e!r} BD={a!r}')
    pendiente = bool(r[7])
    estado, aprobacion = f[7], f[8]
    if pendiente and (estado != 'Inactivo' or aprobacion != 'PENDIENTE'):
        errores.append(f'{id_}: pendiente debe estar Inactivo/PENDIENTE y está {estado}/{aprobacion}')
    if not pendiente and (estado != str(r[6]).strip() or aprobacion != 'NO_REQUERIDA'):
        errores.append(f'{id_}: debe estar {r[6]}/NO_REQUERIDA y está {estado}/{aprobacion}')

for cod, nombre in areas_excel.items():
    a = db_areas.get(cod)
    if not a or a[1] != nombre:
        errores.append(f'Área {cod}: Excel={nombre!r} BD={a[1] if a else None!r}')
if set(db_areas) != set(areas_excel):
    errores.append(f'Áreas distintas: BD {sorted(db_areas)} vs Excel {sorted(areas_excel)}')

if errores:
    print('FAIL  diferencias contra el Excel:')
    for e in errores:
        print('   -', e)
    sys.exit(1)
print(f'PASS  {len(excel)} eventos y {len(areas_excel)} áreas coinciden con el Excel campo por campo (IDs, textos con tildes, criticidades, estados, observaciones)')
