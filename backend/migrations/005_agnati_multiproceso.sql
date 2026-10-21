-- AGNATI + Stock Automática soporta más de un proceso (Corrugado y Emplacado).
-- El modelo actual asume codigo_qr único por máquina (1 QR = 1 proceso), así que
-- para permitir que el mismo QR resuelva a más de un proceso se agrega una segunda
-- fila en maquinas con el mismo codigo_qr y distinto proceso_id.
-- Aditiva: no borra ni modifica filas existentes salvo remover el UNIQUE de codigo_qr.

ALTER TABLE maquinas DROP INDEX codigo_qr;

-- Emplacado (proceso_id = 2) para la misma máquina física AGNATI (codigo_qr existente,
-- fila original id=1 sigue siendo Corrugado, proceso_id = 1).
INSERT INTO maquinas (nombre, codigo_qr, proceso_id, activo)
VALUES ('Agnati + Stock Automática', 'MAQ-COR-AGNATI-STOCK-AUTO', 2, 1);
