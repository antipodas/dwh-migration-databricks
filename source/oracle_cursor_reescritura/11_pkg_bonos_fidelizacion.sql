-- =====================================================================
-- PKG_BONOS: recalculo mensual de bonos de fidelizacion / retencion
-- Estilo "vieja escuela": cursor fila a fila, SELECT INTO por cliente,
-- UPDATE + SQL%ROWCOUNT + INSERT, COMMIT cada 500 filas.
-- Tarda ~40 min en produccion con 3,8 M de clientes (dato de explotacion).
-- =====================================================================
CREATE OR REPLACE PACKAGE BODY DWH_CORE.PKG_BONOS AS

    PROCEDURE P_RECALCULA_BONOS (p_periodo IN VARCHAR2) IS
        v_fin_mes   DATE := LAST_DAY(TO_DATE(p_periodo || '01', 'YYYYMMDD'));
        v_meses     NUMBER;
        v_fact      NUMBER(12,2);
        v_inc       PLS_INTEGER;
        v_porta     PLS_INTEGER;
        v_bono      NUMBER(8,2);
        v_motivo    VARCHAR2(40);
        v_cnt       PLS_INTEGER := 0;

        CURSOR c_cli IS
            SELECT ID_CLIENTE, FECHA_ALTA, SEGMENTO
            FROM DWH_CORE.DIM_CLIENTE
            WHERE ES_ACTUAL = 'S'
              AND SEGMENTO IN ('RESIDENCIAL', 'PYME')
            ORDER BY ID_CLIENTE;
    BEGIN
        DWH_CORE.PKG_LOG.P_INICIO('PKG_BONOS.P_RECALCULA_BONOS', p_periodo);

        FOR r IN c_cli LOOP
            v_meses := TRUNC(MONTHS_BETWEEN(v_fin_mes, r.FECHA_ALTA));

            BEGIN
                SELECT NVL(SUM(IMPORTE_TOTAL), 0) INTO v_fact
                FROM DWH_STG.STG_FACTURAS
                WHERE ID_CLIENTE = r.ID_CLIENTE AND PERIODO = p_periodo;
            EXCEPTION
                WHEN NO_DATA_FOUND THEN v_fact := 0;
            END;

            SELECT COUNT(*) INTO v_inc
            FROM DWH_STG.STG_INCIDENCIAS
            WHERE ID_CLIENTE = r.ID_CLIENTE
              AND FECHA_APERTURA >= v_fin_mes - 90;

            SELECT COUNT(*) INTO v_porta
            FROM DWH_STG.STG_PORTABILIDADES p, DWH_STG.STG_LINEAS l
            WHERE p.ID_LINEA = l.ID_LINEA
              AND l.ID_CLIENTE = r.ID_CLIENTE
              AND p.ESTADO = 'SOLICITADA';

            IF v_porta > 0 THEN
                v_bono := 20;  v_motivo := 'RETENCION_PORTABILIDAD';
            ELSIF v_meses >= 60 AND v_inc >= 3 THEN
                v_bono := LEAST(ROUND(v_fact * 0.10, 2), 15);  v_motivo := 'COMPENSACION_INCIDENCIAS';
            ELSIF v_meses >= 120 THEN
                v_bono := 5;   v_motivo := 'FIDELIDAD_10_ANOS';
            ELSE
                v_bono := 0;
            END IF;

            IF v_bono > 0 THEN
                UPDATE DWH_CORE.BONO_FIDELIZACION
                   SET BONO_EUR = v_bono, MOTIVO = v_motivo, FECHA_CALCULO = SYSDATE
                 WHERE ID_CLIENTE = r.ID_CLIENTE AND PERIODO = p_periodo;

                IF SQL%ROWCOUNT = 0 THEN
                    INSERT INTO DWH_CORE.BONO_FIDELIZACION (PERIODO, ID_CLIENTE, BONO_EUR, MOTIVO, FECHA_CALCULO)
                    VALUES (p_periodo, r.ID_CLIENTE, v_bono, v_motivo, SYSDATE);
                END IF;

                v_cnt := v_cnt + 1;
                IF MOD(v_cnt, 500) = 0 THEN
                    COMMIT;
                END IF;
            END IF;
        END LOOP;

        COMMIT;
        DWH_CORE.PKG_LOG.P_FIN('PKG_BONOS.P_RECALCULA_BONOS', p_periodo, v_cnt);
    EXCEPTION
        WHEN OTHERS THEN
            ROLLBACK;
            DWH_CORE.PKG_LOG.P_ERROR('PKG_BONOS.P_RECALCULA_BONOS', p_periodo, SQLERRM);
            RAISE;
    END P_RECALCULA_BONOS;

END PKG_BONOS;
/
