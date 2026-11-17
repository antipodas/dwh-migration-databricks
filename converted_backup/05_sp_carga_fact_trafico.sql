-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_CORE.SP_CARGA_FACT_TRAFICO
-- =====================================================================
-- SP_CARGA_FACT_TRAFICO: agrega los CDR del dia a nivel linea
-- Reprocesable: borra la particion del dia antes de insertar.
-- =====================================================================

-- El trabajo transaccional se aisla en un procedimiento atomico para conservar el rollback del borrado y la insercion.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.sp_carga_fact_trafico_worker(
    IN p_fecha DATE,
    OUT p_filas DECIMAL(38, 0)
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN ATOMIC
    -- El objeto se cualifica en Unity Catalog y conserva el borrado reprocesable.
    DELETE FROM migracion_dwh.dwh_core.fact_trafico_diario
    WHERE fecha = p_fecha;

    -- Se eliminan los hints APPEND/PARALLEL, se convierte el outer join a LEFT JOIN ANSI y se normalizan las expresiones condicionales y nulas.
    INSERT INTO migracion_dwh.dwh_core.fact_trafico_diario
        (fecha, id_linea, id_cliente, cod_tarifa, minutos_voz, mb_datos, num_sms,
         minutos_roaming, importe_fuera_bono, pct_consumo_bono_datos, fecha_carga)
    SELECT p_fecha,
           l.id_linea,
           l.id_cliente,
           l.cod_tarifa,
           round(sum(CASE WHEN c.tipo_evento = 'VOZ' THEN c.duracion_seg ELSE 0 END) / 60, 2),
           round(sum(CASE WHEN c.tipo_evento = 'DATOS' THEN c.mb_consumidos ELSE 0 END), 3),
           sum(CASE WHEN c.tipo_evento = 'SMS' THEN 1 ELSE 0 END),
           round(sum(CASE WHEN c.tipo_evento = 'ROAMING' OR c.pais_destino <> 'ESP'
                          THEN coalesce(c.duracion_seg, 0) ELSE 0 END) / 60, 2),
           coalesce(sum(c.importe), 0),
           -- % del bono mensual de datos consumido en el dia (GB -> MB)
           CASE WHEN t.gb_incluidos IS NOT NULL THEN
                round(100 * sum(CASE WHEN c.tipo_evento = 'DATOS' THEN c.mb_consumidos ELSE 0 END) / (t.gb_incluidos * 1024), 2)
           ELSE NULL END,
           current_timestamp()
    FROM migracion_dwh.dwh_stg.stg_cdr AS c
    INNER JOIN migracion_dwh.dwh_stg.stg_lineas AS l
        ON c.id_linea = l.id_linea
    LEFT JOIN migracion_dwh.dwh_stg.stg_tarifas AS t
        ON l.cod_tarifa = t.cod_tarifa
    WHERE c.fecha_hora_inicio >= p_fecha
      AND c.fecha_hora_inicio < p_fecha + INTERVAL 1 DAY
      AND l.estado IN ('A', 'S')
    GROUP BY l.id_linea, l.id_cliente, l.cod_tarifa, t.gb_incluidos;

    -- SQL%ROWCOUNT se convierte en GET DIAGNOSTICS inmediatamente despues del INSERT.
    GET DIAGNOSTICS p_filas = ROW_COUNT;
END;

-- Se normaliza el procedimiento publico a Unity Catalog, SQL procedural y seguridad de invocador.
-- TODO: manual review required — Oracle DATE includes time; p_fecha is mapped to DATE because it represents a processing day; verify callers do not pass a meaningful time component.
-- TODO: manual review required — the source transaction is implemented with an atomic worker and a non-atomic logging wrapper; verify callers accept this procedure boundary split.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.sp_carga_fact_trafico(
    IN p_fecha DATE DEFAULT date_sub(current_date(), 1)
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    -- Las declaraciones Oracle se trasladan al inicio del bloque SQL.
    DECLARE c_proceso STRING DEFAULT 'SP_CARGA_FACT_TRAFICO';
    DECLARE v_fecha DATE DEFAULT p_fecha;
    DECLARE v_filas DECIMAL(38, 0);
    DECLARE v_error_message STRING;

    -- NO_DATA_FOUND se convierte en un manejador NOT FOUND.
    DECLARE EXIT HANDLER FOR NOT FOUND
    BEGIN
        -- La llamada de fin se sustituye por el registro corporativo de procesos.
        INSERT INTO migracion_dwh.dwh_core.log_procesos
            (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
        VALUES
            (c_proceso, date_format(v_fecha, 'yyyyMMdd'), 'FIN', 0, NULL, current_timestamp());
    END;

    -- WHEN OTHERS se convierte en un manejador SQLEXCEPTION con diagnostico y relanzamiento.
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- SQLERRM se obtiene mediante GET DIAGNOSTICS.
        GET DIAGNOSTICS CONDITION 1 v_error_message = MESSAGE_TEXT;
        -- La llamada de error se sustituye por el registro corporativo de procesos.
        INSERT INTO migracion_dwh.dwh_core.log_procesos
            (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
        VALUES
            (c_proceso, date_format(v_fecha, 'yyyyMMdd'), 'ERROR', NULL, v_error_message, current_timestamp());
        -- RAISE se convierte en RESIGNAL.
        RESIGNAL;
    END;

    -- La llamada de inicio se sustituye por el registro corporativo de procesos.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, date_format(v_fecha, 'yyyyMMdd'), 'INICIO', NULL, NULL, current_timestamp());

    -- El worker atomico conserva la unidad transaccional del DELETE y el INSERT.
    CALL migracion_dwh.dwh_core.sp_carga_fact_trafico_worker(v_fecha, v_filas);

    -- La llamada de fin se sustituye por el registro corporativo de procesos.
    INSERT INTO migracion_dwh.dwh_core.log_procesos
        (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora)
    VALUES
        (c_proceso, date_format(v_fecha, 'yyyyMMdd'), 'FIN', v_filas, NULL, current_timestamp());
END;
