-- =====================================================================
-- PARADA 3 · ORACLE: TRADUCIR NO ES MIGRAR  (abrir este fichero en el SQL Editor)
--
-- Que es: la MISMA regla de negocio (bonos de fidelizacion) migrada de dos formas.
--   A) pkg_bonos_p_recalcula_bonos_literal -> traduccion literal preparada: el cursor copiado tal cual (bucle fila a fila)
--      codigo: migracion-partners/rewrite_oracle_cursor/01_traduccion_literal.sql
--   B) pkg_bonos_p_recalcula_bonos         -> reescrita en conjuntos (un unico MERGE).
--      Lo ideal: la version que genera Genie Migrate CON la skill migracion-dwh (regla 4.b), desplegada con este nombre.
--      Plan B: mi version, migracion-partners/rewrite_oracle_cursor/02_reescritura_set_based.sql
--   Original Oracle: migracion-partners/source/oracle_cursor_reescritura/11_pkg_bonos_fidelizacion.sql
--
-- Como ejecutarlo: pon el cursor del raton DENTRO de cada sentencia y pulsa Cmd+Shift+Enter
-- (ejecuta solo la sentencia seleccionada). Warehouse: Serverless Starter Warehouse.
-- =====================================================================

-- PASO 1 · Vaciar la tabla de resultados de la version A (1 s)
TRUNCATE TABLE migracion_dwh.dwh_core.bono_fidelizacion_literal;

-- PASO 2 · Version A, bucle fila a fila, SOLO 10 clientes  (~25-35 s)
--          Di mientras corre: "cada vuelta del bucle lanza 3 SELECT y 1 MERGE: unos 2 segundos por cliente"
CALL migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos_literal('202609', 10);

-- PASO 3 · Version B (Genie con skill), en conjuntos, los 4.550 clientes  (~3-6 s)
CALL migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos('202609');

-- PASO 4 · Mismo resultado? (los clientes con bono que recorrio A tienen el mismo bono y motivo en B)
SELECT COUNT(*)                                                   AS clientes_con_bono_en_A,
       COUNT_IF(b.bono_eur = l.bono_eur AND b.motivo = l.motivo)  AS identicos_en_B
FROM migracion_dwh.dwh_core.bono_fidelizacion_literal l
LEFT JOIN migracion_dwh.dwh_core.bono_fidelizacion b USING (periodo, id_cliente);

-- PASO 5 · (opcional) Que ha calculado B para todos los clientes
SELECT motivo, COUNT(*) AS clientes, SUM(bono_eur) AS euros
FROM migracion_dwh.dwh_core.bono_fidelizacion
GROUP BY motivo ORDER BY clientes DESC;

-- Cuentas para decirlas en voz alta:
--   A: ~2,3 s por cliente  -> 4.550 clientes = ~3 horas.     B: 4.550 clientes en ~3-5 segundos.
--   Medido el 13-nov con 50 clientes: A 115 s y 110 s; B 4,6 s y 2,8 s; 25 de 25 identicos.
--   Medido el 14-nov con este fichero: A 32 s (10 clientes); B 5,5 s (4.550); 6 de 6 identicos.
