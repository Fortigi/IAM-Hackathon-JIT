#!/usr/bin/env bash
# Proefcertificaat via de Let's Encrypt staging-CA en DNS-01 op Azure DNS, vanaf je laptop.
# Bewijst dat de NS-delegatie en de DNS-challenge werken, nog voordat de VM bestaat.
# Vereist: lego v5 (brew install lego), az login met schrijfrechten op de DNS-zone, hackathon.env.
#   ./infra/test-cert-staging.sh <e-mailadres>
set -euo pipefail
cd "$(dirname "$0")/.."
EMAIL=${1:?gebruik: ./infra/test-cert-staging.sh <e-mailadres>}
# shellcheck disable=SC1091
source hackathon.env

export AZURE_AUTH_METHOD=cli
export AZURE_SUBSCRIPTION_ID=$AZ_SUBSCRIPTION_ID
export AZURE_RESOURCE_GROUP=$AZ_RG
export AZURE_ZONE_NAME=$DNS_ZONE

OUT=$(mktemp -d)
echo "== NS-delegatie:"; dig NS "$DNS_ZONE" @1.1.1.1 +short || true
echo "== Staging-certificaat aanvragen (opslag: $OUT)"
lego run --path "$OUT" --server letsencrypt-staging --accept-tos \
  --email "$EMAIL" --dns azuredns -d "$DNS_ZONE" -d "*.$DNS_ZONE"
echo
find "$OUT" -name '*.crt' ! -name '*.issuer.crt' -exec openssl x509 -noout -subject -issuer -ext subjectAltName -in {} \;
echo
echo "Gelukt als de uitgever '(STAGING)' bevat. Opruimen: rm -rf $OUT"
