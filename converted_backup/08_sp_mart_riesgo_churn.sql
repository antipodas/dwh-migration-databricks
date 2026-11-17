-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_MART.SP_MART_RIESGO_CHURN
-- =====================================================================
-- SP_MART_RIESGO_CHURN: score de riesgo de baja / portabilidad por cliente
-- Senales: caida de consumo (30d vs 30d previos), incidencias 90d,
--          solicitudes de portabilidad, impagos y antiguedad.
-- =====================================================================

-- Convertido a procedimiento SQL de Unity Catalog; parametro, tipos, fecha por defecto y declaraciones adaptados a Databricks SQL.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_mart.sp_mart_riesgo_churn (
    IN p_fecha_calculo DATE DEFAULT current_date()
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    DECLARE c_proceso STRING DEFAULT 'SP_MART_RIESGO_CHURN';
    DECLARE v_ult_periodo STRING DEFAULT date_format(timestampadd(MONTH, -1, p_fecha_calculo), 'yyyyMM');
    DECLARE v_filas_afectadas BIGINT DEFAULT 0;
    DECLARE v_error_message STRING;

    -- Convertido WHEN OTHERS a un EXIT HANDLER declarado antes de las sentencias ejecutables.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        -- TODO: manual review required — ROLLBACK no tiene equivalencia dentro del procedimiento no atomico; confirme el alcance de recuperacion y la persistencia independiente del log de error.
        INSERT INTO migracion_dwh.dwh_core.log_procesos
            (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
        VALUES
            (c_proceso, 'GENERAL', 'ERROR', NULL, v_error_message, current_timestamp());
        RESIGNAL;
    END;

    -- Sustituida la llamada al paquete Oracle de logging por un registro en la tabla corporativa.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, date_format(p_fecha_calculo, 'yyyyMMdd'), 'INICIO', NULL, NULL, current_timestamp());

    -- Sustituido SQL dinamico innecesario por TRUNCATE nativo con nombre de tres partes.
    TRUNCATE TABLE migracion_dwh.dwh_mart.mart_riesgo_churn;

    -- Convertidos nombres UC, aritmetica de fechas, joins externos Oracle y meses_between a sintaxis Databricks SQL.
    -- TODO: manual review required — ROWNUM = 1 elegia una fila no determinista; any_value conserva la seleccion arbitraria, pero debe confirmarse la regla de desempate de ARPU.
    INSERT INTO migracion_dwh.dwh_mart.mart_riesgo_churn
    WITH consumo AS (
        SELECT f.id_cliente,
               sum(CASE WHEN f.fecha >= dateadd(DAY, -30, p_fecha_calculo) THEN f.mb_datos + f.minutos_voz ELSE 0 END) AS consumo_30d,
               sum(CASE WHEN f.fecha < dateadd(DAY, -30, p_fecha_calculo) THEN f.mb_datos + f.minutos_voz ELSE 0 END) AS consumo_30d_prev
        FROM migracion_dwh.dwh_core.fact_trafico_diario AS f
        WHERE f.fecha >= dateadd(DAY, -60, p_fecha_calculo)
          AND f.fecha < p_fecha_calculo
        GROUP BY f.id_cliente
    ),
    porta AS (
        SELECT l.id_cliente,
               count(*) AS num_portabilidades,
               listagg(DISTINCT p.operador_destino, ', ') WITHIN GROUP (ORDER BY p.operador_destino) AS operadores_destino
        FROM migracion_dwh.dwh_stg.stg_portabilidades AS p
        INNER JOIN migracion_dwh.dwh_stg.stg_lineas AS l
                ON p.id_linea = l.id_linea
        WHERE p.fecha_solicitud >=
              CASE
                  WHEN p_fecha_calculo = last_day(p_fecha_calculo)
                      THEN last_day(timestampadd(MONTH, -6, p_fecha_calculo))
                  ELSE timestampadd(MONTH, -6, p_fecha_calculo)
              END
        GROUP BY l.id_cliente
    ),
    base AS (
        SELECT dc.id_cliente,
               dc.segmento,
               dc.provincia,
               -- ARPU del ultimo periodo facturado (subconsulta escalar correlacionada)
               (SELECT any_value(ff.arpu)
                  FROM migracion_dwh.dwh_core.fact_facturacion_mensual AS ff
                 WHERE ff.id_cliente = dc.id_cliente
                   AND ff.periodo = v_ult_periodo) AS arpu_ultimo_mes,
               round(100 * (nvl(c.consumo_30d, 0) - nvl(c.consumo_30d_prev, 0))
                         / nullif(c.consumo_30d_prev, 0), 2) AS variacion_consumo_pct,
               (SELECT count(*)
                  FROM migracion_dwh.dwh_stg.stg_incidencias AS i
                 WHERE i.id_cliente = dc.id_cliente
                   AND i.fecha_apertura >= dateadd(DAY, -90, p_fecha_calculo)) AS num_incidencias_90d,
               nvl(pt.num_portabilidades, 0) AS num_portabilidades,
               pt.operadores_destino,
               months_between(p_fecha_calculo, dc.fecha_alta, false) AS meses_antiguedad
        FROM migracion_dwh.dwh_core.dim_cliente AS dc
        LEFT JOIN consumo AS c
               ON dc.id_cliente = c.id_cliente
        LEFT JOIN porta AS pt
               ON dc.id_cliente = pt.id_cliente
        WHERE dc.es_actual = 'S'
    ),
    scored AS (
        SELECT b.*,
               least(100,
                     greatest(0, -nvl(b.variacion_consumo_pct, 0)) * 0.4
                   + b.num_incidencias_90d * 8
                   + b.num_portabilidades * 25
                   + decode(sign(b.meses_antiguedad - 12), -1, 10, 0)) AS score_riesgo
        FROM base AS b
    )
    SELECT s.id_cliente,
           s.segmento,
           s.provincia,
           s.arpu_ultimo_mes,
           s.variacion_consumo_pct,
           s.num_incidencias_90d,
           s.num_portabilidades,
           s.operadores_destino,
           round(s.score_riesgo, 2),
           CASE WHEN s.score_riesgo >= 60 THEN 'ALTO'
                WHEN s.score_riesgo >= 30 THEN 'MEDIO'
                ELSE 'BAJO' END,
           dense_rank() OVER (
               PARTITION BY s.provincia
               ORDER BY s.score_riesgo DESC NULLS FIRST,
                        s.arpu_ultimo_mes DESC NULLS LAST
           ),
           p_fecha_calculo
    FROM scored AS s;

    -- Capturado inmediatamente el numero de filas del INSERT y sustituido el logging Oracle.
    GET DIAGNOSTICS v_filas_afectadas = ROW_COUNT;
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'INSERT', 'FIN', v_filas_afectadas, NULL, current_timestamp());

    -- Clientes dados de baja en staging no deben aparecer en el mart
    -- Convertidos nombres de Unity Catalog y el operador Oracle MINUS a EXCEPT.
    DELETE FROM migracion_dwh.dwh_mart.mart_riesgo_churn
    WHERE id_cliente IN (
        SELECT id_cliente
        FROM migracion_dwh.dwh_core.dim_cliente
        WHERE es_actual = 'S'
        EXCEPT
        SELECT DISTINCT id_cliente
        FROM migracion_dwh.dwh_stg.stg_lineas
        WHERE estado IN ('A', 'S')
    );

    -- Capturado inmediatamente el numero de filas del DELETE y sustituido el logging Oracle.
    GET DIAGNOSTICS v_filas_afectadas = ROW_COUNT;
    -- TODO: manual review required — el COMMIT explicito de Oracle se elimina; confirme que la ejecucion no atomica/autocommit de Databricks conserva la visibilidad y recuperacion esperadas.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'DEPURACION_BAJAS', 'FIN', v_filas_afectadas, NULL, current_timestamp());

-- Eliminados la clausula EXCEPTION final, el nombre Oracle tras END y el terminador SQL*Plus; la gestion de errores se declaro al inicio del bloque.
END;
