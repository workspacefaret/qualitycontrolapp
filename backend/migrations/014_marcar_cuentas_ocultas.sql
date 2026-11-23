-- PLANTILLA: marcar cuentas técnicas como ocultas. NO ejecutar hasta que la lista esté aprobada y 014_cuentas_tecnicas_oculto.sql esté aplicada.
-- Solo pone oculto = 1 en filas concretas (por id y código); no toca contraseñas, roles, activo ni nada más. Reversible: poner oculto = 0.
-- Con las listas vacías no hace nada. Cada fila listada debe existir (si no, se aborta todo).
SET XACT_ABORT ON;
SET NOCOUNT ON;

BEGIN TRAN;

DECLARE @innpack TABLE (id INT PRIMARY KEY, codigo_usuario NVARCHAR(50) NOT NULL);
DECLARE @faret   TABLE (id INT PRIMARY KEY, nombre NVARCHAR(150) NOT NULL);

-- <<REVISAR: completar con las cuentas aprobadas>>
-- INSERT INTO @innpack (id, codigo_usuario) VALUES (0, N'CODIGO');
-- INSERT INTO @faret (id, nombre) VALUES (0, N'NOMBRE');

IF (SELECT COUNT(*) FROM @innpack i JOIN dbo.usuarios u ON u.id = i.id AND u.codigo_usuario = i.codigo_usuario) <> (SELECT COUNT(*) FROM @innpack)
    THROW 51410, N'Alguna cuenta INNPACK de la lista no coincide (id + codigo_usuario).', 1;
IF (SELECT COUNT(*) FROM @faret f JOIN dbo.calidad_faret_operadores o ON o.id = f.id AND o.nombre = f.nombre) <> (SELECT COUNT(*) FROM @faret)
    THROW 51411, N'Algun inspector FARET de la lista no coincide (id + nombre).', 1;

UPDATE u SET oculto = 1 FROM dbo.usuarios u JOIN @innpack i ON i.id = u.id;
UPDATE o SET oculto = 1 FROM dbo.calidad_faret_operadores o JOIN @faret f ON f.id = o.id;

COMMIT TRAN;

-- Verificación:  SELECT id, codigo_usuario, rol, activo, oculto FROM dbo.usuarios WHERE oculto = 1;
--                SELECT id, nombre, activo, oculto FROM dbo.calidad_faret_operadores WHERE oculto = 1;
