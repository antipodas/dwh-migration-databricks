-- =====================================================================
-- SP_CARGA_FACT_TRAFICO: agrega los CDR del dia a nivel linea
-- Reprocesable: borra la particion del dia antes de insertar.
-- =====================================================================

CREATE OR REPLACE PROCEDURE DWH_CORE.SP_CARGA_FACT_TRAFICO (p_fecha IN DATE DEFAULT TRUNC(SYSDATE) - 1) AS
    c_proceso CONSTANT VARCHAR2(50) := 'SP_CARGA_FACT_TRAFICO';
    v_fecha   DATE := TRUNC(p_fecha);
    v_filas   NUMBER;
BEGIN
    DWH_CORE.PKG_LOG.P_INICIO(c_proceso, TO_CHAR(v_fecha, 'YYYYMMDD'));

    DELETE FROM DWH_CORE.FACT_TRAFICO_DIARIO WHERE FECHA = v_fecha;

    INSERT /*+ APPEND PARALLEL(8) */ INTO DWH_CORE.FACT_TRAFICO_DIARIO
        (FECHA, ID_LINEA, ID_CLIENTE, COD_TARIFA, MINUTOS_VOZ, MB_DATOS, NUM_SMS,
         MINUTOS_ROAMING, IMPORTE_FUERA_BONO, PCT_CONSUMO_BONO_DATOS, FECHA_CARGA)
    SELECT v_fecha,
           l.ID_LINEA,
           l.ID_CLIENTE,
           l.COD_TARIFA,
           ROUND(SUM(DECODE(c.TIPO_EVENTO, 'VOZ', c.DURACION_SEG, 0)) / 60, 2),
           ROUND(SUM(DECODE(c.TIPO_EVENTO, 'DATOS', c.MB_CONSUMIDOS, 0)), 3),
           SUM(DECODE(c.TIPO_EVENTO, 'SMS', 1, 0)),
           ROUND(SUM(CASE WHEN c.TIPO_EVENTO = 'ROAMING' OR c.PAIS_DESTINO <> 'ESP'
                          THEN NVL(c.DURACION_SEG, 0) ELSE 0 END) / 60, 2),
           NVL(SUM(c.IMPORTE), 0),
           -- % del bono mensual de datos consumido en el dia (GB -> MB)
           NVL2(t.GB_INCLUIDOS,
                ROUND(100 * SUM(DECODE(c.TIPO_EVENTO, 'DATOS', c.MB_CONSUMIDOS, 0)) / (t.GB_INCLUIDOS * 1024), 2),
                NULL),
           SYSDATE
    FROM DWH_STG.STG_CDR c,
         DWH_STG.STG_LINEAS l,
         DWH_STG.STG_TARIFAS t
    WHERE c.ID_LINEA      = l.ID_LINEA
      AND l.COD_TARIFA    = t.COD_TARIFA (+)
      AND c.FECHA_HORA_INICIO >= v_fecha
      AND c.FECHA_HORA_INICIO <  v_fecha + 1
      AND l.ESTADO IN ('A', 'S')
    GROUP BY l.ID_LINEA, l.ID_CLIENTE, l.COD_TARIFA, t.GB_INCLUIDOS;

    v_filas := SQL%ROWCOUNT;
    COMMIT;

    DWH_CORE.PKG_LOG.P_FIN(c_proceso, TO_CHAR(v_fecha, 'YYYYMMDD'), v_filas);

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DWH_CORE.PKG_LOG.P_FIN(c_proceso, TO_CHAR(v_fecha, 'YYYYMMDD'), 0);
    WHEN OTHERS THEN
        ROLLBACK;
        DWH_CORE.PKG_LOG.P_ERROR(c_proceso, TO_CHAR(v_fecha, 'YYYYMMDD'), SQLERRM);
        RAISE;
END SP_CARGA_FACT_TRAFICO;
/
