-- Migración incremental: adaptar catálogo de Paletizado (proceso_id=7) a la lista
-- exacta de "Paletizado Fruta" y agregar sus orígenes del problema.
-- Aditiva; no borra nada (solo desactiva 1 fila que no fue solicitada).

-- "Pallet inestable" no está en la lista pedida (sí está "Pallet en mal estado", id 160).
UPDATE parametros_control_visual SET activo = 0 WHERE id = 154 AND proceso_id = 7;

-- Defectos faltantes de la lista de Paletizado Fruta.
INSERT INTO parametros_control_visual (proceso_id, nombre, criticidad) VALUES
  (7, 'Golpes en material', 'critico'),
  (7, 'Material sobresale del pallet', 'critico');

-- Orígenes del problema específicos de Paletizado Fruta.
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (7, 'Desgaje'),
  (7, 'Paletizado'),
  (7, 'Material de embalaje'),
  (7, 'Armado de pallet'),
  (7, 'Ajuste de maquina'),
  (7, 'Manipulacion interna'),
  (7, 'Sin determinar');
