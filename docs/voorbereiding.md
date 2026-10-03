# Voorbereiding – actielijst

Alles wat af moet zijn vóór de hackathon op vrijdag 9 oktober 2026, 13:00. Bron: het hoofdstuk *Voorbereiding* in [`blauwdruk.html`](blauwdruk.html) en de opbouwstappen in de [README](../README.md).

**Bijwerken:** vink af met `[x]`, zet erachter wie het deed en eventueel een korte notitie (`— Eddie, 4 okt: 2 retries nodig`). Wijkt iets af van het ontwerp, werk dan ook de blauwdruk bij.

Stand: 3 oktober 2026.

## A. Vooraf (gepland do 1 – vr 2 okt)

- [ ] **A1** Entra-testtenant aanmaken (Workforce) met eigen beheeraccount en MFA
- [ ] **A2** Domein `techeddie.dev` verifiëren in de testtenant (TXT-record in Cloudflare). Al geverifieerd in een andere tenant? Dan een subdomein, bv. `id.techeddie.dev`
- [ ] **A3** P2-trial activeren in de testtenant (30 dagen, moet t/m 9 okt lopen). Entra Suite-trial alleen is niet genoeg
- [ ] **A4** vCPU-quotum voor Dsv5 in Sweden Central controleren (8 nodig)
- [x] **A5** Private GitHub-repo aanmaken (`Fortigi/IAM-Hackathon-JIT`)
- [ ] **A6** Teamgenoten uitnodigen als collaborator op de repo
- [ ] **A7** IP-adressen verzamelen: vast kantoor-IP plus drie thuis-IP's → `EXTRA_ALLOWED_IPS` in `hackathon.env`
- [ ] **A8** K9 besluiten (advies: S2, Entra-rol via role-assignable groep) en de blauwdruk bijwerken
- [ ] **A9** Laptop: `az login`, PowerShell 7 met `Microsoft.Graph.Authentication`, `brew install lego`, `hackathon.env` ingevuld

## B. Zaterdag 3 okt – infrastructuur, authentik, Corteza, Entra

- [x] **B1** DNS-zone `jit.techeddie.dev` in Azure en NS-delegatie in Cloudflare (`dig NS jit.techeddie.dev +short` toont de Azure-nameservers)
- [ ] **B2** Certificaatketen testen met de staging-CA: `./infra/test-cert-staging.sh <e-mail>`
- [ ] **B3** `./infra/deploy.sh`: VM, NSG, statisch IP, A-records. Klaar als `dig A wiki.jit.techeddie.dev +short` het publieke IP geeft
- [ ] **B4** VM inrichten: `cloud-init status --wait`, repo clonen naar `/opt/jit/repo`, `./scripts/vm-bootstrap.sh`
- [ ] **B5** Traefik met wildcard-certificaat (productie-CA): geldig slotje op `https://wiki.jit.techeddie.dev`
- [ ] **B6** authentik met blueprint: users, groepen, Team Wiki-proxy, Corteza-OIDC-client, `sa-jit-orchestrator` met token
- [ ] **B7** authentik: MFA-stage voor de admin-app *(snijlijn: mag een hackathon-taak worden)*
- [ ] **B8** Corteza: eerste lokale account aanmaken (wordt beheerder), OIDC naar authentik instellen, inloggen als anna.jansen
- [ ] **B9** Entra seeden: `pwsh ./seed/entra/seed-entra.ps1 -TenantId <guid>` (users, P2-licenties, groepen, apps, role-assignable groepen, service principals met consent)
- [ ] **B10** Entra-waarden uit `seed/entra/out/entra-seed.json` in `compose/.env` op de VM; `./scripts/vm-bootstrap.sh --force-midpoint-objects` en midPoint herstarten
- [ ] **B11** PIM-groepen één keer onder PIM brengen (PIM > Groups > Discover groups), daarna `pim-policy.ps1 -Action apply` en `-Action diff` geeft geen verschillen
- [ ] **B12** MFA registreren voor bram.devries en dirk.visser

## C. Zondag 4 okt – midPoint, koppelingen bewijzen, scripts

- [ ] **C1** midPoint: *Test connection* op *HR (CSV)* en *Entra (testtenant)*. Eerst testen of de MS Graph-connector met 4.10 werkt; zo niet, terugval: Corteza roept Graph aan, midPoint registreert alleen
- [ ] **C2** HR- en Entra-reconciliatie: zes gebruikers, gekoppeld op `employeeId`
- [ ] **C3** `./scripts/midpoint-tune.sh`: validity scanner op 60 seconden
- [ ] **C4** Bewijs ENT-03: assignment met `validTo` over 5 min zet anna.jansen in `app-finance-readers` en haalt haar er na afloop weer uit
- [ ] **C5** Bewijs ENT-04: connector kan lidmaatschap van role-assignable groep `priv-entra-helpdesk-admins` wijzigen. Zo niet: ENT-04 valt terug op S3 (app-rol)
- [ ] **C6** Bewijs `svc-corteza`: gebruiker zoeken en assignment toevoegen via midPoint REST
- [ ] **C7** Bewijs authentik-API met `sa-jit-orchestrator`: `add_user`, `remove_user`, sessies opvragen en verwijderen
- [ ] **C8** Bewijs PIM met `sp-jit-orchestrator`: eligibility-request op een PIM-groep, ook op de role-assignable groep (blijkt of `RoleManagement.ReadWrite.Directory` nodig is)
- [ ] **C9** Bewijs Corteza: een workflow die een assignment in midPoint aanmaakt
- [ ] **C10** Drift-test: handmatig lid in `app-finance-readers` wordt na reconciliatie teruggedraaid (niet-tolerante groepsassociatie)
- [ ] **C11** Negatieve tests: Team Wiki geweigerd zonder groep, jwt.ms geeft AADSTS50105 zonder toewijzing
- [ ] **C12** Scripts testen: `smoke.sh`, `save-work.sh`, `allow-my-ip.sh`, `reset-entra.ps1`
- [ ] **C13** `./scripts/snapshot.sh all` (golden dumps), daarna `reset.sh` per component getest en getimed
- [ ] **C14** Teamleden *Network Contributor* op `iam-hackathon-jit-rg` (zie README stap 7)
- [ ] **C15** `CLAUDE.md`/`AGENTS.md`, README en blauwdruk bijwerken met wat in het weekend anders bleek

## D. Maandag 5 – dinsdag 6 okt – team

- [ ] **D1** Secrets delen via de gedeelde kluis (wachtwoorden, tokens, client secrets)
- [ ] **D2** Teamgenoot 1: `allow-my-ip.sh`, overal inloggen, één API-call per systeem
- [ ] **D3** Teamgenoot 2: idem
- [ ] **D4** Sporen verdelen: wie doet spoor 1 (Corteza), 2 (midPoint en Entra), 3 (authentik-connector)
- [ ] **D5** Spoor 3: ConnDev lokaal bouwen en een lege bundle laten laden in de midPoint-container. Lukt dat niet: spoor 3 vervalt

## E. Woensdag 7 of donderdag 8 okt – dry-run

- [ ] **E1** Dry-run op afstand (45 min): klaar-checklist hieronder plus één reset
- [ ] **E2** Golden dumps verversen (`snapshot.sh all`)
- [ ] **E3** Azure disk-snapshot maken
- [ ] **E4** Kantoor-IP in de allowlist; P2-trial loopt nog

## F. Vrijdag 9 okt

- [ ] **F1** 12:00 VM aan, kantoor-IP in de allowlist, `smoke.sh`
- [ ] **F2** 12:45 iedereen ingelogd op alle GUI's
- [ ] **F3** 13:00 kick-off

## Klaar-checklist (voor de dry-run)

- [ ] Alle vijf hostnamen openen met geldig certificaat vanaf alle drie laptops
- [ ] Elke testgebruiker kan inloggen in authentik en Entra; MFA voor bram.devries en dirk.visser geregistreerd
- [ ] midPoint toont alle zes gebruikers, gekoppeld aan hun Entra-account
- [ ] Corteza-workflow maakt een assignment aan in midPoint
- [ ] midPoint kent een Entra-groep toe en trekt hem na `validTo` weer in; reconciliatie meldt geen verschillen
- [ ] authentik add/remove en een PIM-eligibility-request werken met de service-accounts
- [ ] Negatieve tests werken (Team Wiki geweigerd, AADSTS50105)
- [ ] `reset.sh` per component getest en getimed

## Open vragen

- [ ] K9: privileged recht zonder P2 (advies S2) → zie A8
- [ ] Is `techeddie.dev` al geverifieerd in een andere Entra-tenant? → zie A2
- [ ] Vast uitgaand kantoor-IP → zie A7

## Snijlijnen

Loopt het weekend uit, laat dan in deze volgorde vallen: Key Vault, Dozzle, Postman-collectie, ENT-05 HR Portal, golden dumps (terugval: rebuild plus disk-snapshot), MFA-stage authentik admin-app (B7).
