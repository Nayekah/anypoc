Path to source code:

- `/opt/keycloak-source`
- Vulnerable class: `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java`
- Upstream regression test: `/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java`

Key runtime paths:

- Keycloak distribution: `/opt/keycloak`
- Server launcher: `/opt/keycloak/bin/kc.sh`
- Admin CLI: `/opt/keycloak/bin/kcadm.sh`
- Service health helper: `/opt/keycloak-lab/scripts/keycloak_status.sh`
- Seed script: `/opt/keycloak-lab/scripts/seed_lab.sh`
- Seed metadata: `/opt/keycloak-data/seed-info.json`
- Server log: `/var/log/keycloak/server.log`

Runtime endpoints:

- Base URL: `http://127.0.0.1:8080`
- Health: `http://127.0.0.1:9000/health/ready`
- Master realm token: `http://127.0.0.1:8080/realms/master/protocol/openid-connect/token`
- Lab realm token: `http://127.0.0.1:8080/realms/anypoc/protocol/openid-connect/token`
- Protection API base: `http://127.0.0.1:8080/realms/anypoc/authz/protection`
- Resource registration endpoint: `http://127.0.0.1:8080/realms/anypoc/authz/protection/resource_set`
- Vulnerable UMA policy endpoint shape: `http://127.0.0.1:8080/realms/anypoc/authz/protection/uma-policy/{resourceId}`

Seeded credentials:

- Admin: `admin` / `adminpass`
- Attacker user: `marta` / `password`
- Victim user: `kolo` / `password`
- Protected client: `resource-server-test`
- Protected client secret: `secret`

Seeded lab facts:

- Realm: `anypoc`
- Authz-enabled client: `resource-server-test`
- Attacker-owned resource name: `ANYPOC Marta Resource`
- Victim-owned resource name: `ANYPOC Kolo Resource`
- Common scope names: `Scope A`, `Scope B`, `Scope C`
- Both resources are created with `ownerManagedAccess=true`
- The attacker user `marta` has the client role `uma_protection` on `resource-server-test`

Relevant behavior from the vulnerable implementation:

- `create(@PathParam("resourceId") String resourceId, UmaPermissionRepresentation representation)` calls `checkRequest(resourceId, representation)` and then unconditionally `representation.addResource(resourceId)`.
- On vulnerable versions before 26.5.7, `checkRequest(...)` validates the path resource ownership and scopes but does not reject extra resource ids already present in `representation.getResources()`.
- The fix for CVE-2026-4636 adds a guard that rejects requests when the body contains any resource id other than the one in the URL path.
