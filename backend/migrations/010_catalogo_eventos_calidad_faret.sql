-- Catálogo maestro de eventos de calidad (CALIDAD PRODUCCIÓN FARET). Motor: SQL Server (calidad_db).
-- ETAPA 1: solo base de datos. NO cambia el backend ni la app: mientras no se despliegue la Etapa 2, el sistema
-- sigue funcionando exactamente igual (las columnas nuevas quedan NULL y nadie lee las tablas nuevas).
-- Aditiva e idempotente (re-ejecutable, no duplica ni pisa cambios posteriores). Reversible: 010_..._rollback.sql.
--
-- Qué crea
--   calidad_faret_areas              8 áreas (cod_area estable; area_control = etiqueta que ya usan los registros, p. ej. '03-OFFSET')
--   calidad_faret_eventos            57 eventos con criticidad (Critico/Mayor/Menor), baja lógica y aprobación de Calidad
--   calidad_faret_catalogo_auditoria bitácora append-only de cambios (descripción, criticidad, estado, aprobación)
--   vw_calidad_faret_eventos_operables  única definición de "evento utilizable" (activo + área activa + aprobado si lo requiere)
--   registro_calidad_faret_defectos  + id_evento (FK) y criticidad (foto congelada) -- NULL en todo el histórico
--
-- Garantías (en la propia base, además de las validaciones del backend de la Etapa 2)
--   * Histórico intacto: no se modifica ninguna fila existente; id_evento/criticidad quedan NULL = "anterior al catálogo
--     maestro". NO se asocia nada por parecido de nombres.
--   * IDs y datos de origen del Excel inmutables (trigger); sin DELETE (baja lógica con estado = Inactivo); el ID nunca se reutiliza.
--   * Los 5 eventos con observación de redacción (SER-007, FOL-007, PEG-007, PEG-008, CYD-003) se cargan EXACTAMENTE como el
--     Excel (ID, texto, criticidad, estado_origen = Activo, observación) pero inactivos y con aprobacion = PENDIENTE: un CHECK
--     impide activarlos sin aprobación y un trigger impide registrarlos en una inspección.
--   * Un defecto con id_evento solo se acepta si el evento es operable y pertenece al área del defecto del registro
--     (registros_calidad_faret.area_defecto). Los INSERT antiguos (id_evento NULL) pasan sin ninguna validación nueva.
--   * La criticidad guardada en cada inspección no cambia aunque luego cambie el catálogo (trigger la congela).
--
-- Permisos mínimos: SOLO GRANT SELECT (2 tablas + la vista) a quality_control_backend_sql. Ningún INSERT/UPDATE/DELETE nuevo:
-- el backend no administra el catálogo (eso es la Etapa 4). La cuenta ya tiene INSERT/SELECT a nivel de tabla sobre
-- registro_calidad_faret_defectos, por lo que cubre las 2 columnas nuevas.
--
-- Cómo ejecutar: cuenta con DDL, tras respaldar calidad_db, ANTES de desplegar un backend que use estos cambios.
-- Archivo en UTF-8 sin BOM (como la 007/008). Sin GO: es un solo lote; si algo falla, se revierte todo.
-- Auditoría de cambios futuros: antes de modificar el catálogo, la sesión puede informar quién y por qué:
--   EXEC sp_set_session_context N'usuario', N'<quien>'; EXEC sp_set_session_context N'motivo', N'<por qué>';
-- (si no, queda el login de SQL Server y motivo vacío).
SET XACT_ABORT ON;
SET NOCOUNT ON;
-- Opciones de sesión que exigen los índices filtrados y que quedan guardadas en triggers/vista (iguales a las de la 009 y de la app).
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET QUOTED_IDENTIFIER ON;
-- Si no consigue el bloqueo de esquema de registro_calidad_faret_defectos en 5 s (p. ej. una inspección en curso), se
-- cancela todo sin cambios (error 1222) en vez de hacer esperar a las inserciones que llegan detrás. Basta reintentar.
SET LOCK_TIMEOUT 5000;

-- 0. Verificaciones previas (no cambian nada) --------------------------------------------------------------------
-- Si el archivo se leyó con una codificación equivocada, las tildes del catálogo se cargarían mal: se detecta aquí.
IF (N'ÍÑÓ' COLLATE Latin1_General_BIN2) <> (NCHAR(205) + NCHAR(209) + NCHAR(211)) COLLATE Latin1_General_BIN2
    THROW 51000, N'Codificación incorrecta: ejecute este archivo como UTF-8 (sqlcmd clásico: -f 65001; SSMS: abrirlo como Unicode UTF-8).', 1;

IF OBJECT_ID(N'dbo.registros_calidad_faret', N'U') IS NULL OR OBJECT_ID(N'dbo.registro_calidad_faret_defectos', N'U') IS NULL
    THROW 51001, N'Faltan registros_calidad_faret o registro_calidad_faret_defectos: esta no es la calidad_db esperada.', 1;

IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'registro_id') IS NULL
   OR COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'defecto') IS NULL
   OR COL_LENGTH(N'dbo.registros_calidad_faret', N'area_defecto') IS NULL
    THROW 51002, N'Faltan columnas esperadas (registro_id, defecto, area_defecto): el esquema real difiere del documentado.', 1;

IF (COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NOT NULL AND COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') <> 20)
   OR (COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') IS NOT NULL AND COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') <> 20)
    THROW 51003, N'registro_calidad_faret_defectos ya tiene id_evento/criticidad con otro tipo: revisar antes de continuar.', 1;

BEGIN TRANSACTION;

-- 1. Áreas -----------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NULL
CREATE TABLE dbo.calidad_faret_areas (
    cod_area     NVARCHAR(3)   NOT NULL,
    nombre       NVARCHAR(60)  NOT NULL,
    area_control NVARCHAR(50)  NOT NULL,   -- etiqueta vigente en registros_calidad_faret.area_control / area_defecto
    orden        SMALLINT      NOT NULL,
    estado       NVARCHAR(8)   NOT NULL CONSTRAINT DF_calidad_faret_areas_estado DEFAULT (N'Activo'),
    created_at   DATETIME2(0)  NOT NULL CONSTRAINT DF_calidad_faret_areas_created_at DEFAULT (GETDATE()),
    created_by   NVARCHAR(128) NOT NULL CONSTRAINT DF_calidad_faret_areas_created_by DEFAULT (SUSER_SNAME()),
    updated_at   DATETIME2(0)  NULL,
    updated_by   NVARCHAR(128) NULL,
    row_version  ROWVERSION    NOT NULL,   -- control de concurrencia optimista de la futura administración
    CONSTRAINT PK_calidad_faret_areas PRIMARY KEY CLUSTERED (cod_area),
    CONSTRAINT UQ_calidad_faret_areas_area_control UNIQUE (area_control),
    CONSTRAINT CK_calidad_faret_areas_cod CHECK (cod_area LIKE N'[A-Z][A-Z][A-Z]'),
    CONSTRAINT CK_calidad_faret_areas_estado CHECK (estado IN (N'Activo', N'Inactivo')),
    CONSTRAINT CK_calidad_faret_areas_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

-- 2. Eventos ---------------------------------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL
CREATE TABLE dbo.calidad_faret_eventos (
    id_evento           NVARCHAR(10)  NOT NULL,   -- estable e inmutable (OFF-001); nunca se reutiliza
    cod_area            NVARCHAR(3)   NOT NULL,
    tipo_registro       NVARCHAR(30)  NOT NULL,
    -- Vigente (editable con auditoría)
    defecto             NVARCHAR(150) NOT NULL,
    criticidad          NVARCHAR(10)  NOT NULL,   -- Critico / Mayor / Menor (sin tilde, como define el Excel)
    estado              NVARCHAR(8)   NOT NULL,   -- estado OPERATIVO: Activo / Inactivo (baja lógica)
    orden               SMALLINT      NOT NULL,
    -- Origen: transcripción literal del Excel aprobado (inmutable, protegida por trigger)
    defecto_origen      NVARCHAR(150) NOT NULL,
    criticidad_origen   NVARCHAR(10)  NOT NULL,
    estado_origen       NVARCHAR(8)   NOT NULL,
    observacion_origen  NVARCHAR(300) NULL,
    texto_documento     NVARCHAR(300) NOT NULL,   -- columna TEXTO_ORIGINAL (incluye la criticidad del documento fuente)
    -- Aprobación de Calidad (independiente del estado de origen)
    requiere_aprobacion BIT           NOT NULL CONSTRAINT DF_calidad_faret_eventos_req DEFAULT (0),
    aprobacion          NVARCHAR(13)  NOT NULL CONSTRAINT DF_calidad_faret_eventos_apr DEFAULT (N'NO_REQUERIDA'),
    aprobado_por        NVARCHAR(128) NULL,
    aprobado_at         DATETIME2(0)  NULL,
    aprobacion_ref      NVARCHAR(300) NULL,       -- p. ej. "correo de Calidad del 2026-11-12"
    created_at          DATETIME2(0)  NOT NULL CONSTRAINT DF_calidad_faret_eventos_created_at DEFAULT (GETDATE()),
    created_by          NVARCHAR(128) NOT NULL CONSTRAINT DF_calidad_faret_eventos_created_by DEFAULT (SUSER_SNAME()),
    updated_at          DATETIME2(0)  NULL,
    updated_by          NVARCHAR(128) NULL,
    row_version         ROWVERSION    NOT NULL,
    CONSTRAINT PK_calidad_faret_eventos PRIMARY KEY CLUSTERED (id_evento),
    CONSTRAINT FK_calidad_faret_eventos_area FOREIGN KEY (cod_area) REFERENCES dbo.calidad_faret_areas (cod_area),
    CONSTRAINT UQ_calidad_faret_eventos_area_defecto UNIQUE (cod_area, defecto),
    CONSTRAINT CK_calidad_faret_eventos_id CHECK (id_evento LIKE N'[A-Z][A-Z][A-Z]-[0-9][0-9][0-9]' AND LEFT(id_evento, 3) = cod_area),
    CONSTRAINT CK_calidad_faret_eventos_criticidad CHECK (criticidad IN (N'Critico', N'Mayor', N'Menor')),
    CONSTRAINT CK_calidad_faret_eventos_criticidad_origen CHECK (criticidad_origen IN (N'Critico', N'Mayor', N'Menor')),
    CONSTRAINT CK_calidad_faret_eventos_estado CHECK (estado IN (N'Activo', N'Inactivo')),
    CONSTRAINT CK_calidad_faret_eventos_estado_origen CHECK (estado_origen IN (N'Activo', N'Inactivo')),
    CONSTRAINT CK_calidad_faret_eventos_defecto CHECK (LEN(LTRIM(RTRIM(defecto))) > 0),
    CONSTRAINT CK_calidad_faret_eventos_aprobacion CHECK (aprobacion IN (N'NO_REQUERIDA', N'PENDIENTE', N'APROBADA', N'RECHAZADA')),
    -- requiere_aprobacion y aprobacion coherentes
    CONSTRAINT CK_calidad_faret_eventos_aprob_coherente CHECK (
        (requiere_aprobacion = 0 AND aprobacion = N'NO_REQUERIDA') OR (requiere_aprobacion = 1 AND aprobacion <> N'NO_REQUERIDA')),
    -- No se puede activar un evento que requiere aprobación sin que Calidad lo haya aprobado
    CONSTRAINT CK_calidad_faret_eventos_activo_aprobado CHECK (
        NOT (estado = N'Activo' AND requiere_aprobacion = 1 AND aprobacion <> N'APROBADA')),
    -- Una aprobación deja constancia de quién y cuándo
    CONSTRAINT CK_calidad_faret_eventos_aprobador CHECK (
        aprobacion <> N'APROBADA' OR (aprobado_por IS NOT NULL AND aprobado_at IS NOT NULL))
);

-- 3. Auditoría (append-only) -----------------------------------------------------------------------------------------
IF OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria', N'U') IS NULL
CREATE TABLE dbo.calidad_faret_catalogo_auditoria (
    id             BIGINT IDENTITY(1,1) NOT NULL,
    entidad        NVARCHAR(10)  NOT NULL,   -- AREA / EVENTO
    clave          NVARCHAR(10)  NOT NULL,   -- cod_area o id_evento
    accion         NVARCHAR(15)  NOT NULL,   -- CARGA_INICIAL / MODIFICACION
    campo          NVARCHAR(30)  NOT NULL,
    valor_anterior NVARCHAR(300) NULL,
    valor_nuevo    NVARCHAR(300) NULL,
    usuario        NVARCHAR(128) NOT NULL,
    motivo         NVARCHAR(300) NULL,
    fecha          DATETIME2(0)  NOT NULL CONSTRAINT DF_calidad_faret_catalogo_auditoria_fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_calidad_faret_catalogo_auditoria PRIMARY KEY CLUSTERED (id),
    CONSTRAINT CK_calidad_faret_catalogo_auditoria_entidad CHECK (entidad IN (N'AREA', N'EVENTO')),
    CONSTRAINT CK_calidad_faret_catalogo_auditoria_accion CHECK (accion IN (N'CARGA_INICIAL', N'MODIFICACION'))
);

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_calidad_faret_catalogo_auditoria_clave' AND object_id = OBJECT_ID(N'dbo.calidad_faret_catalogo_auditoria'))
    CREATE INDEX IX_calidad_faret_catalogo_auditoria_clave ON dbo.calidad_faret_catalogo_auditoria (entidad, clave, fecha);

-- 4. Vista: única definición de "evento operable" ---------------------------------------------------------------------
IF OBJECT_ID(N'dbo.vw_calidad_faret_eventos_operables', N'V') IS NOT NULL DROP VIEW dbo.vw_calidad_faret_eventos_operables;
EXEC (N'
CREATE VIEW dbo.vw_calidad_faret_eventos_operables AS
SELECT e.id_evento, e.cod_area, a.area_control, a.nombre AS nombre_area, a.orden AS orden_area,
       e.defecto, e.criticidad, e.orden AS orden_evento
FROM dbo.calidad_faret_eventos e
JOIN dbo.calidad_faret_areas a ON a.cod_area = e.cod_area
WHERE e.estado = N''Activo''
  AND a.estado = N''Activo''
  AND (e.requiere_aprobacion = 0 OR e.aprobacion = N''APROBADA'')');

-- 5. Carga desde el Excel aprobado (bloque generado: tools/generar_catalogo_eventos_calidad_faret.py) -----------------
-- >>> SEED GENERADO (tools/generar_catalogo_eventos_calidad_faret.py) -- NO EDITAR A MANO
-- Fuente: docs/Catalogo_maestro_eventos_calidad.xlsx   SHA-256: f41c18ce269e564b478383d10d96fa2e628e7e33a76c14bfe0fe969a931c079a
-- Áreas: 8 | Eventos: 57 | Critico: 42 | Mayor: 14 | Menor: 1 | Pendientes de aprobación de Calidad: 5 (SER-007, FOL-007, PEG-007, PEG-008, CYD-003)
DECLARE @esp_areas INT = 8, @esp_eventos INT = 57, @esp_critico INT = 42, @esp_mayor INT = 14, @esp_menor INT = 1, @esp_pendientes INT = 5;

CREATE TABLE #seed_areas (
    cod_area NVARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    nombre NVARCHAR(60) COLLATE DATABASE_DEFAULT NOT NULL,
    area_control NVARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL,
    orden SMALLINT NOT NULL,
    estado NVARCHAR(8) COLLATE DATABASE_DEFAULT NOT NULL
);
INSERT INTO #seed_areas (cod_area, nombre, area_control, orden, estado) VALUES
    (N'LAM', N'LAMINADO', N'02-LAMINADO', 1, N'Activo'),
    (N'OFF', N'OFFSET', N'03-OFFSET', 2, N'Activo'),
    (N'SER', N'SERIGRAFÍA', N'04-SERIGRAFÍA', 3, N'Activo'),
    (N'FOL', N'FOLIA', N'05-FOLIA', 4, N'Activo'),
    (N'TRO', N'TROQUELADO', N'07-TROQUELADO', 5, N'Activo'),
    (N'PEG', N'PEGADO', N'10-PEGADO', 6, N'Activo'),
    (N'FLT', N'FOLLETOS', N'12-FOLLETOS', 7, N'Activo'),
    (N'CYD', N'CORTE Y DIMENSIONADO', N'13-CORTE Y DIMENSIONADO', 8, N'Activo');

CREATE TABLE #seed_eventos (
    id_evento NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL PRIMARY KEY,
    cod_area NVARCHAR(3) COLLATE DATABASE_DEFAULT NOT NULL,
    tipo_registro NVARCHAR(30) COLLATE DATABASE_DEFAULT NOT NULL,
    defecto NVARCHAR(150) COLLATE DATABASE_DEFAULT NOT NULL,
    criticidad NVARCHAR(10) COLLATE DATABASE_DEFAULT NOT NULL,
    estado_origen NVARCHAR(8) COLLATE DATABASE_DEFAULT NOT NULL,
    observacion_origen NVARCHAR(300) COLLATE DATABASE_DEFAULT NULL,
    texto_documento NVARCHAR(300) COLLATE DATABASE_DEFAULT NOT NULL,
    orden SMALLINT NOT NULL
);
INSERT INTO #seed_eventos (id_evento, cod_area, tipo_registro, defecto, criticidad, estado_origen, observacion_origen, texto_documento, orden) VALUES
    (N'LAM-001', N'LAM', N'Desviación', N'Defecto de anclaje.', N'Critico', N'Activo', NULL, N'Crítico: Defecto de anclaje.', 1),
    (N'LAM-002', N'LAM', N'Desviación', N'Problemas de tratamiento corona.', N'Critico', N'Activo', NULL, N'Crítico: Problemas de tratamiento corona.', 2),
    (N'LAM-003', N'LAM', N'Desviación', N'Traslape.', N'Menor', N'Activo', NULL, N'Menor: Traslape.', 3),
    (N'LAM-004', N'LAM', N'Desviación', N'Calce de pliego', N'Mayor', N'Activo', NULL, N'Mayor: Calce de pliego', 4),
    (N'OFF-001', N'OFF', N'Desviación', N'Abolladura de mantilla de impresión o barniz', N'Critico', N'Activo', NULL, N'Crítico: Abolladura de mantilla de impresión o barniz', 5),
    (N'OFF-002', N'OFF', N'Desviación', N'Calce de impresión.', N'Critico', N'Activo', NULL, N'Crítico: Calce de impresión.', 6),
    (N'OFF-003', N'OFF', N'Desviación', N'Calce de registro lateral y frontal.', N'Critico', N'Activo', NULL, N'Crítico: Calce de registro lateral y frontal.', 7),
    (N'OFF-004', N'OFF', N'Desviación', N'Diferencia de tono.', N'Critico', N'Activo', NULL, N'Crítico: Diferencia de tono.', 8),
    (N'OFF-005', N'OFF', N'Desviación', N'Empaste.', N'Critico', N'Activo', NULL, N'Crítico: Empaste.', 9),
    (N'OFF-006', N'OFF', N'Desviación', N'Imagen fantasma.', N'Mayor', N'Activo', NULL, N'Mayor: Imagen fantasma.', 10),
    (N'OFF-007', N'OFF', N'Desviación', N'Presencia de piojos.', N'Mayor', N'Activo', NULL, N'Mayor: Presencia de piojos.', 11),
    (N'OFF-008', N'OFF', N'Desviación', N'Presencia de velo.', N'Mayor', N'Activo', NULL, N'Mayor: Presencia de velo.', 12),
    (N'OFF-009', N'OFF', N'Desviación', N'Problemas de sustrato.', N'Critico', N'Activo', NULL, N'Crítico: Problemas de sustrato.', 13),
    (N'OFF-010', N'OFF', N'Desviación', N'Repinte.', N'Critico', N'Activo', NULL, N'Crítico: Repinte.', 14),
    (N'OFF-011', N'OFF', N'Desviación', N'Rayas.', N'Mayor', N'Activo', NULL, N'Mayor: Rayas.', 15),
    (N'OFF-012', N'OFF', N'Desviación', N'Manchas.', N'Mayor', N'Activo', NULL, N'Mayor: Manchas.', 16),
    (N'OFF-013', N'OFF', N'Desviación', N'Desprendimiento de barniz.', N'Critico', N'Activo', NULL, N'Crítico: Desprendimiento de barniz.', 17),
    (N'OFF-014', N'OFF', N'Desviación', N'Reserva de Barniz', N'Critico', N'Activo', NULL, N'Critico: Reserva de Barniz', 18),
    (N'SER-001', N'SER', N'Desviación', N'Calce de barniz.', N'Critico', N'Activo', NULL, N'Crítico: Calce de barniz.', 19),
    (N'SER-002', N'SER', N'Desviación', N'Calce de registro lateral y frontal.', N'Critico', N'Activo', NULL, N'Crítico: Calce de registro lateral y frontal.', 20),
    (N'SER-003', N'SER', N'Desviación', N'Problemas de curado.', N'Critico', N'Activo', NULL, N'Crítico: Problemas de curado.', 21),
    (N'SER-004', N'SER', N'Desviación', N'Rotura de malla.', N'Critico', N'Activo', NULL, N'Crítico: Rotura de malla.', 22),
    (N'SER-005', N'SER', N'Desviación', N'Adherencia de barniz.', N'Critico', N'Activo', NULL, N'Crítico: Adherencia de barniz.', 23),
    (N'SER-006', N'SER', N'Desviación', N'Burbujas en barniz.', N'Mayor', N'Activo', NULL, N'Mayor: Burbujas en barniz.', 24),
    (N'SER-007', N'SER', N'Desviación', N'Pliegos puntos de barniz', N'Mayor', N'Activo', N'Revisar redacción y significado operativo', N'Mayor: Pliegos puntos de barniz', 25),
    (N'FOL-001', N'FOL', N'Desviación', N'Anclaje de folia.', N'Critico', N'Activo', NULL, N'Crítico: Anclaje de folia.', 26),
    (N'FOL-002', N'FOL', N'Desviación', N'Aspecto visual (cliché contexto muy delgado).', N'Mayor', N'Activo', NULL, N'Mayor: Aspecto visual (cliché contexto muy delgado).', 27),
    (N'FOL-003', N'FOL', N'Desviación', N'Descalce de folia.', N'Critico', N'Activo', NULL, N'Crítico: Descalce de folia.', 28),
    (N'FOL-004', N'FOL', N'Desviación', N'Folia picada.', N'Mayor', N'Activo', NULL, N'Mayor: Folia picada.', 29),
    (N'FOL-005', N'FOL', N'Desviación', N'Presión de folia.', N'Critico', N'Activo', NULL, N'Crítico: Presión de folia.', 30),
    (N'FOL-006', N'FOL', N'Desviación', N'Problemas de calce de registro.', N'Critico', N'Activo', NULL, N'Crítico: Problemas de calce de registro.', 31),
    (N'FOL-007', N'FOL', N'Desviación', N'tipo de folia correcta', N'Critico', N'Activo', N'Revisar redacción y significado operativo', N'Critico: tipo de folia correcta', 32),
    (N'TRO-001', N'TRO', N'Desviación', N'Armado de estuche.', N'Critico', N'Activo', NULL, N'Crítico: Armado de estuche.', 33),
    (N'TRO-002', N'TRO', N'Desviación', N'Calce de relieve y braille.', N'Critico', N'Activo', NULL, N'Crítico: Calce de relieve y braille.', 34),
    (N'TRO-003', N'TRO', N'Desviación', N'Calce de troquel e impresión.', N'Mayor', N'Activo', NULL, N'Mayor: Calce de troquel e impresión.', 35),
    (N'TRO-004', N'TRO', N'Desviación', N'Calidad corte externo.', N'Critico', N'Activo', NULL, N'Crítico: Calidad corte externo.', 36),
    (N'TRO-005', N'TRO', N'Desviación', N'Calidad de plisado y definición.', N'Critico', N'Activo', NULL, N'Crítico: Calidad de plisado y definición.', 37),
    (N'TRO-006', N'TRO', N'Desviación', N'Calidad de corte interno.', N'Critico', N'Activo', NULL, N'Crítico: Calidad de corte interno.', 38),
    (N'TRO-007', N'TRO', N'Desviación', N'Calidad de prepicado y medio corte.', N'Critico', N'Activo', NULL, N'Crítico: Calidad de prepicado y medio corte.', 39),
    (N'PEG-001', N'PEG', N'Desviación', N'Arrugas.', N'Mayor', N'Activo', NULL, N'Mayor: Arrugas.', 40),
    (N'PEG-002', N'PEG', N'Desviación', N'Marca de correa.', N'Mayor', N'Activo', NULL, N'Mayor: Marca de correa.', 41),
    (N'PEG-003', N'PEG', N'Desviación', N'Pegado desviado.', N'Critico', N'Activo', NULL, N'Crítico: Pegado desviado.', 42),
    (N'PEG-004', N'PEG', N'Desviación', N'Producto con falta de adhesivo.', N'Critico', N'Activo', NULL, N'Crítico: Producto con falta de adhesivo.', 43),
    (N'PEG-005', N'PEG', N'Desviación', N'Cuna despegada', N'Critico', N'Activo', NULL, N'Critico: Cuna despegada', 44),
    (N'PEG-006', N'PEG', N'Desviación', N'Plisado fantasma', N'Mayor', N'Activo', NULL, N'Mayor: Plisado fantasma', 45),
    (N'PEG-007', N'PEG', N'Desviación', N'Pegando con lector', N'Critico', N'Activo', N'Revisar redacción y significado operativo', N'Critico: Pegando con lector', 46),
    (N'PEG-008', N'PEG', N'Desviación', N'Mezcla', N'Critico', N'Activo', N'Revisar redacción y significado operativo', N'Critico: Mezcla', 47),
    (N'FLT-001', N'FLT', N'Desviación', N'Cantidad de folletos por fajo.', N'Critico', N'Activo', NULL, N'Crítico: Cantidad de folletos por fajo.', 48),
    (N'FLT-002', N'FLT', N'Desviación', N'Doblez desviado.', N'Critico', N'Activo', NULL, N'Crítico: Doblez desviado.', 49),
    (N'FLT-003', N'FLT', N'Desviación', N'Mala rotulación.', N'Critico', N'Activo', NULL, N'Crítico: Mala rotulación.', 50),
    (N'FLT-004', N'FLT', N'Desviación', N'Descalce en gato.', N'Critico', N'Activo', NULL, N'Crítico: Descalce en gato.', 51),
    (N'CYD-001', N'CYD', N'Desviación', N'Curvatura.', N'Critico', N'Activo', NULL, N'Crítico: Curvatura.', 52),
    (N'CYD-002', N'CYD', N'Desviación', N'Corte deficiente o sucio.', N'Critico', N'Activo', NULL, N'Crítico: Corte deficiente o sucio.', 53),
    (N'CYD-003', N'CYD', N'Desviación', N'Formato corresponde', N'Critico', N'Activo', N'Revisar redacción y significado operativo', N'Critico: Formato corresponde', 54),
    (N'CYD-004', N'CYD', N'Desviación', N'Pliegos pegados', N'Critico', N'Activo', NULL, N'Critico: Pliegos pegados', 55),
    (N'CYD-005', N'CYD', N'Desviación', N'Mala rotulación de pila', N'Critico', N'Activo', NULL, N'Critico: Mala rotulación de pila', 56),
    (N'CYD-006', N'CYD', N'Desviación', N'Sentido de fibra', N'Critico', N'Activo', NULL, N'Critico: Sentido de fibra', 57);
-- <<< FIN SEED GENERADO

-- 5b. Inserta lo que falte (nunca pisa filas existentes ni cambios posteriores del catálogo)
DECLARE @nuevas_areas TABLE (cod_area NVARCHAR(3) NOT NULL);
DECLARE @nuevos_eventos TABLE (id_evento NVARCHAR(10) NOT NULL);

INSERT INTO dbo.calidad_faret_areas (cod_area, nombre, area_control, orden, estado)
OUTPUT inserted.cod_area INTO @nuevas_areas
SELECT s.cod_area, s.nombre, s.area_control, s.orden, s.estado
FROM #seed_areas s
WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_areas a WHERE a.cod_area = s.cod_area);

INSERT INTO dbo.calidad_faret_eventos
    (id_evento, cod_area, tipo_registro, defecto, criticidad, estado, orden,
     defecto_origen, criticidad_origen, estado_origen, observacion_origen, texto_documento,
     requiere_aprobacion, aprobacion)
OUTPUT inserted.id_evento INTO @nuevos_eventos
SELECT s.id_evento, s.cod_area, s.tipo_registro, s.defecto, s.criticidad,
       CASE WHEN s.observacion_origen IS NOT NULL THEN N'Inactivo' ELSE s.estado_origen END,   -- pendientes: inactivos hasta aprobación
       s.orden, s.defecto, s.criticidad, s.estado_origen, s.observacion_origen, s.texto_documento,
       CASE WHEN s.observacion_origen IS NOT NULL THEN 1 ELSE 0 END,
       CASE WHEN s.observacion_origen IS NOT NULL THEN N'PENDIENTE' ELSE N'NO_REQUERIDA' END
FROM #seed_eventos s
WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_eventos e WHERE e.id_evento = s.id_evento);

INSERT INTO dbo.calidad_faret_catalogo_auditoria (entidad, clave, accion, campo, valor_nuevo, usuario, motivo)
SELECT N'AREA', a.cod_area, N'CARGA_INICIAL', N'alta', a.area_control + N' | ' + a.estado, SUSER_SNAME(), N'Migración 010 (Excel aprobado por Calidad)'
FROM dbo.calidad_faret_areas a JOIN @nuevas_areas n ON n.cod_area = a.cod_area;

INSERT INTO dbo.calidad_faret_catalogo_auditoria (entidad, clave, accion, campo, valor_nuevo, usuario, motivo)
SELECT N'EVENTO', e.id_evento, N'CARGA_INICIAL', N'alta', e.criticidad + N' | ' + e.estado + N' | ' + e.aprobacion, SUSER_SNAME(), N'Migración 010 (Excel aprobado por Calidad)'
FROM dbo.calidad_faret_eventos e JOIN @nuevos_eventos n ON n.id_evento = e.id_evento;

-- 5c. Si las filas ya existían, deben seguir idénticas al Excel en sus campos de origen (detecta manipulación)
IF EXISTS (
    SELECT 1 FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento
    WHERE e.cod_area COLLATE Latin1_General_BIN2 <> s.cod_area COLLATE Latin1_General_BIN2
       OR e.defecto_origen COLLATE Latin1_General_BIN2 <> s.defecto COLLATE Latin1_General_BIN2
       OR e.criticidad_origen COLLATE Latin1_General_BIN2 <> s.criticidad COLLATE Latin1_General_BIN2
       OR e.estado_origen COLLATE Latin1_General_BIN2 <> s.estado_origen COLLATE Latin1_General_BIN2
       OR e.texto_documento COLLATE Latin1_General_BIN2 <> s.texto_documento COLLATE Latin1_General_BIN2
       OR ISNULL(e.observacion_origen, N'') COLLATE Latin1_General_BIN2 <> ISNULL(s.observacion_origen, N'') COLLATE Latin1_General_BIN2)
    THROW 51010, N'Los datos de origen de calidad_faret_eventos no coinciden con el Excel aprobado.', 1;
IF EXISTS (
    SELECT 1 FROM #seed_areas s JOIN dbo.calidad_faret_areas a ON a.cod_area = s.cod_area
    WHERE a.area_control COLLATE Latin1_General_BIN2 <> s.area_control COLLATE Latin1_General_BIN2)
    THROW 51011, N'calidad_faret_areas.area_control no coincide con el Excel aprobado.', 1;

-- 6. registro_calidad_faret_defectos: foto congelada por inspección (NULL en todo el histórico) ------------------------
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'id_evento') IS NULL
    EXEC (N'ALTER TABLE dbo.registro_calidad_faret_defectos ADD id_evento NVARCHAR(10) NULL');
IF COL_LENGTH(N'dbo.registro_calidad_faret_defectos', N'criticidad') IS NULL
    EXEC (N'ALTER TABLE dbo.registro_calidad_faret_defectos ADD criticidad NVARCHAR(10) NULL');

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_registro_calidad_faret_defectos_evento' AND parent_object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    EXEC (N'ALTER TABLE dbo.registro_calidad_faret_defectos WITH CHECK ADD CONSTRAINT FK_registro_calidad_faret_defectos_evento
            FOREIGN KEY (id_evento) REFERENCES dbo.calidad_faret_eventos (id_evento)');

-- id_evento y criticidad van juntos: ambos NULL (histórico / app antigua) o ambos informados
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_registro_calidad_faret_defectos_evento_crit' AND parent_object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    EXEC (N'ALTER TABLE dbo.registro_calidad_faret_defectos WITH CHECK ADD CONSTRAINT CK_registro_calidad_faret_defectos_evento_crit
            CHECK ((id_evento IS NULL AND criticidad IS NULL)
                OR (id_evento IS NOT NULL AND criticidad IS NOT NULL AND criticidad IN (N''Critico'', N''Mayor'', N''Menor'')))');

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_registro_calidad_faret_defectos_id_evento' AND object_id = OBJECT_ID(N'dbo.registro_calidad_faret_defectos'))
    EXEC (N'CREATE INDEX IX_registro_calidad_faret_defectos_id_evento ON dbo.registro_calidad_faret_defectos (id_evento) INCLUDE (registro_id) WHERE id_evento IS NOT NULL');

-- 7. Triggers ----------------------------------------------------------------------------------------------------------
-- 7a. Defectos de una inspección: solo eventos operables y del área del defecto; la foto congelada no se altera.
--     Si id_evento es NULL (histórico / apps antiguas) el trigger sale de inmediato sin consultar nada.
IF OBJECT_ID(N'dbo.TR_registro_calidad_faret_defectos_evento', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_registro_calidad_faret_defectos_evento;
EXEC (N'
CREATE TRIGGER dbo.TR_registro_calidad_faret_defectos_evento ON dbo.registro_calidad_faret_defectos
AFTER INSERT, UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF EXISTS (SELECT 1 FROM deleted)
    BEGIN
        -- UPDATE: la foto congelada (id_evento + criticidad) no se puede cambiar una vez informada
        IF EXISTS (SELECT 1 FROM deleted d JOIN inserted i ON i.id = d.id
                   WHERE d.id_evento IS NOT NULL
                     AND (ISNULL(i.id_evento, N'''') COLLATE Latin1_General_BIN2 <> d.id_evento COLLATE Latin1_General_BIN2
                          OR ISNULL(i.criticidad, N'''') COLLATE Latin1_General_BIN2 <> ISNULL(d.criticidad, N'''') COLLATE Latin1_General_BIN2))
            THROW 51032, N''El evento y la criticidad registrados en una inspección no se pueden modificar.'', 1;
        IF NOT UPDATE(id_evento) RETURN;
    END
    IF NOT EXISTS (SELECT 1 FROM inserted WHERE id_evento IS NOT NULL) RETURN;
    IF EXISTS (SELECT 1 FROM inserted i WHERE i.id_evento IS NOT NULL
               AND NOT EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables v WHERE v.id_evento = i.id_evento))
        THROW 51030, N''Evento de calidad inexistente, inactivo o pendiente de aprobación de Calidad.'', 1;
    IF EXISTS (SELECT 1 FROM inserted i
               JOIN dbo.vw_calidad_faret_eventos_operables v ON v.id_evento = i.id_evento
               LEFT JOIN dbo.registros_calidad_faret r ON r.id = i.registro_id
               WHERE r.id IS NULL OR r.area_defecto IS NULL OR r.area_defecto <> v.area_control)
        THROW 51031, N''El evento no corresponde al área del defecto del registro.'', 1;
END');

-- 7b. Eventos: IDs/origen inmutables, auditoría de cambios, sin DELETE.
IF OBJECT_ID(N'dbo.TR_calidad_faret_eventos_upd', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_calidad_faret_eventos_upd;
EXEC (N'
CREATE TRIGGER dbo.TR_calidad_faret_eventos_upd ON dbo.calidad_faret_eventos
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID(N''dbo.TR_calidad_faret_eventos_upd''), N''AFTER'', N''DML'') > 1 RETURN;
    IF UPDATE(id_evento) OR UPDATE(cod_area)
        THROW 51040, N''id_evento y cod_area son inmutables: un ID nunca se reutiliza ni se reasigna.'', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.id_evento = i.id_evento
               WHERE i.defecto_origen COLLATE Latin1_General_BIN2 <> d.defecto_origen COLLATE Latin1_General_BIN2
                  OR i.criticidad_origen COLLATE Latin1_General_BIN2 <> d.criticidad_origen COLLATE Latin1_General_BIN2
                  OR i.estado_origen COLLATE Latin1_General_BIN2 <> d.estado_origen COLLATE Latin1_General_BIN2
                  OR i.texto_documento COLLATE Latin1_General_BIN2 <> d.texto_documento COLLATE Latin1_General_BIN2
                  OR ISNULL(i.observacion_origen, N'''') COLLATE Latin1_General_BIN2 <> ISNULL(d.observacion_origen, N'''') COLLATE Latin1_General_BIN2)
        THROW 51041, N''Los campos *_origen conservan el Excel aprobado y no se pueden modificar.'', 1;

    DECLARE @usuario NVARCHAR(128) = COALESCE(CONVERT(NVARCHAR(128), SESSION_CONTEXT(N''usuario'')), SUSER_SNAME());
    DECLARE @motivo NVARCHAR(300) = CONVERT(NVARCHAR(300), SESSION_CONTEXT(N''motivo''));

    INSERT INTO dbo.calidad_faret_catalogo_auditoria (entidad, clave, accion, campo, valor_anterior, valor_nuevo, usuario, motivo)
    SELECT N''EVENTO'', i.id_evento, N''MODIFICACION'', c.campo, c.anterior, c.nuevo, @usuario, @motivo
    FROM inserted i JOIN deleted d ON d.id_evento = i.id_evento
    CROSS APPLY (VALUES
        (N''defecto'',        CONVERT(NVARCHAR(300), d.defecto),        CONVERT(NVARCHAR(300), i.defecto)),
        (N''criticidad'',     CONVERT(NVARCHAR(300), d.criticidad),     CONVERT(NVARCHAR(300), i.criticidad)),
        (N''estado'',         CONVERT(NVARCHAR(300), d.estado),         CONVERT(NVARCHAR(300), i.estado)),
        (N''aprobacion'',     CONVERT(NVARCHAR(300), d.aprobacion),     CONVERT(NVARCHAR(300), i.aprobacion)),
        (N''aprobacion_ref'', CONVERT(NVARCHAR(300), d.aprobacion_ref), CONVERT(NVARCHAR(300), i.aprobacion_ref)),
        (N''orden'',          CONVERT(NVARCHAR(300), d.orden),          CONVERT(NVARCHAR(300), i.orden))
    ) c (campo, anterior, nuevo)
    WHERE ISNULL(c.anterior, N'''') COLLATE Latin1_General_BIN2 <> ISNULL(c.nuevo, N'''') COLLATE Latin1_General_BIN2;

    UPDATE e SET updated_at = GETDATE(), updated_by = @usuario
    FROM dbo.calidad_faret_eventos e JOIN inserted i ON i.id_evento = e.id_evento;
END');

IF OBJECT_ID(N'dbo.TR_calidad_faret_eventos_del', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_calidad_faret_eventos_del;
EXEC (N'
CREATE TRIGGER dbo.TR_calidad_faret_eventos_del ON dbo.calidad_faret_eventos
INSTEAD OF DELETE AS
BEGIN
    THROW 51042, N''Los eventos no se eliminan: use baja lógica (estado = Inactivo).'', 1;
END');

-- 7c. Áreas: cod_area/area_control inmutables (son el vínculo con el histórico), auditoría, sin DELETE.
IF OBJECT_ID(N'dbo.TR_calidad_faret_areas_upd', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_calidad_faret_areas_upd;
EXEC (N'
CREATE TRIGGER dbo.TR_calidad_faret_areas_upd ON dbo.calidad_faret_areas
AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF TRIGGER_NESTLEVEL(OBJECT_ID(N''dbo.TR_calidad_faret_areas_upd''), N''AFTER'', N''DML'') > 1 RETURN;
    IF UPDATE(cod_area)
        THROW 51043, N''cod_area es inmutable.'', 1;
    IF EXISTS (SELECT 1 FROM inserted i JOIN deleted d ON d.cod_area = i.cod_area
               WHERE i.area_control COLLATE Latin1_General_BIN2 <> d.area_control COLLATE Latin1_General_BIN2)
        THROW 51044, N''area_control es inmutable: es la etiqueta con la que se guardaron los registros históricos.'', 1;

    DECLARE @usuario NVARCHAR(128) = COALESCE(CONVERT(NVARCHAR(128), SESSION_CONTEXT(N''usuario'')), SUSER_SNAME());
    DECLARE @motivo NVARCHAR(300) = CONVERT(NVARCHAR(300), SESSION_CONTEXT(N''motivo''));

    INSERT INTO dbo.calidad_faret_catalogo_auditoria (entidad, clave, accion, campo, valor_anterior, valor_nuevo, usuario, motivo)
    SELECT N''AREA'', i.cod_area, N''MODIFICACION'', c.campo, c.anterior, c.nuevo, @usuario, @motivo
    FROM inserted i JOIN deleted d ON d.cod_area = i.cod_area
    CROSS APPLY (VALUES
        (N''nombre'', CONVERT(NVARCHAR(300), d.nombre), CONVERT(NVARCHAR(300), i.nombre)),
        (N''estado'', CONVERT(NVARCHAR(300), d.estado), CONVERT(NVARCHAR(300), i.estado)),
        (N''orden'',  CONVERT(NVARCHAR(300), d.orden),  CONVERT(NVARCHAR(300), i.orden))
    ) c (campo, anterior, nuevo)
    WHERE ISNULL(c.anterior, N'''') COLLATE Latin1_General_BIN2 <> ISNULL(c.nuevo, N'''') COLLATE Latin1_General_BIN2;

    UPDATE a SET updated_at = GETDATE(), updated_by = @usuario
    FROM dbo.calidad_faret_areas a JOIN inserted i ON i.cod_area = a.cod_area;
END');

IF OBJECT_ID(N'dbo.TR_calidad_faret_areas_del', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_calidad_faret_areas_del;
EXEC (N'
CREATE TRIGGER dbo.TR_calidad_faret_areas_del ON dbo.calidad_faret_areas
INSTEAD OF DELETE AS
BEGIN
    THROW 51045, N''Las áreas no se eliminan: use baja lógica (estado = Inactivo).'', 1;
END');

-- 7d. Auditoría: solo se agregan filas
IF OBJECT_ID(N'dbo.TR_calidad_faret_catalogo_auditoria_inmutable', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_calidad_faret_catalogo_auditoria_inmutable;
EXEC (N'
CREATE TRIGGER dbo.TR_calidad_faret_catalogo_auditoria_inmutable ON dbo.calidad_faret_catalogo_auditoria
INSTEAD OF UPDATE, DELETE AS
BEGIN
    THROW 51046, N''La auditoría del catálogo es de solo agregado: no se modifica ni se borra.'', 1;
END');

-- 8. Permisos mínimos: solo lectura del catálogo para la cuenta de la app (guardado: el usuario puede no existir en otros entornos)
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    GRANT SELECT ON dbo.calidad_faret_areas TO [quality_control_backend_sql];
    GRANT SELECT ON dbo.calidad_faret_eventos TO [quality_control_backend_sql];
    GRANT SELECT ON dbo.vw_calidad_faret_eventos_operables TO [quality_control_backend_sql];
END

-- 9. Verificación final dentro de la transacción: si algo no cuadra con el Excel, se revierte todo -----------------------
IF (SELECT COUNT(*) FROM #seed_areas s JOIN dbo.calidad_faret_areas a ON a.cod_area = s.cod_area) <> @esp_areas
    THROW 51050, N'Las áreas cargadas no son las 8 esperadas.', 1;
IF (SELECT COUNT(*) FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento) <> @esp_eventos
    THROW 51051, N'Los eventos cargados no son los 57 esperados.', 1;
IF (SELECT COUNT(*) FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento WHERE e.criticidad_origen = N'Critico') <> @esp_critico
   OR (SELECT COUNT(*) FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento WHERE e.criticidad_origen = N'Mayor') <> @esp_mayor
   OR (SELECT COUNT(*) FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento WHERE e.criticidad_origen = N'Menor') <> @esp_menor
    THROW 51052, N'Los totales por criticidad no coinciden con el Excel (42 / 14 / 1).', 1;
IF (SELECT COUNT(*) FROM #seed_eventos s JOIN dbo.calidad_faret_eventos e ON e.id_evento = s.id_evento
    WHERE s.observacion_origen IS NOT NULL AND e.requiere_aprobacion = 1 AND e.aprobacion IN (N'PENDIENTE', N'RECHAZADA')
      AND NOT EXISTS (SELECT 1 FROM dbo.vw_calidad_faret_eventos_operables v WHERE v.id_evento = e.id_evento)) <> @esp_pendientes
    THROW 51053, N'Los eventos pendientes de aprobación no están bloqueados como corresponde.', 1;

COMMIT TRANSACTION;

SELECT (SELECT COUNT(*) FROM dbo.calidad_faret_areas) AS areas,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos) AS eventos,
       (SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables) AS eventos_operables,
       (SELECT COUNT(*) FROM dbo.calidad_faret_eventos WHERE aprobacion = N'PENDIENTE') AS pendientes_calidad;

-- Verificación posterior sugerida (solo lectura):
--   SELECT a.cod_area, e.criticidad, COUNT(*) FROM dbo.calidad_faret_eventos e JOIN dbo.calidad_faret_areas a ON a.cod_area = e.cod_area GROUP BY a.cod_area, e.criticidad ORDER BY 1, 2;
--   SELECT id_evento, defecto, estado, estado_origen, aprobacion FROM dbo.calidad_faret_eventos WHERE requiere_aprobacion = 1;
--   EXECUTE AS USER = 'quality_control_backend_sql'; SELECT COUNT(*) FROM dbo.vw_calidad_faret_eventos_operables; REVERT;
--   SELECT COUNT(*) total, COUNT(id_evento) con_evento FROM dbo.registro_calidad_faret_defectos;   -- con_evento = 0 hasta la Etapa 2
--
-- Para habilitar los 5 eventos tras la aprobación de Calidad (ejemplo; una sola sentencia por evento, queda auditado):
--   EXEC sp_set_session_context N'usuario', N'<responsable>'; EXEC sp_set_session_context N'motivo', N'<motivo>';
--   UPDATE dbo.calidad_faret_eventos SET aprobacion = N'APROBADA', aprobado_por = N'<Calidad>', aprobado_at = GETDATE(),
--          aprobacion_ref = N'<referencia>', estado = N'Activo' WHERE id_evento = N'PEG-008';
--   (si Calidad cambia la redacción, se actualiza solo "defecto"; defecto_origen conserva el texto del Excel)
