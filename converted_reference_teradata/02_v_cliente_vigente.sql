-- LOCKING ROW FOR ACCESS -> innecesario (aislamiento por snapshot de Delta).
-- QUALIFY se soporta tal cual. INDEX() -> instr(). (fecha (FORMAT 'YYYY')) (CHAR(4)) -> date_format().
CREATE OR REPLACE VIEW migracion_dwh.edw_mkt.v_cliente_vigente AS
SELECT
  h.id_cliente,
  trim(h.nif)                                              AS nif,
  trim(h.nombre)                                           AS nombre,
  h.cod_segmento                                           AS segmento,
  CASE WHEN instr(h.nif, 'B') = 1 THEN 'CIF' ELSE 'NIF' END AS tipo_doc,
  coalesce(h.provincia, 'DESCONOCIDA')                     AS provincia,
  h.fecha_alta,
  CAST(months_between(DATE'2026-10-31', h.fecha_alta) AS INT) AS antiguedad_meses,
  date_format(h.fecha_alta, 'yyyy')                        AS anyo_alta,
  h.fecha_carga
FROM migracion_dwh.edw_stg.cliente_hist h
QUALIFY row_number() OVER (PARTITION BY h.id_cliente ORDER BY h.fecha_carga DESC) = 1;
