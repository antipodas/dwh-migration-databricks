-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_CORE.PKG_LOG
-- =====================================================================
-- PKG_LOG: trazabilidad de procesos del DWH
-- Usa transaccion autonoma para que el log persista aunque el proceso
-- llamante haga ROLLBACK.
-- =====================================================================
-- TODO: manual review required — el paquete se aplana en procedimientos independientes; actualizar los llamadores para usar los nombres con prefijo pkg_log_.
-- El miembro privado del paquete se aplana como procedimiento independiente con sufijo internal.
-- Los modos de parametros, tipos e identificadores se convierten a Databricks SQL y Unity Catalog.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_log_p_escribe_internal(
    IN p_proceso STRING,
    IN p_paso STRING,
    IN p_estado STRING,
    IN p_filas DECIMAL(38, 0),
    IN p_mensaje STRING
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    -- TODO: manual review required — se eliminaron PRAGMA AUTONOMOUS_TRANSACTION y COMMIT; confirmar que el log de auditoria deba persistir independientemente del rollback del llamador o redisenar la persistencia.
    -- assumption: no se requiere conservar el desplazamiento de zona horaria por valor de SYSTIMESTAMP.
    -- SUBSTR se protege con NULLIF para mantener la semantica Oracle de cadena vacia igual a NULL.
    INSERT INTO migracion_dwh.dwh_core.log_procesos (
        proceso,
        paso,
        estado,
        filas_afectadas,
        mensaje,
        fecha_hora
    )
    VALUES (
        p_proceso,
        p_paso,
        p_estado,
        p_filas,
        NULLIF(SUBSTR(p_mensaje, 1, 4000), ''),
        current_timestamp()
    );
END;

-- Guia de despliegue: sustituir el marcador antes de aplicar ambas sentencias juntas.
-- REVOKE EXECUTE ON PROCEDURE migracion_dwh.dwh_core.pkg_log_p_escribe_internal FROM `account users`;
-- GRANT EXECUTE ON PROCEDURE migracion_dwh.dwh_core.pkg_log_p_escribe_internal TO `<owning service principal>`;

-- El procedimiento publico se aplana y la llamada interna se reescribe con CALL al nombre de Unity Catalog.
-- TODO: manual review required — verificar la llamada requalificada al antiguo miembro privado p_escribe.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_log_p_inicio(
    IN p_proceso STRING,
    IN p_paso STRING
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    CALL migracion_dwh.dwh_core.pkg_log_p_escribe_internal(
        p_proceso,
        p_paso,
        'INICIO',
        NULL,
        NULL
    );
END;

-- El procedimiento publico se aplana; NUMBER se tipa como entero decimal por representar filas afectadas.
-- TODO: manual review required — verificar la llamada requalificada al antiguo miembro privado p_escribe.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_log_p_fin(
    IN p_proceso STRING,
    IN p_paso STRING,
    IN p_filas DECIMAL(38, 0)
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    CALL migracion_dwh.dwh_core.pkg_log_p_escribe_internal(
        p_proceso,
        p_paso,
        'OK',
        p_filas,
        NULL
    );
END;

-- El procedimiento publico se aplana y conserva el mensaje recibido; el backtrace Oracle no tiene equivalente SQL directo.
-- TODO: manual review required — DBMS_UTILITY.FORMAT_ERROR_BACKTRACE no tiene equivalente en DBSQL SQL; capture el diagnostico en el orquestador y anadalo a p_mensaje.
-- TODO: manual review required — verificar la llamada requalificada al antiguo miembro privado p_escribe.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_log_p_error(
    IN p_proceso STRING,
    IN p_paso STRING,
    IN p_mensaje STRING
)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
    CALL migracion_dwh.dwh_core.pkg_log_p_escribe_internal(
        p_proceso,
        p_paso,
        'ERROR',
        NULL,
        p_mensaje
    );
END;
