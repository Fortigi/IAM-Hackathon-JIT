#!/usr/bin/env bash
# Maakt alvast de resourcegroep en de Azure DNS-zone aan, zodat je de NS-delegatie in
# Cloudflare kunt zetten en laten propageren vóór de rest van de uitrol.
# deploy.sh (Bicep) neemt de bestaande zone later gewoon over; de nameservers blijven gelijk.
set -euo pipefail
cd "$(dirname "$0")/.."
# shellcheck disable=SC1091
source hackathon.env
az account set --subscription "$AZ_SUBSCRIPTION_ID"
az group create -n "$AZ_RG" -l "$AZ_LOCATION" -o none
az network dns zone create -g "$AZ_RG" -n "$DNS_ZONE" -o none
echo "Zet deze NS-records in Cloudflare voor 'jit' (type NS, naam jit):"
az network dns zone show -g "$AZ_RG" -n "$DNS_ZONE" --query nameServers -o tsv
