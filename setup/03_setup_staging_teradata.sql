-- =====================================================================
-- Setup demo Genie Migrate (empresa ficticia) - EDW de Marketing en Teradata
-- Staging "ya migrado" (EDW_STG) que leen los scripts Teradata de la demo.
-- Deriva de migracion_dwh.dwh_stg (ejecutar antes setup/01). Determinista y re-ejecutable.
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS migracion_dwh.edw_stg COMMENT 'Staging Teradata (EDW_STG) ya migrado';
CREATE SCHEMA IF NOT EXISTS migracion_dwh.edw_mkt COMMENT 'Destino del codigo Teradata convertido (EDW_MKT)';

-- Historico de clientes (SCD tipo "append"): 1 version por cliente + 2a version para 1 de cada 7
CREATE OR REPLACE TABLE migracion_dwh.edw_stg.cliente_hist
COMMENT 'EDW_STG.CLIENTE_HIST (Teradata): una fila por version de cliente'
AS
SELECT id_cliente, nif, nombre, segmento AS cod_segmento, provincia, fecha_alta,
       DATE'2026-06-30' AS fecha_carga, 'ETL_INICIAL' AS usuario_carga
FROM migracion_dwh.dwh_stg.stg_clientes
UNION ALL
SELECT id_cliente, nif, upper(nombre) AS nombre,
       CASE WHEN segmento = 'RES' AND id_cliente % 2 = 0 THEN 'PYM' ELSE segmento END AS cod_segmento,
       CASE WHEN id_cliente % 3 = 0 THEN 'Madrid' ELSE provincia END AS provincia,
       fecha_alta, DATE'2026-10-15' AS fecha_carga, 'ETL_DIARIO' AS usuario_carga
FROM migracion_dwh.dwh_stg.stg_clientes
WHERE id_cliente % 7 = 0;

-- Uso diario por cliente (agregado de CDRs)
CREATE OR REPLACE TABLE migracion_dwh.edw_stg.uso_diario
COMMENT 'EDW_STG.USO_DIARIO (Teradata): consumo diario por cliente'
AS
SELECT l.id_cliente,
       CAST(c.fecha_hora_inicio AS DATE)                                              AS fecha_uso,
       CAST(SUM(c.mb_consumidos) AS DECIMAL(15,3))                                   AS mb_datos,
       CAST(SUM(CASE WHEN c.tipo_evento IN ('VOZ','ROAMING') THEN c.duracion_seg ELSE 0 END) / 60.0 AS DECIMAL(12,2)) AS min_voz,
       CAST(SUM(CASE WHEN c.tipo_evento = 'SMS' THEN 1 ELSE 0 END) AS INT)            AS num_sms,
       CAST(SUM(c.importe) AS DECIMAL(12,4))                                         AS importe_extra
FROM migracion_dwh.dwh_stg.stg_cdr c
JOIN migracion_dwh.dwh_stg.stg_lineas l ON l.id_linea = c.id_linea
GROUP BY ALL;

-- Campanas de marketing
CREATE OR REPLACE TABLE migracion_dwh.edw_stg.campana (
  id_campana INT, nombre_campana STRING, canal STRING, fecha_inicio DATE, fecha_fin DATE, coste_total DECIMAL(12,2))
COMMENT 'EDW_STG.CAMPANA (Teradata)';
INSERT INTO migracion_dwh.edw_stg.campana VALUES
  (101, 'Fibra 1Gb verano',        'EMAIL',   DATE'2026-07-01', DATE'2026-08-31', 18000.00),
  (102, 'Portabilidad movil',      'TELEMKT', DATE'2026-07-15', DATE'2026-09-15', 42000.00),
  (103, 'Pack total upsell',    'APP',     DATE'2026-08-01', DATE'2026-09-30',  9500.00),
  (104, 'Roaming vacaciones',      'SMS',     DATE'2026-07-01', DATE'2026-08-31',  3200.00),
  (105, 'Empresas 50Gb',           'TELEMKT', DATE'2026-09-01', DATE'2026-10-31', 27500.00),
  (106, 'Retencion riesgo alto',   'TELEMKT', DATE'2026-09-15', DATE'2026-10-31', 31000.00),
  (107, 'Vuelta al cole datos',    'EMAIL',   DATE'2026-09-01', DATE'2026-09-30',  7800.00),
  (108, 'TV + fibra otono',        'APP',     DATE'2026-10-01', DATE'2026-11-30', 12400.00);

-- Contactos de campana: ~40 % de los clientes no empresariales, con respuesta y venta
CREATE OR REPLACE TABLE migracion_dwh.edw_stg.contacto_campana
COMMENT 'EDW_STG.CONTACTO_CAMPANA (Teradata): un contacto por cliente y campana'
AS
WITH base AS (
  SELECT c.id_cliente, abs(xxhash64(c.id_cliente, 'cmp')) AS h
  FROM migracion_dwh.dwh_stg.stg_clientes c
  WHERE c.id_cliente > 450
),
asig AS (
  SELECT id_cliente, h, 101 + CAST(h % 8 AS INT) AS id_campana FROM base WHERE h % 5 < 2
)
SELECT a.id_campana, a.id_cliente,
       date_add(k.fecha_inicio, CAST((a.h DIV 8) % 25 AS INT)) AS fecha_contacto,
       k.canal,
       CASE WHEN (a.h DIV 100) % 100 < 12 THEN 'S'
            WHEN (a.h DIV 100) % 100 < 20 THEN NULL
            ELSE 'N' END AS respuesta,
       CASE WHEN (a.h DIV 100) % 100 < 12 THEN CAST(20 + (a.h % 9000) / 100.0 AS DECIMAL(10,2)) ELSE NULL END AS importe_venta
FROM asig a JOIN migracion_dwh.edw_stg.campana k ON k.id_campana = a.id_campana;

-- Facturas (copia de la replica Oracle, como la tiene el EDW Teradata)
CREATE OR REPLACE TABLE migracion_dwh.edw_stg.factura
COMMENT 'EDW_STG.FACTURA (Teradata): facturas mensuales por cliente'
AS SELECT id_factura, id_cliente, periodo, fecha_emision, importe_total, estado_pago
FROM migracion_dwh.dwh_stg.stg_facturas;

SELECT 'cliente_hist' AS tabla, COUNT(*) AS filas FROM migracion_dwh.edw_stg.cliente_hist
UNION ALL SELECT 'uso_diario', COUNT(*) FROM migracion_dwh.edw_stg.uso_diario
UNION ALL SELECT 'campana', COUNT(*) FROM migracion_dwh.edw_stg.campana
UNION ALL SELECT 'contacto_campana', COUNT(*) FROM migracion_dwh.edw_stg.contacto_campana
UNION ALL SELECT 'factura', COUNT(*) FROM migracion_dwh.edw_stg.factura;
