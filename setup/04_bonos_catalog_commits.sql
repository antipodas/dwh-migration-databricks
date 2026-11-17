-- Por si Genie genera BEGIN ATOMIC en el procedimiento de bonos: las transacciones multi-sentencia exigen catalog commits.
ALTER TABLE migracion_dwh.dwh_core.bono_fidelizacion         SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
ALTER TABLE migracion_dwh.dwh_core.bono_fidelizacion_literal SET TBLPROPERTIES ('delta.feature.catalogManaged' = 'supported');
