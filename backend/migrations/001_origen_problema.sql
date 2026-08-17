-- Migración incremental: origen del problema + rename defecto Pegado
-- Aditiva y compatible con registros existentes (1349 filas en registros_control al momento de escribir esto).
-- No borra ni modifica datos históricos salvo el rename puntual de un nombre de catálogo.

-- 1) Rename "Descalce de pegado" -> "Descuadre de pegado" SOLO en el proceso Pegado (proceso_id=4, id=120).
--    NOTA: existe una fila homónima id=106 en Emplacado (proceso_id=2) que NO se toca (no fue pedida).
UPDATE parametros_control_visual SET nombre = 'Descuadre de pegado' WHERE id = 120 AND proceso_id = 4;

-- 2) Catálogo de "Origen del problema" por proceso, selección única.
CREATE TABLE IF NOT EXISTS origenes_problema (
  id INT AUTO_INCREMENT PRIMARY KEY,
  proceso_id INT NOT NULL,
  nombre VARCHAR(100) NOT NULL,
  activo TINYINT(1) NOT NULL DEFAULT 1,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_origenes_problema_proceso FOREIGN KEY (proceso_id) REFERENCES procesos(id)
);

-- Corrugado (proceso_id=1)
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (1, 'Bobina'),
  (1, 'Almidón'),
  (1, 'Ajuste maquina o proceso'),
  (1, 'Sin determinar');

-- Emplacado (proceso_id=2)
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (2, 'Pliego'),
  (2, 'Monotapa'),
  (2, 'Adhesivo PVA'),
  (2, 'Ajuste maquina o proceso'),
  (2, 'Sin determinar');

-- Troquelado (proceso_id=3)
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (3, 'Material de emplacado'),
  (3, 'Ajuste maquina o proceso'),
  (3, 'Humedad de material'),
  (3, 'Corrugado'),
  (3, 'Sin determinar');

-- Pegado (proceso_id=4)
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (4, 'Adhesivo'),
  (4, 'Corrugado'),
  (4, 'Emplacado'),
  (4, 'Impresion'),
  (4, 'Troquelado'),
  (4, 'Ajuste de maquina o proceso'),
  (4, 'Sin determinar');

-- Termoformado (proceso_id=5)
INSERT INTO origenes_problema (proceso_id, nombre) VALUES
  (5, 'Materia prima (Faja)'),
  (5, 'Impresión'),
  (5, 'Sellado / Temperatura'),
  (5, 'Ajuste de maquina o proceso'),
  (5, 'Sin determinar');

-- 3) Vincular registros_control con el origen seleccionado (opcional, no rompe registros existentes).
ALTER TABLE registros_control
  ADD COLUMN origen_id INT NULL,
  ADD CONSTRAINT fk_registros_control_origen FOREIGN KEY (origen_id) REFERENCES origenes_problema(id);
