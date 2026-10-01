# Verdict
Valid

# Rejection Reason
Other

# Analysis Details
I confirmed this is a real cross-user authorization flaw in the UMA policy creation path.

Key code path examined:
- `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74-84`
- `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149-180`
- `/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:343-406`

Root cause:
- `create(resourceId, representation)` calls `checkRequest(resourceId, representation)`, but `checkRequest(...)` only validates the resource in the URL path: existence, ownership, owner-managed access, remote management, and scopes.
- It does not reject extra resource IDs already present in `representation.getResources()`.
- After that, `create(...)` unconditionally runs `representation.addResource(resourceId)`.
- Result: a caller can post to `/uma-policy/{theirResourceId}` while smuggling a victim resource ID in the JSON body, producing a UMA policy associated with both resources.

The contrast with `update()` is important:
- `update()` explicitly rejects resource changes unless the resource set is empty or exactly the original resource.
- The existing regression test only covers that update-time invariant. There is no equivalent create-time guard in this vulnerable version.

HTTP validation on the live lab:
- Server is Keycloak `26.5.6` per `/var/log/keycloak/server.log`.
- `marta` initially hit a normal `VERIFY_PROFILE` required action, so I completed that standard login workflow once. After that, `marta` could authenticate normally.
- I created a fresh victim-owned resource `ANYPOC Kolo Resource 2` with ID `56d24373-dba4-439f-8ecb-4c479654f149`, owned by `kolo`.
- Before the exploit, `marta` requested a UMA token for that victim resource via `POST /realms/anypoc/protocol/openid-connect/token` with `grant_type=urn:ietf:params:oauth:grant-type:uma-ticket`, `audience=resource-server-test`, `permission=56d24373-dba4-439f-8ecb-4c479654f149` and got `403` with `{"error":"access_denied","error_description":"not_authorized"}`.
- Then `marta` sent `POST /realms/anypoc/authz/protection/uma-policy/fd1f69f8-dec4-467f-9541-0b172738bdf5` using her own resource in the path, with body `{"name":"cross-boundary-poc-2","users":["marta"],"resources":["56d24373-dba4-439f-8ecb-4c479654f149"]}`.
- That request succeeded and created policy `8f2838df-66be-4a80-aa21-684ab2a9bb8c`.
- `GET /realms/anypoc/authz/protection/uma-policy?resource=56d24373-dba4-439f-8ecb-4c479654f149` then returned that Marta-owned UMA policy, showing the victim resource had been bound into her policy state.
- After the policy create, the same UMA token request returned `200` and issued an access token whose `authorization.permissions` included `rsid=56d24373-dba4-439f-8ecb-4c479654f149` and `rsname="ANYPOC Kolo Resource 2"`.

Consequence:
- A low-privilege authenticated user can create permission state affecting a victim-owned resource and then obtain UMA authorization for that victim resource.
- This is a meaningful cross-user privilege escalation, not just a validation bug or 4xx-only issue.