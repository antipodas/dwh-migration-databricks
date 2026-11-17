# Guion de la demo: migrar un DWH a Databricks con Genie Migrate

Este documento explica, paso a paso, cómo **montar** la demo en un workspace de Databricks, cómo **prepararla** y
cómo **correrla en directo**, y qué está pasando por debajo en cada paso. Duración en directo: unos **20 minutos**
(más ~20 min de slides y 5 de preguntas si la haces en una sesión de 45).

En todo el documento:
- `<tu-usuario>` es tu usuario del workspace (p. ej. `nombre.apellido@empresa.com`).
- `<repo>` es la carpeta donde has clonado este repositorio.
- `PROFILE` es el perfil de la Databricks CLI y `WAREHOUSE` el id del SQL warehouse que vas a usar.

---

## 1. Qué enseña la demo

Una empresa ficticia tiene dos plataformas legacy. La demo enseña, con código realista y datos sintéticos, por qué
**no todos los orígenes cuestan lo mismo** y cómo se trabaja con Genie Migrate:

| Parada | Qué se enseña | Mensaje |
|---|---|---|
| **1 · Teradata** (EDW de marketing, 6 scripts) | Crear un Migration Project, *Analyze* (complejidad y lineage), convertir y revisar el diff | El SQL declarativo convierte bien: es el caso fácil |
| **2 · Skills y paridad** | Instalar una *custom skill* con las convenciones del cliente, reconvertir y **reconciliar contra datos** | La herramienta valida sintaxis; la confianza la da reconciliar |
| **3 · Oracle** (cursor fila a fila) | Genie con la skill de Oracle reescribe un cursor en conjuntos; se cronometra frente a una traducción literal | En Oracle no se traduce: se reescribe |

---

## 2. Montaje (una vez por workspace, ~20 min)

### 2.1 Requisitos

Ver la sección *Requisitos del workspace* del [README](README.md). Lo imprescindible:
1. Preview **Migration Projects Experimental Features** (Beta) **activada**: avatar → **Settings** → **Previews** → *On*.
2. **Genie Code** activo, de modo que en **+ New** aparezca **Migration project**.
3. Un SQL warehouse y permiso para crear el catálogo `migracion_dwh`.
4. Databricks CLI con un perfil del workspace y [`uv`](https://docs.astral.sh/uv/).

### 2.2 Subir el código al workspace

```bash
cd <repo>
databricks workspace import-dir . /Users/<tu-usuario>/migracion-partners --profile $PROFILE
```

Qué hace: copia las fuentes legacy, las skills y los scripts a tu Home del workspace como ficheros. Los Migration
Projects leen el código **desde el workspace**, no desde tu portátil. Crea también las carpetas de trabajo:

```bash
W=/Users/<tu-usuario>/migracion-partners
for d in proyectos converted/ensayo_td converted/backup_td converted/backup_ora converted/vivo_td converted/cursor converted/cursor_sin_skill; do
  databricks workspace mkdirs $W/$d --profile $PROFILE
done
```

### 2.3 Crear los datos y desplegar lo convertido

```bash
export PROFILE=<perfil> WAREHOUSE=<id-del-warehouse>

# Oracle (DWH de facturación)
setup/run.sh setup/01_setup_datos_staging.sql converted_backup/0[1-9]_*.sql setup/02_activar_catalog_commits.sql \
             validation/00_ejecutar_cadena.sql validation/01_reconciliacion.sql
# Teradata (EDW de marketing)
setup/run.sh setup/03_setup_staging_teradata.sql converted_reference_teradata/0*.sql \
             validation/02_ejecutar_cadena_teradata.sql validation/03_reconciliacion_teradata.sql
# Cursor de Oracle (parada 3)
setup/run.sh rewrite_oracle_cursor/00_tabla_bonos.sql rewrite_oracle_cursor/01_traduccion_literal.sql \
             rewrite_oracle_cursor/02_reescritura_set_based.sql setup/04_bonos_catalog_commits.sql
```

Qué hace cada bloque:

| Script | Qué hace |
|---|---|
| `setup/01_setup_datos_staging.sql` | Crea el catálogo `migracion_dwh` y el staging Oracle (`dwh_stg`): 5.000 clientes, 11.000 líneas, 1,2 M de CDRs, facturas… Es el dato "ya migrado" que leerá el código convertido |
| `converted_backup/01..09` | Código Oracle **ya convertido por Genie Migrate** (con skill): tablas, vistas y procedimientos en `dwh_core` / `dwh_mart` |
| `setup/02_activar_catalog_commits.sql` | Activa *catalog commits* en las tablas destino: los procedimientos usan `BEGIN ATOMIC` y lo exigen |
| `validation/00_ejecutar_cadena.sql` | Ejecuta la cadena diaria del DWH con el código convertido (≈8 min: 60 días de tráfico) |
| `validation/01_reconciliacion.sql` | **10 controles**: cada objeto convertido frente a un cálculo independiente sobre staging |
| `setup/03_setup_staging_teradata.sql` | Staging Teradata (`edw_stg`): histórico de clientes, uso diario, campañas, contactos, facturas |
| `converted_reference_teradata/01..06` | Conversión de **referencia** Teradata → Databricks SQL (hecha a mano y reconciliada), para comparar con la de Genie |
| `validation/02_…` y `03_reconciliacion_teradata.sql` | Cadena mensual de marketing y **10 controles** Teradata (uno con tolerancia acordada) |
| `rewrite_oracle_cursor/00..02` | Tablas de bonos y dos procedimientos con la misma regla: **A** traducción literal (bucle) y **B** reescritura en conjuntos |
| `setup/04_bonos_catalog_commits.sql` | Catalog commits en las tablas de bonos (por si la versión de Genie usa `BEGIN ATOMIC`) |

Resultado esperado: todos los controles en `OK` (uno `OK (tolerancia)`).

---

## 3. Preparación antes de la demo (~45 min)

La conversión tarda varios minutos, así que antes de la demo se preparan **proyectos de respaldo**: en directo solo
conviertes un lote pequeño y enseñas el resto ya hecho.

### 3.1 Las skills

Hay dos *custom skills*, **una por origen**. Genie Code elige cuál cargar leyendo su `description`, así que con una por
dialecto solo aplica las reglas que tocan:

| Skill | Qué contiene |
|---|---|
| `skills/migracion-teradata/SKILL.md` | Nombres `EDW_STG`/`EDW_MKT` → `migracion_dwh.edw_*`, tipos, `MACRO` → `PROCEDURE`, tablas volátiles, `UPDATE … FROM` → `MERGE`, `QUANTILE` → `NTILE`… |
| `skills/migracion-oracle/SKILL.md` | Nombres `DWH_*` → `migracion_dwh.dwh_*`, tipos, paquetes PL/SQL, `DBMS_SCHEDULER`… y **§4.b: cursores fila a fila → conjuntos + un único `MERGE`** |

Dos formas de instalarlas (como skill **personal**, solo para ti):
- **UI:** **Genie Code** (icono arriba a la derecha) → ⚙ **Settings** → **Skills** → **+ Add skill** → sube el `SKILL.md`.
  Comprueba que **no** sale el aviso *"This skill's YAML frontmatter could not be parsed"*.
- **CLI:** `PROFILE=<perfil> setup/skill_on.sh teradata` (u `oracle`, o `todas`). Para quitarlas: `setup/skill_off.sh`.

Se guardan en `/Users/<tu-usuario>/.assistant/skills/<skill>/SKILL.md`. (También existe la ubicación de workspace,
`/Workspace/.assistant/skills/`, que la ven todos los usuarios; no hace falta para la demo.)

### 3.2 Proyectos de respaldo

Para cada uno: **+ New → Migration project** y rellena el diálogo:

| Campo | ENSAYO Teradata | BACKUP Teradata | BACKUP Oracle |
|---|---|---|---|
| **Project name** | `ENSAYO - Teradata EDW (sin skill)` | `BACKUP - Teradata EDW (con skill)` | `BACKUP - Oracle facturacion (con skill)` |
| **Save project in** | `/Users/<tu-usuario>/migracion-partners/proyectos` | igual | igual |
| **Source → Code type** | `Teradata` | `Teradata` | `Oracle` |
| **Source → Files** (📁, elige la **carpeta**) | `…/migracion-partners/source/teradata_edw_marketing` | igual | `…/migracion-partners/source/oracle_dwh_facturacion` |
| **Target → Code type** | `DBSQL` | `DBSQL` | `DBSQL` |
| **Target → carpeta** | `…/migracion-partners/converted/ensayo_td` | `…/converted/backup_td` | `…/converted/backup_ora` |
| Skill activa al convertir | **ninguna** | `migracion-teradata` | `migracion-oracle` |

Después, en cada proyecto: **Analyze all** (≈1,5–2 min) y **Convert all** (≈5–8 min).

> **¿DBSQL o Notebooks?** **DBSQL.** El código legacy es SQL y DBSQL lo convierte en vistas y
> `CREATE PROCEDURE … LANGUAGE SQL` de Unity Catalog, que es lo que validan los scripts de `validation/`.
> *Notebooks* genera PySpark (Beta).

Qué conviene comprobar:
- En el **ENSAYO**, los nombres quedan como `EDW_MKT.X` (dos partes, sin catálogo): es el "antes" de la parada 2.
- En el **BACKUP Teradata**, compara lo convertido con `converted_reference_teradata/`. Si quieres desplegar la versión
  de Genie, ejecútala en el SQL Editor y relanza `validation/02_…` y `validation/03_…`.

### 3.3 La parada 3: que Genie reescriba el cursor (paso a paso)

**Qué hay:**

| | Qué es | Dónde |
|---|---|---|
| Original Oracle | Paquete con un cursor que recorre los clientes uno a uno (`FOR r IN c LOOP`, tres `SELECT INTO` y un `UPDATE`/`INSERT` por cliente) | `source/oracle_cursor_reescritura/11_pkg_bonos_fidelizacion.sql` |
| Versión A · "traducir" | El cursor copiado tal cual como bucle `FOR … DO`. Compila y acierta, pero va fila a fila | `rewrite_oracle_cursor/01_traduccion_literal.sql` → `pkg_bonos_p_recalcula_bonos_literal` |
| Versión B · "reescribir" | La misma regla en conjuntos con un único `MERGE`. Lo ideal es que sea **la que genera Genie con la skill**; si no, se usa la del repo | `rewrite_oracle_cursor/02_reescritura_set_based.sql` → `pkg_bonos_p_recalcula_bonos` |
| Script de medición | 5 pasos comentados para el SQL Editor | `rewrite_oracle_cursor/04_DEMO_EN_VIVO.sql` |

**Pasos (todo en el navegador):**

1. Genie Code → Settings → **Skills**: si está `migracion-oracle`, **apágala**.
2. **+ New → Migration project**: *Project name* `CURSOR - Oracle bonos (sin skill)`, *Save project in*
   `…/migracion-partners/proyectos`, *Source* **Oracle**, *Files* = carpeta `source/oracle_cursor_reescritura`,
   *Target* **DBSQL**, carpeta `…/converted/cursor_sin_skill` → **Create project** → convertir.
3. Abre el diff y **solo mira**: ¿ha generado un bucle (`FOR … DO`, `WHILE`, `LOOP`) o conjuntos (`WITH` + `CASE` +
   `MERGE`)? Haz una captura: es el "sin reglas".
4. Genie Code → Settings → Skills → **+ Add skill** → `skills/migracion-oracle/SKILL.md` (sin aviso de YAML).
5. **Otro proyecto nuevo**, igual que el del paso 2 salvo *Project name* `CURSOR - Oracle bonos (con skill)` y carpeta
   `…/converted/cursor`. Convierte y abre el diff. Comprueba:
   - no hay `FOR … DO` / `WHILE` / `LOOP`;
   - hay bloques `WITH`, un `CASE` y **un solo `MERGE`**;
   - el procedimiento se llama `migracion_dwh.dwh_core.pkg_bonos_p_recalcula_bonos` (apunta el nombre exacto).
6. **Accept** en el diff.
7. **Crear el procedimiento de Genie**: con el fichero abierto en el SQL Editor, elige tu warehouse y pulsa **Run all**.
   Esto **no calcula bonos**: solo crea (o reemplaza) el procedimiento con el código de Genie. Si hay error, pulsa
   **Diagnose error**, aplica el arreglo y **Accept all**.
8. **Comprobar que da lo mismo**: abre `rewrite_oracle_cursor/04_DEMO_EN_VIVO.sql` (si Genie puso otro nombre al
   procedimiento, cámbialo en el PASO 3) y ejecuta los pasos uno a uno con **Cmd+Shift+Enter**. El **PASO 4** debe
   devolver **dos números iguales**.
   - Iguales → la versión de Genie es la que usas en directo.
   - Distintos → Genie ha cambiado la lógica: restaura la del repo ejecutando `02_reescritura_set_based.sql`
     (**Run all**) y cuéntalo en directo como *"por esto siempre se reconcilia"*.
   - Si Genie sigue generando un bucle con la skill: no lo despliegues; usa la versión del repo.
9. Al terminar, apaga las dos skills (las vuelves a poner en directo).

### 3.4 Justo antes de empezar (T-15 min)

- Skills **apagadas** (`setup/skill_off.sh` o desde Settings → Skills).
- Arranca el SQL warehouse.
- Pestañas abiertas: (a) carpeta `migracion-partners/source`, (b) proyecto `BACKUP - Teradata EDW (con skill)`,
  (c) proyecto `CURSOR - Oracle bonos (con skill)`, (d) SQL Editor con `validation/03_reconciliacion_teradata.sql`,
  (e) SQL Editor con `rewrite_oracle_cursor/04_DEMO_EN_VIVO.sql`.
- Ten a mano `skills/migracion-teradata/SKILL.md` en el portátil. Zoom del navegador al 125 %.

---

## 4. La demo en directo (20 min)

### Parada 1 · Teradata: el camino fácil (8 min)

1. **El código legacy (1 min).** Pestaña (a) → `source/teradata_edw_marketing`. Señala:
   - `01_ddl_edw_mkt.sql`: `MULTISET`/`SET`, `FALLBACK`, `COMPRESS`, `PRIMARY INDEX`, `PARTITION BY RANGE_N`, `COLLECT STATISTICS`.
   - `03_m_carga_uso_mensual.sql`: una **MACRO** con parámetros (`:P_PERIODO`), `ZEROIFNULL`, `CAST(… FORMAT 'YYYYMMDD')`.
   - `05_sp_segmentacion_valor.sql`: `QUANTILE(10, …)`, `ACTIVITY_COUNT`, `EXIT HANDLER`.
   - `source/teradata_bteq_no_soportado/cadena_mensual_marketing.btq`: BTEQ **no** se convierte; la orquestación se
     rediseña como Lakeflow Job.
2. **Crear el proyecto (1 min).** **+ New → Migration project**: *Project name*
   `Migracion - EDW Marketing (Teradata a DBSQL) - vivo`, *Save project in* `…/migracion-partners/proyectos`,
   *Source* **Teradata**, *Files* = carpeta `source/teradata_edw_marketing`, *Target* **DBSQL**, carpeta
   `…/converted/vivo_td` → **Create project**. El texto del diálogo lo dice: *"Your source files never change"*.
3. **Analyze all (≈1,5 min).** *Qué pasa por debajo:* parsea cada sentencia, resuelve qué objetos crea cada script y
   cuáles lee, calcula dependencias y propone el orden de migración.
   - **Lineage**: `01_ddl` alimenta al resto; `02_v_cliente_vigente` la leen `03` y `05`; `06` lee `04`.
     Es el input del plan de olas: qué se migra junto y en qué orden.
   - **Report**: % de sentencias analizadas y el aviso de objetos que no crea ningún script (las tablas de `EDW_STG`:
     deben existir antes, es la carga de datos). **Export** para llevárselo.
4. **Convertir un lote pequeño (≈4 min).** Marca `02_v_cliente_vigente`, `03_m_carga_uso_mensual` y
   `05_sp_segmentacion_valor` → **Convert selected**. *Qué pasa por debajo:* Genie Code lanza subagentes en paralelo;
   cada uno convierte, compila contra Databricks, compara la intención con el original y, si falla, se corrige.
   Mientras espera, enseña el proyecto BACKUP ya convertido (**Report → Conversion summary**).
5. **Revisar el diff (2 min).** Clic en el `05` convertido → diff en el SQL Editor (rojo origen, verde propuesta).
   - `QUANTILE(10, x)` → `ntile(10) OVER (ORDER BY x) - 1` (o lo que proponga: léelo y juzga en voz alta).
   - La MACRO del `03` → `CREATE PROCEDURE … LANGUAGE SQL`.
   - **Sin skill** deja nombres de dos partes (`EDW_MKT.SEGMENTO_VALOR`), que no existen en Unity Catalog → parada 2.
   - **Accept** y guarda (si no, el query se queda con el código viejo).

### Parada 2 · Skills y paridad (6 min)

1. **Instalar la skill en vivo (2 min).** Genie Code → Settings → Skills → **+ Add skill** →
   `skills/migracion-teradata/SKILL.md`. Enseña el bloque `---` (`name`, `description`: Genie decide cuándo usarla por
   la descripción) y las reglas: nombres de tres partes, `MACRO → PROCEDURE`, `VOLATILE → subconsulta`,
   `UPDATE FROM → MERGE`, `QUANTILE → NTILE`. Flujo recomendado: convertir una muestra → ver errores repetidos → una
   regla por error → reconvertir solo lo afectado.
2. **Reconvertir (≈4 min, en segundo plano).** En el proyecto en vivo marca solo `05_sp_segmentacion_valor` →
   **Convert selected**. Mientras, enseña el mismo fichero en el BACKUP, ya con `migracion_dwh.edw_mkt.segmento_valor`.
3. **La paridad (2 min).** Pestaña (d): `validation/03_reconciliacion_teradata.sql` → **Run**. *Qué pasa por debajo:*
   cada control compara un objeto convertido con un cálculo independiente sobre el staging.
   - Diez controles en `OK`; uno `OK (tolerancia)`: 0,1 GB de diferencia porque el original redondea por cliente a 3
     decimales antes de sumar. Las tolerancias se pactan con negocio **antes** de convertir.
   - (Opcional) `validation/01_reconciliacion.sql`: los 10 controles de Oracle (facturación al céntimo, jerarquía
     `CONNECT BY` 450/60/3).

### Parada 3 · Oracle: traducir no es migrar (6 min)

1. **El original (1,5 min).** `source/oracle_cursor_reescritura/11_pkg_bonos_fidelizacion.sql`: `FOR r IN c_cli LOOP`
   recorre los clientes uno a uno; dentro, tres `SELECT … INTO` y un `UPDATE`/`INSERT` (cuatro viajes a la base de
   datos por cliente) y un `COMMIT` cada 500. En un motor distribuido, ir fila a fila es lo peor que se puede hacer.
2. **Lo que ha hecho Genie con la skill (1,5 min).** Pestaña (c): diff del proyecto `CURSOR - Oracle bonos (con skill)`:
   CTEs con los agregados por cliente, un `CASE` con las mismas reglas en el mismo orden y un único `MERGE`. Abre
   `skills/migracion-oracle/SKILL.md`, §4.b: lo ha hecho así porque la skill lo exige. Si tienes la captura del
   proyecto *sin skill* con un bucle, enséñala: es el "antes".
3. **Medirlo (2 min).** Pestaña (e): `04_DEMO_EN_VIVO.sql`. Cursor dentro de cada sentencia y **Cmd+Shift+Enter**:
   - PASO 1: vacía la tabla de resultados de la versión A (1 s).
   - **PASO 2**: llama a la **traducción literal** con **10 clientes**: **~25–35 s** (unos 3 s por cliente).
   - **PASO 3**: llama a la **versión reescrita** (la de Genie) con **los 4.550 clientes**: **~3–6 s**.
   - PASO 4: dos números iguales → mismo resultado.
   - La cuenta: la literal, para 4.550 clientes, serían unas 3 horas.
4. **Mensaje (1 min).** Mismo resultado, órdenes de magnitud de diferencia. En Oracle procedural se reescribe en
   conjuntos y se vuelve a probar; se pone como regla en la skill, cada paquete PL/SQL se revisa y se presupuesta.

Mediciones de referencia (serverless, nov-2026): literal 110–115 s con 50 clientes y 30–33 s con 10; reescrita
2,8–5,5 s con 4.550; resultados idénticos en todos los casos.

---

## 5. Si algo va mal

| Problema | Qué hacer |
|---|---|
| No aparece **Migration project** en + New | Activa la preview y comprueba Genie Code (sección 2.1). Mientras, las paradas 2 y 3 funcionan solo con el SQL Editor |
| *Analyze* tarda más de 3 min | Sigue con Lineage y Report del proyecto BACKUP |
| *Convert* en cola más de 4 min | Normal en el primer lote del día: enseña el BACKUP y vuelve |
| Conversión en rojo | Abre el motivo y relanza Convert de ese fichero |
| Aviso de YAML en la skill | El bloque `---` está mal: entrecomilla la `description` (un `: ` sin comillas rompe el parseo) |
| La skill no se aplica | Settings → Skills: activada y sin aviso; el fichero se llama exactamente `SKILL.md` |
| Error al ejecutar código convertido | **Diagnose error** (Genie Code): propone el arreglo y pide permiso antes de aplicarlo |
| `TRANSACTION_NOT_SUPPORTED` | `BEGIN ATOMIC` exige catalog commits: `setup/02_…` y `setup/04_…` |
| `LATERAL_COLUMN_ALIAS_IN_GROUP_BY` | Alias laterales con `GROUP BY ALL`: usa `GROUP BY` explícito |

## 6. Después (reset)

- Borra el proyecto en vivo y la carpeta `converted/vivo_td`.
- Quita las skills: `setup/skill_off.sh`.
- Para volver a dejar el cursor como estaba: ejecuta `rewrite_oracle_cursor/02_reescritura_set_based.sql`.
- Para reconstruirlo todo desde cero: repite la sección 2.3 (los scripts son idempotentes).
