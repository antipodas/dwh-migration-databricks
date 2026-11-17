#!/bin/bash
# Quita skills de migracion (de tu carpeta personal y, si estan, tambien de la del workspace).
# Uso: setup/skill_off.sh            (quita las dos)
#      setup/skill_off.sh teradata | oracle
cd "$(dirname "$0")/.."
P="${PROFILE:?Define PROFILE=<perfil de la CLI>}"
ME=$(databricks current-user me --profile "$P" -o json | python3 -c "import sys,json;print(json.load(sys.stdin)['userName'])")
case "$1" in
  teradata) SK=(migracion-teradata) ;;
  oracle)   SK=(migracion-oracle) ;;
  ""|todas) SK=(migracion-teradata migracion-oracle) ;;
  *) echo "Uso: $0 [teradata|oracle|todas]"; exit 1 ;;
esac
for s in "${SK[@]}"; do
  for BASE in "/Users/$ME/.assistant/skills" /Workspace/.assistant/skills; do
    databricks workspace delete "$BASE/$s" --recursive --profile "$P" 2>/dev/null && echo "Skill $s QUITADA de $BASE"
  done
done
echo "Hecho."
