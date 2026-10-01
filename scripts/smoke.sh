#!/usr/bin/env bash
# Snelle rooktest van alle hostnamen (draai op laptop of VM).
set -uo pipefail
D=${DOMAIN:-jit.techeddie.dev}
for h in auth portal midpoint wiki logs; do
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 "https://$h.$D/")
  cert=$(echo | openssl s_client -servername "$h.$D" -connect "$h.$D:443" 2>/dev/null | openssl x509 -noout -issuer 2>/dev/null | sed 's/issuer=//')
  printf '%-10s HTTP %s  cert: %s\n' "$h" "$code" "${cert:-?}"
done
echo "Verwacht: auth/portal 200 of 302, midpoint 302, wiki/logs 302 (redirect naar authentik)."
