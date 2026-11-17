-- Referencia de conversion (Teradata EDW_MKT -> Databricks SQL / Unity Catalog)
-- FALLBACK/JOURNAL/MERGEBLOCKRATIO/COMPRESS: sin equivalente (Delta ya replica y comprime).
-- PRIMARY INDEX + PARTITION BY RANGE_N -> CLUSTER BY (liquid clustering). COLLECT STATISTICS -> Predictive Optimization.
-- SET TABLE (sin duplicados) -> PRIMARY KEY informativa + MERGE en la carga.
CREATE TABLE IF NOT EXISTS migracion_dwh.edw_mkt.uso_mensual (
  periodo STRING NOT NULL,
  periodo_dt DATE NOT NULL,
  id_cliente INT NOT NULL,
  segmento STRING,
  dias_con_uso SMALLINT,
  gb_datos DECIMAL(12,3),
  min_voz DECIMAL(12,2),
  num_sms INT,
  importe_extra DECIMAL(12,2),
  flag_heavy_user TINYINT,
  fecha_proceso TIMESTAMP DEFAULT current_timestamp())
CLUSTER BY (periodo_dt, id_cliente)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

CREATE TABLE IF NOT EXISTS migracion_dwh.edw_mkt.respuesta_campana (
  id_campana INT NOT NULL,
  id_cliente INT NOT NULL,
  canal STRING,
  fecha_contacto DATE,
  ind_respuesta STRING,
  importe_venta DECIMAL(10,2),
  fecha_actualizacion DATE,
  CONSTRAINT pk_respuesta_campana PRIMARY KEY (id_campana, id_cliente))
CLUSTER BY (id_campana);

CREATE TABLE IF NOT EXISTS migracion_dwh.edw_mkt.segmento_valor (
  periodo STRING NOT NULL,
  id_cliente INT NOT NULL,
  segmento STRING,
  provincia STRING,
  facturacion DECIMAL(12,2),
  decil_valor TINYINT,
  tramo_valor STRING)
CLUSTER BY (periodo, id_cliente);

CREATE TABLE IF NOT EXISTS migracion_dwh.edw_mkt.log_carga (
  proceso STRING,
  periodo STRING,
  estado STRING,
  filas INT,
  mensaje STRING,
  ts_log TIMESTAMP DEFAULT current_timestamp())
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');
