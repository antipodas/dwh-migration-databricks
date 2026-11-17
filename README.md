# Kit demo: Migrations Deep Dive (Genie Migrate)

Demo de **Genie Migrate** (Migration Projects) para migraciones de DWH a Databricks: un EDW de marketing en **Teradata**
(el caso directo) y un DWH de facturación en **Oracle PL/SQL** (el caso difícil, con un cursor fila a fila), con datos
sintéticos, *custom skills* por origen y scripts de reconciliación. La empresa es ficticia y los datos, sintéticos.

> **¿Cómo se corre la demo?** Todo, paso a paso, en **[GUION_DEMO.md](GUION_DEMO.md)**: montaje en el workspace,
> preparación (skills y proyectos de respaldo), la demo en directo parada a parada explicando qué pasa por debajo en
> cada paso, plan B y reset.

## En resumen

1. **Requisitos**: activa la preview *Migration Projects Experimental Features* y comprueba Genie Code (abajo).
2. **Montaje** (~20 min): sube el código al workspace y ejecuta los scripts de `setup/` para crear el catálogo
   `migracion_dwh` con datos sintéticos y el código convertido ya validado (guion, sección 2).
3. **Preparación** (~45 min): instala las skills y crea los proyectos de respaldo (ENSAYO sin skill, BACKUP con skill,
   CURSOR sin y con skill) para no depender de los tiempos de conversión en directo (guion, sección 3).
4. **Demo en directo** (~20 min), tres paradas (guion, sección 4):
   - **Teradata**: Migration Project → *Analyze* (lineage, report) → convertir → revisar el diff.
   - **Skills y paridad**: instalar la skill `migracion-teradata`, reconvertir y reconciliar (10 controles).
   - **Oracle**: Genie reescribe un cursor fila a fila gracias a la skill `migracion-oracle`; se cronometra frente a la
     traducción literal (~30 s para 10 clientes frente a ~5 s para 4.550, mismo resultado).

## Requisitos del workspace (antes de nada)

1. **Activar la preview _Migration Projects Experimental Features_ (Beta).** Un admin del workspace:
   avatar (arriba a la derecha) → **Settings** → **Previews** → busca *Migration Projects Experimental Features* → **On**.
   Habilita, dentro de los Migration Projects: el **análisis y lineage** del código legacy (*Analyze*), el target
   **Notebooks (PySpark)** para orígenes SQL e **Informatica PowerCenter** como origen ETL. Sin ella, la demo pierde la
   parte de assessment (Analyze, Lineage, Report).
2. **Genie Code** activo en el workspace (la conversión agéntica corre sobre Genie Code). Si en **+ New** no aparece
   **Migration project**, revisa también en *Previews* que esté activada la conversión agéntica de Genie Code.
3. Un **SQL warehouse** (serverless recomendado) y permiso para **crear un catálogo** en Unity Catalog (`migracion_dwh`).
4. **Databricks CLI** configurada con un perfil del workspace y [`uv`](https://docs.astral.sh/uv/) para ejecutar los scripts de `setup/`.

## Montarlo en tu workspace

```bash
# 1) Sube el código al workspace (cambia el perfil)
databricks workspace import-dir . /Users/<tu-usuario>/migracion-partners --profile <perfil>

# 2) Crea el catálogo migracion_dwh con datos sintéticos, despliega y valida (≈15 min)
export PROFILE=<perfil> WAREHOUSE=<id-del-warehouse>
setup/run.sh setup/01_setup_datos_staging.sql converted_backup/0[1-9]_*.sql setup/02_activar_catalog_commits.sql \
             validation/00_ejecutar_cadena.sql validation/01_reconciliacion.sql
setup/run.sh setup/03_setup_staging_teradata.sql converted_reference_teradata/0*.sql \
             validation/02_ejecutar_cadena_teradata.sql validation/03_reconciliacion_teradata.sql
setup/run.sh rewrite_oracle_cursor/00_tabla_bonos.sql rewrite_oracle_cursor/01_traduccion_literal.sql \
             rewrite_oracle_cursor/02_reescritura_set_based.sql setup/04_bonos_catalog_commits.sql

# 3) Skills de Genie Code (personales; o súbelas con Genie Code → Settings → Skills → Add skill)
setup/skill_on.sh teradata    # o: oracle | todas  ·  setup/skill_off.sh para quitarlas (usa PROFILE)
```

## Contenido

| Carpeta | Qué hay |
|---|---|
| `source/teradata_edw_marketing/` | 6 scripts Teradata SQL (DDL, vista con QUALIFY, MACRO, volátil + UPDATE FROM, SP con QUANTILE, KPIs) |
| `source/teradata_bteq_no_soportado/` | Cadena BTEQ (para enseñar lo que no convierte) |
| `source/oracle_dwh_facturacion/` | 10 scripts PL/SQL (paquetes, SCD2, CONNECT BY, DBMS_SCHEDULER/UTL_MAIL) |
| `source/oracle_cursor_reescritura/` | Paquete con cursor fila a fila (parada 3) |
| `source/tsql_backup/` | 3 scripts T-SQL por si piden otro dialecto |
| `skills/migracion-teradata/SKILL.md` | Skill de ejemplo para Teradata: nombres UC, tipos, MACRO, VOLATILE, UPDATE FROM, QUANTILE |
| `skills/migracion-oracle/SKILL.md` | Skill de ejemplo para Oracle PL/SQL (y T-SQL): nombres UC, paquetes, scheduler, cursores → conjuntos |
| `converted_backup/` | Salida de Genie Migrate para Oracle (ensayo 29-oct, con skill), desplegable tal cual |
| `converted_reference_teradata/` | Conversión de referencia Teradata → Databricks SQL (manual, desplegada y reconciliada) |
| `rewrite_oracle_cursor/` | Traducción literal vs reescritura set-based + benchmark |
| `setup/` | Datos sintéticos (Oracle y Teradata), catalog commits, runner `run.sh` (usa `PROFILE` y `WAREHOUSE`), `skill_on.sh` / `skill_off.sh` |
| `validation/` | Cadenas de ejecución y reconciliaciones (10 controles Oracle, 10 Teradata) |

Resultados medidos (nov-2026, Azure Databricks, catálogo `migracion_dwh`):
Oracle 22 objetos UC desplegados sin editar · 10/10 controles · Teradata 10/10 controles (1 con tolerancia) ·
cursor literal 115 s / 50 clientes vs set-based 4,6 s / 4.550 clientes, 25/25 idénticos.
Todo es ficticio y sintético.
