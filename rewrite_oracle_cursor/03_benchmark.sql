-- Benchmark en vivo: misma regla de negocio, dos formas de migrarla.
TRUNCATE TABLE migracion_dwh.dwh_core.bono_fidelizacion_literal;
TRUNCATE TABLE migracion_dwh.dwh_core.bono_fidelizacion;
CALL migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos_literal('202609', 50);
CALL migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos('202609');
-- Mismo resultado en los clientes que recorrio el cursor
SELECT COUNT(*) AS filas_literal,
       COUNT_IF(b.bono_eur = l.bono_eur AND b.motivo = l.motivo) AS coinciden_con_set_based
FROM migracion_dwh.dwh_core.bono_fidelizacion_literal l
LEFT JOIN migracion_dwh.dwh_core.bono_fidelizacion b ON b.periodo = l.periodo AND b.id_cliente = l.id_cliente;
SELECT motivo, COUNT(*) AS clientes, SUM(bono_eur) AS eur FROM migracion_dwh.dwh_core.bono_fidelizacion GROUP BY motivo ORDER BY clientes DESC;
