#!/bin/bash
# Instala una skill de migracion para Genie Code.
# Uso: PROFILE=<perfil> setup/skill_on.sh teradata | oracle | todas
#   Por defecto la instala como skill PERSONAL (solo para ti): /Users/<tu usuario>/.assistant/skills/<skill>/SKILL.md
#   (es lo mismo que hace Genie Code -> Settings -> Skills -> Add skill).
#   SCOPE=workspace setup/skill_on.sh ...  -> la instala para TODO el workspace: /Workspace/.assistant/skills/<skill>/SKILL.md
set -e
cd "$(dirname "$0")/.."
P="${PROFILE:?Define PROFILE=<perfil de la CLI>}"
ME=$(databricks current-user me --profile "$P" -o json | python3 -c "import sys,json;print(json.load(sys.stdin)['userName'])")
if [ "${SCOPE:-user}" = "workspace" ]; then BASE=/Workspace/.assistant/skills; else BASE="/Users/$ME/.assistant/skills"; fi
case "$1" in
  teradata) SK=(migracion-teradata) ;;
  oracle)   SK=(migracion-oracle) ;;
  todas)    SK=(migracion-teradata migracion-oracle) ;;
  *) echo "Uso: $0 teradata|oracle|todas"; exit 1 ;;
esac
for s in "${SK[@]}"; do
  databricks workspace mkdirs "$BASE/$s" --profile "$P"
  databricks workspace import "$BASE/$s/SKILL.md" --file "skills/$s/SKILL.md" --format AUTO --overwrite --profile "$P"
  echo "Skill $s INSTALADA en $BASE/$s/SKILL.md"
done
