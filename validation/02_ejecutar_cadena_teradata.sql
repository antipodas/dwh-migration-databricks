-- Cadena mensual de marketing con el codigo Teradata convertido (sustituye a cadena_mensual_marketing.btq).
-- En produccion: Lakeflow Job con 3 tareas (uso -> campanas -> segmentacion) + alerta si la segmentacion sale vacia.
CALL migracion_dwh.edw_mkt.m_carga_uso_mensual('202609');
CALL migracion_dwh.edw_mkt.m_carga_uso_mensual('202610');
CALL migracion_dwh.edw_mkt.sp_segmentacion_valor('202609');
SELECT proceso, periodo, estado, filas FROM migracion_dwh.edw_mkt.log_carga ORDER BY ts_log;
