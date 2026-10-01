# Keycloak UMA cross-resource ownership PoC

Run `./run_poc.sh` while the supplied Keycloak lab is running. The runner:

1. authenticates as ordinary user `marta`;
2. records a denied UMA decision for Kolo's resource and `Scope A`;
3. posts a policy on Marta's resource route whose JSON references both resources;
4. verifies the same decision becomes `200 {"result":true}`;
5. deletes the policy through Marta's endpoint and verifies denial is restored.

Raw redacted requests and responses are written to `/home/playground/output/attempt_1/evidence`.
The policy is deleted on both success and failure cleanup paths.
