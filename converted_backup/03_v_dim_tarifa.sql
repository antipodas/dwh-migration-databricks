-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_CORE.V_DIM_TARIFA
-- =====================================================================
-- V_DIM_TARIFA: dimension de tarifas con atributos derivados para BI
-- =====================================================================

-- Se aplican nombres de tres partes de Unity Catalog e identificadores en minusculas.
-- TO_CHAR numerico con NLS se sustituye por formato fijo, intercambio de separadores y sufijo monetario.
-- TRUNC(SYSDATE, 'MM') y ADD_MONTHS se sustituyen por DATE_TRUNC y TIMESTAMPADD.
CREATE OR REPLACE VIEW migracion_dwh.dwh_core.v_dim_tarifa AS
SELECT
    t.cod_tarifa,
    initcap(t.desc_tarifa) AS desc_tarifa,
    t.familia,
    decode(
        t.familia,
        'Fusion', 'CONVERGENTE',
        'Pack', 'CONVERGENTE',
        'Empresas', 'B2B',
        'SOLO_MOVIL'
    ) AS tipo_oferta,
    t.cuota_mensual,
    nvl(t.gb_incluidos, 0) AS gb_incluidos,
    nvl(t.min_incluidos, 0) AS min_incluidos,
    CASE
        WHEN t.gb_incluidos IS NULL OR t.gb_incluidos >= 999 THEN 'ILIMITADA'
        WHEN t.gb_incluidos >= 50 THEN 'ALTA'
        WHEN t.gb_incluidos >= 10 THEN 'MEDIA'
        ELSE 'BASICA'
    END AS gama_datos,
    round(t.cuota_mensual / nullif(nvl(t.gb_incluidos, 0), 0), 2) AS eur_por_gb,
    concat(translate(format_number(t.cuota_mensual, 2), ',.', '.,'), '€') AS cuota_texto
FROM migracion_dwh.dwh_stg.stg_tarifas AS t
WHERE t.fecha_fin_comercial IS NULL
   OR t.fecha_fin_comercial > timestampadd(MONTH, -24, date_trunc('MONTH', current_timestamp()));
