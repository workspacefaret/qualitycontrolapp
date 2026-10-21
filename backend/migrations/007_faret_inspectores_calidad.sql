-- Inspectores de Calidad FARET (autocomplete "Operador" del home). Motor: SQL Server (calidad_db).
-- Idempotente: re-ejecutable sin efecto. Compara sin distinguir mayúsculas ni tildes (CI_AI),
-- para no duplicar nombres ya escritos a mano (p. ej. "Mónica Valdivia").
-- Antes de aplicar, revisar el formato actual: SELECT nombre FROM calidad_faret_operadores ORDER BY nombre;
SET XACT_ABORT ON;
BEGIN TRANSACTION;

INSERT INTO calidad_faret_operadores (nombre)
SELECT v.nombre
FROM (VALUES
    (N'MONICA VALDIVIA'),
    (N'ANDRES FLORES'),
    (N'PEDRO ROA'),
    (N'FRANCISCA PACHECO'),
    (N'OLGA ZAPATA')
) AS v(nombre)
WHERE NOT EXISTS (
    SELECT 1
    FROM calidad_faret_operadores o
    WHERE o.nombre COLLATE Latin1_General_CI_AI = v.nombre COLLATE Latin1_General_CI_AI
);

COMMIT TRANSACTION;
