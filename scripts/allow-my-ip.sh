#!/usr/bin/env bash
# Voegt je huidige publieke IP toe aan de NSG-allowlist (443 en 22).
# Draai vanaf je laptop: ./scripts/allow-my-ip.sh [extra-ip/32 ...]
# Vereist: az (ingelogd) en Network Contributor op de resourcegroep.
set -euo pipefail
cd "$(dirname "$0")/.."
RG=${AZ_RG:-rg-jit-hackathon}
NSG=${NSG:-nsg-jit}
[[ -f hackathon.env ]] && source hackathon.env && RG=$AZ_RG
MYIP=$(curl -fsS https://api.ipify.org)/32
for RULE in allow-https-team allow-ssh-team; do
  CURRENT=$(az network nsg rule show -g "$RG" --nsg-name "$NSG" -n "$RULE" --query "sourceAddressPrefixes" -o tsv)
  NEW=$(printf '%s\n' $CURRENT "$MYIP" "$@" | sort -u | tr '\n' ' ')
  # shellcheck disable=SC2086
  az network nsg rule update -g "$RG" --nsg-name "$NSG" -n "$RULE" --source-address-prefixes $NEW -o none
  echo "$RULE: $NEW"
done
