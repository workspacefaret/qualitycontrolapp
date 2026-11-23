-- Auditoría de cuentas técnicas / de prueba / de servicio en calidad_db (INNPACK y FARET). SOLO LECTURA: únicamente SELECT.
-- No modifica datos, contraseñas, roles ni estados. Ejecutar con cualquier cuenta con SELECT sobre calidad_db y enviar el resultado.
-- Uso conocido (fuera de la BD): SERVICIO_FARET_HIBRIDO = cuenta de servicio de INNPACK que usan las vistas híbridas de Photino
-- bajo sesión FARET (config.json, sección InnpackApiServiceAccount). NO debe cambiarse su clave ni su estado.
SET NOCOUNT ON;

-- 1) INNPACK: TODA cuenta de dbo.usuarios que no sea un inspector 'operador', o cuyo código/nombre parezca técnico/de prueba.
SELECT u.id, u.codigo_usuario, u.nombre_completo, u.rol, u.activo,
       CASE WHEN u.rol = N'operador' THEN N'aparece hoy en Administracion > Inspectores' ELSE N'no aparece en Inspectores (rol distinto)' END AS en_panel
FROM dbo.usuarios u
WHERE u.rol <> N'operador'
   OR u.codigo_usuario LIKE N'%SERV%' OR u.codigo_usuario LIKE N'%SVC%' OR u.codigo_usuario LIKE N'%TEST%' OR u.codigo_usuario LIKE N'%PRUEBA%'
   OR u.codigo_usuario LIKE N'%DEMO%' OR u.codigo_usuario LIKE N'%DEV%' OR u.codigo_usuario LIKE N'%API%' OR u.codigo_usuario LIKE N'%HIBRIDO%'
   OR u.codigo_usuario LIKE N'%CLAUDE%' OR u.codigo_usuario LIKE N'%ADMIN%' OR u.codigo_usuario LIKE N'%QA%'
   OR u.nombre_completo LIKE N'%servicio%' OR u.nombre_completo LIKE N'%test%' OR u.nombre_completo LIKE N'%prueba%'
   OR u.nombre_completo LIKE N'%demo%' OR u.nombre_completo LIKE N'%desarrollo%' OR u.nombre_completo LIKE N'%claude%'
   OR u.nombre_completo LIKE N'ZZ%'
ORDER BY u.rol, u.codigo_usuario;

-- 2) INNPACK: inspectores 'operador' con su uso (registros de control que han creado, si la columna existe). Sin uso + nombre raro = candidata.
IF COL_LENGTH(N'dbo.registros_control', N'usuario_id') IS NOT NULL
    EXEC (N'
    SELECT u.id, u.codigo_usuario, u.nombre_completo, u.activo,
           (SELECT COUNT(*) FROM dbo.registros_control r WHERE r.usuario_id = u.id) AS registros_control
    FROM dbo.usuarios u WHERE u.rol = N''operador'' ORDER BY registros_control, u.nombre_completo;');
ELSE
    SELECT u.id, u.codigo_usuario, u.nombre_completo, u.activo, CAST(NULL AS INT) AS registros_control
    FROM dbo.usuarios u WHERE u.rol = N'operador' ORDER BY u.nombre_completo;

-- 3) FARET: todos los inspectores del catálogo (calidad_faret_operadores es una lista corta).
SELECT id, nombre, activo FROM dbo.calidad_faret_operadores ORDER BY nombre;

-- 4) Datos de prueba sueltos en los otros catálogos de planta (restos de pruebas del módulo, 'ZZ ...' o 'TEST').
SELECT N'INNPACK.maquinas' AS tabla, id, nombre, activo FROM dbo.maquinas WHERE nombre LIKE N'ZZ%' OR nombre LIKE N'%test%'
UNION ALL SELECT N'INNPACK.operadores_maquina', id, nombre, activo FROM dbo.operadores_maquina WHERE nombre LIKE N'ZZ%' OR nombre LIKE N'%test%'
UNION ALL SELECT N'INNPACK.procesos', id, nombre, activo FROM dbo.procesos WHERE nombre LIKE N'ZZ%' OR nombre LIKE N'%test%'
UNION ALL SELECT N'FARET.maquinas', id, nombre, CASE WHEN estado = N'Activo' THEN 1 ELSE 0 END FROM dbo.calidad_faret_maquinas WHERE nombre LIKE N'ZZ%' OR nombre LIKE N'%TEST%'
UNION ALL SELECT N'FARET.operadores_area', id, nombre, CASE WHEN estado = N'Activo' THEN 1 ELSE 0 END FROM dbo.calidad_faret_operadores_area WHERE nombre LIKE N'ZZ%' OR nombre LIKE N'%TEST%';

-- 5) Estado de la migración 014 (0 = aún no aplicada).
SELECT COL_LENGTH(N'dbo.usuarios', N'oculto') AS usuarios_oculto, COL_LENGTH(N'dbo.calidad_faret_operadores', N'oculto') AS faret_oculto;
