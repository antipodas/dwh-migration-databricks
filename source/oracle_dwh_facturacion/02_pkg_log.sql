-- =====================================================================
-- PKG_LOG: trazabilidad de procesos del DWH
-- Usa transaccion autonoma para que el log persista aunque el proceso
-- llamante haga ROLLBACK.
-- =====================================================================

CREATE OR REPLACE PACKAGE DWH_CORE.PKG_LOG AS
    PROCEDURE P_INICIO (p_proceso IN VARCHAR2, p_paso IN VARCHAR2);
    PROCEDURE P_FIN    (p_proceso IN VARCHAR2, p_paso IN VARCHAR2, p_filas IN NUMBER);
    PROCEDURE P_ERROR  (p_proceso IN VARCHAR2, p_paso IN VARCHAR2, p_mensaje IN VARCHAR2);
END PKG_LOG;
/

CREATE OR REPLACE PACKAGE BODY DWH_CORE.PKG_LOG AS

    PROCEDURE P_ESCRIBE (p_proceso IN VARCHAR2, p_paso IN VARCHAR2,
                         p_estado IN VARCHAR2, p_filas IN NUMBER, p_mensaje IN VARCHAR2) IS
        PRAGMA AUTONOMOUS_TRANSACTION;
    BEGIN
        INSERT INTO DWH_CORE.LOG_PROCESOS (PROCESO, PASO, ESTADO, FILAS_AFECTADAS, MENSAJE, FECHA_HORA)
        VALUES (p_proceso, p_paso, p_estado, p_filas, SUBSTR(p_mensaje, 1, 4000), SYSTIMESTAMP);
        COMMIT;
    END P_ESCRIBE;

    PROCEDURE P_INICIO (p_proceso IN VARCHAR2, p_paso IN VARCHAR2) IS
    BEGIN
        P_ESCRIBE(p_proceso, p_paso, 'INICIO', NULL, NULL);
    END P_INICIO;

    PROCEDURE P_FIN (p_proceso IN VARCHAR2, p_paso IN VARCHAR2, p_filas IN NUMBER) IS
    BEGIN
        P_ESCRIBE(p_proceso, p_paso, 'OK', p_filas, NULL);
    END P_FIN;

    PROCEDURE P_ERROR (p_proceso IN VARCHAR2, p_paso IN VARCHAR2, p_mensaje IN VARCHAR2) IS
    BEGIN
        P_ESCRIBE(p_proceso, p_paso, 'ERROR', NULL, p_mensaje || ' | ' || DBMS_UTILITY.FORMAT_ERROR_BACKTRACE);
    END P_ERROR;

END PKG_LOG;
/
