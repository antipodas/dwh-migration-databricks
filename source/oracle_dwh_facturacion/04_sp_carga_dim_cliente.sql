-- =====================================================================
-- SP_CARGA_DIM_CLIENTE: carga SCD tipo 2 de la dimension cliente
-- Detecta cambios en segmento / provincia / nombre / cliente padre
-- comparando un hash de atributos contra la version vigente.
-- =====================================================================

CREATE OR REPLACE PROCEDURE DWH_CORE.SP_CARGA_DIM_CLIENTE AS
    c_proceso   CONSTANT VARCHAR2(50) := 'SP_CARGA_DIM_CLIENTE';
    v_cerrados  NUMBER := 0;
    v_nuevos    NUMBER := 0;
    v_hoy       DATE   := TRUNC(SYSDATE);
BEGIN
    DWH_CORE.PKG_LOG.P_INICIO(c_proceso, 'CIERRE_VERSIONES');

    -- 1) Cerrar versiones vigentes cuyos atributos han cambiado
    MERGE INTO DWH_CORE.DIM_CLIENTE d
    USING (
        SELECT s.ID_CLIENTE,
               STANDARD_HASH(NVL(s.NOMBRE,'#') || '|' || NVL(s.SEGMENTO,'#') || '|' ||
                             NVL(s.PROVINCIA,'#') || '|' || NVL(TO_CHAR(s.ID_CLIENTE_PADRE),'#'), 'SHA256') AS HASH_NUEVO
        FROM DWH_STG.STG_CLIENTES s
    ) src
    ON (d.ID_CLIENTE = src.ID_CLIENTE AND d.ES_ACTUAL = 'S')
    WHEN MATCHED THEN UPDATE
        SET d.FECHA_FIN_VIGENCIA = v_hoy - 1,
            d.ES_ACTUAL          = 'N'
        WHERE d.HASH_ATRIBUTOS <> RAWTOHEX(src.HASH_NUEVO);

    v_cerrados := SQL%ROWCOUNT;
    DWH_CORE.PKG_LOG.P_FIN(c_proceso, 'CIERRE_VERSIONES', v_cerrados);

    -- 2) Insertar nuevas versiones (clientes nuevos o modificados)
    DWH_CORE.PKG_LOG.P_INICIO(c_proceso, 'ALTA_VERSIONES');

    INSERT INTO DWH_CORE.DIM_CLIENTE
        (SK_CLIENTE, ID_CLIENTE, NIF, NOMBRE, SEGMENTO, PROVINCIA, ID_CLIENTE_PADRE,
         FECHA_ALTA, FECHA_INICIO_VIGENCIA, FECHA_FIN_VIGENCIA, ES_ACTUAL, HASH_ATRIBUTOS)
    SELECT DWH_CORE.SEQ_DIM_CLIENTE.NEXTVAL,
           s.ID_CLIENTE,
           UPPER(TRIM(s.NIF)),
           s.NOMBRE,
           DECODE(s.SEGMENTO, 'RES', 'RESIDENCIAL', 'PYM', 'PYME', 'EMP', 'EMPRESA', s.SEGMENTO),
           NVL(s.PROVINCIA, 'DESCONOCIDA'),
           s.ID_CLIENTE_PADRE,
           s.FECHA_ALTA,
           v_hoy,
           TO_DATE('31/12/9999', 'DD/MM/YYYY'),
           'S',
           RAWTOHEX(STANDARD_HASH(NVL(s.NOMBRE,'#') || '|' || NVL(s.SEGMENTO,'#') || '|' ||
                                  NVL(s.PROVINCIA,'#') || '|' || NVL(TO_CHAR(s.ID_CLIENTE_PADRE),'#'), 'SHA256'))
    FROM DWH_STG.STG_CLIENTES s
    WHERE NOT EXISTS (
        SELECT 1
        FROM DWH_CORE.DIM_CLIENTE d
        WHERE d.ID_CLIENTE = s.ID_CLIENTE
          AND d.ES_ACTUAL  = 'S'
    );

    v_nuevos := SQL%ROWCOUNT;
    DWH_CORE.PKG_LOG.P_FIN(c_proceso, 'ALTA_VERSIONES', v_nuevos);

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('DIM_CLIENTE -> cerradas: ' || v_cerrados || ' / nuevas: ' || v_nuevos);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DWH_CORE.PKG_LOG.P_ERROR(c_proceso, 'GENERAL', SQLERRM);
        RAISE;
END SP_CARGA_DIM_CLIENTE;
/
