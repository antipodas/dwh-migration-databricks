CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.bono_fidelizacion (
  periodo STRING NOT NULL, id_cliente BIGINT NOT NULL, bono_eur DECIMAL(8,2), motivo STRING, fecha_calculo TIMESTAMP)
CLUSTER BY (periodo, id_cliente);
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.bono_fidelizacion_literal (
  periodo STRING NOT NULL, id_cliente BIGINT NOT NULL, bono_eur DECIMAL(8,2), motivo STRING, fecha_calculo TIMESTAMP)
CLUSTER BY (periodo, id_cliente);
