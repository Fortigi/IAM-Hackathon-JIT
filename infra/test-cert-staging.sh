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

# Publieke resolvers gebruiken, niet de lokale DNS (die kan een oude NXDOMAIN gecached hebben)
RESOLVERS=${RESOLVERS:-1.1.1.1:53,8.8.8.8:53}

echo "== NS-delegatie volgens 1.1.1.1:"
NS=$(dig NS "$DNS_ZONE" @1.1.1.1 +short)
echo "${NS:-<geen>}"
if ! grep -q azure-dns <<<"$NS"; then
  echo "FOUT: $DNS_ZONE is (nog) niet gedelegeerd naar Azure DNS. Controleer de NS-records in Cloudflare."
  echo "      Diagnose: dig +trace NS $DNS_ZONE"
  exit 1
fi

OUT=$(mktemp -d)
echo "== Staging-certificaat aanvragen (opslag: $OUT, resolvers: $RESOLVERS)"
lego run --path "$OUT" --server letsencrypt-staging --accept-tos \
  --email "$EMAIL" --dns azuredns --dns.resolvers "$RESOLVERS" \
  -d "$DNS_ZONE" -d "*.$DNS_ZONE"
echo
find "$OUT" -name '*.crt' ! -name '*.issuer.crt' -exec openssl x509 -noout -subject -issuer -ext subjectAltName -in {} \;
echo
echo "Gelukt als de uitgever '(STAGING)' bevat. Opruimen: rm -rf $OUT"
