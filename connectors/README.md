# Connectoren (hackathon-spoor 3)

Hier komt de midPoint-connector voor authentik, gebouwd met Evolveum ConnDev
(https://github.com/Evolveum/conndev) en Claude Code.

Minimale scope voor 9 oktober:
- objectklassen `User` en `Group` lezen (`/api/v3/core/users/`, `/api/v3/core/groups/`)
- lidmaatschap toevoegen en verwijderen (`add_user` / `remove_user` op de groep)
- optioneel: bij verwijderen ook de sessies van de gebruiker intrekken

Voorbereiding (± 1 uur, in de week voor de hackathon): ConnDev lokaal bouwen en een lege
bundle in `compose/runtime/midpoint/connid-connectors/` laten laden door midPoint.
Lukt dat niet, dan valt dit spoor af; de Corteza-route voor authentik werkt al.

Authenticatie: Bearer-token van service account `sa-jit-orchestrator` (`AK_ORCHESTRATOR_TOKEN`).
