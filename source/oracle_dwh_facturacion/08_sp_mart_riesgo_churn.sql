-- =====================================================================
-- SP_MART_RIESGO_CHURN: score de riesgo de baja / portabilidad por cliente
-- Senales: caida de consumo (30d vs 30d previos), incidencias 90d,
--          solicitudes de portabilidad, impagos y antiguedad.
-- =====================================================================

CREATE OR REPLACE PROCEDURE DWH_MART.SP_MART_RIESGO_CHURN (p_fecha_calculo IN DATE DEFAULT TRUNC(SYSDATE)) AS
    c_proceso CONSTANT VARCHAR2(50) := 'SP_MART_RIESGO_CHURN';
    v_ult_periodo VARCHAR2(6) := TO_CHAR(ADD_MONTHS(p_fecha_calculo, -1), 'YYYYMM');
BEGIN
    DWH_CORE.PKG_LOG.P_INICIO(c_proceso, TO_CHAR(p_fecha_calculo, 'YYYYMMDD'));

    EXECUTE IMMEDIATE 'TRUNCATE TABLE DWH_MART.MART_RIESGO_CHURN';

    INSERT INTO DWH_MART.MART_RIESGO_CHURN
    WITH consumo AS (
        SELECT f.ID_CLIENTE,
               SUM(CASE WHEN f.FECHA >= p_fecha_calculo - 30 THEN f.MB_DATOS + f.MINUTOS_VOZ ELSE 0 END) AS CONSUMO_30D,
               SUM(CASE WHEN f.FECHA <  p_fecha_calculo - 30 THEN f.MB_DATOS + f.MINUTOS_VOZ ELSE 0 END) AS CONSUMO_30D_PREV
        FROM DWH_CORE.FACT_TRAFICO_DIARIO f
        WHERE f.FECHA >= p_fecha_calculo - 60
          AND f.FECHA <  p_fecha_calculo
        GROUP BY f.ID_CLIENTE
    ),
    porta AS (
        SELECT l.ID_CLIENTE,
               COUNT(*) AS NUM_PORTABILIDADES,
               LISTAGG(DISTINCT p.OPERADOR_DESTINO, ', ') WITHIN GROUP (ORDER BY p.OPERADOR_DESTINO) AS OPERADORES_DESTINO
        FROM DWH_STG.STG_PORTABILIDADES p, DWH_STG.STG_LINEAS l
        WHERE p.ID_LINEA = l.ID_LINEA
          AND p.FECHA_SOLICITUD >= ADD_MONTHS(p_fecha_calculo, -6)
        GROUP BY l.ID_CLIENTE
    ),
    base AS (
        SELECT dc.ID_CLIENTE,
               dc.SEGMENTO,
               dc.PROVINCIA,
               -- ARPU del ultimo periodo facturado (subconsulta escalar correlacionada)
               (SELECT ff.ARPU
                  FROM DWH_CORE.FACT_FACTURACION_MENSUAL ff
                 WHERE ff.ID_CLIENTE = dc.ID_CLIENTE
                   AND ff.PERIODO = v_ult_periodo
                   AND ROWNUM = 1)                                         AS ARPU_ULTIMO_MES,
               ROUND(100 * (NVL(c.CONSUMO_30D, 0) - NVL(c.CONSUMO_30D_PREV, 0))
                         / NULLIF(c.CONSUMO_30D_PREV, 0), 2)              AS VARIACION_CONSUMO_PCT,
               (SELECT COUNT(*)
                  FROM DWH_STG.STG_INCIDENCIAS i
                 WHERE i.ID_CLIENTE = dc.ID_CLIENTE
                   AND i.FECHA_APERTURA >= p_fecha_calculo - 90)          AS NUM_INCIDENCIAS_90D,
               NVL(pt.NUM_PORTABILIDADES, 0)                               AS NUM_PORTABILIDADES,
               pt.OPERADORES_DESTINO,
               MONTHS_BETWEEN(p_fecha_calculo, dc.FECHA_ALTA)              AS MESES_ANTIGUEDAD
        FROM DWH_CORE.DIM_CLIENTE dc, consumo c, porta pt
        WHERE dc.ES_ACTUAL  = 'S'
          AND dc.ID_CLIENTE = c.ID_CLIENTE (+)
          AND dc.ID_CLIENTE = pt.ID_CLIENTE (+)
    ),
    scored AS (
        SELECT b.*,
               LEAST(100,
                     GREATEST(0, -NVL(b.VARIACION_CONSUMO_PCT, 0)) * 0.4
                   + b.NUM_INCIDENCIAS_90D * 8
                   + b.NUM_PORTABILIDADES * 25
                   + DECODE(SIGN(b.MESES_ANTIGUEDAD - 12), -1, 10, 0)) AS SCORE_RIESGO
        FROM base b
    )
    SELECT s.ID_CLIENTE,
           s.SEGMENTO,
           s.PROVINCIA,
           s.ARPU_ULTIMO_MES,
           s.VARIACION_CONSUMO_PCT,
           s.NUM_INCIDENCIAS_90D,
           s.NUM_PORTABILIDADES,
           s.OPERADORES_DESTINO,
           ROUND(s.SCORE_RIESGO, 2),
           CASE WHEN s.SCORE_RIESGO >= 60 THEN 'ALTO'
                WHEN s.SCORE_RIESGO >= 30 THEN 'MEDIO'
                ELSE 'BAJO' END,
           DENSE_RANK() OVER (PARTITION BY s.PROVINCIA ORDER BY s.SCORE_RIESGO DESC, s.ARPU_ULTIMO_MES DESC NULLS LAST),
           p_fecha_calculo
    FROM scored s;

    DWH_CORE.PKG_LOG.P_FIN(c_proceso, 'INSERT', SQL%ROWCOUNT);

    -- Clientes dados de baja en staging no deben aparecer en el mart
    DELETE FROM DWH_MART.MART_RIESGO_CHURN m
    WHERE m.ID_CLIENTE IN (
        SELECT ID_CLIENTE FROM DWH_CORE.DIM_CLIENTE WHERE ES_ACTUAL = 'S'
        MINUS
        SELECT DISTINCT ID_CLIENTE FROM DWH_STG.STG_LINEAS WHERE ESTADO IN ('A', 'S')
    );

    COMMIT;
    DWH_CORE.PKG_LOG.P_FIN(c_proceso, 'DEPURACION_BAJAS', SQL%ROWCOUNT);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DWH_CORE.PKG_LOG.P_ERROR(c_proceso, 'GENERAL', SQLERRM);
        RAISE;
END SP_MART_RIESGO_CHURN;
/
