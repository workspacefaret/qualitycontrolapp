-- Administración de defectos y controles de las inspecciones FARET (QCC Desktop > Administración de planta). Motor: SQL Server (calidad_db).
-- Aditiva e idempotente (re-ejecutable). Reversible: 015_admin_defectos_faret_rollback.sql. No modifica ninguna fila existente.
--
-- Único cambio estructural: parametros_control_visual.empresa (NULL = compartido, 'FARET' = defecto propio de FARET).
--   Por qué es necesario: Producto Terminado guarda cada defecto marcado en registro_pt_hallazgo_defectos.defecto_id con FK a
--   parametros_control_visual(id), así que un defecto propio de FARET debe existir en esa misma tabla, que INNPACK también lee
--   (formularios de control, catálogo offline, filtros y reportes). Sin una marca por fila no hay forma de que INNPACK no lo vea.
--   Todo lo existente queda en NULL = compartido: ningún consumidor actual cambia hasta que se despliegue el backend nuevo, que filtra
--   `empresa IS NULL` donde INNPACK enumera defectos y solo agrega los de FARET cuando la app de Producto Terminado lo pide.
-- Calidad/Producción (calidad_faret_eventos) y Control Pallet/Papel (calidad_faret_pallet_preguntas) ya tienen todo lo que hace falta
-- (ID estable, baja lógica, criticidad congelada por inspección, bitácora propia, created_at): no se tocan sus estructuras.
--
-- Permisos mínimos para quality_control_backend_sql (solo si el usuario existe), por columna donde SQL Server lo permite:
--   calidad_faret_eventos            INSERT + UPDATE(defecto, criticidad, estado, orden)   (los triggers de la 010 siguen protegiendo ID y *_origen)
--   calidad_faret_pallet_preguntas   INSERT + UPDATE(texto, orden, activo)
--   parametros_control_visual        INSERT + UPDATE(nombre, criticidad, activo)           (el backend solo toca filas con empresa = 'FARET')
--
-- Cómo ejecutar: cuenta con DDL, tras respaldar calidad_db, ANTES de desplegar el backend que usa `empresa`. UTF-8 sin BOM. Sin GO.
SET XACT_ABORT ON;
SET NOCOUNT ON;

IF OBJECT_ID(N'dbo.parametros_control_visual', N'U') IS NULL THROW 51500, N'Falta parametros_control_visual.', 1;
IF OBJECT_ID(N'dbo.calidad_faret_eventos', N'U') IS NULL THROW 51501, N'Falta calidad_faret_eventos (migracion 010).', 1;
IF OBJECT_ID(N'dbo.calidad_faret_pallet_preguntas', N'U') IS NULL THROW 51502, N'Falta calidad_faret_pallet_preguntas.', 1;
IF COL_LENGTH(N'dbo.calidad_faret_pallet_preguntas', N'created_at') IS NULL THROW 51503, N'calidad_faret_pallet_preguntas no tiene created_at: la tolerancia de preguntas nuevas lo necesita.', 1;

BEGIN TRAN;

IF COL_LENGTH(N'dbo.parametros_control_visual', N'empresa') IS NULL
    EXEC (N'ALTER TABLE dbo.parametros_control_visual ADD empresa NVARCHAR(10) NULL');

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_parametros_control_visual_empresa' AND parent_object_id = OBJECT_ID(N'dbo.parametros_control_visual'))
    EXEC (N'ALTER TABLE dbo.parametros_control_visual WITH CHECK ADD CONSTRAINT CK_parametros_control_visual_empresa CHECK (empresa IS NULL OR empresa = N''FARET'')');

IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    EXEC (N'
    GRANT INSERT ON dbo.calidad_faret_eventos TO [quality_control_backend_sql];
    GRANT UPDATE (defecto, criticidad, estado, orden) ON dbo.calidad_faret_eventos TO [quality_control_backend_sql];

    GRANT INSERT ON dbo.calidad_faret_pallet_preguntas TO [quality_control_backend_sql];
    GRANT UPDATE (texto, orden, activo) ON dbo.calidad_faret_pallet_preguntas TO [quality_control_backend_sql];

    GRANT INSERT ON dbo.parametros_control_visual TO [quality_control_backend_sql];
    GRANT UPDATE (nombre, criticidad, activo) ON dbo.parametros_control_visual TO [quality_control_backend_sql];
    ');
END
ELSE
    PRINT N'AVISO: no existe el usuario quality_control_backend_sql en esta base; no se otorgaron permisos.';

COMMIT;
PRINT N'015 aplicada: parametros_control_visual.empresa (NULL = compartido) y permisos mínimos de administración de defectos FARET.';
