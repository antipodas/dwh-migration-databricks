-- Alias laterales (RESPUESTAS / CONTACTOS / VENTAS reutilizados en la misma SELECT): Databricks los soporta,
-- PERO no combinados con GROUP BY ALL (UNSUPPORTED_FEATURE.LATERAL_COLUMN_ALIAS_IN_GROUP_BY): GROUP BY explicito.
-- NULLIFZERO -> nullif(,0). ZEROIFNULL -> coalesce(,0).
CREATE OR REPLACE VIEW migracion_dwh.edw_mkt.v_kpi_campanas AS
SELECT c.id_campana,
       c.nombre_campana,
       c.canal,
       c.coste_total,
       COUNT(r.id_cliente)                                         AS contactos,
       SUM(CASE WHEN r.ind_respuesta = 'S' THEN 1 ELSE 0 END)      AS respuestas,
       CAST(respuestas AS DECIMAL(9,4)) / nullif(contactos, 0)     AS tasa_respuesta,
       coalesce(SUM(r.importe_venta), 0)                           AS ventas,
       (ventas - c.coste_total) / nullif(c.coste_total, 0)         AS roi
FROM migracion_dwh.edw_stg.campana c
LEFT JOIN migracion_dwh.edw_mkt.respuesta_campana r ON r.id_campana = c.id_campana
GROUP BY c.id_campana, c.nombre_campana, c.canal, c.coste_total;

CREATE OR REPLACE VIEW migracion_dwh.edw_mkt.v_top_campanas_canal AS
SELECT canal, id_campana, nombre_campana, roi,
       rank() OVER (PARTITION BY canal ORDER BY roi DESC) AS ranking
FROM migracion_dwh.edw_mkt.v_kpi_campanas
QUALIFY rank() OVER (PARTITION BY canal ORDER BY roi DESC) <= 2;
