---
keywords:
- keycloak
- seed-info.json
- seeded lab
- resource ids
- token endpoint
- protection api
- credentials
- readiness
times_used: 0
times_useful: 0
---

Successful Keycloak PoC runners in this lab should read `/opt/keycloak-data/seed-info.json` instead of hard-coding realm details, client credentials, or resource IDs.

Fields used directly by the successful runner were:

- `.realm`
- `.token_endpoint`
- `.protection_api_base`
- `.client.client_id`
- `.client.client_secret`
- `.attacker.username`
- `.attacker.password`
- `.attacker.resource_id`
- `.attacker.resource_name`
- `.victim.resource_id`
- `.victim.resource_name`

Practical use:

- Build the OIDC token endpoint and protection API calls from the JSON metadata.
- Read attacker and victim resource IDs from the seed file so the PoC survives reseeds and ID churn.
- Emit a per-run `context.json` snapshot into the evidence directory so later checks can correlate the exact seeded IDs and endpoints used.

The successful runner also paired this with a readiness gate against `http://127.0.0.1:9000/health/ready` before making any authz calls.