-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_CORE.SP_CARGA_DIM_CLIENTE
-- =====================================================================
-- SP_CARGA_DIM_CLIENTE: carga SCD tipo 2 de la dimension cliente
-- Detecta cambios en segmento / provincia / nombre / cliente padre
-- comparando un hash de atributos contra la version vigente.
-- =====================================================================

-- TODO: manual review required — BEGIN ATOMIC y el wrapper conservan el COMMIT/ROLLBACK final; confirmar que ningun invocador dependa de controlar externamente esa transaccion.
-- Procedimiento auxiliar atomico para que la carga y sus registros de exito se confirmen o reviertan como una unidad.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.sp_carga_dim_cliente_worker()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN ATOMIC
    -- Declaraciones Oracle trasladadas al inicio del bloque SQL.
    DECLARE c_proceso STRING DEFAULT 'SP_CARGA_DIM_CLIENTE';
    DECLARE v_cerrados BIGINT DEFAULT 0;
    DECLARE v_nuevos BIGINT DEFAULT 0;
    -- TRUNC(SYSDATE) se convierte a la fecha de sesion actual.
    DECLARE v_hoy DATE DEFAULT current_date();

    -- La llamada PKG_LOG.P_INICIO se sustituye por el registro equivalente en Delta.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'CIERRE_VERSIONES', 'INICIO', NULL, NULL, current_timestamp());

    -- 1) Cerrar versiones vigentes cuyos atributos han cambiado
    -- Se cualifican objetos en Unity Catalog, se normalizan cadenas vacias y SHA256 se expresa con sha2.
    -- El WHERE del UPDATE Oracle se traslada a la condicion WHEN MATCHED de MERGE.
    MERGE INTO migracion_dwh.dwh_core.dim_cliente AS d
    USING (
        SELECT
            s.id_cliente,
            upper(sha2(concat_ws('',
                nvl(nullif(s.nombre, ''), '#'), '|',
                nvl(nullif(s.segmento, ''), '#'), '|',
                nvl(nullif(s.provincia, ''), '#'), '|',
                nvl(cast(s.id_cliente_padre AS STRING), '#')
            ), 256)) AS hash_nuevo
        FROM migracion_dwh.dwh_stg.stg_clientes AS s
    ) AS src
    ON d.id_cliente = src.id_cliente AND d.es_actual = 'S'
    WHEN MATCHED AND d.hash_atributos <> src.hash_nuevo THEN
        UPDATE SET
            d.fecha_fin_vigencia = v_hoy - INTERVAL 1 DAY,
            d.es_actual = 'N';

    -- SQL%ROWCOUNT se sustituye por diagnosticos capturados inmediatamente despues del MERGE.
    GET DIAGNOSTICS v_cerrados = ROW_COUNT;

    -- La llamada PKG_LOG.P_FIN se sustituye por el registro equivalente en Delta.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'CIERRE_VERSIONES', 'FIN', v_cerrados, NULL, current_timestamp());

    -- 2) Insertar nuevas versiones (clientes nuevos o modificados)
    -- La llamada PKG_LOG.P_INICIO se sustituye por el registro equivalente en Delta.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'ALTA_VERSIONES', 'INICIO', NULL, NULL, current_timestamp());

    -- La clave sk_cliente respaldada por secuencia se omite para que la genere la columna IDENTITY de destino.
    -- Se convierten nombres, fecha literal, concatenacion con nulos y hash SHA256 a equivalentes Databricks.
    INSERT INTO migracion_dwh.dwh_core.dim_cliente
        (id_cliente, nif, nombre, segmento, provincia, id_cliente_padre,
         fecha_alta, fecha_inicio_vigencia, fecha_fin_vigencia, es_actual, hash_atributos)
    SELECT
        s.id_cliente,
        upper(trim(s.nif)),
        s.nombre,
        decode(s.segmento, 'RES', 'RESIDENCIAL', 'PYM', 'PYME', 'EMP', 'EMPRESA', s.segmento),
        nvl(nullif(s.provincia, ''), 'DESCONOCIDA'),
        s.id_cliente_padre,
        s.fecha_alta,
        v_hoy,
        to_date('31/12/9999', 'dd/MM/yyyy'),
        'S',
        upper(sha2(concat_ws('',
            nvl(nullif(s.nombre, ''), '#'), '|',
            nvl(nullif(s.segmento, ''), '#'), '|',
            nvl(nullif(s.provincia, ''), '#'), '|',
            nvl(cast(s.id_cliente_padre AS STRING), '#')
        ), 256))
    FROM migracion_dwh.dwh_stg.stg_clientes AS s
    WHERE NOT EXISTS (
        SELECT 1
        FROM migracion_dwh.dwh_core.dim_cliente AS d
        WHERE d.id_cliente = s.id_cliente
          AND d.es_actual = 'S'
    );

    -- SQL%ROWCOUNT se sustituye por diagnosticos capturados inmediatamente despues del INSERT.
    GET DIAGNOSTICS v_nuevos = ROW_COUNT;

    -- La llamada PKG_LOG.P_FIN se sustituye por el registro equivalente en Delta.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, 'ALTA_VERSIONES', 'FIN', v_nuevos, NULL, current_timestamp());

    -- COMMIT se elimina porque BEGIN ATOMIC confirma automaticamente la unidad completa.
    -- DBMS_OUTPUT.PUT_LINE se elimina; los resultados quedan persistidos en log_procesos.
END;

-- Wrapper con el nombre publico original; el handler reemplaza EXCEPTION WHEN OTHERS, ROLLBACK, SQLERRM y RAISE.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.sp_carga_dim_cliente()
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    -- Variable de diagnostico declarada antes del handler.
    DECLARE v_error_msg STRING;
    -- El handler registra el error despues del rollback automatico del worker y vuelve a propagarlo.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- SQLERRM se obtiene mediante GET DIAGNOSTICS.
        GET DIAGNOSTICS CONDITION 1 v_error_msg = MESSAGE_TEXT;
        -- La llamada PKG_LOG.P_ERROR se sustituye por el registro equivalente en Delta.
        INSERT INTO migracion_dwh.dwh_core.log_procesos
            (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
        VALUES
            ('SP_CARGA_DIM_CLIENTE', 'GENERAL', 'ERROR', NULL, v_error_msg, current_timestamp());
        -- RAISE se convierte en RESIGNAL para conservar la excepcion original.
        RESIGNAL;
    END;

    -- El procedimiento publico delega la unidad transaccional en el worker atomico.
    CALL migracion_dwh.dwh_core.sp_carga_dim_cliente_worker();
END;
