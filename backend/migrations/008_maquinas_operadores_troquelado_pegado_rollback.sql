-- Reversa de 008_maquinas_operadores_troquelado_pegado.sql. SQL Server (calidad_db).
-- Seguro ante datos reales: lo que ya tiene inspecciones asociadas se DESACTIVA (activo = 0) en vez de borrarse,
-- para no romper claves foráneas ni la trazabilidad. Solo se elimina la tabla/columna nuevas si nadie las usa.
-- Nunca borra máquinas ni usuarios (solo desactiva). Las pruebas confirman que no toca ninguna fila preexistente.
-- Si después de un rollback se vuelve a aplicar la 008, las máquinas/inspectores quedan inactivos (la 008 los ve
-- como ya existentes): reactivarlos con
--   UPDATE maquinas SET activo = 1 WHERE codigo_qr LIKE 'MAQ-TRO-1%' OR codigo_qr LIKE 'MAQ-PEG-FARM-%' OR codigo_qr LIKE 'MAQ-PEG-IND-%';
--   UPDATE usuarios SET activo = 1 WHERE codigo_usuario IN ('CAL-RBASTIAS','CAL-AMARCANO','CAL-HOLAVARRIETA','CAL-DARCOS');
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- Máquinas nuevas
UPDATE maquinas SET activo = 0
WHERE codigo_qr IN (
    N'MAQ-TRO-104-1', N'MAQ-TRO-104-2', N'MAQ-TRO-106-1', N'MAQ-TRO-106-2', N'MAQ-TRO-144-1', N'MAQ-TRO-144-2',
    N'MAQ-PEG-FARM-PRO-1', N'MAQ-PEG-FARM-PRO-2', N'MAQ-PEG-FARM-PRO-3', N'MAQ-PEG-IND-ALPINA',
    N'MAQ-PEG-IND-EXPERTFOLD', N'MAQ-PEG-IND-DIANA-3', N'MAQ-PEG-IND-DIANA-5', N'MAQ-PEG-IND-DIANA-7'
);

-- Inspectores nuevos
UPDATE usuarios SET activo = 0
WHERE codigo_usuario IN (N'CAL-RBASTIAS', N'CAL-AMARCANO', N'CAL-HOLAVARRIETA', N'CAL-DARCOS');

-- Operadores de máquina: si ya hay inspecciones guardadas con operador, solo desactivar.
IF OBJECT_ID(N'operadores_maquina', N'U') IS NOT NULL
   AND COL_LENGTH(N'registros_control', N'operador_maquina_id') IS NOT NULL
   AND EXISTS (SELECT 1 FROM registros_control WHERE operador_maquina_id IS NOT NULL)
BEGIN
    UPDATE operadores_maquina SET activo = 0;
END
ELSE
BEGIN
    IF COL_LENGTH(N'registros_control', N'operador_maquina_id') IS NOT NULL
    BEGIN
        ALTER TABLE registros_control DROP CONSTRAINT fk_registros_control_operador_maquina;
        ALTER TABLE registros_control DROP COLUMN operador_maquina_id;
    END;
    IF OBJECT_ID(N'operadores_maquina', N'U') IS NOT NULL
        DROP TABLE operadores_maquina;
END;

COMMIT TRANSACTION;
