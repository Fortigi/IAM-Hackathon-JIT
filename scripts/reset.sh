#!/usr/bin/env bash
# Zet één of alle componenten terug naar de golden snapshot.
#   ./scripts/reset.sh authentik|midpoint|corteza|all [bronmap]
# Draai eerst ./scripts/save-work.sh als je tussentijds werk wilt bewaren.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/lib-components.sh
WHAT=${1:?gebruik: reset.sh authentik|midpoint|corteza|all [bronmap]}; SRC=${2:-golden}
[[ $WHAT == all ]] && LIST=$COMPONENTS || LIST=$WHAT
for c in $LIST; do
  [[ -d "$SRC/$c" ]] || { echo "Geen snapshot in $SRC/$c"; exit 1; }
  echo "== reset $c vanuit $SRC/$c ($(cat "$SRC/$c/TAKEN_AT" 2>/dev/null))"
  # shellcheck disable=SC2086
  $COMPOSE stop ${SERVICES[$c]}
  for v in ${VOLUMES[$c]}; do restore_volume "$v" "$SRC/$c"; done
  # shellcheck disable=SC2086
  $COMPOSE start ${SERVICES[$c]}
done
echo
echo "Klaar. Vergeet niet:"
echo " - Entra: pwsh ./seed/entra/reset-entra.ps1 -TenantId <id>  (vanaf je laptop)"
echo " - midPoint: draai daarna de taak 'Entra-reconciliatie' zodat register en tenant weer kloppen"
