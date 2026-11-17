-- QUANTILE(10, x) (legacy Teradata, 0..9 ascendente) -> ntile(10) OVER (ORDER BY x) - 1.
-- ACTIVITY_COUNT -> num_inserted_rows de la sentencia (GET DIAGNOSTICS). EXIT HANDLER se soporta.
CREATE OR REPLACE PROCEDURE migracion_dwh.edw_mkt.sp_segmentacion_valor(IN p_periodo STRING)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
  DECLARE v_filas INT DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    INSERT INTO migracion_dwh.edw_mkt.log_carga (proceso, periodo, estado, filas, mensaje)
    VALUES ('SP_SEGMENTACION_VALOR', p_periodo, 'ERROR', 0, 'Error en la segmentacion');
  END;

  DELETE FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = p_periodo;

  INSERT INTO migracion_dwh.edw_mkt.segmento_valor
  WITH f AS (
    SELECT id_cliente, SUM(importe_total) AS facturacion
    FROM migracion_dwh.edw_stg.factura
    WHERE periodo = p_periodo
    GROUP BY id_cliente
  ),
  q AS (
    SELECT c.id_cliente, c.segmento, c.provincia, f.facturacion,
           ntile(10) OVER (ORDER BY f.facturacion) - 1 AS quantile_10
    FROM migracion_dwh.edw_mkt.v_cliente_vigente c
    JOIN f ON f.id_cliente = c.id_cliente
  )
  SELECT p_periodo, id_cliente, segmento, provincia, facturacion,
         quantile_10 + 1,
         CASE WHEN quantile_10 >= 8 THEN 'ALTO' WHEN quantile_10 >= 4 THEN 'MEDIO' ELSE 'BAJO' END
  FROM q;

  SET v_filas = (SELECT COUNT(*) FROM migracion_dwh.edw_mkt.segmento_valor WHERE periodo = p_periodo);

  INSERT INTO migracion_dwh.edw_mkt.log_carga (proceso, periodo, estado, filas, mensaje)
  VALUES ('SP_SEGMENTACION_VALOR', p_periodo, 'OK', v_filas, 'Deciles de valor');
END;
