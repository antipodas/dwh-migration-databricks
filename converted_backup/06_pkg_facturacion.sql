-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_CORE.PKG_FACTURACION
-- =====================================================================
-- PKG_FACTURACION: hechos de facturacion mensual por cliente
--   F_CALCULA_ARPU        -> ARPU = ingreso base / lineas activas
--   P_CARGA_FACT_MENSUAL  -> carga FACT_FACTURACION_MENSUAL de un periodo
-- =====================================================================

-- TODO: manual review required — validar los consumidores externos tras aplanar los miembros públicos del paquete
-- Conversión: función de paquete a función escalar UC; NUMBER sin precisión se representa como DOUBLE y DETERMINISTIC se omite
-- TODO: DBSQL doesn't have a type with same precision as Oracle NUMBER without arguments, check if the precision is lost.
CREATE OR REPLACE FUNCTION migracion_dwh.dwh_core.pkg_facturacion_f_calcula_arpu(
    p_importe_base DOUBLE,
    p_num_lineas DOUBLE
)
RETURNS DOUBLE
RETURN CASE
    WHEN coalesce(p_num_lineas, 0) = 0 THEN 0
    ELSE round(p_importe_base / p_num_lineas, 2)
END;

-- Conversión: procedimiento de paquete a procedimiento SQL de Unity Catalog con nombres en snake_case
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_facturacion_p_carga_fact_mensual(
    IN p_periodo STRING
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    DECLARE v_ini_mes DATE DEFAULT to_date(concat_ws('', p_periodo, '01'), 'yyyyMMdd');
    DECLARE v_fin_mes DATE DEFAULT last_day(to_date(concat_ws('', p_periodo, '01'), 'yyyyMMdd'));
    DECLARE v_error_message STRING;

    -- Conversión: EXCEPTION WHEN OTHERS y SQLERRM se sustituyen por un manejador SQLEXCEPTION con diagnósticos
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        -- Conversión: PKG_LOG.P_ERROR se registra directamente en la tabla de procesos
        INSERT INTO migracion_dwh.dwh_core.log_procesos
            (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
        VALUES
            ('PKG_FACTURACION.P_CARGA_FACT_MENSUAL', p_periodo, 'ERROR', NULL, v_error_message, current_timestamp());
        RESIGNAL;
    END;

    -- Conversión: PKG_LOG.P_INICIO se registra directamente en la tabla de procesos
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        ('PKG_FACTURACION.P_CARGA_FACT_MENSUAL', p_periodo, 'INICIO', NULL, NULL, current_timestamp());

    IF v_ini_mes > date_trunc('MONTH', current_timestamp()) THEN
        -- Conversión: RAISE_APPLICATION_ERROR(-20001) se sustituye por SIGNAL SQLSTATE 45000
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = concat_ws('', 'Periodo futuro no permitido: ', p_periodo);
    END IF;

    -- Conversión: TRUNCATE PARTITION dinámico se sustituye por borrado estático del periodo
    DELETE FROM migracion_dwh.dwh_core.fact_facturacion_mensual
    WHERE periodo = p_periodo;

    -- TODO: manual review required — BULK COLLECT has no Databricks equivalent; validar la reescritura como INSERT SELECT
    -- TODO: manual review required — FORALL has no Databricks equivalent; validar la DML basada en conjuntos
    -- TODO: manual review required — la colección TABLE OF %ROWTYPE se eliminó al convertir el flujo a SQL basado en conjuntos
    -- TODO: manual review required — los COMMIT por lote y ROLLBACK de Oracle se sustituyeron por la atomicidad de sentencias Databricks
    -- TODO: manual review required — Oracle DATE incluye hora; confirmar que fecha_carga es TIMESTAMP en la tabla destino
    -- Conversión: cursor, BULK COLLECT y FORALL se consolidan en un único INSERT SELECT
    INSERT INTO migracion_dwh.dwh_core.fact_facturacion_mensual (
        periodo,
        id_cliente,
        segmento,
        num_lineas_activas,
        importe_base,
        importe_total,
        importe_impagado,
        arpu,
        meses_antiguedad,
        fecha_carga
    )
    -- Fix NESTED_AGGREGATE_FUNCTION: se agrega primero en subconsulta y el ARPU se calcula fuera del GROUP BY
    SELECT a.periodo,
           a.id_cliente,
           a.segmento,
           a.num_lineas_activas,
           a.importe_base,
           a.importe_total,
           a.importe_impagado,
           migracion_dwh.dwh_core.pkg_facturacion_f_calcula_arpu(
               a.importe_base,
               a.num_lineas_activas
           ) AS arpu,
           a.meses_antiguedad,
           a.fecha_carga
    FROM (
    SELECT p_periodo AS periodo,
           f.id_cliente,
           dc.segmento,
           coalesce(ln.num_lineas, 0) AS num_lineas_activas,
           sum(f.importe_base) AS importe_base,
           sum(f.importe_total) AS importe_total,
           sum(CASE WHEN f.estado_pago = 'IMPAGADA' THEN f.importe_total ELSE 0 END) AS importe_impagado,
           CASE
               WHEN months_between(v_fin_mes, dc.fecha_alta, false) >= 0
                   THEN floor(months_between(v_fin_mes, dc.fecha_alta, false))
               ELSE ceil(months_between(v_fin_mes, dc.fecha_alta, false))
           END AS meses_antiguedad,
           current_timestamp() AS fecha_carga
    FROM migracion_dwh.dwh_stg.stg_facturas AS f
    INNER JOIN migracion_dwh.dwh_core.dim_cliente AS dc
        ON dc.id_cliente = f.id_cliente
       AND dc.es_actual = 'S'
    LEFT JOIN (
        SELECT l.id_cliente,
               count(*) AS num_lineas
        FROM migracion_dwh.dwh_stg.stg_lineas AS l
        WHERE l.fecha_alta <= v_fin_mes
          AND (l.fecha_baja IS NULL OR l.fecha_baja > v_fin_mes)
        GROUP BY l.id_cliente
    ) AS ln
        ON ln.id_cliente = f.id_cliente
    WHERE f.periodo = p_periodo
    GROUP BY f.id_cliente,
             dc.segmento,
             ln.num_lineas,
             dc.fecha_alta
    ) AS a;

    -- Conversión: PKG_LOG.P_FIN se registra directamente en la tabla de procesos
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        ('PKG_FACTURACION.P_CARGA_FACT_MENSUAL', p_periodo, 'FIN', NULL, NULL, current_timestamp());
END;
