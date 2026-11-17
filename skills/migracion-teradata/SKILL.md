---
name: migracion-teradata
description: "Reglas para convertir a Databricks SQL el EDW de marketing en Teradata (bases EDW_STG y EDW_MKT; tablas, vistas, macros y procedimientos), con destino el catalogo migracion_dwh de Unity Catalog. Aplicar SOLO cuando el codigo de origen sea Teradata SQL de este EDW, en un Migration Project o con Genie Code."
---

# Reglas de migracion: EDW Marketing (Teradata) -> Databricks SQL

Aplica SIEMPRE estas reglas al convertir codigo Teradata del EDW de marketing.
Para codigo Oracle PL/SQL usa la skill `migracion-oracle`, no esta.

## 1. Nombres y Unity Catalog
- Usa siempre nombres de tres partes en el catalogo `migracion_dwh`:
  - `EDW_STG.<tabla>` -> `migracion_dwh.edw_stg.<tabla>`
  - `EDW_MKT.<objeto>` -> `migracion_dwh.edw_mkt.<objeto>`
- Todos los identificadores (tablas, columnas, vistas, procedimientos) en minusculas y snake_case, sin comillas.

## 2. Tipos de datos
- `INTEGER` -> `INT`; `SMALLINT` -> `SMALLINT`; `BYTEINT` -> `TINYINT`; `DECIMAL(p,s)` -> `DECIMAL(p,s)`.
- `CHAR(n)` y `VARCHAR(n)` (cualquier `CHARACTER SET`) -> `STRING`.
- `DATE FORMAT '...'` -> `DATE`; `TIMESTAMP(n)` -> `TIMESTAMP`. `DEFAULT CURRENT_TIMESTAMP(0)` -> `DEFAULT current_timestamp()`
  (y en ese caso `TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported')`).

## 3. DDL, vistas, macros y procedimientos
- `SET`/`MULTISET`, `FALLBACK`, `JOURNAL`, `CHECKSUM`, `MERGEBLOCKRATIO`, `COMPRESS`, `CHARACTER SET ... CASESPECIFIC`, `FORMAT`: eliminar.
- `PRIMARY INDEX` / `PARTITION BY RANGE_N` -> `CLUSTER BY` (columna de particion primero). `UNIQUE PRIMARY INDEX` / `SET TABLE` -> `CONSTRAINT pk_... PRIMARY KEY (...)` informativa.
- `INDEX` secundarios y `COLLECT STATISTICS` -> eliminar (Predictive Optimization).
- `BYTEINT` -> `TINYINT`. `CHAR(n)` -> `STRING`.
- `REPLACE VIEW` -> `CREATE OR REPLACE VIEW`. `LOCKING ROW FOR ACCESS` -> eliminar. `SEL`/`INS`/`UPD`/`DEL` -> palabra completa.
- `REPLACE MACRO` -> `CREATE OR REPLACE PROCEDURE ... LANGUAGE SQL` (parametros `:P` -> `p`). `EXEC` -> `CALL`.
- `CREATE VOLATILE TABLE ... ON COMMIT PRESERVE ROWS` -> subconsulta o CTE en la sentencia que la usa (no tablas temporales).
- `UPDATE t FROM ...` + `INSERT ... WHERE NOT EXISTS` -> un unico `MERGE`.
- `ZEROIFNULL(x)` -> `coalesce(x, 0)`; `NULLIFZERO(x)` -> `nullif(x, 0)`; `INDEX(s, t)` -> `instr(s, t)`;
  `CAST(x AS DATE FORMAT 'YYYYMMDD')` -> `to_date(x, 'yyyyMMdd')`; `(fecha (FORMAT 'YYYY')) (CHAR(4))` -> `date_format(fecha, 'yyyy')`.
- `QUANTILE(n, x)` (0..n-1 ascendente) -> `ntile(n) OVER (ORDER BY x) - 1`.
- `ACTIVITY_COUNT` -> contar las filas afectadas con una consulta posterior.
- Alias laterales de columna: permitidos, pero NO con `GROUP BY ALL` (`LATERAL_COLUMN_ALIAS_IN_GROUP_BY`): usa `GROUP BY` explicito.
- Las tablas de `edw_mkt` NO llevan `catalogManaged` (sus procedimientos no usan `BEGIN ATOMIC`).
- BTEQ (`.LOGON`, `.IF ERRORCODE`, `.EXPORT`, `.OS`) no se convierte: proponer un Lakeflow Job equivalente.


## 4. Estilo
- Cabecera: `-- Migrado desde Teradata (EDW Marketing) con Genie Migrate` + nombre del objeto original.
- Mantener los comentarios de negocio originales en castellano.
