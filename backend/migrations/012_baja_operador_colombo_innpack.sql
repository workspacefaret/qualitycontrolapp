-- INNPACK: baja logica del operador de maquina "Luis Colombo" (Pegado). Solicitud de Produccion 2026-11-12.
-- Motor: SQL Server (calidad_db). Idempotente. Baja logica (activo = 0): NO se borra, los registros_control
-- historicos que lo referencian (operador_maquina_id) siguen intactos. Reversible: ver _rollback.sql.
-- Requiere la migracion 008 (tabla operadores_maquina). Ejecutar con cuenta con permiso UPDATE (el dueño, como la 008).
SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE o
SET o.activo = 0
FROM operadores_maquina o
INNER JOIN procesos p ON p.id = o.proceso_id
WHERE p.nombre COLLATE Latin1_General_CI_AI = N'Pegado'
  AND o.nombre COLLATE Latin1_General_CI_AI = N'Luis Colombo'
  AND o.activo = 1;

COMMIT TRANSACTION;

-- Verificacion: SELECT id, nombre, activo FROM operadores_maquina WHERE nombre LIKE N'%Colombo%';  -- activo = 0
