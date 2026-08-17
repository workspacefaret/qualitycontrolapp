-- Producto Terminado: inspección final NCh44:2007 (Termoformado/Pegado).
-- Tablas nuevas, independientes; reutiliza origenes_problema y
-- parametros_control_visual ya existentes (procesos Pegado=4, Termoformado=5).

CREATE TABLE registros_producto_terminado (
  id INT AUTO_INCREMENT PRIMARY KEY,
  usuario_id INT NOT NULL,
  np VARCHAR(50) NULL,
  cliente VARCHAR(255) NULL,
  codigo_producto VARCHAR(100) NULL,
  descripcion_producto VARCHAR(255) NULL,
  proceso_pt ENUM('Termoformado','Pegado') NOT NULL,
  cantidad_lote INT NOT NULL,
  cantidad_pallets INT NULL,
  cantidad_cajas_bins INT NULL,
  maquina VARCHAR(150) NULL,
  turno ENUM('A','B','C') NOT NULL,
  nivel_inspeccion ENUM('I','II','III') NOT NULL,
  aql DECIMAL(7,3) NOT NULL,
  letra_codigo CHAR(1) NOT NULL,
  tamano_muestra INT NOT NULL,
  ac INT NULL,
  re INT NULL,
  inspeccion_100 TINYINT(1) NOT NULL DEFAULT 0,
  unidades_nc INT NOT NULL DEFAULT 0,
  defectos_totales INT NOT NULL DEFAULT 0,
  resultado ENUM('CONFORME','NO CONFORME') NOT NULL,
  fecha_registro DATE NOT NULL,
  hora_registro TIME NOT NULL,
  creado_en TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  CONSTRAINT fk_pt_usuario FOREIGN KEY (usuario_id) REFERENCES usuarios(id)
);

CREATE TABLE registro_pt_pallets (
  id INT AUTO_INCREMENT PRIMARY KEY,
  registro_id INT NOT NULL,
  pallet_id VARCHAR(100) NOT NULL,
  CONSTRAINT fk_pt_pallets_registro FOREIGN KEY (registro_id)
    REFERENCES registros_producto_terminado(id)
);

CREATE TABLE registro_pt_hallazgos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  registro_id INT NOT NULL,
  correlativo INT NOT NULL,
  origen_id INT NOT NULL,
  observacion VARCHAR(120) NULL,
  foto_nombre_original VARCHAR(255) NOT NULL,
  foto_nombre_archivo VARCHAR(255) NOT NULL,
  foto_ruta VARCHAR(500) NOT NULL,
  CONSTRAINT fk_pt_hallazgos_registro FOREIGN KEY (registro_id)
    REFERENCES registros_producto_terminado(id),
  CONSTRAINT fk_pt_hallazgos_origen FOREIGN KEY (origen_id)
    REFERENCES origenes_problema(id)
);

CREATE TABLE registro_pt_hallazgo_defectos (
  id INT AUTO_INCREMENT PRIMARY KEY,
  hallazgo_id INT NOT NULL,
  defecto_id INT NOT NULL,
  CONSTRAINT fk_pt_hallazgo_defectos_hallazgo FOREIGN KEY (hallazgo_id)
    REFERENCES registro_pt_hallazgos(id),
  CONSTRAINT fk_pt_hallazgo_defectos_defecto FOREIGN KEY (defecto_id)
    REFERENCES parametros_control_visual(id)
);
