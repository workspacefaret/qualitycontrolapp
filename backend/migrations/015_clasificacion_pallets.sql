-- Clasificación de pallets (AZUL / ROJO / VERDE) en las inspecciones CALIDAD INNPACK y PRODUCCION INNPACK.
-- Motor: SQL Server (calidad_db). ADITIVA e idempotente (re-ejecutable): solo crea 2 tablas nuevas, sus índices y GRANTs.
-- NO modifica ninguna tabla ni dato existente. Reversible: 015_clasificacion_pallets_rollback.sql.
--
-- Modelo (trazabilidad de solo-agregar):
--   * pallet_clasificaciones: UN EVENTO por clasificación. Un pallet (pallet_codigo = código de su tarja, p. ej. 466568-1)
--     puede tener varias filas: la última no anulada es la vigente y las anteriores son el historial (nunca se actualizan
--     ni se borran; una clasificación errónea se ANULA con motivo, no se elimina).
--   * Se guarda una COPIA de los datos de FPS al clasificar (orden, NP, cliente, producto, máquina, operador...), para que
--     la trazabilidad no dependa de que FPS cambie o elimine el registro original. fps_verificado = 1 si el servidor los
--     consultó en FPS al guardar; 0 si FPS no respondió y se conservan los que envió la app.
--   * El responsable, proceso, máquina, NP y turno de la inspección salen de registros_control (FK registro_id).
--   * Significado interno (no se muestra al operador): AZUL = en revisión; ROJO = malo, listo para destrucción; VERDE = bueno.
-- Ejecutar con una cuenta con DDL, tras respaldar calidad_db y ANTES de desplegar el backend que usa estas tablas.
SET XACT_ABORT ON;
SET QUOTED_IDENTIFIER ON;
BEGIN TRANSACTION;

IF OBJECT_ID(N'dbo.pallet_clasificaciones', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pallet_clasificaciones (
        id                 INT IDENTITY(1,1) NOT NULL,
        registro_id        INT NOT NULL,
        pallet_codigo      NVARCHAR(50) NOT NULL,
        record_key         NVARCHAR(50) NULL,
        n_etiqueta         INT NULL,
        color              NVARCHAR(5) NOT NULL,
        observacion        NVARCHAR(500) NULL,
        foto_nombre_original NVARCHAR(255) NULL,
        foto_nombre_archivo  NVARCHAR(255) NULL,
        foto_ruta          NVARCHAR(500) NULL,
        foto_mime_type     NVARCHAR(100) NULL,
        foto_tamano_bytes  INT NULL,
        clasificado_en     DATETIME2(0) NOT NULL CONSTRAINT DF_pallet_clasificaciones_en DEFAULT (GETDATE()),
        -- Copia de FPS al momento de clasificar
        fps_verificado     BIT NOT NULL CONSTRAINT DF_pallet_clasificaciones_fpsv DEFAULT 0,
        orden_fabricacion  NVARCHAR(30) NULL,
        np_faret           NVARCHAR(30) NULL,
        np_innpack         NVARCHAR(30) NULL,
        cliente            NVARCHAR(255) NULL,
        item_np            NVARCHAR(20) NULL,
        codigo_producto    NVARCHAR(100) NULL,
        producto           NVARCHAR(255) NULL,
        proceso_fps        NVARCHAR(100) NULL,
        maquina_fps        NVARCHAR(150) NULL,
        operador_fps       NVARCHAR(150) NULL,
        fecha_tarja        DATETIME2(0) NULL,
        cantidad_unidades  DECIMAL(18,2) NULL,
        total_etiquetas    INT NULL,
        -- Anulación lógica (nunca borrado)
        anulado            BIT NOT NULL CONSTRAINT DF_pallet_clasificaciones_anulado DEFAULT 0,
        anulado_en         DATETIME2(0) NULL,
        anulado_por        NVARCHAR(100) NULL,
        motivo_anulacion   NVARCHAR(250) NULL,
        CONSTRAINT PK_pallet_clasificaciones PRIMARY KEY CLUSTERED (id),
        CONSTRAINT FK_pallet_clasificaciones_registro FOREIGN KEY (registro_id) REFERENCES dbo.registros_control (id),
        CONSTRAINT CK_pallet_clasificaciones_color CHECK (color IN (N'AZUL', N'ROJO', N'VERDE'))
    );
END;

IF OBJECT_ID(N'dbo.pallet_clasificacion_defectos', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.pallet_clasificacion_defectos (
        id               INT IDENTITY(1,1) NOT NULL,
        clasificacion_id INT NOT NULL,
        parametro_id     INT NOT NULL,
        CONSTRAINT PK_pallet_clasificacion_defectos PRIMARY KEY CLUSTERED (id),
        CONSTRAINT FK_pallet_clasif_defectos_clasif FOREIGN KEY (clasificacion_id) REFERENCES dbo.pallet_clasificaciones (id),
        CONSTRAINT FK_pallet_clasif_defectos_param FOREIGN KEY (parametro_id) REFERENCES dbo.parametros_control_visual (id),
        CONSTRAINT UQ_pallet_clasif_defectos UNIQUE (clasificacion_id, parametro_id)
    );
END;

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pallet_clasificaciones_pallet' AND object_id = OBJECT_ID(N'dbo.pallet_clasificaciones'))
    CREATE INDEX IX_pallet_clasificaciones_pallet ON dbo.pallet_clasificaciones (pallet_codigo, id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pallet_clasificaciones_registro' AND object_id = OBJECT_ID(N'dbo.pallet_clasificaciones'))
    CREATE INDEX IX_pallet_clasificaciones_registro ON dbo.pallet_clasificaciones (registro_id);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_pallet_clasificaciones_fecha' AND object_id = OBJECT_ID(N'dbo.pallet_clasificaciones'))
    CREATE INDEX IX_pallet_clasificaciones_fecha ON dbo.pallet_clasificaciones (clasificado_en) INCLUDE (color, anulado);

-- Permisos mínimos de la cuenta de la app (GRANT explícito tabla por tabla, como en el resto del esquema).
-- UPDATE solo sobre pallet_clasificaciones: lo usa únicamente la anulación lógica.
IF USER_ID(N'quality_control_backend_sql') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT, UPDATE ON dbo.pallet_clasificaciones TO [quality_control_backend_sql];
    GRANT SELECT, INSERT ON dbo.pallet_clasificacion_defectos TO [quality_control_backend_sql];
END;

COMMIT TRANSACTION;

-- Verificación posterior:
--   SELECT name FROM sys.tables WHERE name LIKE 'pallet_clasific%';
--   SELECT OBJECT_NAME(object_id) tabla, name FROM sys.indexes WHERE name LIKE 'IX_pallet_clasif%';
--   EXECUTE AS USER = 'quality_control_backend_sql'; SELECT COUNT(*) FROM pallet_clasificaciones; REVERT;
