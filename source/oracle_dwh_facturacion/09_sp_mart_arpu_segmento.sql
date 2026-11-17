-- =====================================================================
-- SP_MART_ARPU_SEGMENTO: ARPU e ingresos por segmento y provincia
-- Incluye subtotales (ROLLUP), peso sobre el total y variacion MoM.
-- =====================================================================

CREATE OR REPLACE PROCEDURE DWH_MART.SP_MART_ARPU_SEGMENTO (p_periodo IN VARCHAR2) AS
    c_proceso   CONSTANT VARCHAR2(50) := 'SP_MART_ARPU_SEGMENTO';
    v_per_ant   VARCHAR2(6) := TO_CHAR(ADD_MONTHS(TO_DATE(p_periodo, 'YYYYMM'), -1), 'YYYYMM');
    v_filas     NUMBER;
BEGIN
    DWH_CORE.PKG_LOG.P_INICIO(c_proceso, p_periodo);

    MERGE INTO DWH_MART.MART_ARPU_SEGMENTO tgt
    USING (
        WITH actual AS (
            SELECT NVL(f.SEGMENTO, 'TOTAL')                              AS SEGMENTO,
                   NVL(dc.PROVINCIA, 'TOTAL')                            AS PROVINCIA,
                   COUNT(DISTINCT f.ID_CLIENTE)                          AS NUM_CLIENTES,
                   SUM(f.IMPORTE_TOTAL)                                  AS INGRESOS_TOTALES,
                   DWH_CORE.PKG_FACTURACION.F_CALCULA_ARPU(SUM(f.IMPORTE_BASE), SUM(f.NUM_LINEAS_ACTIVAS)) AS ARPU_MEDIO,
                   GROUPING_ID(f.SEGMENTO, dc.PROVINCIA)                 AS GID
            FROM DWH_CORE.FACT_FACTURACION_MENSUAL f
            JOIN DWH_CORE.DIM_CLIENTE dc
              ON dc.ID_CLIENTE = f.ID_CLIENTE AND dc.ES_ACTUAL = 'S'
            WHERE f.PERIODO = p_periodo
              -- Las filiales de grupos empresariales se reportan en la provincia del grupo
              AND NOT EXISTS (SELECT 1 FROM DWH_MART.V_JERARQUIA_EMPRESAS j
                               WHERE j.ID_CLIENTE = f.ID_CLIENTE AND j.NIVEL > 2)
            GROUP BY ROLLUP (f.SEGMENTO, dc.PROVINCIA)
        )
        SELECT p_periodo AS PERIODO,
               a.SEGMENTO,
               a.PROVINCIA,
               a.NUM_CLIENTES,
               a.INGRESOS_TOTALES,
               a.ARPU_MEDIO,
               ROUND(100 * RATIO_TO_REPORT(DECODE(a.GID, 0, a.INGRESOS_TOTALES)) OVER (), 2) AS PESO_INGRESOS_PCT,
               ROUND(100 * (a.ARPU_MEDIO - ant.ARPU_MEDIO) / NULLIF(ant.ARPU_MEDIO, 0), 2)  AS VARIACION_ARPU_MOM_PCT
        FROM actual a
        LEFT JOIN DWH_MART.MART_ARPU_SEGMENTO ant
               ON ant.PERIODO   = v_per_ant
              AND ant.SEGMENTO  = a.SEGMENTO
              AND ant.PROVINCIA = a.PROVINCIA
    ) src
    ON (tgt.PERIODO = src.PERIODO AND tgt.SEGMENTO = src.SEGMENTO AND tgt.PROVINCIA = src.PROVINCIA)
    WHEN MATCHED THEN UPDATE SET
        tgt.NUM_CLIENTES           = src.NUM_CLIENTES,
        tgt.INGRESOS_TOTALES       = src.INGRESOS_TOTALES,
        tgt.ARPU_MEDIO             = src.ARPU_MEDIO,
        tgt.PESO_INGRESOS_PCT      = src.PESO_INGRESOS_PCT,
        tgt.VARIACION_ARPU_MOM_PCT = src.VARIACION_ARPU_MOM_PCT,
        tgt.FECHA_CARGA            = SYSDATE
    WHEN NOT MATCHED THEN INSERT
        (PERIODO, SEGMENTO, PROVINCIA, NUM_CLIENTES, INGRESOS_TOTALES, ARPU_MEDIO,
         PESO_INGRESOS_PCT, VARIACION_ARPU_MOM_PCT, FECHA_CARGA)
    VALUES
        (src.PERIODO, src.SEGMENTO, src.PROVINCIA, src.NUM_CLIENTES, src.INGRESOS_TOTALES, src.ARPU_MEDIO,
         src.PESO_INGRESOS_PCT, src.VARIACION_ARPU_MOM_PCT, SYSDATE);

    v_filas := SQL%ROWCOUNT;
    COMMIT;
    DWH_CORE.PKG_LOG.P_FIN(c_proceso, p_periodo, v_filas);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DWH_CORE.PKG_LOG.P_ERROR(c_proceso, p_periodo, SQLERRM);
        RAISE;
END SP_MART_ARPU_SEGMENTO;
/
