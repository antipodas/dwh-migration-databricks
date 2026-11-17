-- (B) REESCRITURA SET-BASED: la misma regla de negocio expresada como conjuntos. Un unico MERGE.
-- Esto es lo que hay que pedir (en la skill y en la revision) para cualquier cursor fila a fila.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos(IN p_periodo STRING)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
  DECLARE v_fin_mes DATE DEFAULT last_day(to_date(p_periodo || '01', 'yyyyMMdd'));
  MERGE INTO migracion_dwh.dwh_core.bono_fidelizacion t
  USING (
    WITH cli AS (
      SELECT id_cliente, CAST(floor(months_between(v_fin_mes, fecha_alta)) AS INT) AS meses
      FROM migracion_dwh.dwh_core.dim_cliente
      WHERE es_actual = 'S' AND segmento IN ('RESIDENCIAL', 'PYME')),
    fac AS (SELECT id_cliente, SUM(importe_total) AS fact FROM migracion_dwh.dwh_stg.stg_facturas
            WHERE periodo = p_periodo GROUP BY id_cliente),
    inc AS (SELECT id_cliente, COUNT(*) AS n FROM migracion_dwh.dwh_stg.stg_incidencias
            WHERE fecha_apertura >= date_sub(v_fin_mes, 90) GROUP BY id_cliente),
    por AS (SELECT DISTINCT l.id_cliente FROM migracion_dwh.dwh_stg.stg_portabilidades p
            JOIN migracion_dwh.dwh_stg.stg_lineas l ON p.id_linea = l.id_linea WHERE p.estado = 'SOLICITADA'),
    reglas AS (
      SELECT c.id_cliente,
             CASE WHEN por.id_cliente IS NOT NULL THEN 20
                  WHEN c.meses >= 60 AND coalesce(inc.n, 0) >= 3 THEN least(round(coalesce(fac.fact, 0) * 0.10, 2), 15)
                  WHEN c.meses >= 120 THEN 5 ELSE 0 END AS bono_eur,
             CASE WHEN por.id_cliente IS NOT NULL THEN 'RETENCION_PORTABILIDAD'
                  WHEN c.meses >= 60 AND coalesce(inc.n, 0) >= 3 THEN 'COMPENSACION_INCIDENCIAS'
                  WHEN c.meses >= 120 THEN 'FIDELIDAD_10_ANOS' END AS motivo
      FROM cli c LEFT JOIN fac ON fac.id_cliente = c.id_cliente
      LEFT JOIN inc ON inc.id_cliente = c.id_cliente
      LEFT JOIN por ON por.id_cliente = c.id_cliente)
    SELECT p_periodo AS periodo, id_cliente, bono_eur, motivo FROM reglas WHERE bono_eur > 0
  ) s
  ON t.periodo = s.periodo AND t.id_cliente = s.id_cliente
  WHEN MATCHED THEN UPDATE SET bono_eur = s.bono_eur, motivo = s.motivo, fecha_calculo = current_timestamp()
  WHEN NOT MATCHED THEN INSERT (periodo, id_cliente, bono_eur, motivo, fecha_calculo)
    VALUES (s.periodo, s.id_cliente, s.bono_eur, s.motivo, current_timestamp());
END;
