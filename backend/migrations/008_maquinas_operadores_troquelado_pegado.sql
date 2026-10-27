-- QR INNPACK: nuevas máquinas de Troquelado y Pegado, operadores de máquina e inspectores de calidad.
-- Motor: SQL Server (calidad_db). Idempotente: re-ejecutable sin efecto. Reversible: ver 008_..._rollback.sql.
-- Compara sin distinguir mayúsculas ni tildes (CI_AI) para no duplicar nombres ya existentes.
--
-- Contenido:
--   1. Tabla operadores_maquina (operador físico de la máquina, distinto del inspector en `usuarios`).
--   2. Columna registros_control.operador_maquina_id (NULL: los registros históricos no cambian).
--   3. Máquinas nuevas (ADICIONALES; no se modifica ninguna existente).
--   4. Operadores de máquina por proceso.
--   5. Inspectores de calidad en `usuarios`.
--
-- Validada contra el esquema real de calidad_db (SQL Server 2016, solo lectura, 2026-10-27) y probada
-- (aplicar, re-aplicar, rollback, re-aplicar) en una base local descartable con el mismo esquema.
--
-- ANTES DE APLICAR: respaldar calidad_db. Ejecutar con una cuenta con permiso DDL (la cuenta de la app no lo tiene).
-- Aplicar en horario de baja actividad: ALTER TABLE sobre registros_control toma un bloqueo de esquema breve.
-- Esquema real: maquinas.codigo_qr NO tiene índice único (AGNATI repite código a propósito);
-- usuarios.rol es NOT NULL con CHECK (valores en uso: operador, admin, admin_ti) -> los inspectores van como 'operador'.
SET XACT_ABORT ON;
BEGIN TRANSACTION;

-- 1. Operadores de máquina -------------------------------------------------------------------------------
IF OBJECT_ID(N'operadores_maquina', N'U') IS NULL
BEGIN
    CREATE TABLE operadores_maquina (
        id          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_operadores_maquina PRIMARY KEY,
        nombre      NVARCHAR(150) NOT NULL,
        proceso_id  INT NOT NULL CONSTRAINT fk_operadores_maquina_proceso REFERENCES procesos(id),
        activo      BIT NOT NULL CONSTRAINT DF_operadores_maquina_activo DEFAULT 1,
        creado_en   DATETIME2 NULL CONSTRAINT DF_operadores_maquina_creado_en DEFAULT SYSDATETIME(),
        CONSTRAINT UQ_operadores_maquina_proceso_nombre UNIQUE (proceso_id, nombre)
    );
END;

-- 2. Operador de máquina asociado a cada inspección ------------------------------------------------------
IF COL_LENGTH(N'registros_control', N'operador_maquina_id') IS NULL
BEGIN
    ALTER TABLE registros_control
        ADD operador_maquina_id INT NULL
        CONSTRAINT fk_registros_control_operador_maquina REFERENCES operadores_maquina(id);
END;

-- 3. Máquinas nuevas -------------------------------------------------------------------------------------
-- Troquelado: sin marca en el pedido; no se inventa (las Bobst 142-x / Ibérica TR105 existentes no se tocan).
-- Pegado: Farmacéutico (PRO-x) e Industrial se distinguen por el nombre. Diana VIII existente no se toca.
INSERT INTO maquinas (nombre, codigo_qr, proceso_id, activo)
SELECT v.nombre, v.codigo_qr, p.id, 1
FROM (VALUES
    (N'Troquelado 104-1',               N'MAQ-TRO-104-1',          N'Troquelado'),
    (N'Troquelado 104-2',               N'MAQ-TRO-104-2',          N'Troquelado'),
    (N'Troquelado 106-1',               N'MAQ-TRO-106-1',          N'Troquelado'),
    (N'Troquelado 106-2',               N'MAQ-TRO-106-2',          N'Troquelado'),
    (N'Troquelado 144-1',               N'MAQ-TRO-144-1',          N'Troquelado'),
    (N'Troquelado 144-2',               N'MAQ-TRO-144-2',          N'Troquelado'),
    (N'Pegado Farmacéutico PRO-1',      N'MAQ-PEG-FARM-PRO-1',     N'Pegado'),
    (N'Pegado Farmacéutico PRO-2',      N'MAQ-PEG-FARM-PRO-2',     N'Pegado'),
    (N'Pegado Farmacéutico PRO-3',      N'MAQ-PEG-FARM-PRO-3',     N'Pegado'),
    (N'Pegado Industrial ALPINA',       N'MAQ-PEG-IND-ALPINA',     N'Pegado'),
    (N'Pegado Industrial EXPERTFOLD',   N'MAQ-PEG-IND-EXPERTFOLD', N'Pegado'),
    (N'Pegado Industrial DIANA-3',      N'MAQ-PEG-IND-DIANA-3',    N'Pegado'),
    (N'Pegado Industrial DIANA-5',      N'MAQ-PEG-IND-DIANA-5',    N'Pegado'),
    (N'Pegado Industrial DIANA-7',      N'MAQ-PEG-IND-DIANA-7',    N'Pegado')
) AS v(nombre, codigo_qr, proceso)
INNER JOIN procesos p ON p.nombre COLLATE Latin1_General_CI_AI = v.proceso COLLATE Latin1_General_CI_AI
WHERE NOT EXISTS (
    SELECT 1 FROM maquinas m
    WHERE m.codigo_qr = v.codigo_qr AND m.proceso_id = p.id
);

-- 4. Operadores de máquina (filtrados por proceso en la app) ---------------------------------------------
INSERT INTO operadores_maquina (nombre, proceso_id)
SELECT v.nombre, p.id
FROM (VALUES
    -- Troquelado
    (N'Kervin Mosquera',     N'Troquelado'),
    (N'Carlos Avello',       N'Troquelado'),
    (N'Carlos Rivera',       N'Troquelado'),
    (N'José Cordero',        N'Troquelado'),
    (N'Luis Aravena',        N'Troquelado'),
    (N'Rodrigo Álvarez',     N'Troquelado'),
    (N'Carlos Medel',        N'Troquelado'),
    -- Pegado Farmacéutico
    (N'Cristian Muñoz',      N'Pegado'),
    (N'Keibert Yusty',       N'Pegado'),
    (N'Jorge Huenuqueo',     N'Pegado'),
    -- Pegado Industrial
    (N'Sebastián Bucarei',   N'Pegado'),
    (N'Marcos Astorga',      N'Pegado'),
    (N'Claudio Cariqueo',    N'Pegado'),
    (N'Rodrigo Amaya',       N'Pegado'),
    (N'Luis Colombo',        N'Pegado')
) AS v(nombre, proceso)
INNER JOIN procesos p ON p.nombre COLLATE Latin1_General_CI_AI = v.proceso COLLATE Latin1_General_CI_AI
WHERE NOT EXISTS (
    SELECT 1 FROM operadores_maquina o
    WHERE o.proceso_id = p.id
      AND o.nombre COLLATE Latin1_General_CI_AI = v.nombre COLLATE Latin1_General_CI_AI
);

-- 5. Inspectores de calidad (patrón existente: CAL-<inicial><apellido>) ----------------------------------
-- Sin contraseña (password_hash NULL), igual que los CAL-HSANHUEZA / CAL-IBUENO existentes: la app los usa
-- solo como selección de "Operador" en el home. Si se necesita login web, asignar contraseña por la vía normal.
INSERT INTO usuarios (codigo_usuario, nombre_completo, rol, activo)
SELECT v.codigo_usuario, v.nombre_completo, N'operador', 1
FROM (VALUES
    (N'CAL-RBASTIAS',     N'Rodrigo Bastías'),
    (N'CAL-AMARCANO',     N'Asdrúbal Marcano'),
    (N'CAL-HOLAVARRIETA', N'Henry Olavarrieta'),
    (N'CAL-DARCOS',       N'Dennisse Arcos')
) AS v(codigo_usuario, nombre_completo)
WHERE NOT EXISTS (
    SELECT 1 FROM usuarios u
    WHERE u.codigo_usuario COLLATE Latin1_General_CI_AI = v.codigo_usuario COLLATE Latin1_General_CI_AI
       OR u.nombre_completo COLLATE Latin1_General_CI_AI = v.nombre_completo COLLATE Latin1_General_CI_AI
);

COMMIT TRANSACTION;

-- Verificación posterior:
--   SELECT nombre, codigo_qr FROM maquinas WHERE codigo_qr LIKE 'MAQ-TRO-1%' OR codigo_qr LIKE 'MAQ-PEG-%' ORDER BY codigo_qr;
--   SELECT p.nombre AS proceso, o.nombre FROM operadores_maquina o JOIN procesos p ON p.id = o.proceso_id ORDER BY 1, 2;
--   SELECT id, codigo_usuario, nombre_completo FROM usuarios WHERE codigo_usuario LIKE 'CAL-%';
