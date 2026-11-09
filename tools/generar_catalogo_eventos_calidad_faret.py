#!/usr/bin/env python3
"""Genera el bloque de carga (seed) del catálogo maestro de eventos de calidad FARET.

Lee el Excel aprobado por Calidad (docs/Catalogo_maestro_eventos_calidad.xlsx), lo VALIDA contra sus propias
reglas (hoja "Guia programador") y contra su hoja "Resumen criticidad", y escribe el resultado como SQL dentro de
backend/migrations/010_catalogo_eventos_calidad_faret.sql, entre los marcadores:

    -- >>> SEED GENERADO ...
    -- <<< FIN SEED GENERADO

Nada se transcribe a mano: IDs, textos y criticidades salen del Excel tal cual (sin corregir redacción).

Uso (desde la raíz del repo):
    python -I tools/generar_catalogo_eventos_calidad_faret.py --verificar   # no escribe; exit 1 si el SQL no coincide con el Excel
    python -I tools/generar_catalogo_eventos_calidad_faret.py --escribir    # regenera el bloque en la migración

Requiere openpyxl (solo lectura del .xlsx). No toca ninguna base de datos.
"""
import argparse
import hashlib
import re
import sys
import unicodedata
from collections import Counter, OrderedDict
from pathlib import Path

import openpyxl

RAIZ = Path(__file__).resolve().parent.parent
XLSX = RAIZ / 'docs' / 'Catalogo_maestro_eventos_calidad.xlsx'
MIGRACION = RAIZ / 'backend' / 'migrations' / '010_catalogo_eventos_calidad_faret.sql'
CATALOGO_DART = RAIZ / 'lib' / 'features' / 'calidad_faret' / 'domain' / 'calidad_faret_catalog.dart'

INICIO = '-- >>> SEED GENERADO'
FIN = '-- <<< FIN SEED GENERADO'

CRITICIDADES = ('Critico', 'Mayor', 'Menor')
ESTADOS = ('Activo', 'Inactivo')

# Número de área de control que usa la app y los registros históricos (registros_calidad_faret.area_control,
# p. ej. '03-OFFSET'). El Excel solo trae el código de 3 letras: esta tabla es el puente hacia lo que ya existe.
NUM_AREA_CONTROL = OrderedDict([
    ('LAM', '02'), ('OFF', '03'), ('SER', '04'), ('FOL', '05'),
    ('TRO', '07'), ('PEG', '10'), ('FLT', '12'), ('CYD', '13'),
])

# Resultado esperado según el pedido de Calidad (Pedro Roa); el generador falla si el Excel difiere.
ESPERADO = {'areas': 8, 'eventos': 57, 'Critico': 42, 'Mayor': 14, 'Menor': 1}
PENDIENTES_ESPERADOS = ['CYD-003', 'FOL-007', 'PEG-007', 'PEG-008', 'SER-007']


def norm(s):
    s = unicodedata.normalize('NFD', str(s).strip().upper())
    return ''.join(c for c in s if unicodedata.category(c) != 'Mn')


def texto(v):
    return None if v is None or str(v).strip() == '' else str(v)


def sql_str(v, maxlen=None):
    if v is None:
        return 'NULL'
    if maxlen is not None and len(v) > maxlen:
        raise SystemExit(f'ERROR: texto de {len(v)} caracteres excede {maxlen}: {v!r}')
    return "N'" + v.replace("'", "''") + "'"


def leer_excel(ruta):
    wb = openpyxl.load_workbook(ruta, data_only=False)
    for hoja in ('Catalogo eventos', 'Areas', 'Resumen criticidad'):
        if hoja not in wb.sheetnames:
            raise SystemExit(f'ERROR: falta la hoja {hoja!r} (hay {wb.sheetnames})')

    errores = []

    # ---- Áreas ---------------------------------------------------------------------------------
    filas = list(wb['Areas'].iter_rows(values_only=True))
    if [norm(c) for c in filas[0][:3]] != ['COD_AREA', 'NOMBRE_AREA', 'ESTADO']:
        errores.append(f'Encabezado inesperado en hoja Areas: {filas[0]}')
    areas = OrderedDict()
    for f in filas[1:]:
        if not f or f[0] is None:
            continue
        cod, nombre, estado = (str(f[0]).strip(), str(f[1]).strip(), str(f[2]).strip())
        if cod in areas:
            errores.append(f'Área duplicada: {cod}')
        if estado not in ESTADOS:
            errores.append(f'Estado de área inválido {cod}: {estado!r}')
        areas[cod] = {'cod': cod, 'nombre': nombre, 'estado': estado}

    # ---- Eventos -------------------------------------------------------------------------------
    filas = list(wb['Catalogo eventos'].iter_rows(values_only=True))
    esperado = ['ID_EVENTO', 'COD_AREA', 'AREA', 'TIPO_REGISTRO', 'DEFECTO', 'CRITICIDAD', 'ESTADO',
                'OBSERVACIONES', 'TEXTO_ORIGINAL']
    if [norm(c) for c in filas[0][:9]] != esperado:
        errores.append(f'Encabezado inesperado en hoja Catalogo eventos: {filas[0]}')
    eventos = []
    ids, por_area_defecto = set(), set()
    for n, f in enumerate(filas[1:], start=2):
        if not f or f[0] is None:
            continue
        ev = {
            'id': str(f[0]).strip(), 'cod': str(f[1]).strip(), 'area': str(f[2]).strip(),
            'tipo': str(f[3]).strip(), 'defecto': str(f[4]), 'criticidad': str(f[5]).strip(),
            'estado': str(f[6]).strip(), 'observacion': texto(f[7]), 'texto_original': str(f[8]),
            'fila': n,
        }
        if not re.fullmatch(r'[A-Z]{3}-\d{3}', ev['id']):
            errores.append(f'Fila {n}: ID_EVENTO con formato inválido {ev["id"]!r}')
        if ev['id'] in ids:
            errores.append(f'Fila {n}: ID_EVENTO duplicado {ev["id"]}')
        ids.add(ev['id'])
        if ev['id'][:3] != ev['cod']:
            errores.append(f'Fila {n}: el prefijo del ID ({ev["id"]}) no coincide con COD_AREA ({ev["cod"]})')
        if ev['cod'] not in areas:
            errores.append(f'Fila {n}: COD_AREA {ev["cod"]} no existe en la hoja Areas')
        elif norm(areas[ev['cod']]['nombre']) != norm(ev['area']):
            errores.append(f'Fila {n}: AREA {ev["area"]!r} no coincide con la hoja Areas ({areas[ev["cod"]]["nombre"]!r})')
        if ev['criticidad'] not in CRITICIDADES:
            errores.append(f'Fila {n}: CRITICIDAD inválida {ev["criticidad"]!r} (solo {CRITICIDADES})')
        if ev['estado'] not in ESTADOS:
            errores.append(f'Fila {n}: ESTADO inválido {ev["estado"]!r}')
        if not ev['defecto'].strip():
            errores.append(f'Fila {n}: DEFECTO vacío')
        clave = (ev['cod'], norm(ev['defecto']).rstrip('.'))
        if clave in por_area_defecto:
            errores.append(f'Fila {n}: defecto repetido en el área {ev["cod"]}: {ev["defecto"]!r}')
        por_area_defecto.add(clave)
        eventos.append(ev)

    # ---- Resumen criticidad: debe cuadrar con el detalle ---------------------------------------
    cuenta = Counter((norm(e['area']), e['criticidad']) for e in eventos)
    filas = list(wb['Resumen criticidad'].iter_rows(values_only=True))
    for f in filas[1:]:
        if not f or f[0] is None or norm(f[0]).startswith('TOTAL'):
            continue
        for col, crit in ((1, 'Critico'), (2, 'Mayor'), (3, 'Menor')):
            if int(f[col] or 0) != cuenta.get((norm(f[0]), crit), 0):
                errores.append(f'Resumen criticidad no cuadra: {f[0]} {crit} = {f[col]} vs detalle {cuenta.get((norm(f[0]), crit), 0)}')

    # ---- Totales exigidos ----------------------------------------------------------------------
    tot = Counter(e['criticidad'] for e in eventos)
    reales = {'areas': len(areas), 'eventos': len(eventos), 'Critico': tot['Critico'], 'Mayor': tot['Mayor'], 'Menor': tot['Menor']}
    if reales != ESPERADO:
        errores.append(f'Totales distintos de lo aprobado: {reales} vs {ESPERADO}')
    pendientes = sorted(e['id'] for e in eventos if e['observacion'])
    if pendientes != PENDIENTES_ESPERADOS:
        errores.append(f'Eventos con observación: {pendientes} vs esperados {PENDIENTES_ESPERADOS}')
    if set(NUM_AREA_CONTROL) != set(areas):
        errores.append(f'Áreas del Excel {list(areas)} no coinciden con el mapa a área de control {list(NUM_AREA_CONTROL)}')

    # ---- Etiqueta área de control: debe existir EXACTA en el catálogo vigente de la app --------
    if CATALOGO_DART.exists():
        dart = CATALOGO_DART.read_text(encoding='utf-8')
        bloque = dart.split('areasControl = [')[1].split('];')[0]
        etiquetas_app = re.findall(r"'([^']+)'", bloque)
        for cod, a in areas.items():
            a['area_control'] = f'{NUM_AREA_CONTROL[cod]}-{a["nombre"]}'
            if a['area_control'] not in etiquetas_app:
                errores.append(f'Etiqueta de área de control {a["area_control"]!r} no existe en calidad_faret_catalog.dart {etiquetas_app}')
    else:
        for cod, a in areas.items():
            a['area_control'] = f'{NUM_AREA_CONTROL[cod]}-{a["nombre"]}'

    if errores:
        raise SystemExit('ERRORES DE VALIDACIÓN DEL EXCEL:\n  - ' + '\n  - '.join(errores))
    return areas, eventos


def generar_bloque(areas, eventos, sha256):
    tot = Counter(e['criticidad'] for e in eventos)
    pend = [e['id'] for e in eventos if e['observacion']]
    L = []
    L.append(f'{INICIO} (tools/generar_catalogo_eventos_calidad_faret.py) -- NO EDITAR A MANO')
    L.append(f'-- Fuente: docs/Catalogo_maestro_eventos_calidad.xlsx   SHA-256: {sha256}')
    L.append(f'-- Áreas: {len(areas)} | Eventos: {len(eventos)} | Critico: {tot["Critico"]} | Mayor: {tot["Mayor"]} | '
             f'Menor: {tot["Menor"]} | Pendientes de aprobación de Calidad: {len(pend)} ({", ".join(pend)})')
    L.append(f'DECLARE @esp_areas INT = {len(areas)}, @esp_eventos INT = {len(eventos)}, @esp_critico INT = {tot["Critico"]}, '
             f'@esp_mayor INT = {tot["Mayor"]}, @esp_menor INT = {tot["Menor"]}, @esp_pendientes INT = {len(pend)};')
    L.append('')
    L.append('CREATE TABLE #seed_areas (')
    L.append('    cod_area NVARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,')
    L.append('    nombre NVARCHAR(60) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    area_control NVARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    orden SMALLINT NOT NULL,')
    L.append('    estado NVARCHAR(8) COLLATE DATABASE_DEFAULT NOT NULL')
    L.append(');')
    L.append('INSERT INTO #seed_areas (cod_area, nombre, area_control, orden, estado) VALUES')
    filas = []
    for i, a in enumerate(areas.values(), start=1):
        filas.append(f'    ({sql_str(a["cod"], 3)}, {sql_str(a["nombre"], 60)}, {sql_str(a["area_control"], 50)}, {i}, {sql_str(a["estado"], 8)})')
    L.append(',\n'.join(filas) + ';')
    L.append('')
    L.append('CREATE TABLE #seed_eventos (')
    L.append('    id_evento NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,')
    L.append('    cod_area NVARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    tipo_registro NVARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    defecto NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    criticidad NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    estado_origen NVARCHAR(8) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    observacion_origen NVARCHAR(300) COLLATE DATABASE_DEFAULT NULL,')
    L.append('    texto_documento NVARCHAR(300) COLLATE DATABASE_DEFAULT NOT NULL,')
    L.append('    orden SMALLINT NOT NULL')
    L.append(');')
    L.append('INSERT INTO #seed_eventos (id_evento, cod_area, tipo_registro, defecto, criticidad, estado_origen, observacion_origen, texto_documento, orden) VALUES')
    filas = []
    for i, e in enumerate(eventos, start=1):
        filas.append(
            f'    ({sql_str(e["id"], 10)}, {sql_str(e["cod"], 3)}, {sql_str(e["tipo"], 30)}, {sql_str(e["defecto"], 150)}, '
            f'{sql_str(e["criticidad"], 10)}, {sql_str(e["estado"], 8)}, {sql_str(e["observacion"], 300)}, '
            f'{sql_str(e["texto_original"], 300)}, {i})')
    L.append(',\n'.join(filas) + ';')
    L.append(FIN)
    return '\n'.join(L)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--verificar', action='store_true', help='compara el bloque de la migración con el Excel (no escribe)')
    g.add_argument('--escribir', action='store_true', help='regenera el bloque dentro de la migración')
    ap.add_argument('--xlsx', default=str(XLSX))
    ap.add_argument('--migracion', default=str(MIGRACION))
    args = ap.parse_args()

    xlsx = Path(args.xlsx)
    sha256 = hashlib.sha256(xlsx.read_bytes()).hexdigest()
    areas, eventos = leer_excel(xlsx)
    bloque = generar_bloque(areas, eventos, sha256)

    mig = Path(args.migracion)
    contenido = mig.read_text(encoding='utf-8')
    patron = re.compile(re.escape(INICIO) + r'.*?' + re.escape(FIN), re.S)
    if not patron.search(contenido):
        raise SystemExit(f'ERROR: {mig} no tiene los marcadores "{INICIO}" / "{FIN}"')
    nuevo = patron.sub(lambda _m: bloque, contenido, count=1)

    tot = Counter(e['criticidad'] for e in eventos)
    print(f'Excel OK: {len(areas)} áreas, {len(eventos)} eventos '
          f'(Critico {tot["Critico"]}, Mayor {tot["Mayor"]}, Menor {tot["Menor"]}); SHA-256 {sha256[:16]}…')
    if args.verificar:
        if nuevo != contenido:
            print('DIFERENCIA: el bloque de la migración NO coincide con el Excel. Ejecute --escribir y revise el diff.')
            return 1
        print('La migración coincide exactamente con el Excel.')
        return 0
    if nuevo != contenido:
        mig.write_text(nuevo, encoding='utf-8', newline='\n')
        print(f'Bloque regenerado en {mig}')
    else:
        print('Sin cambios (ya estaba al día).')
    return 0


if __name__ == '__main__':
    sys.exit(main())
