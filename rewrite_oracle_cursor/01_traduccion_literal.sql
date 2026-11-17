-- (A) TRADUCCION LITERAL: lo que sale si se "traduce" el cursor tal cual (FOR ... DO fila a fila).
-- Compila y da el resultado correcto... pero cada iteracion lanza 3 SELECT + 1 MERGE contra Delta.
-- p_max_clientes solo existe para poder medirlo en la demo sin esperar horas.
CREATE OR REPLACE PROCEDURE migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos_literal(IN p_periodo STRING, IN p_max_clientes INT)
LANGUAGE SQL
SQL SECURITY INVOKER
AS BEGIN
  DECLARE v_fin_mes DATE DEFAULT last_day(to_date(p_periodo || '01', 'yyyyMMdd'));
  DECLARE v_meses INT; DECLARE v_fact DECIMAL(12,2); DECLARE v_inc INT; DECLARE v_porta INT;
  DECLARE v_bono DECIMAL(8,2); DECLARE v_motivo STRING;
  FOR r AS (SELECT id_cliente, fecha_alta FROM migracion_dwh.dwh_core.dim_cliente
            WHERE es_actual = 'S' AND segmento IN ('RESIDENCIAL', 'PYME')
            ORDER BY id_cliente LIMIT p_max_clientes) DO
    SET v_meses = CAST(floor(months_between(v_fin_mes, r.fecha_alta)) AS INT);
    SET v_fact = (SELECT coalesce(SUM(importe_total), 0) FROM migracion_dwh.dwh_stg.stg_facturas
                  WHERE id_cliente = r.id_cliente AND periodo = p_periodo);
    SET v_inc = (SELECT COUNT(*) FROM migracion_dwh.dwh_stg.stg_incidencias
                 WHERE id_cliente = r.id_cliente AND fecha_apertura >= date_sub(v_fin_mes, 90));
    SET v_porta = (SELECT COUNT(*) FROM migracion_dwh.dwh_stg.stg_portabilidades p
                   JOIN migracion_dwh.dwh_stg.stg_lineas l ON p.id_linea = l.id_linea
                   WHERE l.id_cliente = r.id_cliente AND p.estado = 'SOLICITADA');
    IF v_porta > 0 THEN SET v_bono = 20; SET v_motivo = 'RETENCION_PORTABILIDAD';
    ELSEIF v_meses >= 60 AND v_inc >= 3 THEN SET v_bono = least(round(v_fact * 0.10, 2), 15); SET v_motivo = 'COMPENSACION_INCIDENCIAS';
    ELSEIF v_meses >= 120 THEN SET v_bono = 5; SET v_motivo = 'FIDELIDAD_10_ANOS';
    ELSE SET v_bono = 0;
    END IF;
    IF v_bono > 0 THEN
      MERGE INTO migracion_dwh.dwh_core.bono_fidelizacion_literal t
      USING (SELECT p_periodo AS periodo, r.id_cliente AS id_cliente) s
        ON t.periodo = s.periodo AND t.id_cliente = s.id_cliente
      WHEN MATCHED THEN UPDATE SET bono_eur = v_bono, motivo = v_motivo, fecha_calculo = current_timestamp()
      WHEN NOT MATCHED THEN INSERT (periodo, id_cliente, bono_eur, motivo, fecha_calculo)
        VALUES (p_periodo, r.id_cliente, v_bono, v_motivo, current_timestamp());
    END IF;
  END FOR;
END;
