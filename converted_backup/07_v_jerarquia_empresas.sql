-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DWH_MART.V_JERARQUIA_EMPRESAS
-- =====================================================================
-- V_JERARQUIA_EMPRESAS: arbol de cuentas Empresas
-- (grupo empresarial -> filiales -> sedes) a partir de ID_CLIENTE_PADRE
-- =====================================================================

-- TODO: manual review required — CONNECT BY hierarchy translated to WITH RECURSIVE; verify LEVEL, CONNECT_BY_ROOT, SYS_CONNECT_BY_PATH, CONNECT_BY_ISLEAF, NOCYCLE, and ORDER SIBLINGS BY behavior.
-- Oracle CONNECT BY NOCYCLE is replaced by an explicit visited-ID array, and sibling order is represented by a hierarchical sort path.
-- Oracle two-part object names are replaced with Unity Catalog three-part names, and identifiers are normalized to lowercase snake_case.
-- Oracle NULL-swallowing concatenation is replaced with concat_ws/coalesce.
CREATE OR REPLACE VIEW migracion_dwh.dwh_mart.v_jerarquia_empresas AS
WITH RECURSIVE jerarquia AS (
    SELECT
        dc.id_cliente AS id_grupo,
        dc.nombre AS nombre_grupo,
        dc.id_cliente,
        dc.nombre,
        dc.id_cliente_padre,
        1 AS nivel,
        array(dc.id_cliente) AS ids_visitados,
        concat('/', coalesce(cast(dc.id_cliente AS STRING), '')) AS ruta,
        array(named_struct(
            'es_nulo', dc.nombre IS NULL,
            'valor', coalesce(dc.nombre, '')
        )) AS ruta_orden
    FROM migracion_dwh.dwh_core.dim_cliente AS dc
    WHERE dc.id_cliente_padre IS NULL
      AND dc.segmento = 'EMPRESA'
      AND dc.es_actual = 'S'

    UNION ALL

    SELECT
        j.id_grupo,
        j.nombre_grupo,
        dc.id_cliente,
        dc.nombre,
        dc.id_cliente_padre,
        j.nivel + 1 AS nivel,
        concat(j.ids_visitados, array(dc.id_cliente)) AS ids_visitados,
        concat(j.ruta, '/', coalesce(cast(dc.id_cliente AS STRING), '')) AS ruta,
        concat(
            j.ruta_orden,
            array(named_struct(
                'es_nulo', dc.nombre IS NULL,
                'valor', coalesce(dc.nombre, '')
            ))
        ) AS ruta_orden
    FROM migracion_dwh.dwh_core.dim_cliente AS dc
    INNER JOIN jerarquia AS j
        ON j.id_cliente = dc.id_cliente_padre
    WHERE dc.es_actual = 'S'
      AND NOT array_contains(j.ids_visitados, dc.id_cliente)
)
SELECT
    j.id_grupo,
    j.nombre_grupo,
    j.id_cliente,
    j.nombre,
    j.id_cliente_padre,
    j.nivel,
    concat_ws('', lpad(' ', 2 * (j.nivel - 1)), j.nombre) AS nombre_indentado,
    j.ruta,
    CASE
        WHEN EXISTS (
            SELECT 1
            FROM migracion_dwh.dwh_core.dim_cliente AS hija
            WHERE hija.id_cliente_padre = j.id_cliente
              AND hija.es_actual = 'S'
              AND NOT array_contains(j.ids_visitados, hija.id_cliente)
        ) THEN 0
        ELSE 1
    END AS es_hoja,
    dc.segmento,
    dc.provincia
FROM jerarquia AS j
INNER JOIN migracion_dwh.dwh_core.dim_cliente AS dc
    ON dc.id_cliente = j.id_cliente
   AND dc.es_actual = 'S'
ORDER BY j.ruta_orden;
