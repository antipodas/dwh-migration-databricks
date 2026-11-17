-- =====================================================================
-- Ejecuta la cadena del DWH con el codigo convertido por Genie Migrate
-- (equivalente a lo que hacia PKG_ORQUESTACION + DBMS_SCHEDULER).
-- Prerrequisito: haber desplegado converted_backup/01..09 en orden.
-- =====================================================================

CALL migracion_dwh.dwh_core.sp_carga_dim_cliente();

BEGIN
  DECLARE d DATE DEFAULT DATE'2026-08-30';
  WHILE d <= DATE'2026-10-28' DO
    CALL migracion_dwh.dwh_core.sp_carga_fact_trafico(d);
    SET d = d + INTERVAL 1 DAY;
  END WHILE;
END;

CALL migracion_dwh.dwh_core.pkg_facturacion_p_carga_fact_mensual('202607');
CALL migracion_dwh.dwh_core.pkg_facturacion_p_carga_fact_mensual('202608');
CALL migracion_dwh.dwh_core.pkg_facturacion_p_carga_fact_mensual('202609');

CALL migracion_dwh.dwh_mart.sp_mart_arpu_segmento('202608');
CALL migracion_dwh.dwh_mart.sp_mart_arpu_segmento('202609');

CALL migracion_dwh.dwh_mart.sp_mart_riesgo_churn(DATE'2026-10-29');

SELECT proceso, estado, COUNT(*) AS pasos, SUM(filas_afectadas) AS filas
FROM migracion_dwh.dwh_core.log_procesos
GROUP BY proceso, estado
ORDER BY proceso, estado;
