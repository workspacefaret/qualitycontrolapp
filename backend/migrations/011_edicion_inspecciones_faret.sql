-- Edición de inspecciones FARET (Calidad y Pallet/Papel) con auditoría. Motor: SQL Server (calidad_db).
-- Aditiva e idempotente (re-ejecutable). Reversible: 011_..._rollback.sql. NO modifica ninguna fila existente.
--
-- Qué crea
--   inspecciones_faret_auditoria  bitácora append-only: una fila por campo modificado (tipo, registro, campo, valor anterior,
--                                 valor nuevo, motivo, usuario id/nombre, origen del token, fecha). Un trigger impide UPDATE/DELETE.
-- Permisos mínimos para quality_control_backend_sql (guardado: solo si el usuario existe)
--   SELECT, INSERT          inspecciones_faret_auditoria
--   UPDATE (solo las columnas editables; fecha/hora, operador_registro, client_uuid y eliminado no se amplían)
--                           registros_calidad_faret, registros_calidad_faret_pallet, registro_calidad_faret_pallet_respuestas
--   DELETE                  registro_calidad_faret_defectos  (la edición reemplaza solo los defectos quitados por el usuario)
--
-- Cómo ejecutar: cuenta con DDL, tras respaldar calidad_db, ANTES de desplegar el backend con los PUT de edición.
-- Sin GO: un solo lote; si algo falla, se revierte todo. Archivo en UTF-8 sin BOM.
SET XACT_ABORT ON;
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;

BEGIN TRAN;

-- 0. Prechequeos: las tablas que se editan deben existir
IF OBJECT_ID(N'dbo.registros_calidad_faret', N'U') IS NULL THROW 51100, N'Falta registros_calidad_faret.', 1;
IF OBJECT_ID(N'dbo.registro_calidad_faret_defectos', N'U') IS NULL THROW 51101, N'Falta registro_calidad_faret_defectos.', 1;
IF OBJECT_ID(N'dbo.registros_calidad_faret_pallet', N'U') IS NULL THROW 51102, N'Falta registros_calidad_faret_pallet.', 1;
IF OBJECT_ID(N'dbo.registro_calidad_faret_pallet_respuestas', N'U') IS NULL THROW 51103, N'Falta registro_calidad_faret_pallet_respuestas.', 1;

-- 1. Bitácora
IF OBJECT_ID(N'dbo.inspecciones_faret_auditoria', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.inspecciones_faret_auditoria (
        id              BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_inspecciones_faret_auditoria PRIMARY KEY,
        tipo            NVARCHAR(10)  NOT NULL,           -- CALIDAD | PALLET
        registro_id     INT           NOT NULL,
        campo           NVARCHAR(200) NOT NULL,
        valor_anterior  NVARCHAR(MAX) NULL,
        valor_nuevo     NVARCHAR(MAX) NULL,
        motivo          NVARCHAR(500) NOT NULL,
        usuario_id      NVARCHAR(50)  NULL,
        usuario_nombre  NVARCHAR(150) NULL,
        origen          NVARCHAR(20)  NULL,               -- faret | innpack (API que emitió el token)
        fecha           DATETIME2(0)  NOT NULL CONSTRAINT DF_inspecciones_faret_auditoria_fecha DEFAULT (SYSDATETIME()),
        CONSTRAINT CK_inspecciones_faret_auditoria_tipo CHECK (tipo IN (N'CALIDAD', N'PALLET'))
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_inspecciones_faret_auditoria_registro' AND object_id = OBJECT_ID(N'dbo.inspecciones_faret_auditoria'))
    CREATE INDEX IX_inspecciones_faret_auditoria_registro ON dbo.inspecciones_faret_auditoria (tipo, registro_id, fecha);

-- 2. Solo agregado: no se modifica ni se borra
IF OBJECT_ID(N'dbo.TR_inspecciones_faret_auditoria_inmutable', N'TR') IS NOT NULL DROP TRIGGER dbo.TR_inspecciones_faret_auditoria_inmutable;
EXEC (N'
CREATE TRIGGER dbo.TR_inspecciones_faret_auditoria_inmutable ON dbo.inspecciones_faret_auditoria
INSTEAD OF UPDATE, DELETE AS
BEGIN
    THROW 51110, N''La auditoría de inspecciones es de solo agregado: no se modifica ni se borra.'', 1;
END');

-- 3. Permisos mínimos
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT ON dbo.inspecciones_faret_auditoria TO [quality_control_backend_sql];
    GRANT UPDATE (nv_faret, nv_vb_aprobado, n_pliego, n_pasada, n_item, pliego_control_n, observaciones, area_control, operador, operador_otro, maquina, presenta_defectos, area_defecto, tipo_folia, accion_correctiva) ON dbo.registros_calidad_faret TO [quality_control_backend_sql];
    GRANT UPDATE (tipo_material, dimension, fibra, numero_pallet, numero_pasadas_prensa, observaciones, area_control, operador, operador_otro, maquina) ON dbo.registros_calidad_faret_pallet TO [quality_control_backend_sql];
    GRANT UPDATE (resultado, observacion) ON dbo.registro_calidad_faret_pallet_respuestas TO [quality_control_backend_sql];
    GRANT DELETE ON dbo.registro_calidad_faret_defectos TO [quality_control_backend_sql];
END

-- 4. Verificación final
IF OBJECT_ID(N'dbo.inspecciones_faret_auditoria', N'U') IS NULL THROW 51120, N'No se creó la bitácora.', 1;
IF OBJECT_ID(N'dbo.TR_inspecciones_faret_auditoria_inmutable', N'TR') IS NULL THROW 51121, N'No se creó el trigger de inmutabilidad.', 1;

COMMIT TRAN;
PRINT N'011 aplicada: bitácora de edición de inspecciones y permisos mínimos.';
