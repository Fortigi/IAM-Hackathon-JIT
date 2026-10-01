#!/usr/bin/env bash
# Rolt de Azure-infrastructuur uit. Draai vanaf je laptop in de repo-root:
#   ./infra/deploy.sh
# Vereist: az (ingelogd), hackathon.env in de repo-root.
set -euo pipefail
cd "$(dirname "$0")/.."
[[ -f hackathon.env ]] || { echo "hackathon.env ontbreekt (kopieer hackathon.env.example)"; exit 1; }
# shellcheck disable=SC1091
source hackathon.env

MYIP=$(curl -fsS https://api.ipify.org)
echo "Je huidige publieke IP: $MYIP (wordt toegevoegd aan de allowlist)"
IPS_JSON=$(printf '%s\n' "$MYIP/32" ${EXTRA_ALLOWED_IPS} | jq -R . | jq -sc 'unique')

az account set --subscription "$AZ_SUBSCRIPTION_ID"
az group create -n "$AZ_RG" -l "$AZ_LOCATION" -o none

SSH_KEY=$(cat "${SSH_PUBLIC_KEY_FILE/#\~/$HOME}")

az deployment group create \
  -g "$AZ_RG" -n "jit-$(date +%Y%m%d%H%M)" \
  -f infra/main.bicep \
  -p location="$AZ_LOCATION" prefix="$PREFIX" dnsZoneName="$DNS_ZONE" \
     adminUsername="$ADMIN_USERNAME" sshPublicKey="$SSH_KEY" vmSize="$VM_SIZE" \
     allowedSourceIps="$IPS_JSON" \
  --query properties.outputs -o json | tee infra/last-deploy.json

echo
echo "== Zet deze NS-records in Cloudflare voor 'jit' (DNS only):"
jq -r '.nameServers.value[]' infra/last-deploy.json
echo
echo "== SSH: ssh -A $ADMIN_USERNAME@$(jq -r '.publicIp.value' infra/last-deploy.json)"
