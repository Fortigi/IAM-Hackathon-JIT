#!/usr/bin/env bash
# Draai op de VM vanuit de repo-root (bv. /opt/jit/repo):  ./scripts/vm-bootstrap.sh
# - maakt compose/.env met gegenereerde secrets (eenmalig)
# - rendert midPoint-objecten, kopieert de HR-CSV, haalt de MS Graph-connector op
# - start alle containers
# Opnieuw draaien is veilig: bestaande .env en al geïmporteerde midPoint-objecten blijven staan.
# Optie --force-midpoint-objects rendert de midPoint-objecten opnieuw (worden bij herstart opnieuw geïmporteerd).
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT=$(pwd)
ENV=compose/.env
RT=compose/runtime/midpoint
FORCE_MP=false
[[ "${1:-}" == "--force-midpoint-objects" ]] && FORCE_MP=true

rand() { openssl rand -hex "${1:-24}"; }

# ---------------------------------------------------------------- .env
if [[ ! -f $ENV ]]; then
  echo "== compose/.env aanmaken"
  IMDS=$(curl -fsS -H Metadata:true "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01" || echo '{}')
  SUB=$(jq -r '.subscriptionId // "CHANGEME"' <<<"$IMDS")
  RG=$(jq -r '.resourceGroupName // "iam-hackathon-jit-rg"' <<<"$IMDS")
  read -rp "E-mailadres voor Let's Encrypt en de authentik-beheerder: " ACME
  sed -e "s|^ACME_EMAIL=.*|ACME_EMAIL=$ACME|" \
      -e "s|^AZ_SUBSCRIPTION_ID=.*|AZ_SUBSCRIPTION_ID=$SUB|" \
      -e "s|^AZ_RG=.*|AZ_RG=$RG|" \
      -e "s|^AK_DB_PASS=.*|AK_DB_PASS=$(rand)|" \
      -e "s|^AK_SECRET_KEY=.*|AK_SECRET_KEY=$(rand 40)|" \
      -e "s|^AK_BOOTSTRAP_PASSWORD=.*|AK_BOOTSTRAP_PASSWORD=$(rand 12)|" \
      -e "s|^AK_BOOTSTRAP_TOKEN=.*|AK_BOOTSTRAP_TOKEN=$(rand 32)|" \
      -e "s|^AK_ORCHESTRATOR_TOKEN=.*|AK_ORCHESTRATOR_TOKEN=$(rand 32)|" \
      -e "s|^CORTEZA_OIDC_CLIENT_SECRET=.*|CORTEZA_OIDC_CLIENT_SECRET=$(rand 32)|" \
      -e "s|^TEST_USER_PASSWORD=.*|TEST_USER_PASSWORD=Jit-$(rand 6)!|" \
      -e "s|^HACK_ADMIN_PASSWORD=.*|HACK_ADMIN_PASSWORD=Hack-$(rand 8)!|" \
      -e "s|^MP_DB_PASS=.*|MP_DB_PASS=$(rand)|" \
      -e "s|^MP_ADMIN_PASSWORD=.*|MP_ADMIN_PASSWORD=Mp-$(rand 8)!|" \
      -e "s|^MP_SVC_CORTEZA_PASSWORD=.*|MP_SVC_CORTEZA_PASSWORD=Svc-$(rand 12)!|" \
      -e "s|^CORTEZA_DB_PASS=.*|CORTEZA_DB_PASS=$(rand)|" \
      compose/.env.example > $ENV
  chmod 600 $ENV
  echo "   Klaar. Zet de wachtwoorden in de gedeelde kluis: grep -E 'PASSWORD|TOKEN|SECRET' $ENV"
  echo "   Vul ENTRA_* in na seed-entra.ps1 en draai dit script opnieuw met --force-midpoint-objects."
fi
set -a
# shellcheck source=/dev/null
source "$ENV"
set +a
export JIT_UPN_DOMAIN=${JIT_UPN_DOMAIN:-techeddie.dev}

# ---------------------------------------------------------------- midPoint runtime
mkdir -p $RT/post-initial-objects $RT/connid-connectors $RT/resource_files
cp seed/users.csv $RT/resource_files/hr.csv

VARS='${JIT_UPN_DOMAIN} ${ENTRA_TENANT_ID} ${ENTRA_MIDPOINT_CLIENT_ID} ${ENTRA_MIDPOINT_CLIENT_SECRET} ${MP_SVC_CORTEZA_PASSWORD}'
for tpl in seed/midpoint/templates/*.xml; do
  name=$(basename "$tpl"); dst=$RT/post-initial-objects/$name
  if [[ "$name" == 020-resource-entra.xml && "${ENTRA_TENANT_ID:-CHANGEME}" == CHANGEME ]]; then
    echo "   $name overgeslagen: ENTRA_* nog niet ingevuld"; continue
  fi
  if $FORCE_MP || [[ ! -f $dst && ! -f $dst.done ]]; then
    envsubst "$VARS" < "$tpl" > "$dst"; rm -f "$dst.done"; echo "   midPoint-object klaargezet: $name"
  fi
done

# MS Graph-connector (niet meegeleverd met midPoint)
MSG_VER=${MSGRAPH_CONNECTOR_VERSION:-1.2.0.0}
JAR=$RT/connid-connectors/connector-msgraph-$MSG_VER.jar
if [[ ! -f $JAR ]]; then
  URL="https://nexus.evolveum.com/nexus/repository/releases/com/evolveum/polygon/connector-msgraph/$MSG_VER/connector-msgraph-$MSG_VER.jar"
  echo "== MS Graph-connector ophalen: $URL"
  if ! curl -fsSL "$URL" -o "$JAR"; then
    rm -f "$JAR"
    echo "   Download mislukt; bouwen vanaf broncode (tag v$MSG_VER) met Maven in Docker"
    TMP=$(mktemp -d)
    git clone --depth 1 --branch "v$MSG_VER" https://github.com/Evolveum/connector-microsoft-graph-api "$TMP/src"
    docker run --rm -v "$TMP/src:/src" -w /src maven:3-eclipse-temurin-17 mvn -q -DskipTests package
    cp "$TMP"/src/target/connector-msgraph-*.jar "$JAR"
  fi
fi
chmod -R a+rwX compose/runtime

# ---------------------------------------------------------------- Starten
cd compose
docker compose pull
docker compose up -d
docker compose ps
cd "$ROOT"
echo
echo "== Klaar. Controleer met ./scripts/smoke.sh. midPoint heeft bij de eerste start enkele minuten nodig."
