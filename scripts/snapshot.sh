#!/usr/bin/env bash
# Maakt een snapshot van één of alle componenten (volumes, met de diensten even gestopt).
#   ./scripts/snapshot.sh [authentik|midpoint|corteza|all] [doelmap]
# Standaard doelmap: golden/  (de "gouden" stand waar reset.sh naar terugzet)
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-components.sh
WHAT=${1:-all}; DEST=${2:-golden}
[[ $WHAT == all ]] && LIST=$COMPONENTS || LIST=$WHAT
for c in $LIST; do
  [[ -n "${SERVICES[$c]:-}" ]] || { echo "Onbekende component: $c"; exit 1; }
  mkdir -p "$DEST/$c"
  echo "== snapshot $c -> $DEST/$c"
  # shellcheck disable=SC2086
  $COMPOSE stop ${SERVICES[$c]}
  for v in ${VOLUMES[$c]}; do backup_volume "$v" "$DEST/$c"; done
  # shellcheck disable=SC2086
  $COMPOSE start ${SERVICES[$c]}
  date -u +%FT%TZ > "$DEST/$c/TAKEN_AT"
done
echo "Klaar."
