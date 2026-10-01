#!/usr/bin/env bash
# Bewaart de huidige stand van alle componenten in saves/<tijd>/, terug te zetten met:
#   ./scripts/reset.sh <component> saves/<tijd>
# Tip: exporteer daarnaast de Corteza-namespace (Admin > Namespaces > Export) en
# Corteza-workflows (Workflow > Export) en commit die in de repo onder work/.
set -euo pipefail
cd "$(dirname "$0")/.."
TS=$(date +%Y%m%d-%H%M)
./scripts/snapshot.sh all "saves/$TS"
echo "Opgeslagen in saves/$TS"
