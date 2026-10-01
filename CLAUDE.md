# CLAUDE.md – IAM Hackathon JIT

Context voor AI-assistenten (Claude Code, Codex) die in deze repo werken. Houd `AGENTS.md` gelijk aan dit bestand.

## Doel

Just-in-Time toegang bouwen in een halve dag. Een gebruiker vraagt tijdelijke toegang aan in **Corteza**, een goedkeurder keurt goed, de grant wordt in **midPoint** vastgelegd met een einddatum, en de toegang verdwijnt vanzelf na afloop.

## Wie doet wat (besloten ontwerp)

| Doelsysteem | Uitvoering | Wie trekt in |
|---|---|---|
| Entra zonder P2 (ENT-03, ENT-04) | midPoint, MS Graph-connector | midPoint validity scanner |
| authentik (ENT-01, ENT-02) | Corteza roept authentik-API aan | Corteza revoke-workflow (later midPoint-connector) |
| Entra met P2 (ENT-05, ENT-06) | Corteza maakt PIM-eligibility met einddatum | Entra PIM |

midPoint registreert **elke** grant als assignment op de catalogusrol, met `activation/validTo`.

## Omgeving

- Domein: `jit.techeddie.dev`; Entra-testtenant met UPN-suffix `techeddie.dev`
- Hosts: `portal.` (Corteza), `midpoint.` (midPoint, pad `/midpoint/`), `auth.` (authentik), `wiki.` (testapp), `logs.` (Dozzle)
- Alles draait op één Azure-VM met Docker Compose (`compose/docker-compose.yml`, project `jit`)
- Tijden altijd in **UTC ISO 8601** (`2026-10-09T11:05:00Z`)

## Catalogus

| ID | Recht | Doel | Groep | midPoint-rol OID |
|---|---|---|---|---|
| ENT-01 | Team Wiki gebruiker | authentik | app-wiki-users | 98b404e9-06bb-47d0-9aca-38b4337c685e |
| ENT-02 | authentik beheerder | authentik | priv-authentik-admins | e2db27be-590f-4c81-915f-927bc4d3c09a |
| ENT-03 | Finance Portal lezer | Entra | app-finance-readers | 46c3bb43-ebcc-44c3-a0e6-4c161505e071 |
| ENT-04 | Entra Helpdesk Administrator | Entra (role-assignable) | priv-entra-helpdesk-admins | b78d0d13-b274-4f33-8d4c-4281cebea8ef |
| ENT-05 | HR Portal editor | Entra PIM | pim-app-hr-editors | d33f888e-3dfe-4115-b91e-f7e31a0cfec3 |
| ENT-06 | Entra User Administrator | Entra PIM (role-assignable) | pim-entra-user-admins | d4785e33-f647-4dec-b064-1ce02742f652 |

Testgebruikers: `seed/users.csv` (anna.jansen, bram.devries, carla.bakker = manager, dirk.visser = resource owner, eva.smit = security, gijs.oud = uit dienst).

## API's

Secrets staan in `compose/.env` op de VM en `seed/entra/out/entra-seed.json` op de laptop. Lees ze uit omgevingsvariabelen; zet ze nooit in code of commits.

### midPoint REST (basic auth, `svc-corteza`)

```bash
MP=https://midpoint.jit.techeddie.dev/midpoint/ws/rest
# gebruiker zoeken
curl -u svc-corteza:$MP_SVC_CORTEZA_PASSWORD -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -X POST $MP/users/search -d '{"query":{"filter":{"text":"name = \"anna.jansen\""}}}'
# grant aanmaken: assignment met einddatum
curl -u svc-corteza:$MP_SVC_CORTEZA_PASSWORD -H 'Content-Type: application/json' -X PATCH $MP/users/<user-oid> -d '{
 "objectModification":{"itemDelta":{"modificationType":"add","path":"assignment",
  "value":{"targetRef":{"oid":"46c3bb43-ebcc-44c3-a0e6-4c161505e071","type":"RoleType"},
           "activation":{"validTo":"2026-10-09T11:15:00Z"},"description":"JIT REQ-0001"}}}}'
```

### authentik API (Bearer, service account `sa-jit-orchestrator`)

```bash
AK=https://auth.jit.techeddie.dev/api/v3
H="Authorization: Bearer $AK_ORCHESTRATOR_TOKEN"
curl -H "$H" "$AK/core/users/?username=anna.jansen"                 # user pk
curl -H "$H" "$AK/core/groups/?name=app-wiki-users"                 # group uuid (pk)
curl -H "$H" -H 'Content-Type: application/json' -X POST "$AK/core/groups/<group-pk>/add_user/" -d '{"pk": <user-pk>}'
curl -H "$H" -H 'Content-Type: application/json' -X POST "$AK/core/groups/<group-pk>/remove_user/" -d '{"pk": <user-pk>}'
curl -H "$H" "$AK/core/authenticated_sessions/?user__username=anna.jansen"   # daarna DELETE per uuid
```

### Microsoft Graph (client credentials, `sp-jit-orchestrator`)

```bash
TOKEN=$(curl -s -X POST "https://login.microsoftonline.com/$ENTRA_TENANT_ID/oauth2/v2.0/token" \
  -d client_id=$ORCH_CLIENT_ID -d client_secret=$ORCH_CLIENT_SECRET \
  -d scope=https://graph.microsoft.com/.default -d grant_type=client_credentials | jq -r .access_token)
# P-b: eligibility met einddatum
curl -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' -X POST \
  https://graph.microsoft.com/v1.0/identityGovernance/privilegedAccess/group/eligibilityScheduleRequests -d '{
  "accessId":"member","principalId":"<user-id>","groupId":"<group-id>","action":"adminAssign",
  "justification":"REQ-0001","scheduleInfo":{"startDateTime":"2026-10-09T11:05:00Z",
  "expiration":{"type":"afterDuration","duration":"P1D"}}}'
```

PIM: toewijzingen minimaal 5 minuten, en niet binnen 5 minuten na toekennen in te trekken.

## Regels

- Alleen de testtenant. Service principals hebben zware rechten (`RoleManagement.ReadWrite.Directory`).
- Geen secrets in git. `compose/.env`, `hackathon.env` en `seed/entra/out/` staan in `.gitignore`.
- JIT-groepen krijgen hun leden alleen via de JIT-flow, nooit via seeds of blueprints.
- Voor je iets kapot maakt: `./scripts/save-work.sh`. Terugzetten: `./scripts/reset.sh <component>`.
- midPoint-objecten staan als template in `seed/midpoint/templates` (`${VAR}` wordt door `vm-bootstrap.sh` ingevuld). Wijzig de template, niet alleen de runtime-kopie.
