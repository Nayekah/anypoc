# Verdict
Valid

# Rejection Reason
Other

# Analysis Details
I validated this as a real cross-user authorization flaw in Keycloak `26.5.6` on the intended HTTP surface.

Key code path examined:
- [`UserManagedPermissionService.create()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74) only calls `checkRequest(resourceId, representation)` for the path resource, then unconditionally appends the path resource with `representation.addResource(resourceId)` and creates the policy.
- [`checkRequest(...)`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) validates ownership and scopes for the URL path resource only. It does not reject extra resource IDs already present in `representation.getResources()`.
- [`getAssociatedResourceId()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:184) later picks an arbitrary first resource from the persisted policy set, which explains why some crafted requests return `400` and roll back while others succeed.
- The existing regression area in [`testUpdateResources()`](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:344) covers `PUT` resource changes but not the vulnerable `POST` create path.

HTTP validation:
1. Baseline: before the attack, `marta` requesting UMA authorization for victim resource `6a0a015c-e34c-458c-a3a6-4fa886ce108b` and scope `Scope A` via `POST /realms/anypoc/protocol/openid-connect/token` with `grant_type=urn:ietf:params:oauth:grant-type:uma-ticket` returned `403 {"error":"access_denied","error_description":"not_authorized"}`.
2. Sanity check: a normal UMA policy created by `marta` on her own resource successfully granted `kolo` access, confirming the policy format and oracle were correct.
3. Exploit: `marta` created a new attacker-owned UMA resource (`8f9c2ba5-6a5c-446e-93b4-439209153eca`) and sent:
   - `POST /realms/anypoc/authz/protection/uma-policy/8f9c2ba5-6a5c-446e-93b4-439209153eca`
   - body: `{"name":"fuzz-pol-1","resources":["8f9c2ba5-6a5c-446e-93b4-439209153eca","6a0a015c-e34c-458c-a3a6-4fa886ce108b"],"scopes":["Scope A"],"users":["marta"]}`
4. Result: the policy creation returned `200`, appeared in `GET /authz/protection/uma-policy?name=fuzz-pol-1`, and a follow-up UMA authorization request by `marta` for the victim resource returned `200` with an access token whose decoded `authorization.permissions[0].rsid` was the victim resource ID `6a0a015c-e34c-458c-a3a6-4fa886ce108b`.

Consequence refinement:
- The meaningful impact is not just malformed policy state. A low-privilege authenticated user with normal UMA management rights can cause Keycloak to issue authorization for another user’s owner-managed resource.
- The clean oracle is RPT issuance for the victim resource: before exploit `403 not_authorized`, after exploit `200` and the token contains the victim resource in `authorization.permissions`.

Nuance:
- Exploitability is somewhat order-dependent. Using the seeded attacker resource produced a `400` and rollback, but attacker-controlled creation of another owned resource made the smuggled cross-user policy succeed immediately. That does not negate the bug; it means the practical exploit is “create an owned UMA resource and use it as the path resource until the persisted resource ordering favors the attacker-owned one.”