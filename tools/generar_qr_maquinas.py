from reportlab.lib.units import mm
from reportlab.pdfgen import canvas
import qrcode
import os

# =========================
# MAQUINAS
# =========================

maquinas = [

    # =========================
    # CORRUGADO
    # =========================

    {
        'codigo_qr': 'MAQ-COR-AGNATI-STOCK-AUTO',
        'nombre_maquina': 'AGNATI + STOCK AUTOMATICA',
        'proceso': 'CORRUGADO',
        'archivo': 'qr_agnati_stock_auto',
    },
    {
        'codigo_qr': 'MAQ-COR-WEST-RIVER',
        'nombre_maquina': 'WEST RIVER',
        'proceso': 'CORRUGADO',
        'archivo': 'qr_west_river',
    },

    # =========================
    # EMPLACADO
    # =========================

    {
        'codigo_qr': 'MAQ-EMP-STOCK-MANUAL-125',
        'nombre_maquina': 'STOCK MANUAL 125',
        'proceso': 'EMPLACADO',
        'archivo': 'qr_stock_manual_125',
    },
    {
        'codigo_qr': 'MAQ-EMP-STOCK-SEMI-145-1',
        'nombre_maquina': 'STOCK SEMI 145-1',
        'proceso': 'EMPLACADO',
        'archivo': 'qr_stock_semi_145_1',
    },
    {
        'codigo_qr': 'MAQ-EMP-STOCK-SEMI-145-2',
        'nombre_maquina': 'STOCK SEMI 145-2',
        'proceso': 'EMPLACADO',
        'archivo': 'qr_stock_semi_145_2',
    },

    # =========================
    # TROQUELADO
    # =========================

    {
        'codigo_qr': 'MAQ-TRO-BOBST-142-1',
        'nombre_maquina': 'BOBST 142-1',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_142_1',
    },
    {
        'codigo_qr': 'MAQ-TRO-BOBST-142-2',
        'nombre_maquina': 'BOBST 142-2',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_142_2',
    },
    {
        'codigo_qr': 'MAQ-TRO-BOBST-142-3',
        'nombre_maquina': 'BOBST 142-3',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_142_3',
    },
    {
        'codigo_qr': 'MAQ-TRO-BOBST-142-4',
        'nombre_maquina': 'BOBST 142-4',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_142_4',
    },
    {
        'codigo_qr': 'MAQ-TRO-BOBST-142-5',
        'nombre_maquina': 'BOBST 142-5',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_142_5',
    },
    {
        'codigo_qr': 'MAQ-TRO-BOBST-160',
        'nombre_maquina': 'BOBST 160',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_bobst_160',
    },
    {
        'codigo_qr': 'MAQ-TRO-IBERICA-TR105',
        'nombre_maquina': 'IBERICA TR105',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_iberica_tr105',
    },
    {
        'codigo_qr': 'MAQ-TRO-104-1',
        'nombre_maquina': 'TROQUELADO 104-1',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_104_1',
    },
    {
        'codigo_qr': 'MAQ-TRO-104-2',
        'nombre_maquina': 'TROQUELADO 104-2',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_104_2',
    },
    {
        'codigo_qr': 'MAQ-TRO-106-1',
        'nombre_maquina': 'TROQUELADO 106-1',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_106_1',
    },
    {
        'codigo_qr': 'MAQ-TRO-106-2',
        'nombre_maquina': 'TROQUELADO 106-2',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_106_2',
    },
    {
        'codigo_qr': 'MAQ-TRO-144-1',
        'nombre_maquina': 'TROQUELADO 144-1',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_144_1',
    },
    {
        'codigo_qr': 'MAQ-TRO-144-2',
        'nombre_maquina': 'TROQUELADO 144-2',
        'proceso': 'TROQUELADO',
        'archivo': 'qr_troquelado_144_2',
    },

    # =========================
    # PEGADO
    # =========================

    {
        'codigo_qr': 'MAQ-PEG-DIANA-VIII',
        'nombre_maquina': 'DIANA VIII',
        'proceso': 'PEGADO',
        'archivo': 'qr_diana_viii',
    },
    {
        'codigo_qr': 'MAQ-PEG-MANUAL',
        'nombre_maquina': 'PEGADO MANUAL',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_manual',
    },
    {
        'codigo_qr': 'MAQ-PEG-FARM-PRO-1',
        'nombre_maquina': 'FARMACEUTICO PRO-1',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_farm_pro_1',
    },
    {
        'codigo_qr': 'MAQ-PEG-FARM-PRO-2',
        'nombre_maquina': 'FARMACEUTICO PRO-2',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_farm_pro_2',
    },
    {
        'codigo_qr': 'MAQ-PEG-FARM-PRO-3',
        'nombre_maquina': 'FARMACEUTICO PRO-3',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_farm_pro_3',
    },
    {
        'codigo_qr': 'MAQ-PEG-IND-ALPINA',
        'nombre_maquina': 'INDUSTRIAL ALPINA',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_ind_alpina',
    },
    {
        'codigo_qr': 'MAQ-PEG-IND-EXPERTFOLD',
        'nombre_maquina': 'INDUSTRIAL EXPERTFOLD',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_ind_expertfold',
    },
    {
        'codigo_qr': 'MAQ-PEG-IND-DIANA-3',
        'nombre_maquina': 'INDUSTRIAL DIANA-3',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_ind_diana_3',
    },
    {
        'codigo_qr': 'MAQ-PEG-IND-DIANA-5',
        'nombre_maquina': 'INDUSTRIAL DIANA-5',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_ind_diana_5',
    },
    {
        'codigo_qr': 'MAQ-PEG-IND-DIANA-7',
        'nombre_maquina': 'INDUSTRIAL DIANA-7',
        'proceso': 'PEGADO',
        'archivo': 'qr_pegado_ind_diana_7',
    },

    # =========================
    # TERMOFORMADO
    # =========================

    {
        'codigo_qr': 'MAQ-TER-DISC-CIL-1',
        'nombre_maquina': 'DISCOVER CILINDRICA 1',
        'proceso': 'TERMOFORMADO',
        'archivo': 'qr_discover_cil_1',
    },
    {
        'codigo_qr': 'MAQ-TER-DISC-CIL-2',
        'nombre_maquina': 'DISCOVER CILINDRICA 2',
        'proceso': 'TERMOFORMADO',
        'archivo': 'qr_discover_cil_2',
    },
    {
        'codigo_qr': 'MAQ-TER-DISC-CONICA-OVALADA',
        'nombre_maquina': 'DISCOVER CONICA OVALADA',
        'proceso': 'TERMOFORMADO',
        'archivo': 'qr_discover_conica_ovalada',
    },
]

# =========================
# MEDIDAS ETIQUETA ZEBRA
# =========================

label_width = 145 * mm
label_height = 168 * mm

output_dir = 'tools/qr_maquinas'
os.makedirs(output_dir, exist_ok=True)


def generar_etiqueta(maquina):
    codigo_qr = maquina['codigo_qr']
    nombre_maquina = maquina['nombre_maquina']
    proceso = maquina['proceso']
    archivo = maquina['archivo']

    qr_path = f'{output_dir}/{archivo}.png'
    pdf_path = f'{output_dir}/{archivo}.pdf'

    qr = qrcode.QRCode(
        error_correction=qrcode.constants.ERROR_CORRECT_H,
        box_size=14,
        border=3,
    )
    qr.add_data(codigo_qr)
    qr.make(fit=True)
    qr.make_image(fill_color='black', back_color='white').save(qr_path)

    c = canvas.Canvas(pdf_path, pagesize=(label_width, label_height))

    # Fondo
    c.setFillColorRGB(1, 1, 1)
    c.rect(0, 0, label_width, label_height, fill=1, stroke=0)

    margin = 7 * mm

    # Encabezado
    header_h = 30 * mm
    c.setFillColorRGB(0.05, 0.07, 0.09)
    c.roundRect(
        margin,
        label_height - margin - header_h,
        label_width - 2 * margin,
        header_h,
        4 * mm,
        fill=1,
        stroke=0,
    )

    c.setFillColorRGB(1, 1, 1)
    c.setFont('Helvetica-Bold', 20)
    c.drawCentredString(label_width / 2, label_height - 19 * mm, 'CONTROL DE CALIDAD')

    c.setFont('Helvetica-Bold', 15)
    c.drawCentredString(label_width / 2, label_height - 28 * mm, proceso)


    # QR
    qr_size = 88 * mm
    qr_x = (label_width - qr_size) / 2
    qr_y = 50 * mm

    c.drawImage(
        qr_path,
        qr_x,
        qr_y,
        width=qr_size,
        height=qr_size,
        preserveAspectRatio=True,
        mask='auto',
    )

    # Separador
    c.setStrokeColorRGB(0.15, 0.15, 0.15)
    c.setLineWidth(1)
    c.line(margin + 6 * mm, 42 * mm, label_width - margin - 6 * mm, 42 * mm)

    # Máquina
    c.setFillColorRGB(0, 0, 0)
    c.setFont('Helvetica-Bold', 24)
    c.drawCentredString(label_width / 2, 32 * mm, nombre_maquina)

    # Código QR visible
    c.setFont('Helvetica-Bold', 12)
    c.drawCentredString(label_width / 2, 22 * mm, codigo_qr)

    # Pie
    footer_h = 10 * mm
    c.setFillColorRGB(0.05, 0.07, 0.09)
    c.roundRect(
        margin,
        margin,
        label_width - 2 * margin,
        footer_h,
        3 * mm,
        fill=1,
        stroke=0,
    )

    c.setFillColorRGB(1, 1, 1)
    c.setFont('Helvetica-Bold', 10)
    c.drawCentredString(label_width / 2, margin + 3.5 * mm, 'ESCANEAR PARA INICIAR CONTROL')

    c.save()

    print(f'Generado: {pdf_path}')


for maquina in maquinas:
    generar_etiqueta(maquina)

print('QR generados correctamente.')