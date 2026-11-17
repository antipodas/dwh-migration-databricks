-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_MART.SP_MART_ARPU_SEGMENTO
-- =====================================================================
-- SP_MART_ARPU_SEGMENTO: ARPU e ingresos por segmento y provincia
-- Incluye subtotales (ROLLUP), peso sobre el total y variacion MoM.
-- =====================================================================

-- TODO: manual review required — confirmar que la separacion wrapper/worker conserva los limites transaccionales y la persistencia del log esperados.
-- Se separa el trabajo atomico para que el MERGE se revierta ante errores y el wrapper pueda registrar el fallo despues.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_mart.sp_mart_arpu_segmento_worker(
    IN p_periodo STRING,
    OUT p_filas BIGINT
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN ATOMIC
    -- La fecha YYYYMM siempre representa el primer dia del mes; TIMESTAMPADD conserva el calculo del periodo anterior.
    DECLARE v_per_ant STRING DEFAULT date_format(timestampadd(MONTH, -1, to_date(p_periodo, 'yyyyMM')), 'yyyyMM');

    -- MERGE de Oracle convertido a nombres Unity Catalog de tres partes e identificadores snake_case.
    MERGE INTO migracion_dwh.dwh_mart.mart_arpu_segmento AS tgt
    USING (
        WITH actual AS (
            SELECT nvl(nullif(f.segmento, ''), 'TOTAL') AS segmento,
                   nvl(nullif(dc.provincia, ''), 'TOTAL') AS provincia,
                   count(DISTINCT f.id_cliente) AS num_clientes,
                   sum(f.importe_total) AS ingresos_totales,
                   -- TODO: manual review required — verificar que la funcion aplanada existe con este nombre y firma en Unity Catalog.
                   migracion_dwh.dwh_core.pkg_facturacion_f_calcula_arpu(
                       sum(f.importe_base),
                       sum(f.num_lineas_activas)
                   ) AS arpu_medio,
                   grouping_id(f.segmento, dc.provincia) AS gid
            FROM migracion_dwh.dwh_core.fact_facturacion_mensual AS f
            JOIN migracion_dwh.dwh_core.dim_cliente AS dc
              ON dc.id_cliente = f.id_cliente
             AND dc.es_actual = 'S'
            WHERE f.periodo = p_periodo
              -- Las filiales de grupos empresariales se reportan en la provincia del grupo
              AND NOT EXISTS (
                  SELECT 1
                  FROM migracion_dwh.dwh_mart.v_jerarquia_empresas AS j
                  WHERE j.id_cliente = f.id_cliente
                    AND j.nivel > 2
              )
            GROUP BY ROLLUP (f.segmento, dc.provincia)
        )
        SELECT p_periodo AS periodo,
               a.segmento,
               a.provincia,
               a.num_clientes,
               a.ingresos_totales,
               a.arpu_medio,
               -- RATIO_TO_REPORT se expresa como valor dividido por la suma de ventana equivalente.
               round(
                   100 * decode(a.gid, 0, a.ingresos_totales)
                       / sum(decode(a.gid, 0, a.ingresos_totales)) OVER (),
                   2
               ) AS peso_ingresos_pct,
               round(
                   100 * (a.arpu_medio - ant.arpu_medio) / nullif(ant.arpu_medio, 0),
                   2
               ) AS variacion_arpu_mom_pct
        FROM actual AS a
        LEFT JOIN migracion_dwh.dwh_mart.mart_arpu_segmento AS ant
               ON ant.periodo = v_per_ant
              AND ant.segmento = a.segmento
              AND ant.provincia = a.provincia
    ) AS src
    ON tgt.periodo = src.periodo
   AND tgt.segmento = src.segmento
   AND tgt.provincia = src.provincia
    WHEN MATCHED THEN UPDATE SET
        tgt.num_clientes = src.num_clientes,
        tgt.ingresos_totales = src.ingresos_totales,
        tgt.arpu_medio = src.arpu_medio,
        tgt.peso_ingresos_pct = src.peso_ingresos_pct,
        tgt.variacion_arpu_mom_pct = src.variacion_arpu_mom_pct,
        -- SYSDATE conserva su componente de hora como CURRENT_TIMESTAMP.
        tgt.fecha_carga = current_timestamp()
    WHEN NOT MATCHED THEN INSERT (
        periodo,
        segmento,
        provincia,
        num_clientes,
        ingresos_totales,
        arpu_medio,
        peso_ingresos_pct,
        variacion_arpu_mom_pct,
        fecha_carga
    ) VALUES (
        src.periodo,
        src.segmento,
        src.provincia,
        src.num_clientes,
        src.ingresos_totales,
        src.arpu_medio,
        src.peso_ingresos_pct,
        src.variacion_arpu_mom_pct,
        current_timestamp()
    );

    -- SQL%ROWCOUNT se captura inmediatamente mediante GET DIAGNOSTICS.
    GET DIAGNOSTICS p_filas = ROW_COUNT;
END;

-- El wrapper sustituye las llamadas Oracle PKG_LOG por escrituras en la tabla corporativa de procesos.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_mart.sp_mart_arpu_segmento(
    IN p_periodo STRING
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    -- CONSTANT VARCHAR2 se convierte en variable STRING inicializada al inicio del bloque.
    DECLARE c_proceso STRING DEFAULT 'SP_MART_ARPU_SEGMENTO';
    DECLARE v_filas BIGINT DEFAULT 0;
    DECLARE v_error STRING;

    -- EXCEPTION WHEN OTHERS se convierte en un EXIT HANDLER declarado antes de las sentencias ejecutables.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- SQLERRM se obtiene mediante GET DIAGNOSTICS y RAISE se convierte en RESIGNAL.
        GET DIAGNOSTICS CONDITION 1 v_error = MESSAGE_TEXT;
        INSERT INTO migracion_dwh.dwh_core.log_procesos (
            proceso,
            paso,
            estado,
            filas_afectadas,
            mensaje,
            fecha_hora
        ) VALUES (
            c_proceso,
            p_periodo,
            'ERROR',
            NULL,
            v_error,
            current_timestamp()
        );
        RESIGNAL;
    END;

    INSERT INTO migracion_dwh.dwh_core.log_procesos (
        proceso,
        paso,
        estado,
        filas_afectadas,
        mensaje,
        fecha_hora
    ) VALUES (
        c_proceso,
        p_periodo,
        'INICIO',
        NULL,
        NULL,
        current_timestamp()
    );

    -- La llamada al worker reemplaza el cuerpo transaccional y devuelve las filas afectadas.
    CALL migracion_dwh.dwh_mart.sp_mart_arpu_segmento_worker(p_periodo, v_filas);

    INSERT INTO migracion_dwh.dwh_core.log_procesos (
        proceso,
        paso,
        estado,
        filas_afectadas,
        mensaje,
        fecha_hora
    ) VALUES (
        c_proceso,
        p_periodo,
        'FIN',
        v_filas,
        NULL,
        current_timestamp()
    );
END;
