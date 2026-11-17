-- =====================================================================
-- Validacion "reconcile-lite" del codigo convertido por Genie Migrate
-- Compara lo que producen los procedimientos/vistas convertidos con un
-- calculo de referencia independiente hecho directamente sobre staging.
-- Ejecutar DESPUES de la cadena (validation/00_ejecutar_cadena.sql).
-- Cada fila debe salir con resultado = 'OK'.
-- =====================================================================
WITH
dim AS (
  SELECT COUNT_IF(es_actual = 'S') AS vigentes,
         COUNT_IF(es_actual = 'S' AND segmento IN ('RESIDENCIAL', 'PYME', 'EMPRESA')) AS decodificados
  FROM migracion_dwh.dwh_core.dim_cliente
),
stg_cli AS (SELECT COUNT(*) AS n FROM migracion_dwh.dwh_stg.stg_clientes),
trafico_conv AS (
  SELECT SUM(minutos_voz) AS voz FROM migracion_dwh.dwh_core.fact_trafico_diario
  WHERE fecha = DATE'2026-10-28'
),
trafico_ref AS (
  SELECT SUM(voz) AS voz FROM (
    SELECT ROUND(SUM(CASE WHEN c.tipo_evento = 'VOZ' THEN c.duracion_seg ELSE 0 END) / 60, 2) AS voz
    FROM migracion_dwh.dwh_stg.stg_cdr c
    JOIN migracion_dwh.dwh_stg.stg_lineas l ON l.id_linea = c.id_linea
    WHERE c.fecha_hora_inicio >= DATE'2026-10-28' AND c.fecha_hora_inicio < DATE'2026-10-29'
      AND l.estado IN ('A', 'S')
    GROUP BY l.id_linea)
),
fact_conv AS (
  SELECT periodo, SUM(importe_total) AS total FROM migracion_dwh.dwh_core.fact_facturacion_mensual GROUP BY periodo
),
fact_ref AS (
  SELECT periodo, SUM(importe_total) AS total FROM migracion_dwh.dwh_stg.stg_facturas GROUP BY periodo
),
jer AS (
  SELECT COUNT(*) AS nodos, COUNT_IF(nivel = 1) AS raices, MAX(nivel) AS niveles
  FROM migracion_dwh.dwh_mart.v_jerarquia_empresas
),
sedes AS (SELECT id_cliente FROM migracion_dwh.dwh_mart.v_jerarquia_empresas WHERE nivel > 2),
arpu_conv AS (
  SELECT ingresos_totales AS total FROM migracion_dwh.dwh_mart.mart_arpu_segmento
  WHERE periodo = '202609' AND segmento = 'TOTAL' AND provincia = 'TOTAL'
),
arpu_ref AS (
  SELECT SUM(f.importe_total) AS total
  FROM migracion_dwh.dwh_core.fact_facturacion_mensual f
  LEFT ANTI JOIN sedes s ON s.id_cliente = f.id_cliente
  WHERE f.periodo = '202609'
),
activos AS (
  SELECT DISTINCT id_cliente FROM migracion_dwh.dwh_stg.stg_lineas WHERE estado IN ('A', 'S')
),
churn_bajas AS (
  SELECT COUNT(*) AS n FROM migracion_dwh.dwh_mart.mart_riesgo_churn m
  LEFT ANTI JOIN activos a ON a.id_cliente = m.id_cliente
),
churn_senal AS (
  SELECT ROUND(100 * AVG(CASE WHEN id_cliente % 12 = 0 AND nivel_riesgo = 'ALTO' THEN 1
                              WHEN id_cliente % 12 = 0 THEN 0 END), 1) AS pct_alto_senal,
         ROUND(100 * AVG(CASE WHEN id_cliente % 12 <> 0 AND nivel_riesgo = 'ALTO' THEN 1
                              WHEN id_cliente % 12 <> 0 THEN 0 END), 1) AS pct_alto_resto
  FROM migracion_dwh.dwh_mart.mart_riesgo_churn
)
SELECT '1. dim_cliente: versiones vigentes = clientes staging' AS control,
       CAST(d.vigentes AS STRING) AS convertido, CAST(s.n AS STRING) AS referencia,
       IF(d.vigentes = s.n, 'OK', 'KO') AS resultado
FROM dim d CROSS JOIN stg_cli s
UNION ALL
SELECT '2. dim_cliente: segmentos RES/PYM/EMP decodificados',
       CAST(d.decodificados AS STRING), CAST(s.n AS STRING), IF(d.decodificados = s.n, 'OK', 'KO')
FROM dim d CROSS JOIN stg_cli s
UNION ALL
SELECT '3. fact_trafico 28-oct: minutos de voz vs CDR',
       CAST(c.voz AS STRING), CAST(r.voz AS STRING), IF(abs(c.voz - r.voz) < 0.01, 'OK', 'KO')
FROM trafico_conv c CROSS JOIN trafico_ref r
UNION ALL
SELECT concat('4. fact_facturacion ', r.periodo, ': importe_total vs facturas'),
       CAST(c.total AS STRING), CAST(r.total AS STRING), IF(c.total = r.total, 'OK', 'KO')
FROM fact_ref r LEFT JOIN fact_conv c USING (periodo)
UNION ALL
SELECT '5. v_jerarquia_empresas (CONNECT BY): nodos / raices / niveles',
       concat(j.nodos, ' / ', j.raices, ' / ', j.niveles), '450 / 60 / 3',
       IF(j.nodos = 450 AND j.raices = 60 AND j.niveles = 3, 'OK', 'KO')
FROM jer j
UNION ALL
SELECT '6. mart_arpu_segmento 202609: fila TOTAL/TOTAL vs facturacion (sin sedes nivel 3)',
       CAST(c.total AS STRING), CAST(r.total AS STRING), IF(c.total = r.total, 'OK', 'KO')
FROM arpu_conv c CROSS JOIN arpu_ref r
UNION ALL
SELECT '7. mart_riesgo_churn: sin clientes dados de baja',
       CAST(b.n AS STRING), '0', IF(b.n = 0, 'OK', 'KO')
FROM churn_bajas b
UNION ALL
SELECT '8. mart_riesgo_churn: % ALTO en clientes con senal sintetica > resto',
       CAST(c.pct_alto_senal AS STRING), CAST(c.pct_alto_resto AS STRING),
       IF(c.pct_alto_senal > c.pct_alto_resto, 'OK', 'KO')
FROM churn_senal c;
