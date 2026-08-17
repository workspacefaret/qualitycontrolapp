-- Producto Terminado: nueva pregunta de selección rápida "Empresa" (Faret/Innpack).
ALTER TABLE registros_producto_terminado
  ADD COLUMN empresa ENUM('FARET','INNPACK') NULL AFTER proceso_pt;
