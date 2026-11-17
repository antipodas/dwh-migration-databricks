-- Las transacciones multi-sentencia (BEGIN ATOMIC) que genera Genie Migrate solo pueden
-- escribir en tablas UC managed con catalog commits. Ejecutar tras desplegar 01_ddl_core_mart.
ALTER TABLE migracion_dwh.dwh_core.dim_cliente              SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_core.fact_trafico_diario      SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_core.fact_facturacion_mensual SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_core.log_procesos             SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_mart.mart_arpu_segmento       SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_mart.mart_riesgo_churn        SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
