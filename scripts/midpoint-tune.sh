#!/usr/bin/env bash
# Zet de interval van de midPoint Validity Scanner op 60 seconden, zodat verlopen
# JIT-assignments binnen een minuut worden ingetrokken. Draai na de eerste start.
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; source compose/.env; set +a
BASE="https://midpoint.${DOMAIN}/midpoint/ws/rest"
AUTH="administrator:${MP_ADMIN_PASSWORD}"
OID=$(curl -fsS -u "$AUTH" -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -X POST "$BASE/tasks/search" \
  -d '{"query":{"filter":{"text":"name = \"Validity Scanner\""}}}' | jq -r '.. | .oid? // empty' | head -1)
[[ -n "$OID" ]] || OID=00000000-0000-0000-0000-000000000006
echo "Validity Scanner: $OID"
curl -fsS -u "$AUTH" -H 'Content-Type: application/json' -X PATCH "$BASE/tasks/$OID" -d '{
  "objectModification": {"itemDelta": {"modificationType": "replace", "path": "schedule/interval", "value": 60}}
}' && echo "Interval op 60 seconden gezet."
