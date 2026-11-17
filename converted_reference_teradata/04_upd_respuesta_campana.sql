-- VOLATILE TABLE -> subconsulta en el USING (o TEMPORARY VIEW si se ejecuta en una misma sesion).
-- UPDATE ... FROM + INSERT ... NOT EXISTS -> un unico MERGE (atomico).
-- NULLIFZERO -> nullif(,0). COLLECT STATISTICS / DROP volatil -> eliminados.
MERGE INTO migracion_dwh.edw_mkt.respuesta_campana r
USING (
  SELECT k.id_campana,
         k.id_cliente,
         k.canal,
         k.fecha_contacto,
         coalesce(k.respuesta, '?')   AS ind_respuesta,
         nullif(k.importe_venta, 0)   AS importe_venta
  FROM migracion_dwh.edw_stg.contacto_campana k
  JOIN migracion_dwh.edw_stg.campana c ON c.id_campana = k.id_campana
  WHERE k.fecha_contacto <= DATE'2026-10-31'
) v
  ON r.id_campana = v.id_campana AND r.id_cliente = v.id_cliente
WHEN MATCHED AND (r.ind_respuesta <> v.ind_respuesta OR r.ind_respuesta IS NULL) THEN UPDATE SET
  ind_respuesta = v.ind_respuesta,
  importe_venta = v.importe_venta,
  fecha_actualizacion = DATE'2026-10-31'
WHEN NOT MATCHED THEN INSERT
  (id_campana, id_cliente, canal, fecha_contacto, ind_respuesta, importe_venta, fecha_actualizacion)
  VALUES (v.id_campana, v.id_cliente, v.canal, v.fecha_contacto, v.ind_respuesta, v.importe_venta, DATE'2026-10-31');
