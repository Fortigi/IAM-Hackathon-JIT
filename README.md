# IAM Hackathon – JIT

Just-in-Time toegang (normaal en privileged) met **Corteza** als aanvraagportaal, **midPoint** als register en uitvoerder, en **authentik** en **Microsoft Entra** (met en zonder P2/PIM) als doelsystemen.

- Hackathon: vrijdag 9 oktober 2026, 13:00–17:00
- Ontwerp en keuzes: [`docs/blauwdruk.html`](docs/blauwdruk.html)
- Werkafspraken voor Claude Code en Codex: [`CLAUDE.md`](CLAUDE.md) / [`AGENTS.md`](AGENTS.md)

| Dienst | URL | Inloggen |
|---|---|---|
| Portaal (Corteza) | https://portal.jit.techeddie.dev | via authentik |
| midPoint | https://midpoint.jit.techeddie.dev/midpoint/ | `administrator` / `MP_ADMIN_PASSWORD` |
| authentik | https://auth.jit.techeddie.dev | `akadmin` / `AK_BOOTSTRAP_PASSWORD`, of `hack-*` |
| Team Wiki (testapp) | https://wiki.jit.techeddie.dev | testgebruiker met groep `app-wiki-users` |
| Logs (Dozzle) | https://logs.jit.techeddie.dev | `hack-*` |

Alle wachtwoorden staan in `compose/.env` op de VM en in de gedeelde kluis. Nooit in git.

## Repo-indeling

```
infra/        Bicep (VM, NSG, IP, DNS-zone), cloud-init, deploy.sh
compose/      docker-compose.yml en .env.example
seed/         users.csv (bron voor alles), authentik-blueprint, Entra-scripts, midPoint-objecten
scripts/      vm-bootstrap, snapshot, reset, save-work, allow-my-ip, smoke, midpoint-tune
docs/         blauwdruk
connectors/   ruimte voor de authentik-connector (hackathon-spoor 3)
```

## Opbouw (weekend 3–4 oktober)

### 0. Laptop voorbereiden

- `az login` en de juiste subscription
- PowerShell 7 met `Install-Module Microsoft.Graph.Authentication -Scope CurrentUser`
- `cp hackathon.env.example hackathon.env` en invullen (subscription, SSH-sleutel)
- Entra: P2-trial actief in de testtenant, domein `techeddie.dev` geverifieerd

### 1. Infrastructuur

```bash
./infra/deploy.sh
```

Het script voegt je huidige publieke IP toe aan de allowlist en print de vier Azure-nameservers. Zet die in Cloudflare als **NS-records voor `jit`** (DNS only). Controle:

```bash
dig NS jit.techeddie.dev +short     # moet de Azure-nameservers tonen
dig A wiki.jit.techeddie.dev +short # moet het publieke IP tonen
```

### 2. VM inrichten

```bash
ssh -A jitadmin@<publiek-ip>
cloud-init status --wait
git clone git@github.com:ehuibers/IAM-Hackathon-JIT.git /opt/jit/repo
cd /opt/jit/repo
./scripts/vm-bootstrap.sh
```

Tip: zet bij de eerste run `ACME_CA_SERVER=https://acme-staging-v02.api.letsencrypt.org/directory` in `compose/.env` tot alles werkt; daarna weghalen, het volume `jit_letsencrypt` verwijderen en Traefik herstarten.

### 3. Entra seeden (vanaf de laptop)

```bash
pwsh ./seed/entra/seed-entra.ps1 -TenantId <tenant-guid>
```

Gebruik hetzelfde wachtwoord als `TEST_USER_PASSWORD` in `compose/.env`. Het script schrijft `seed/entra/out/entra-seed.json` met id's en secrets. Zet op de VM in `compose/.env`:

```
ENTRA_TENANT_ID=...
ENTRA_MIDPOINT_CLIENT_ID=...       # servicePrincipals.sp-jit-midpoint.clientId
ENTRA_MIDPOINT_CLIENT_SECRET=...   # servicePrincipals.sp-jit-midpoint.clientSecret
```

en draai `./scripts/vm-bootstrap.sh --force-midpoint-objects && (cd compose && docker compose restart midpoint)`.

Meldt het script dat er nog geen PIM-policy is voor een PIM-groep: open de groep één keer in Entra > PIM > Groups > Discover groups en draai het script opnieuw.

### 4. midPoint

1. Inloggen als `administrator`. In Resources: **Test connection** op *HR (CSV)* en *Entra (testtenant)*.
2. Taken *HR-reconciliatie* en *Entra-reconciliatie* draaien: 6 gebruikers, gekoppeld aan hun Entra-account.
3. `./scripts/midpoint-tune.sh` zet de Validity Scanner op 60 seconden.
4. Test: geef anna.jansen rol *ENT-03* met een einddatum over 5 minuten. Ze verschijnt in `app-finance-readers` en verdwijnt na afloop.

De midPoint-objecten (`seed/midpoint/templates`) zijn niet in een draaiende midPoint getest. Ze volgen de voorbeelden van Evolveum; reken op wat bijwerk.

### 5. Corteza

1. Open het portaal en registreer eerst een lokaal account: **de eerste gebruiker wordt beheerder**.
2. Admin > System > Settings > External authentication > OpenID Connect toevoegen:
   - Issuer: `https://auth.jit.techeddie.dev/application/o/corteza/`
   - Client ID: `corteza`
   - Client secret: `CORTEZA_OIDC_CLIENT_SECRET` uit `compose/.env`
3. Uitloggen, inloggen met *authentik* als anna.jansen.

### 6. Controleren en vastleggen

```bash
./scripts/smoke.sh
./scripts/snapshot.sh all        # dit wordt de golden stand voor reset.sh
```

Plus de checklist in de blauwdruk (iedereen kan overal in, negatieve tests werken).

### 7. Teamleden toegang geven

```bash
# Network Contributor zodat allow-my-ip.sh werkt
az role assignment create --assignee <upn-teamlid> --role "Network Contributor" \
  --scope $(az group show -n rg-jit-hackathon --query id -o tsv)
```

Teamleden draaien daarna zelf `./scripts/allow-my-ip.sh`.

## Tijdens de hackathon

| Wat | Commando (op de VM, in `/opt/jit/repo`) |
|---|---|
| Werk bewaren | `./scripts/save-work.sh` |
| Eén component terugzetten | `./scripts/reset.sh authentik` (of `midpoint`, `corteza`) |
| Alles terugzetten | `./scripts/reset.sh all`, daarna `reset-entra.ps1` vanaf de laptop en Entra-reconciliatie in midPoint |
| Logs | https://logs.jit.techeddie.dev of `docker compose -f compose/docker-compose.yml logs -f <dienst>` |
| IP toevoegen | `./scripts/allow-my-ip.sh` (laptop) |

## Snijlijnen als het weekend uitloopt

1. Dozzle weglaten (`docker compose logs` volstaat)
2. ENT-05 HR Portal (één PIM-groep is genoeg)
3. Golden snapshots → terugvallen op opnieuw opbouwen plus Azure disk-snapshot
4. Step-up MFA voor de authentik admin-app wordt een hackathon-taak
