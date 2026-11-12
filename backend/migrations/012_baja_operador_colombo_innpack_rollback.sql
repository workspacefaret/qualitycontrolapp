-- Rollback de 012: reactiva a "Luis Colombo" (Pegado) en operadores_maquina. Idempotente.
SET XACT_ABORT ON;
BEGIN TRANSACTION;

UPDATE o
SET o.activo = 1
FROM operadores_maquina o
INNER JOIN procesos p ON p.id = o.proceso_id
WHERE p.nombre COLLATE Latin1_General_CI_AI = N'Pegado'
  AND o.nombre COLLATE Latin1_General_CI_AI = N'Luis Colombo'
  AND o.activo = 0;

COMMIT TRANSACTION;
