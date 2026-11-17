-- MACRO -> PROCEDURE (LANGUAGE SQL). :P_PERIODO -> parametro. ZEROIFNULL -> coalesce(,0).
-- CAST(... AS DATE FORMAT 'YYYYMMDD') -> to_date(, 'yyyyMMdd'). ADD_MONTHS(x,1) - 1 -> date_sub(add_months(x,1),1).
CREATE OR REPLACE PROCEDURE migracion_dwh.edw_mkt.m_carga_uso_mensual(IN p_periodo STRING)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
  DECLARE v_ini DATE DEFAULT to_date(p_periodo || '01', 'yyyyMMdd');

  DELETE FROM migracion_dwh.edw_mkt.uso_mensual WHERE periodo = p_periodo;

  INSERT INTO migracion_dwh.edw_mkt.uso_mensual
    (periodo, periodo_dt, id_cliente, segmento, dias_con_uso, gb_datos, min_voz, num_sms, importe_extra, flag_heavy_user)
  SELECT
    p_periodo,
    v_ini,
    u.id_cliente,
    c.segmento,
    COUNT(DISTINCT u.fecha_uso),
    coalesce(SUM(u.mb_datos), 0) / 1024,
    coalesce(SUM(u.min_voz), 0),
    coalesce(SUM(u.num_sms), 0),
    CAST(coalesce(SUM(u.importe_extra), 0) AS DECIMAL(12,2)),
    CASE WHEN SUM(u.mb_datos) / 1024 > 20 THEN 1 ELSE 0 END
  FROM migracion_dwh.edw_stg.uso_diario u
  JOIN migracion_dwh.edw_mkt.v_cliente_vigente c ON c.id_cliente = u.id_cliente
  WHERE u.fecha_uso BETWEEN v_ini AND date_sub(add_months(v_ini, 1), 1)
  GROUP BY ALL;

  INSERT INTO migracion_dwh.edw_mkt.log_carga (proceso, periodo, estado, filas, mensaje)
  SELECT 'M_CARGA_USO_MENSUAL', p_periodo, 'OK', COUNT(*), 'Carga mensual de uso'
  FROM migracion_dwh.edw_mkt.uso_mensual WHERE periodo = p_periodo;
END;
