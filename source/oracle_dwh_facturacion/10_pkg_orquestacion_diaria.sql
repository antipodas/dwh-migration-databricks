-- =====================================================================
-- PKG_ORQUESTACION: cadena diaria del DWH (lanzada por DBMS_SCHEDULER)
--   1. Dimension cliente   2. Trafico del dia   3. Facturacion (dia 3)
--   4. Marts               5. Estadisticas + aviso por correo
-- =====================================================================

CREATE OR REPLACE PACKAGE DWH_CORE.PKG_ORQUESTACION AS
    PROCEDURE P_CADENA_DIARIA (p_fecha IN DATE DEFAULT TRUNC(SYSDATE) - 1);
END PKG_ORQUESTACION;
/

CREATE OR REPLACE PACKAGE BODY DWH_CORE.PKG_ORQUESTACION AS

    c_proceso CONSTANT VARCHAR2(50) := 'PKG_ORQUESTACION.P_CADENA_DIARIA';

    PROCEDURE P_ESTADISTICAS (p_owner IN VARCHAR2, p_tabla IN VARCHAR2) IS
    BEGIN
        DBMS_STATS.GATHER_TABLE_STATS(ownname => p_owner, tabname => p_tabla,
                                      estimate_percent => DBMS_STATS.AUTO_SAMPLE_SIZE,
                                      cascade => TRUE, degree => 8);
    END P_ESTADISTICAS;

    PROCEDURE P_CADENA_DIARIA (p_fecha IN DATE DEFAULT TRUNC(SYSDATE) - 1) IS
        v_periodo_cerrado VARCHAR2(6) := TO_CHAR(ADD_MONTHS(p_fecha, -1), 'YYYYMM');
        v_sql             VARCHAR2(500);
    BEGIN
        DWH_CORE.PKG_LOG.P_INICIO(c_proceso, TO_CHAR(p_fecha, 'YYYYMMDD'));

        DWH_CORE.SP_CARGA_DIM_CLIENTE;
        DWH_CORE.SP_CARGA_FACT_TRAFICO(p_fecha);

        -- La facturacion del mes anterior se cierra el dia 3
        IF TO_CHAR(p_fecha, 'DD') = '03' THEN
            DWH_CORE.PKG_FACTURACION.P_CARGA_FACT_MENSUAL(v_periodo_cerrado);
            DWH_MART.SP_MART_ARPU_SEGMENTO(v_periodo_cerrado);
        END IF;

        DWH_MART.SP_MART_RIESGO_CHURN(p_fecha + 1);

        FOR t IN (SELECT OWNER, TABLE_NAME
                    FROM ALL_TABLES
                   WHERE OWNER IN ('DWH_CORE', 'DWH_MART')
                     AND TABLE_NAME LIKE 'FACT\_%' ESCAPE '\'
                      OR TABLE_NAME LIKE 'MART\_%' ESCAPE '\') LOOP
            P_ESTADISTICAS(t.OWNER, t.TABLE_NAME);
        END LOOP;

        v_sql := 'BEGIN DWH_CORE.PKG_LOG.P_FIN(:1, :2, NULL); END;';
        EXECUTE IMMEDIATE v_sql USING c_proceso, TO_CHAR(p_fecha, 'YYYYMMDD');

        UTL_MAIL.SEND(sender     => 'dwh-noreply@empresa.example',
                      recipients => 'bi-operaciones@empresa.example',
                      subject    => 'DWH facturacion - cadena diaria OK ' || TO_CHAR(p_fecha, 'DD/MM/YYYY'),
                      message    => 'La cadena diaria ha finalizado correctamente.');
    EXCEPTION
        WHEN OTHERS THEN
            DWH_CORE.PKG_LOG.P_ERROR(c_proceso, TO_CHAR(p_fecha, 'YYYYMMDD'), SQLERRM);
            UTL_MAIL.SEND(sender     => 'dwh-noreply@empresa.example',
                          recipients => 'bi-operaciones@empresa.example',
                          subject    => 'DWH facturacion - ERROR cadena diaria ' || TO_CHAR(p_fecha, 'DD/MM/YYYY'),
                          message    => SQLERRM);
            RAISE;
    END P_CADENA_DIARIA;

END PKG_ORQUESTACION;
/

BEGIN
    DBMS_SCHEDULER.CREATE_JOB(
        job_name        => 'DWH_CORE.JOB_CADENA_DIARIA',
        job_type        => 'PLSQL_BLOCK',
        job_action      => 'BEGIN DWH_CORE.PKG_ORQUESTACION.P_CADENA_DIARIA; END;',
        start_date      => SYSTIMESTAMP,
        repeat_interval => 'FREQ=DAILY; BYHOUR=4; BYMINUTE=30',
        enabled         => TRUE,
        comments        => 'Cadena diaria DWH facturacion');
END;
/
