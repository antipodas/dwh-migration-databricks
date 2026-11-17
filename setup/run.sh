#!/bin/bash
# Uso: PROFILE=<perfil CLI> WAREHOUSE=<id del SQL warehouse> setup/run.sh fichero.sql [fichero2.sql ...]
cd "$(dirname "$0")/.."
for f in "$@"; do
  echo "### $f"
  uv run -q --with databricks-sdk python setup/run_sql.py --profile "${PROFILE:?Define PROFILE=<perfil de la CLI>}" --warehouse "${WAREHOUSE:?Define WAREHOUSE=<id del SQL warehouse>}" "$f" || exit 1
done
