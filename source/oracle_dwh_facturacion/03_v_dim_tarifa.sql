-- =====================================================================
-- V_DIM_TARIFA: dimension de tarifas con atributos derivados para BI
-- =====================================================================

CREATE OR REPLACE VIEW DWH_CORE.V_DIM_TARIFA AS
SELECT
    t.COD_TARIFA,
    INITCAP(t.DESC_TARIFA)                                       AS DESC_TARIFA,
    t.FAMILIA,
    DECODE(t.FAMILIA, 'Fusion',     'CONVERGENTE',
                      'Pack', 'CONVERGENTE',
                      'Empresas',   'B2B',
                                    'SOLO_MOVIL')                AS TIPO_OFERTA,
    t.CUOTA_MENSUAL,
    NVL(t.GB_INCLUIDOS, 0)                                       AS GB_INCLUIDOS,
    NVL(t.MIN_INCLUIDOS, 0)                                      AS MIN_INCLUIDOS,
    CASE
        WHEN t.GB_INCLUIDOS IS NULL OR t.GB_INCLUIDOS >= 999 THEN 'ILIMITADA'
        WHEN t.GB_INCLUIDOS >= 50                            THEN 'ALTA'
        WHEN t.GB_INCLUIDOS >= 10                            THEN 'MEDIA'
        ELSE                                                      'BASICA'
    END                                                          AS GAMA_DATOS,
    ROUND(t.CUOTA_MENSUAL / NULLIF(NVL(t.GB_INCLUIDOS, 0), 0), 2) AS EUR_POR_GB,
    TO_CHAR(t.CUOTA_MENSUAL, 'FM9G990D00L', 'NLS_NUMERIC_CHARACTERS='',.'' NLS_CURRENCY=''€''') AS CUOTA_TEXTO
FROM DWH_STG.STG_TARIFAS t
WHERE t.FECHA_FIN_COMERCIAL IS NULL
   OR t.FECHA_FIN_COMERCIAL > ADD_MONTHS(TRUNC(SYSDATE, 'MM'), -24);
