/* Vista de cliente vigente: ultima version de cada cliente en el historico.
   Usada por todos los procesos de marketing. */
REPLACE VIEW EDW_MKT.V_CLIENTE_VIGENTE AS
LOCKING ROW FOR ACCESS
SEL
    H.ID_CLIENTE,
    TRIM(BOTH FROM H.NIF)                                  AS NIF,
    TRIM(H.NOMBRE)                                         AS NOMBRE,
    H.COD_SEGMENTO                                         AS SEGMENTO,
    CASE WHEN INDEX(H.NIF, 'B') = 1 THEN 'CIF' ELSE 'NIF' END AS TIPO_DOC,
    COALESCE(H.PROVINCIA, 'DESCONOCIDA')                   AS PROVINCIA,
    H.FECHA_ALTA,
    CAST(MONTHS_BETWEEN(DATE '2026-10-31', H.FECHA_ALTA) AS INTEGER) AS ANTIGUEDAD_MESES,
    (H.FECHA_ALTA (FORMAT 'YYYY')) (CHAR(4))               AS ANYO_ALTA,
    H.FECHA_CARGA
FROM EDW_STG.CLIENTE_HIST H
QUALIFY ROW_NUMBER() OVER (PARTITION BY H.ID_CLIENTE ORDER BY H.FECHA_CARGA DESC) = 1;
