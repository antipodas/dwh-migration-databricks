---
name: migracion-oracle
description: "Reglas para convertir a Databricks SQL el DWH de facturacion en Oracle PL/SQL (esquemas DWH_STG, DWH_CORE, DWH_MART) y sus replicas T-SQL (stg.*), con destino el catalogo migracion_dwh de Unity Catalog. Aplicar SOLO cuando el codigo de origen sea Oracle o T-SQL de este DWH, en un Migration Project o con Genie Code. Incluye el patron obligatorio para reescribir cursores fila a fila en conjuntos."
---

# Reglas de migracion: DWH de facturacion (Oracle PL/SQL) -> Databricks SQL

Aplica SIEMPRE estas reglas al convertir codigo Oracle PL/SQL (o T-SQL) del DWH de facturacion.
Para codigo Teradata usa la skill `migracion-teradata`, no esta.

## 1. Nombres y Unity Catalog
- Usa siempre nombres de tres partes en el catalogo `migracion_dwh`:
  - `DWH_STG.<tabla>`  -> `migracion_dwh.dwh_stg.<tabla>`
  - `DWH_CORE.<objeto>` -> `migracion_dwh.dwh_core.<objeto>`
  - `DWH_MART.<objeto>` -> `migracion_dwh.dwh_mart.<objeto>`
  - T-SQL `stg.<Tabla>` -> `migracion_dwh.dwh_stg.stg_<tabla en snake_case>` (p. ej. `stg.Cdr` -> `stg_cdr`, columna `IdLinea` -> `id_linea`).
- Todos los identificadores (tablas, columnas, procedimientos) en minusculas y snake_case, sin comillas.

## 2. Tipos de datos
- `NUMBER(p,0)` con p <= 9 -> `INT`; con p entre 10 y 18 -> `BIGINT`. `NUMBER(p,s)` -> `DECIMAL(p,s)`.
- `VARCHAR2`, `NVARCHAR2`, `CHAR`, `CLOB` -> `STRING`.
- Oracle `DATE`: si la columna representa un dia (`fecha`, `fecha_alta`, `fecha_baja`, `fecha_inicio_vigencia`, `fecha_fin_vigencia`, `fecha_emision`, `fecha_solicitud`, `fecha_calculo`) -> `DATE`; si lleva hora (`fecha_hora_*`, `fecha_apertura`, `fecha_cierre`, `fecha_carga`) -> `TIMESTAMP`.

## 3. DDL fisico
- Elimina `TABLESPACE`, `COMPRESS`, `PCTFREE`, `STORAGE` y los `GRANT` a roles Oracle (deja un comentario `-- TODO UC GRANT`).
- Sustituye `PARTITION BY RANGE/LIST/INTERVAL` por `CLUSTER BY (<columna de particion>)` (liquid clustering).
- No crees indices (`CREATE INDEX`, `BITMAP INDEX`): elimina la sentencia y anade la columna al `CLUSTER BY` si procede.
- Las secuencias usadas como clave subrogada se sustituyen por `BIGINT GENERATED ALWAYS AS IDENTITY` en la tabla; no generes `CREATE SEQUENCE` ni `NEXTVAL` (omite la columna en el INSERT).
- Usa `CREATE TABLE IF NOT EXISTS` para tablas y `CREATE OR REPLACE VIEW` para vistas.
- Toda tabla destino (`dwh_core`, `dwh_mart`) lleva `TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported')`
  (catalog commits): los procedimientos usan `BEGIN ATOMIC` y las transacciones multi-sentencia solo
  pueden escribir en tablas con esta feature.

## 4. Logica procedural
- Los procedimientos y paquetes PL/SQL se convierten en `CREATE OR REPLACE PROCEDURE migracion_dwh.<esquema>.<nombre>(...) LANGUAGE SQL SQL SECURITY INVOKER AS BEGIN ... END`. Un paquete se convierte en un procedimiento por cada procedimiento publico, con prefijo del paquete (`pkg_facturacion_p_carga_fact_mensual`). Las funciones deterministas se convierten en funciones SQL de UC (`CREATE OR REPLACE FUNCTION`).
- `DWH_CORE.PKG_LOG.P_INICIO/P_FIN/P_ERROR` -> `INSERT INTO migracion_dwh.dwh_core.log_procesos (proceso, paso, estado, filas_afectadas, mensaje, fecha_hora) VALUES (..., current_timestamp())`. No hace falta transaccion autonoma.
- `STANDARD_HASH(x, 'SHA256')` + `RAWTOHEX` -> `upper(sha2(x, 256))`.
- Cursores con `BULK COLLECT` / `FORALL` -> una unica sentencia `INSERT ... SELECT` basada en conjuntos.
- **Cursores fila a fila (`FOR r IN c LOOP` con `SELECT INTO` / `UPDATE` por fila) NUNCA se traducen como bucle**
  (`FOR ... DO` en SQL scripting): reescribe la logica como conjuntos (CTEs con agregados por cliente + `LEFT JOIN`
  + `CASE` con las mismas reglas en el mismo orden) y un unico `MERGE`. `UPDATE` + `SQL%ROWCOUNT = 0` + `INSERT` -> `MERGE`.
  Los `COMMIT` cada N filas se eliminan. Si no puedes garantizar la equivalencia, deja `-- TODO: manual review required`.
- `EXECUTE IMMEDIATE 'TRUNCATE ...'` o `TRUNCATE PARTITION` -> `DELETE FROM ... WHERE <filtro de la particion>` o `TRUNCATE TABLE`.
- `DBMS_OUTPUT.PUT_LINE` -> eliminar. `DBMS_STATS.GATHER_TABLE_STATS` -> eliminar (Predictive Optimization) con comentario.
- `UTL_MAIL` y `DBMS_SCHEDULER` NO se convierten: deja un comentario `-- MIGRADO A LAKEFLOW JOBS: <descripcion>` indicando la programacion y la notificacion equivalentes (schedule cron + email notifications del job).
- Manten la semantica de negocio exacta (joins, filtros, redondeos, `NVL`, `DECODE`), aunque haya que reescribir la sintaxis.

## 4.b Patron OBLIGATORIO para cursores fila a fila (Oracle PL/SQL)
Si el codigo recorre filas con `CURSOR ... IS SELECT` + `FOR r IN c LOOP` (o `OPEN/FETCH/LOOP`) y dentro hace
`SELECT ... INTO` por fila, `IF/ELSIF` y `UPDATE` + `SQL%ROWCOUNT = 0` + `INSERT`:
- **Prohibido** generar `FOR ... DO`, `WHILE`, `REPEAT` o `LOOP` que recorran filas de una tabla.
- Cada `SELECT ... INTO` por fila se convierte en una CTE agregada por la clave (`GROUP BY id_cliente`) unida con `LEFT JOIN`.
- Cada variable calculada por fila (`v_meses`, `v_fact`, `v_inc`...) se convierte en una columna calculada (con `coalesce(..., 0)`
  donde el original usaba `NVL` o `COUNT(*)`).
- El `IF/ELSIF/ELSE` se convierte en `CASE WHEN` **con las mismas condiciones y en el mismo orden** (una columna para el importe y otra para el motivo).
- `UPDATE` + `IF SQL%ROWCOUNT = 0 THEN INSERT` se convierte en un **unico `MERGE`** (`WHEN MATCHED THEN UPDATE` / `WHEN NOT MATCHED THEN INSERT`),
  filtrando en el `USING` las filas que el original no escribia (p. ej. `WHERE bono_eur > 0`).
- Los `COMMIT` cada N filas y el `ROLLBACK` del `EXCEPTION WHEN OTHERS` se eliminan: el `MERGE` ya es atomico. **No uses `BEGIN ATOMIC`** si el cuerpo es un unico `MERGE`.
- `PKG_LOG.P_INICIO/P_FIN/P_ERROR` se pueden omitir en este patron (deja un comentario).
- El nombre del procedimiento sigue la regla de paquetes: `PKG_BONOS.P_RECALCULA_BONOS` -> `migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos(IN p_periodo STRING)`.
- Anade un comentario `-- Reescrito en conjuntos (antes: cursor fila a fila)` en la cabecera.

Ejemplo (esquema):
```
-- Oracle
FOR r IN (SELECT id_cliente FROM DWH_CORE.DIM_CLIENTE WHERE ES_ACTUAL = 'S') LOOP
  SELECT NVL(SUM(importe), 0) INTO v_fact FROM DWH_STG.STG_FACTURAS WHERE id_cliente = r.id_cliente AND periodo = p_periodo;
  IF v_fact > 100 THEN v_bono := 10; ELSE v_bono := 0; END IF;
  IF v_bono > 0 THEN
    UPDATE DWH_CORE.BONO SET bono = v_bono WHERE id_cliente = r.id_cliente AND periodo = p_periodo;
    IF SQL%ROWCOUNT = 0 THEN INSERT INTO DWH_CORE.BONO VALUES (p_periodo, r.id_cliente, v_bono); END IF;
  END IF;
END LOOP;

-- Databricks (obligatorio)
MERGE INTO migracion_dwh.dwh_core.bono t
USING (
  WITH cli AS (SELECT id_cliente FROM migracion_dwh.dwh_core.dim_cliente WHERE es_actual = 'S'),
       fac AS (SELECT id_cliente, SUM(importe) AS fact FROM migracion_dwh.dwh_stg.stg_facturas
               WHERE periodo = p_periodo GROUP BY id_cliente),
       reglas AS (SELECT c.id_cliente, CASE WHEN coalesce(f.fact, 0) > 100 THEN 10 ELSE 0 END AS bono
                  FROM cli c LEFT JOIN fac f ON f.id_cliente = c.id_cliente)
  SELECT p_periodo AS periodo, id_cliente, bono FROM reglas WHERE bono > 0
) s
ON t.periodo = s.periodo AND t.id_cliente = s.id_cliente
WHEN MATCHED THEN UPDATE SET bono = s.bono
WHEN NOT MATCHED THEN INSERT (periodo, id_cliente, bono) VALUES (s.periodo, s.id_cliente, s.bono);
```

## 5. Estilo
- Cabecera: `-- Migrado desde Oracle (DWH facturacion) con Genie Migrate` + nombre del objeto original.
- Mantener los comentarios de negocio originales en castellano.
