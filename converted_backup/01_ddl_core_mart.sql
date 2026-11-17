-- Migrado desde Oracle (DWH facturacion) con Genie Migrate
-- Objeto original: DDL capa CORE y MART (Oracle 19c)
-- =====================================================================
-- DWH FACTURACION - DDL capa CORE y MART (Oracle 19c)
-- Autor: Equipo BI Corporativo   Fecha: 2014-03-11   Ult. mod: 2023-06-02
-- Las tablas de staging (DWH_STG.*) las carga el ETL de ingesta (ODI).
-- =====================================================================

-- Secuencia sustituida por la identidad de dim_cliente.sk_cliente.
-- TODO: manual review required — confirmar que seq_dim_cliente no tiene consumidores externos antes de retirarla.

-- Tipos Oracle, secuencia, nombres y almacenamiento físico adaptados a Delta en Unity Catalog.
-- TODO: manual review required — confirmar la estrategia de clave subrogada identity; impide escrituras concurrentes y puede generar huecos.
-- TODO: manual review required — confirmar que fecha_inicio_vigencia es una fecha de negocio sin componente horario antes de usar DATE y CURRENT_DATE.
-- NOTE: Los DEFAULT requieren la feature Delta allowColumnDefaults.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.dim_cliente (
    sk_cliente              BIGINT          GENERATED ALWAYS AS IDENTITY NOT NULL,
    id_cliente              BIGINT          NOT NULL,
    nif                     STRING,
    nombre                  STRING,
    segmento                STRING,
    provincia               STRING,
    id_cliente_padre        BIGINT,
    fecha_alta              DATE,
    fecha_inicio_vigencia   DATE            DEFAULT CURRENT_DATE NOT NULL,
    fecha_fin_vigencia      DATE            DEFAULT DATE '9999-12-31',
    es_actual               STRING          DEFAULT 'S',
    hash_atributos          STRING,
    CONSTRAINT pk_dim_cliente PRIMARY KEY (sk_cliente) NOT ENFORCED
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Índice bitmap ix_dim_cliente_seg eliminado; Delta usa data skipping y puede optimizarse manualmente por segmento.
-- Índice ix_dim_cliente_id eliminado; usar liquid clustering o Z-ORDER por id_cliente y es_actual si el patrón de consulta lo justifica.

-- Tipos Oracle, nombres y almacenamiento físico adaptados a Delta en Unity Catalog.
-- Particionado RANGE/INTERVAL sustituido por liquid clustering sobre fecha; el esquema intervalado no limitaba el dominio de fechas.
-- TODO: manual review required — verificar que fecha contiene únicamente días sin hora antes de mantener el tipo DATE.
-- TODO: manual review required — verificar que TIMESTAMP es el destino previsto para fecha_carga y su DEFAULT CURRENT_TIMESTAMP.
-- NOTE: Los DEFAULT requieren la feature Delta allowColumnDefaults.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.fact_trafico_diario (
    fecha                   DATE            NOT NULL,
    id_linea                BIGINT          NOT NULL,
    id_cliente              BIGINT          NOT NULL,
    cod_tarifa              STRING,
    minutos_voz             DECIMAL(12,2)   DEFAULT 0,
    mb_datos                DECIMAL(14,3)   DEFAULT 0,
    num_sms                 INT             DEFAULT 0,
    minutos_roaming         DECIMAL(12,2)   DEFAULT 0,
    importe_fuera_bono      DECIMAL(12,4)   DEFAULT 0,
    pct_consumo_bono_datos  DECIMAL(6,2),
    fecha_carga             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
)
CLUSTER BY (fecha)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Tipos Oracle, nombres y almacenamiento físico adaptados a Delta en Unity Catalog.
-- Particionado LIST AUTOMATIC sustituido por liquid clustering; al ser automático no limitaba el dominio de periodo.
-- TODO: manual review required — verificar que TIMESTAMP es el destino previsto para fecha_carga y su DEFAULT CURRENT_TIMESTAMP.
-- NOTE: El DEFAULT requiere la feature Delta allowColumnDefaults.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.fact_facturacion_mensual (
    periodo                 STRING          NOT NULL,
    id_cliente              BIGINT          NOT NULL,
    segmento                STRING,
    num_lineas_activas      INT,
    importe_base            DECIMAL(14,2),
    importe_total           DECIMAL(14,2),
    importe_impagado        DECIMAL(14,2),
    arpu                    DECIMAL(12,2),
    meses_antiguedad        INT,
    fecha_carga             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_fact_fact_mens PRIMARY KEY (periodo, id_cliente) NOT ENFORCED
)
CLUSTER BY (periodo)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Tipos Oracle, nombres y almacenamiento físico adaptados a Delta en Unity Catalog.
-- TODO: manual review required — confirmar la estrategia identity; impide escrituras concurrentes y puede generar huecos.
-- assumption: el offset de zona de SYSTIMESTAMP no se conserva porque DBSQL TIMESTAMP no almacena un offset por valor.
-- NOTE: El DEFAULT requiere la feature Delta allowColumnDefaults.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_core.log_procesos (
    id_ejecucion            BIGINT          GENERATED ALWAYS AS IDENTITY,
    proceso                 STRING,
    paso                    STRING,
    estado                  STRING,
    filas_afectadas         BIGINT,
    mensaje                 STRING,
    fecha_hora              TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Tipos Oracle, nombres y almacenamiento físico adaptados a Delta en Unity Catalog.
-- TODO: manual review required — verificar que TIMESTAMP es el destino previsto para fecha_carga y su DEFAULT CURRENT_TIMESTAMP.
-- NOTE: El DEFAULT requiere la feature Delta allowColumnDefaults.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_mart.mart_arpu_segmento (
    periodo                 STRING,
    segmento                STRING,
    provincia               STRING,
    num_clientes            BIGINT,
    ingresos_totales        DECIMAL(16,2),
    arpu_medio              DECIMAL(12,2),
    peso_ingresos_pct       DECIMAL(6,2),
    variacion_arpu_mom_pct  DECIMAL(8,2),
    fecha_carga             TIMESTAMP       DEFAULT CURRENT_TIMESTAMP
)
TBLPROPERTIES ('delta.feature.allowColumnDefaults' = 'supported');

-- Tipos Oracle, nombres, clave primaria y almacenamiento físico adaptados a Delta en Unity Catalog.
-- TODO: manual review required — verificar que fecha_calculo contiene únicamente días sin hora antes de mantener el tipo DATE.
CREATE TABLE IF NOT EXISTS migracion_dwh.dwh_mart.mart_riesgo_churn (
    id_cliente              BIGINT          NOT NULL,
    segmento                STRING,
    provincia               STRING,
    arpu_ultimo_mes         DECIMAL(12,2),
    variacion_consumo_pct   DECIMAL(8,2),
    num_incidencias_90d     INT,
    num_portabilidades      INT,
    operadores_destino      STRING,
    score_riesgo            DECIMAL(5,2),
    nivel_riesgo            STRING,
    ranking_provincia       INT,
    fecha_calculo           DATE,
    CONSTRAINT pk_mart_riesgo_churn PRIMARY KEY (id_cliente) NOT ENFORCED
);

-- TODO UC GRANT: conceder SELECT sobre migracion_dwh.dwh_mart.mart_arpu_segmento al principal equivalente de rol_bi_lectura.
-- TODO UC GRANT: conceder SELECT sobre migracion_dwh.dwh_mart.mart_riesgo_churn al principal equivalente de rol_bi_lectura.
