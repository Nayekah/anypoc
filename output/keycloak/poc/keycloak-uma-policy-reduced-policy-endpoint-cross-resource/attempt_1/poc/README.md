# Keycloak cross-user UMA policy PoC

Run `./run_poc.sh` once against the seeded local lab. It authenticates as
Marta, verifies that Marta is initially denied `Scope A` on Kolo's resource,
posts a policy through Marta's resource route while naming Kolo's resource in
the JSON body, and verifies both the changed decision and the resulting RPT
permission. Raw request/response evidence is written to
`/home/playground/output/attempt_1/evidence`.
