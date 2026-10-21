-- Sección "Humedad" para Corrugado (AGNATI, West River) cuando el área es PRODUCCION INNPACK.
-- Aditiva: columnas nuevas NULL en registros_control, no afecta filas existentes.

ALTER TABLE registros_control
  ADD COLUMN humedad_bobina VARCHAR(50) NULL,
  ADD COLUMN humedad_liner_izquierda VARCHAR(50) NULL,
  ADD COLUMN humedad_liner_centro VARCHAR(50) NULL,
  ADD COLUMN humedad_liner_derecha VARCHAR(50) NULL,
  ADD COLUMN humedad_onda_izquierda VARCHAR(50) NULL,
  ADD COLUMN humedad_onda_centro VARCHAR(50) NULL,
  ADD COLUMN humedad_onda_derecha VARCHAR(50) NULL;
