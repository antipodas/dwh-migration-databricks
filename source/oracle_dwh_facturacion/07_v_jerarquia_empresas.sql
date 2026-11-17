-- =====================================================================
-- V_JERARQUIA_EMPRESAS: arbol de cuentas Empresas
-- (grupo empresarial -> filiales -> sedes) a partir de ID_CLIENTE_PADRE
-- =====================================================================

CREATE OR REPLACE VIEW DWH_MART.V_JERARQUIA_EMPRESAS AS
SELECT
    CONNECT_BY_ROOT dc.ID_CLIENTE                      AS ID_GRUPO,
    CONNECT_BY_ROOT dc.NOMBRE                          AS NOMBRE_GRUPO,
    dc.ID_CLIENTE,
    dc.NOMBRE,
    dc.ID_CLIENTE_PADRE,
    LEVEL                                              AS NIVEL,
    LPAD(' ', 2 * (LEVEL - 1)) || dc.NOMBRE            AS NOMBRE_INDENTADO,
    SYS_CONNECT_BY_PATH(dc.ID_CLIENTE, '/')            AS RUTA,
    CONNECT_BY_ISLEAF                                  AS ES_HOJA,
    dc.SEGMENTO,
    dc.PROVINCIA
FROM DWH_CORE.DIM_CLIENTE dc
WHERE dc.ES_ACTUAL = 'S'
START WITH dc.ID_CLIENTE_PADRE IS NULL
       AND dc.SEGMENTO = 'EMPRESA'
       AND dc.ES_ACTUAL = 'S'
CONNECT BY NOCYCLE PRIOR dc.ID_CLIENTE = dc.ID_CLIENTE_PADRE
       AND dc.ES_ACTUAL = 'S'
ORDER SIBLINGS BY dc.NOMBRE;
