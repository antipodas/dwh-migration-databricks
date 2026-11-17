-- Reconciliacion del dominio Teradata (EDW Marketing): objeto convertido vs calculo independiente sobre staging.
-- Cada control devuelve convertido, referencia y OK/KO. Pensado para ejecutarse en el SQL Editor en vivo.
WITH
c1 AS (SELECT 'v_cliente_vigente: 1 fila por cliente' AS control,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.v_cliente_vigente) AS convertido,
              (SELECT COUNT(DISTINCT id_cliente) FROM migracion_dwh.edw_stg.cliente_hist) AS referencia, 0 AS tolerancia),
c2 AS (SELECT 'v_cliente_vigente: ultima version (QUALIFY)' AS control,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.v_cliente_vigente WHERE fecha_carga = DATE'2026-10-15') AS convertido,
              (SELECT COUNT(*) FROM migracion_dwh.edw_stg.cliente_hist WHERE usuario_carga = 'ETL_DIARIO') AS referencia, 0 AS tolerancia),
c3 AS (SELECT 'uso_mensual 202609: clientes' AS control,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.uso_mensual WHERE periodo = '202609') AS convertido,
              (SELECT COUNT(DISTINCT id_cliente) FROM migracion_dwh.edw_stg.uso_diario
                WHERE fecha_uso BETWEEN DATE'2026-09-01' AND DATE'2026-09-30') AS referencia, 0 AS tolerancia),
c4 AS (SELECT 'uso_mensual 202609: GB totales' AS control,
              (SELECT ROUND(SUM(gb_datos), 1) FROM migracion_dwh.edw_mkt.uso_mensual WHERE periodo = '202609') AS convertido,
              (SELECT ROUND(SUM(mb_datos) / 1024, 1) FROM migracion_dwh.edw_stg.uso_diario
                WHERE fecha_uso BETWEEN DATE'2026-09-01' AND DATE'2026-09-30') AS referencia,
              0.5 AS tolerancia),  -- redondeo por fila: DECIMAL(12,3) por cliente antes de sumar (igual que en Teradata)
c5 AS (SELECT 'respuesta_campana: contactos' AS control,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.respuesta_campana) AS convertido,
              (SELECT COUNT(*) FROM migracion_dwh.edw_stg.contacto_campana WHERE fecha_contacto <= DATE'2026-10-31') AS referencia, 0 AS tolerancia),
c6 AS (SELECT 'respuesta_campana: ventas (EUR)' AS control,
              (SELECT SUM(importe_venta) FROM migracion_dwh.edw_mkt.respuesta_campana) AS convertido,
              (SELECT SUM(importe_venta) FROM migracion_dwh.edw_stg.contacto_campana WHERE fecha_contacto <= DATE'2026-10-31') AS referencia, 0 AS tolerancia),
c7 AS (SELECT 'segmento_valor 202609: facturacion (EUR)' AS control,
              (SELECT SUM(facturacion) FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = '202609') AS convertido,
              (SELECT SUM(importe_total) FROM migracion_dwh.edw_stg.factura WHERE periodo = '202609') AS referencia, 0 AS tolerancia),
c8 AS (SELECT 'segmento_valor: deciles 1..10 (QUANTILE->NTILE)' AS control,
              (SELECT COUNT(DISTINCT decil_valor) FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = '202609') AS convertido,
              10 AS referencia, 0 AS tolerancia),
c9 AS (SELECT 'segmento_valor: tramo ALTO = deciles 9-10' AS control,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = '202609' AND tramo_valor = 'ALTO') AS convertido,
              (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = '202609' AND decil_valor >= 9) AS referencia, 0 AS tolerancia),
c10 AS (SELECT 'v_kpi_campanas: ventas = suma de respuestas' AS control,
              (SELECT SUM(ventas) FROM migracion_dwh.edw_mkt.v_kpi_campanas) AS convertido,
              (SELECT coalesce(SUM(importe_venta), 0) FROM migracion_dwh.edw_mkt.respuesta_campana) AS referencia, 0 AS tolerancia)
SELECT control, CAST(convertido AS STRING) AS convertido, CAST(referencia AS STRING) AS referencia,
       CAST(tolerancia AS STRING) AS tolerancia,
       CASE WHEN convertido = referencia THEN 'OK'
            WHEN abs(convertido - referencia) <= tolerancia THEN 'OK (tolerancia)'
            ELSE 'KO' END AS resultado
FROM (SELECT * FROM c1 UNION ALL SELECT * FROM c2 UNION ALL SELECT * FROM c3 UNION ALL SELECT * FROM c4
      UNION ALL SELECT * FROM c5 UNION ALL SELECT * FROM c6 UNION ALL SELECT * FROM c7 UNION ALL SELECT * FROM c8
      UNION ALL SELECT * FROM c9 UNION ALL SELECT * FROM c10);
