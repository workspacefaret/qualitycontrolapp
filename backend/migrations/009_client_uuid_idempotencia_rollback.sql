-- Reversa de 009_client_uuid_idempotencia.sql. SQL Server (calidad_db).
-- Solo elimina los índices y las columnas client_uuid (la clave de deduplicación). No toca ningún registro ni foto:
-- las filas existentes quedan idénticas. Tras revertir, desplegar también el backend anterior (el actual escribe client_uuid).
-- NO revoca el SELECT sobre operadores_maquina: lo necesita el backend de la 008 (operador de máquina). Si se quisiera
-- retirar igualmente:  REVOKE SELECT ON dbo.operadores_maquina FROM [quality_control_backend_sql];
SET XACT_ABORT ON;
BEGIN TRANSACTION;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_registros_control_client_uuid' AND object_id = OBJECT_ID(N'registros_control'))
    DROP INDEX UX_registros_control_client_uuid ON registros_control;
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_registros_calidad_faret_client_uuid' AND object_id = OBJECT_ID(N'registros_calidad_faret'))
    DROP INDEX UX_registros_calidad_faret_client_uuid ON registros_calidad_faret;

IF COL_LENGTH(N'registros_control', N'client_uuid') IS NOT NULL
    ALTER TABLE registros_control DROP COLUMN client_uuid;
IF COL_LENGTH(N'registros_calidad_faret', N'client_uuid') IS NOT NULL
    ALTER TABLE registros_calidad_faret DROP COLUMN client_uuid;

COMMIT TRANSACTION;
