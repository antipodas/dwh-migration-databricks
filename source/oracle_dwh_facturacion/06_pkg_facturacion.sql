-- =====================================================================
-- PKG_FACTURACION: hechos de facturacion mensual por cliente
--   F_CALCULA_ARPU        -> ARPU = ingreso base / lineas activas
--   P_CARGA_FACT_MENSUAL  -> carga FACT_FACTURACION_MENSUAL de un periodo
-- =====================================================================

CREATE OR REPLACE PACKAGE DWH_CORE.PKG_FACTURACION AS
    FUNCTION  F_CALCULA_ARPU (p_importe_base IN NUMBER, p_num_lineas IN NUMBER) RETURN NUMBER DETERMINISTIC;
    PROCEDURE P_CARGA_FACT_MENSUAL (p_periodo IN VARCHAR2);
END PKG_FACTURACION;
/

CREATE OR REPLACE PACKAGE BODY DWH_CORE.PKG_FACTURACION AS

    c_proceso CONSTANT VARCHAR2(50) := 'PKG_FACTURACION.P_CARGA_FACT_MENSUAL';

    TYPE t_tab_fact IS TABLE OF DWH_CORE.FACT_FACTURACION_MENSUAL%ROWTYPE;

    FUNCTION F_CALCULA_ARPU (p_importe_base IN NUMBER, p_num_lineas IN NUMBER) RETURN NUMBER DETERMINISTIC IS
    BEGIN
        IF NVL(p_num_lineas, 0) = 0 THEN
            RETURN 0;
        END IF;
        RETURN ROUND(p_importe_base / p_num_lineas, 2);
    END F_CALCULA_ARPU;

    PROCEDURE P_CARGA_FACT_MENSUAL (p_periodo IN VARCHAR2) IS
        v_ini_mes  DATE := TO_DATE(p_periodo || '01', 'YYYYMMDD');
        v_fin_mes  DATE := LAST_DAY(TO_DATE(p_periodo || '01', 'YYYYMMDD'));
        v_datos    t_tab_fact;

        CURSOR c_fact IS
            SELECT p_periodo                                         AS PERIODO,
                   f.ID_CLIENTE,
                   dc.SEGMENTO,
                   NVL(ln.NUM_LINEAS, 0)                             AS NUM_LINEAS_ACTIVAS,
                   SUM(f.IMPORTE_BASE)                               AS IMPORTE_BASE,
                   SUM(f.IMPORTE_TOTAL)                              AS IMPORTE_TOTAL,
                   SUM(DECODE(f.ESTADO_PAGO, 'IMPAGADA', f.IMPORTE_TOTAL, 0)) AS IMPORTE_IMPAGADO,
                   F_CALCULA_ARPU(SUM(f.IMPORTE_BASE), NVL(ln.NUM_LINEAS, 0)) AS ARPU,
                   TRUNC(MONTHS_BETWEEN(v_fin_mes, dc.FECHA_ALTA))   AS MESES_ANTIGUEDAD,
                   SYSDATE                                           AS FECHA_CARGA
            FROM DWH_STG.STG_FACTURAS f
            JOIN DWH_CORE.DIM_CLIENTE dc
              ON dc.ID_CLIENTE = f.ID_CLIENTE
             AND dc.ES_ACTUAL  = 'S'
            LEFT JOIN (
                SELECT l.ID_CLIENTE, COUNT(*) AS NUM_LINEAS
                FROM DWH_STG.STG_LINEAS l
                WHERE l.FECHA_ALTA <= v_fin_mes
                  AND (l.FECHA_BAJA IS NULL OR l.FECHA_BAJA > v_fin_mes)
                GROUP BY l.ID_CLIENTE
            ) ln ON ln.ID_CLIENTE = f.ID_CLIENTE
            WHERE f.PERIODO = p_periodo
            GROUP BY f.ID_CLIENTE, dc.SEGMENTO, ln.NUM_LINEAS, dc.FECHA_ALTA;

    BEGIN
        DWH_CORE.PKG_LOG.P_INICIO(c_proceso, p_periodo);

        IF v_ini_mes > TRUNC(SYSDATE, 'MM') THEN
            RAISE_APPLICATION_ERROR(-20001, 'Periodo futuro no permitido: ' || p_periodo);
        END IF;

        EXECUTE IMMEDIATE 'ALTER TABLE DWH_CORE.FACT_FACTURACION_MENSUAL TRUNCATE PARTITION FOR (''' || p_periodo || ''')';

        OPEN c_fact;
        LOOP
            FETCH c_fact BULK COLLECT INTO v_datos LIMIT 10000;
            EXIT WHEN v_datos.COUNT = 0;

            FORALL i IN 1 .. v_datos.COUNT
                INSERT INTO DWH_CORE.FACT_FACTURACION_MENSUAL VALUES v_datos(i);

            COMMIT;
        END LOOP;
        CLOSE c_fact;

        DWH_CORE.PKG_LOG.P_FIN(c_proceso, p_periodo, NULL);

    EXCEPTION
        WHEN OTHERS THEN
            IF c_fact%ISOPEN THEN CLOSE c_fact; END IF;
            ROLLBACK;
            DWH_CORE.PKG_LOG.P_ERROR(c_proceso, p_periodo, SQLERRM);
            RAISE;
    END P_CARGA_FACT_MENSUAL;

END PKG_FACTURACION;
/
