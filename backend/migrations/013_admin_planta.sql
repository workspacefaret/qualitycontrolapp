-- Administración de planta (QCC Desktop): operadores, inspectores, máquinas y áreas de INNPACK y FARET. Motor: SQL Server (calidad_db).
-- Aditiva e idempotente (re-ejecutable). Reversible: 013_admin_planta_rollback.sql. NO modifica filas existentes salvo agregar la columna `activo`.
--
-- Qué crea
--   calidad_faret_maquinas          máquinas de FARET por área (antes fijas en el código de la app móvil)
--   calidad_faret_operadores_area   operadores de máquina de FARET por área (idem)
--   calidad_faret_operadores.activo columna nueva (baja lógica de inspectores FARET; los existentes quedan activos)
--   admin_planta_auditoria          bitácora: una fila por campo modificado (empresa, entidad, clave, antes/después, usuario, fecha)
--   + carga inicial de máquinas y operadores desde el catálogo vigente de la app (calidad_faret_catalog.dart, 2026-11-12)
-- Las áreas de FARET ya existen (calidad_faret_areas, migración 010) y se reutilizan.
-- Todo se da de baja con estado/activo, nunca se borra: los registros históricos guardan el texto y no se alteran.
--
-- Permisos mínimos para quality_control_backend_sql (solo si el usuario existe), por columna donde aplica:
--   FARET: SELECT/INSERT/UPDATE(nombre, estado) en calidad_faret_maquinas, calidad_faret_operadores_area y calidad_faret_areas;
--          UPDATE(nombre, activo) en calidad_faret_operadores
--   INNPACK: procesos, maquinas, operadores_maquina y usuarios (INSERT a nivel de tabla, que SQL Server no permite por columna; UPDATE solo de las columnas que administra el módulo)
--
-- Cómo ejecutar: cuenta con DDL, tras respaldar calidad_db, ANTES de desplegar el backend con /api/admin-planta.
-- Sin GO: un solo lote; si algo falla se revierte todo. Archivo UTF-8 sin BOM.
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRAN;

IF OBJECT_ID(N'dbo.calidad_faret_areas', N'U') IS NULL THROW 51300, N'Falta calidad_faret_areas (migracion 010).', 1;
IF OBJECT_ID(N'dbo.calidad_faret_operadores', N'U') IS NULL THROW 51301, N'Falta calidad_faret_operadores.', 1;
IF OBJECT_ID(N'dbo.operadores_maquina', N'U') IS NULL THROW 51303, N'Falta operadores_maquina (migracion 008).', 1;

-- 1. Inspectores FARET: baja lógica
IF COL_LENGTH(N'dbo.calidad_faret_operadores', N'activo') IS NULL
    EXEC (N'ALTER TABLE dbo.calidad_faret_operadores ADD activo BIT NOT NULL CONSTRAINT DF_calidad_faret_operadores_activo DEFAULT (1)');

-- 2. Máquinas FARET
IF OBJECT_ID(N'dbo.calidad_faret_maquinas', N'U') IS NULL
CREATE TABLE dbo.calidad_faret_maquinas (
    id         INT IDENTITY(1,1) NOT NULL,
    cod_area   NVARCHAR(3)   NOT NULL,
    nombre     NVARCHAR(100) NOT NULL,
    estado     NVARCHAR(8)   NOT NULL CONSTRAINT DF_calidad_faret_maquinas_estado DEFAULT (N'Activo'),
    created_at DATETIME2(0)  NOT NULL CONSTRAINT DF_calidad_faret_maquinas_created DEFAULT (GETDATE()),
    CONSTRAINT PK_calidad_faret_maquinas PRIMARY KEY CLUSTERED (id),
    CONSTRAINT FK_calidad_faret_maquinas_area FOREIGN KEY (cod_area) REFERENCES dbo.calidad_faret_areas (cod_area),
    CONSTRAINT UQ_calidad_faret_maquinas UNIQUE (cod_area, nombre),
    CONSTRAINT CK_calidad_faret_maquinas_estado CHECK (estado IN (N'Activo', N'Inactivo')),
    CONSTRAINT CK_calidad_faret_maquinas_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

-- 3. Operadores de máquina FARET
IF OBJECT_ID(N'dbo.calidad_faret_operadores_area', N'U') IS NULL
CREATE TABLE dbo.calidad_faret_operadores_area (
    id         INT IDENTITY(1,1) NOT NULL,
    cod_area   NVARCHAR(3)   NOT NULL,
    nombre     NVARCHAR(100) NOT NULL,
    estado     NVARCHAR(8)   NOT NULL CONSTRAINT DF_calidad_faret_operadores_area_estado DEFAULT (N'Activo'),
    created_at DATETIME2(0)  NOT NULL CONSTRAINT DF_calidad_faret_operadores_area_created DEFAULT (GETDATE()),
    CONSTRAINT PK_calidad_faret_operadores_area PRIMARY KEY CLUSTERED (id),
    CONSTRAINT FK_calidad_faret_operadores_area_area FOREIGN KEY (cod_area) REFERENCES dbo.calidad_faret_areas (cod_area),
    CONSTRAINT UQ_calidad_faret_operadores_area UNIQUE (cod_area, nombre),
    CONSTRAINT CK_calidad_faret_operadores_area_estado CHECK (estado IN (N'Activo', N'Inactivo')),
    CONSTRAINT CK_calidad_faret_operadores_area_nombre CHECK (LEN(LTRIM(RTRIM(nombre))) > 0)
);

-- 4. Auditoría
IF OBJECT_ID(N'dbo.admin_planta_auditoria', N'U') IS NULL
CREATE TABLE dbo.admin_planta_auditoria (
    id             BIGINT IDENTITY(1,1) NOT NULL,
    empresa        NVARCHAR(10)  NOT NULL,   -- INNPACK / FARET
    entidad        NVARCHAR(15)  NOT NULL,   -- areas / maquinas / operadores / inspectores
    clave          NVARCHAR(20)  NOT NULL,   -- id o cod_area del registro
    registro       NVARCHAR(150) NULL,       -- nombre del registro al momento del cambio (legible en el historial)
    accion         NVARCHAR(10)  NOT NULL,   -- CREAR / MODIFICAR
    campo          NVARCHAR(30)  NOT NULL,
    valor_anterior NVARCHAR(200) NULL,
    valor_nuevo    NVARCHAR(200) NULL,
    usuario        NVARCHAR(150) NOT NULL,
    origen         NVARCHAR(10)  NULL,       -- faret / innpack (API que emitió el token)
    fecha          DATETIME2(0)  NOT NULL CONSTRAINT DF_admin_planta_auditoria_fecha DEFAULT (GETDATE()),
    CONSTRAINT PK_admin_planta_auditoria PRIMARY KEY CLUSTERED (id)
);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_admin_planta_auditoria_fecha' AND object_id = OBJECT_ID(N'dbo.admin_planta_auditoria'))
    CREATE INDEX IX_admin_planta_auditoria_fecha ON dbo.admin_planta_auditoria (fecha DESC);

-- 5. Carga inicial desde el catálogo vigente de la app (idempotente; compara sin mayúsculas/tildes)
CREATE TABLE #maq (area_control NVARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL, nombre NVARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL);
INSERT INTO #maq (area_control, nombre) VALUES
    (N'02-LAMINADO', N'AQUA 120 STEINEMANN'), (N'02-LAMINADO', N'SIRYUS'), (N'02-LAMINADO', N'WEN CHYUAN'),
    (N'03-OFFSET', N'CD 102 4-L'), (N'03-OFFSET', N'KBA 145 / 164'), (N'03-OFFSET', N'KBA 2'),
    (N'03-OFFSET', N'XL - 2'), (N'03-OFFSET', N'XL - 3'), (N'03-OFFSET', N'SM 74'),
    (N'04-SERIGRAFÍA', N'SAKURAI'),
    (N'05-FOLIA', N'SPERIA FOILMASTER 104'), (N'05-FOLIA', N'FOLIA 2'),
    (N'07-TROQUELADO', N'BOBST 104 - 1'), (N'07-TROQUELADO', N'BOBST 104 - 2'), (N'07-TROQUELADO', N'BOBST 106 - 1'),
    (N'07-TROQUELADO', N'BOBST 106 - 2'), (N'07-TROQUELADO', N'IBERICA KBA 144 - 1'), (N'07-TROQUELADO', N'IBERICA KBA 144 - 2'),
    (N'10-PEGADO', N'ALPINA 110'), (N'10-PEGADO', N'DIANA 3'), (N'10-PEGADO', N'DIANA 5'), (N'10-PEGADO', N'DIANA 7'),
    (N'10-PEGADO', N'DIANA EXPERFOLD'), (N'10-PEGADO', N'DIANA PRO 1'), (N'10-PEGADO', N'DIANA PRO 2'), (N'10-PEGADO', N'DIANA PRO 3'),
    (N'12-FOLLETOS', N'FOLLETOS TI 36/4'), (N'12-FOLLETOS', N'FOLLETOS TI 36/6'),
    (N'13-CORTE Y DIMENSIONADO', N'APOLLO DIMENSIONADORA'), (N'13-CORTE Y DIMENSIONADO', N'DIMENSIONADORA CHINA (EUROPA)'),
    (N'13-CORTE Y DIMENSIONADO', N'GUILLOTINA 1 POLAR 137'), (N'13-CORTE Y DIMENSIONADO', N'GUILLOTINA 2 POLAR 155');

CREATE TABLE #ope (area_control NVARCHAR(50) COLLATE DATABASE_DEFAULT NOT NULL, nombre NVARCHAR(100) COLLATE DATABASE_DEFAULT NOT NULL);
INSERT INTO #ope (area_control, nombre) VALUES
    (N'02-LAMINADO', N'ALAIN ESCORCIA'), (N'02-LAMINADO', N'EMERSON RODRIGUEZ'), (N'02-LAMINADO', N'JORGE GONZALEZ'),
    (N'02-LAMINADO', N'LUIS SEPULVEDA'), (N'02-LAMINADO', N'ORANGEL MARTINEZ'), (N'02-LAMINADO', N'ORLANDO MEDINA'),
    (N'03-OFFSET', N'AXEL CRUZ'), (N'03-OFFSET', N'DEDIER LEIVA'), (N'03-OFFSET', N'EMERSON RAMIREZ'), (N'03-OFFSET', N'GUILLERMO MORENO'),
    (N'03-OFFSET', N'HERNAN VARGAS'), (N'03-OFFSET', N'JUAN PAILLAMAN'), (N'03-OFFSET', N'MANUEL PADILLA'), (N'03-OFFSET', N'OSVALDO CAMPOS'),
    (N'03-OFFSET', N'PEDRO CASTILLO'), (N'03-OFFSET', N'RENIER CELIS'), (N'03-OFFSET', N'ROLANDO PEÑA'),
    (N'04-SERIGRAFÍA', N'ALEJANDRO ALBORNOZ'),
    (N'05-FOLIA', N'JUAN SALDIAS'), (N'05-FOLIA', N'JULIO SALDIAS'), (N'05-FOLIA', N'VICTOR MACAYA'),
    (N'07-TROQUELADO', N'CARLOS AVELLO'), (N'07-TROQUELADO', N'CARLOS RIVERA'), (N'07-TROQUELADO', N'GUILLERMO DIAZ'),
    (N'07-TROQUELADO', N'KERVIN MOSQUERA'), (N'07-TROQUELADO', N'LUIS ARAVENA'), (N'07-TROQUELADO', N'LUIS MONTOYA'),
    (N'07-TROQUELADO', N'RODRIGO ALVAREZ'), (N'07-TROQUELADO', N'SERGIO TORO'), (N'07-TROQUELADO', N'YURI MARTINEZ'),
    (N'10-PEGADO', N'CLAUDIO CARIQUEO'), (N'10-PEGADO', N'CRISTIAN MUÑOZ'), (N'10-PEGADO', N'FERNANDO ALFARO'),
    (N'10-PEGADO', N'FRANCISCO DIAZ'), (N'10-PEGADO', N'JORGE HUENUQUEO'), (N'10-PEGADO', N'MARCOS ASTORGA'),
    (N'10-PEGADO', N'MARCOS MORALES'), (N'10-PEGADO', N'RODRIGO AMAYA'), (N'10-PEGADO', N'SEBASTIAN BUCAREI'),
    (N'12-FOLLETOS', N'GABRIEL ROMERO'), (N'12-FOLLETOS', N'LUIS RAMIREZ'), (N'12-FOLLETOS', N'MARIA CARDENAS'),
    (N'13-CORTE Y DIMENSIONADO', N'ALFREDO NAVARRETE'), (N'13-CORTE Y DIMENSIONADO', N'JOSE HERNANDEZ'), (N'13-CORTE Y DIMENSIONADO', N'JUAN PLAZA'),
    (N'13-CORTE Y DIMENSIONADO', N'MARCELO ROMO'), (N'13-CORTE Y DIMENSIONADO', N'RICARDO PALMA');

-- Cada nombre debe caer en un área existente: si no, el esquema real difiere del esperado.
IF EXISTS (SELECT 1 FROM #maq s WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_areas a WHERE a.area_control COLLATE DATABASE_DEFAULT = s.area_control))
   OR EXISTS (SELECT 1 FROM #ope s WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_areas a WHERE a.area_control COLLATE DATABASE_DEFAULT = s.area_control))
    THROW 51302, N'Un area_control del catalogo no existe en calidad_faret_areas.', 1;

-- Los tres INSERT van por EXEC: el compilador resuelve nombres al preparar el lote y las tablas nuevas aún no existen en ese momento.
EXEC (N'
INSERT INTO dbo.calidad_faret_maquinas (cod_area, nombre)
SELECT a.cod_area, s.nombre FROM #maq s JOIN dbo.calidad_faret_areas a ON a.area_control COLLATE DATABASE_DEFAULT = s.area_control
WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_maquinas m WHERE m.cod_area = a.cod_area AND m.nombre COLLATE Latin1_General_CI_AI = s.nombre COLLATE Latin1_General_CI_AI);

INSERT INTO dbo.calidad_faret_operadores_area (cod_area, nombre)
SELECT a.cod_area, s.nombre FROM #ope s JOIN dbo.calidad_faret_areas a ON a.area_control COLLATE DATABASE_DEFAULT = s.area_control
WHERE NOT EXISTS (SELECT 1 FROM dbo.calidad_faret_operadores_area o WHERE o.cod_area = a.cod_area AND o.nombre COLLATE Latin1_General_CI_AI = s.nombre COLLATE Latin1_General_CI_AI);

INSERT INTO dbo.admin_planta_auditoria (empresa, entidad, clave, registro, accion, campo, valor_nuevo, usuario, origen)
SELECT N''FARET'', N''maquinas'', CAST(id AS NVARCHAR(20)), nombre, N''CREAR'', N''nombre'', nombre, N''migracion 013'', NULL FROM dbo.calidad_faret_maquinas m
WHERE NOT EXISTS (SELECT 1 FROM dbo.admin_planta_auditoria x WHERE x.empresa = N''FARET'' AND x.entidad = N''maquinas'' AND x.clave = CAST(m.id AS NVARCHAR(20)))
UNION ALL
SELECT N''FARET'', N''operadores'', CAST(id AS NVARCHAR(20)), nombre, N''CREAR'', N''nombre'', nombre, N''migracion 013'', NULL FROM dbo.calidad_faret_operadores_area o
WHERE NOT EXISTS (SELECT 1 FROM dbo.admin_planta_auditoria x WHERE x.empresa = N''FARET'' AND x.entidad = N''operadores'' AND x.clave = CAST(o.id AS NVARCHAR(20)));
');

DROP TABLE #maq;
DROP TABLE #ope;

-- 6. Permisos mínimos (solo si existe la cuenta de la app)
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    EXEC (N'
    GRANT SELECT, INSERT ON dbo.admin_planta_auditoria TO [quality_control_backend_sql];

    GRANT SELECT, INSERT ON dbo.calidad_faret_maquinas TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, estado) ON dbo.calidad_faret_maquinas TO [quality_control_backend_sql];
    GRANT SELECT, INSERT ON dbo.calidad_faret_operadores_area TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, estado) ON dbo.calidad_faret_operadores_area TO [quality_control_backend_sql];
    GRANT INSERT ON dbo.calidad_faret_areas TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, estado) ON dbo.calidad_faret_areas TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, activo) ON dbo.calidad_faret_operadores TO [quality_control_backend_sql];

    GRANT INSERT ON dbo.procesos TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, activo) ON dbo.procesos TO [quality_control_backend_sql];
    GRANT INSERT ON dbo.maquinas TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, codigo_qr, proceso_id, activo) ON dbo.maquinas TO [quality_control_backend_sql];
    GRANT INSERT ON dbo.operadores_maquina TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, proceso_id, activo) ON dbo.operadores_maquina TO [quality_control_backend_sql];
    GRANT INSERT ON dbo.usuarios TO [quality_control_backend_sql];
    GRANT UPDATE (nombre_completo, activo) ON dbo.usuarios TO [quality_control_backend_sql];
    ');
END;

COMMIT TRAN;

-- Verificación:
--   SELECT a.area_control, COUNT(*) FROM calidad_faret_maquinas m JOIN calidad_faret_areas a ON a.cod_area = m.cod_area GROUP BY a.area_control;  -- 32 máquinas
--   SELECT COUNT(*) FROM calidad_faret_operadores_area;   -- 47 operadores
