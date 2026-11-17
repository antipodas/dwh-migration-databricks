-- =====================================================================
-- Setup demo Genie Migrate (empresa ficticia) - datos sinteticos de staging
-- Representa los datos YA migrados desde Oracle (DWH_STG) a Unity Catalog.
-- Todo es ficticio y determinista (hash), re-ejecutable.
-- Fecha de referencia de la demo: 2026-10-29
-- =====================================================================

CREATE CATALOG IF NOT EXISTS migracion_dwh COMMENT 'Demo Genie Migrate: DWH facturacion Oracle -> Databricks (datos sinteticos)';
CREATE SCHEMA IF NOT EXISTS migracion_dwh.dwh_stg  COMMENT 'Staging: replica de DWH_STG (Oracle) ya migrada';
CREATE SCHEMA IF NOT EXISTS migracion_dwh.dwh_core COMMENT 'Capa core: destino del codigo convertido (DWH_CORE)';
CREATE SCHEMA IF NOT EXISTS migracion_dwh.dwh_mart COMMENT 'Capa mart: destino del codigo convertido (DWH_MART)';

-- ---------------------------------------------------------------- TARIFAS
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_tarifas (
  cod_tarifa STRING, desc_tarifa STRING, familia STRING, cuota_mensual DECIMAL(8,2),
  gb_incluidos INT, min_incluidos INT, fecha_inicio_comercial DATE, fecha_fin_comercial DATE)
COMMENT 'Catalogo de tarifas (Oracle DWH_STG.STG_TARIFAS)';

INSERT INTO migracion_dwh.dwh_stg.stg_tarifas VALUES
  ('MOV05',  'contrato movil 5gb',          'Movil',      12.00,   5,  999, DATE'2019-01-01', NULL),
  ('MOV30',  'contrato movil 30gb',         'Movil',      20.00,  30,  999, DATE'2020-03-01', NULL),
  ('MOVILI', 'contrato movil ilimitado',    'Movil',      35.00, 999,  999, DATE'2021-06-01', NULL),
  ('MIM1',   'pack fibra 1gb + movil','Pack', 70.00,  50,  999, DATE'2023-05-01', NULL),
  ('MIM2',   'pack total',            'Pack',115.00, 999,  999, DATE'2023-05-01', NULL),
  ('FUS0',   'fusion cero',                 'Fusion',     62.00,  25,  999, DATE'2018-01-01', DATE'2023-04-30'),
  ('FUS+',   'fusion plus',                 'Fusion',     95.00, 999,  999, DATE'2018-01-01', DATE'2023-04-30'),
  ('FIB600', 'solo fibra 600mb',            'Fibra',      35.00, NULL, NULL, DATE'2020-01-01', NULL),
  ('EMP10',  'empresas movil 10gb',         'Empresas',   15.00,  10,  999, DATE'2019-01-01', NULL),
  ('EMP50',  'empresas movil 50gb',         'Empresas',   25.00,  50,  999, DATE'2021-01-01', NULL),
  ('EMPILI', 'empresas movil ilimitado',    'Empresas',   39.00, 999,  999, DATE'2022-01-01', NULL),
  ('TARJ',   'prepago tarjeta',             'Movil',       9.00,   3,  100, DATE'2015-01-01', DATE'2021-12-31');

-- ---------------------------------------------------------------- CLIENTES
-- 1-60 grupos empresariales (raiz), 61-300 filiales (nivel 2), 301-450 sedes (nivel 3),
-- 451-5000 residencial (80%) / pyme (20%)
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_clientes
COMMENT 'Clientes (Oracle DWH_STG.STG_CLIENTES). SEGMENTO viene codificado RES/PYM/EMP'
AS
WITH base AS (
  SELECT CAST(id AS INT) AS id_cliente, abs(xxhash64(id, 'cli')) AS h
  FROM range(1, 5001)
),
prov AS (
  SELECT posexplode(array('Madrid','Madrid','Madrid','Barcelona','Barcelona','Valencia','Sevilla','Malaga',
                          'Bizkaia','Zaragoza','A Coruna','Asturias','Murcia','Alicante','Las Palmas','Valladolid')) AS (pos, provincia)
)
SELECT
  b.id_cliente,
  concat(CASE WHEN b.id_cliente <= 450 THEN 'B' ELSE '' END,
         lpad(CAST(b.h % 100000000 AS STRING), 8, '0'),
         CASE WHEN b.id_cliente <= 450 THEN '' ELSE substr('TRWAGMYFPDXBNJZSQVHLCKE', CAST(b.h % 23 AS INT) + 1, 1) END) AS nif,
  CASE
    WHEN b.id_cliente <= 60  THEN concat('Grupo ', element_at(array('Iberica','Atlantico','Levante','Cantabrico','Meseta','Mediterraneo'), CAST(b.h % 6 AS INT) + 1), ' ', b.id_cliente, ' SA')
    WHEN b.id_cliente <= 300 THEN concat('Filial ', b.id_cliente, ' SL')
    WHEN b.id_cliente <= 450 THEN concat('Sede ', b.id_cliente)
    ELSE concat(element_at(array('Lucia','Hugo','Martina','Mateo','Sofia','Leo','Paula','Daniel','Carmen','Javier'), CAST(b.h % 10 AS INT) + 1), ' ',
                element_at(array('Garcia','Rodriguez','Gonzalez','Fernandez','Lopez','Martinez','Sanchez','Perez','Gomez','Martin'), CAST((b.h DIV 10) % 10 AS INT) + 1))
  END AS nombre,
  CASE WHEN b.id_cliente <= 450 THEN 'EMP'
       WHEN b.h % 5 = 0 THEN 'PYM'
       ELSE 'RES' END AS segmento,
  p.provincia,
  CASE WHEN b.id_cliente BETWEEN 61  AND 300 THEN CAST(1  + (b.h % 60)  AS INT)
       WHEN b.id_cliente BETWEEN 301 AND 450 THEN CAST(61 + (b.h % 240) AS INT)
       ELSE NULL END AS id_cliente_padre,
  date_add(DATE'2005-01-01', CAST(b.h % 7900 AS INT)) AS fecha_alta,
  DATE'2026-10-29' AS fecha_carga
FROM base b
JOIN prov p ON p.pos = b.h % 16;

-- ---------------------------------------------------------------- LINEAS
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.tmp_lineas AS
WITH l AS (
  SELECT CAST(id AS BIGINT) AS id_linea, abs(xxhash64(id, 'lin')) AS h
  FROM range(1, 11001)
),
lc AS (
  -- empresas concentran mas lineas
  SELECT l.*, CASE WHEN l.h % 4 = 0 THEN CAST(1 + (l.h DIV 4) % 450 AS INT)
                   ELSE CAST(451 + (l.h DIV 4) % 4550 AS INT) END AS id_cliente
  FROM l
)
SELECT
  lc.id_linea,
  lc.id_cliente,
  concat('6', lpad(CAST(lc.h % 100000000 AS STRING), 8, '0')) AS msisdn,
  CASE WHEN c.segmento = 'EMP' THEN element_at(array('EMP10','EMP50','EMPILI'), CAST(lc.h % 3 AS INT) + 1)
       ELSE element_at(array('MOV05','MOV30','MOVILI','MIM1','MIM2','FUS0','FUS+','FIB600','TARJ','MOV30'), CAST(lc.h % 10 AS INT) + 1) END AS cod_tarifa,
  CASE WHEN c.segmento <> 'EMP' AND lc.h % 10 = 7 THEN 'FIBRA' ELSE 'MOVIL' END AS tipo_linea,
  greatest(c.fecha_alta, date_add(c.fecha_alta, CAST(lc.h % 1500 AS INT))) AS fecha_alta_raw,
  CASE WHEN lc.h % 100 < 90 THEN 'A' WHEN lc.h % 100 < 94 THEN 'S' ELSE 'B' END AS estado
FROM lc JOIN migracion_dwh.dwh_stg.stg_clientes c USING (id_cliente);

CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_lineas
COMMENT 'Lineas moviles/fijas (Oracle DWH_STG.STG_LINEAS). ESTADO A=activa, S=suspendida, B=baja'
AS
SELECT id_linea, id_cliente, msisdn, cod_tarifa, tipo_linea,
       least(fecha_alta_raw, DATE'2026-07-01') AS fecha_alta,
       CASE WHEN estado = 'B' THEN date_add(DATE'2026-05-01', CAST(id_linea % 170 AS INT)) END AS fecha_baja,
       estado
FROM migracion_dwh.dwh_stg.tmp_lineas;

DROP TABLE IF EXISTS migracion_dwh.dwh_stg.tmp_lineas;

-- ---------------------------------------------------------------- CDR (60 dias)
-- Clientes "en riesgo" (id_cliente % 12 = 0) reducen consumo los ultimos 30 dias.
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_cdr
COMMENT 'Call Detail Records 30-ago a 28-oct-2026 (Oracle DWH_STG.STG_CDR)'
AS
WITH dias AS (
  SELECT explode(sequence(DATE'2026-08-30', DATE'2026-10-28', INTERVAL 1 DAY)) AS dia
),
ld AS (
  SELECT l.id_linea, l.id_cliente, d.dia,
         abs(xxhash64(l.id_linea, d.dia)) AS h,
         CASE WHEN l.id_cliente % 12 = 0 AND d.dia >= DATE'2026-09-29' THEN 1 ELSE 3 END AS max_eventos
  FROM migracion_dwh.dwh_stg.stg_lineas l CROSS JOIN dias d
  WHERE l.estado IN ('A', 'S')
),
ev AS (
  SELECT ld.*, k, abs(xxhash64(ld.h, k)) AS hk
  FROM ld LATERAL VIEW explode(sequence(1, CAST(1 + ld.h % ld.max_eventos AS INT))) e AS k
)
SELECT
  id_linea * 100000 + datediff(dia, DATE'2026-01-01') * 10 + k AS id_cdr,
  id_linea,
  to_timestamp(dia) + make_interval(0, 0, 0, 0, CAST(hk % 24 AS INT), CAST((hk DIV 24) % 60 AS INT), 0) AS fecha_hora_inicio,
  CASE WHEN hk % 100 < 50 THEN 'DATOS' WHEN hk % 100 < 82 THEN 'VOZ' WHEN hk % 100 < 96 THEN 'SMS' ELSE 'ROAMING' END AS tipo_evento,
  CASE WHEN hk % 100 BETWEEN 50 AND 81 OR hk % 100 >= 96 THEN CAST(10 + hk % 900 AS INT) ELSE 0 END AS duracion_seg,
  CASE WHEN hk % 100 < 50 THEN CAST((hk % 80000) / 100.0 AS DECIMAL(12,3)) ELSE 0 END AS mb_consumidos,
  CASE WHEN hk % 100 >= 96 THEN element_at(array('FRA','PRT','GBR','USA','MAR'), CAST(hk % 5 AS INT) + 1) ELSE 'ESP' END AS pais_destino,
  CASE WHEN hk % 100 >= 96 THEN CAST((hk % 500) / 100.0 AS DECIMAL(10,4))
       WHEN hk % 100 BETWEEN 82 AND 95 THEN CAST(0.12 AS DECIMAL(10,4))
       ELSE CAST(0 AS DECIMAL(10,4)) END AS importe
FROM ev;

-- ---------------------------------------------------------------- FACTURAS (jul-sep 2026)
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_facturas
COMMENT 'Facturas mensuales por cliente (Oracle DWH_STG.STG_FACTURAS). PERIODO = YYYYMM'
AS
WITH per AS (
  SELECT explode(array('202607','202608','202609')) AS periodo
),
cuotas AS (
  SELECT l.id_cliente, SUM(t.cuota_mensual) AS cuota
  FROM migracion_dwh.dwh_stg.stg_lineas l
  JOIN migracion_dwh.dwh_stg.stg_tarifas t USING (cod_tarifa)
  GROUP BY l.id_cliente
)
SELECT
  CAST(c.id_cliente AS BIGINT) * 1000 + CAST(substr(p.periodo, 5, 2) AS INT) AS id_factura,
  c.id_cliente,
  p.periodo,
  date_add(to_date(concat(p.periodo, '01'), 'yyyyMMdd'), 33) AS fecha_emision,
  CAST(c.cuota * (0.92 + (abs(xxhash64(c.id_cliente, p.periodo)) % 17) / 100.0) AS DECIMAL(12,2)) AS importe_base,
  CAST(c.cuota * (0.92 + (abs(xxhash64(c.id_cliente, p.periodo)) % 17) / 100.0) * 0.21 AS DECIMAL(12,2)) AS importe_impuestos,
  CAST(c.cuota * (0.92 + (abs(xxhash64(c.id_cliente, p.periodo)) % 17) / 100.0) * 1.21 AS DECIMAL(12,2)) AS importe_total,
  CASE WHEN c.id_cliente % 12 = 0 AND p.periodo >= '202608' AND abs(xxhash64(c.id_cliente)) % 3 = 0 THEN 'IMPAGADA'
       WHEN abs(xxhash64(c.id_cliente, p.periodo, 'pago')) % 100 < 3 THEN 'IMPAGADA'
       WHEN abs(xxhash64(c.id_cliente, p.periodo, 'pago')) % 100 < 8 THEN 'PENDIENTE'
       ELSE 'PAGADA' END AS estado_pago
FROM cuotas c CROSS JOIN per p;

-- ---------------------------------------------------------------- PORTABILIDADES
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_portabilidades
COMMENT 'Solicitudes de portabilidad saliente (Oracle DWH_STG.STG_PORTABILIDADES)'
AS
SELECT
  CAST(id_linea AS BIGINT) + 900000000 AS id_solicitud,
  id_linea,
  element_at(array('MasOrange','Vodafone','Digi','Lowi','Simyo'), CAST(abs(xxhash64(id_linea, 'op')) % 5 AS INT) + 1) AS operador_destino,
  date_add(DATE'2026-05-01', CAST(abs(xxhash64(id_linea, 'fs')) % 180 AS INT)) AS fecha_solicitud,
  element_at(array('SOLICITADA','RETENIDA','EJECUTADA'), CAST(abs(xxhash64(id_linea, 'st')) % 3 AS INT) + 1) AS estado
FROM migracion_dwh.dwh_stg.stg_lineas
WHERE (id_cliente % 12 = 0 AND abs(xxhash64(id_linea, 'p')) % 3 = 0)
   OR abs(xxhash64(id_linea, 'p')) % 100 = 0;

-- ---------------------------------------------------------------- INCIDENCIAS
CREATE OR REPLACE TABLE migracion_dwh.dwh_stg.stg_incidencias
COMMENT 'Incidencias / reclamaciones de clientes (Oracle DWH_STG.STG_INCIDENCIAS)'
AS
WITH i AS (SELECT id, abs(xxhash64(id, 'inc')) AS h FROM range(1, 7001))
SELECT
  CAST(id AS BIGINT) AS id_incidencia,
  CAST(CASE WHEN h % 3 = 0 THEN 12 * (1 + (h DIV 3) % 416) ELSE 1 + (h DIV 3) % 5000 END AS INT) AS id_cliente,
  to_timestamp(date_add(DATE'2026-04-01', CAST(h % 210 AS INT))) + make_interval(0,0,0,0, CAST(h % 13 AS INT) + 8, 0, 0) AS fecha_apertura,
  element_at(array('COBERTURA','FACTURACION','AVERIA_FIBRA','ATENCION_CLIENTE','PORTABILIDAD'), CAST(h % 5 AS INT) + 1) AS categoria,
  CASE WHEN h % 10 < 8 THEN to_timestamp(date_add(DATE'2026-04-01', CAST(h % 210 AS INT) + CAST(h % 7 AS INT))) END AS fecha_cierre
FROM i;

-- ---------------------------------------------------------------- RESUMEN
SELECT 'stg_clientes' AS tabla, COUNT(*) AS filas FROM migracion_dwh.dwh_stg.stg_clientes
UNION ALL SELECT 'stg_lineas', COUNT(*) FROM migracion_dwh.dwh_stg.stg_lineas
UNION ALL SELECT 'stg_tarifas', COUNT(*) FROM migracion_dwh.dwh_stg.stg_tarifas
UNION ALL SELECT 'stg_cdr', COUNT(*) FROM migracion_dwh.dwh_stg.stg_cdr
UNION ALL SELECT 'stg_facturas', COUNT(*) FROM migracion_dwh.dwh_stg.stg_facturas
UNION ALL SELECT 'stg_portabilidades', COUNT(*) FROM migracion_dwh.dwh_stg.stg_portabilidades
UNION ALL SELECT 'stg_incidencias', COUNT(*) FROM migracion_dwh.dwh_stg.stg_incidencias;
