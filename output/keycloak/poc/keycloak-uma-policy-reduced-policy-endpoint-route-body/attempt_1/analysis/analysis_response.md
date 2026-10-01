# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The vulnerability was reproduced locally using Marta’s ordinary bearer token.

- Baseline: Marta requesting `KoloResource#Scope A` received `403 access_denied`.
- Exploit: Marta posted to `/realms/anypoc/authz/protection/uma-policy/<MartaResource>` with a policy referencing both Marta’s and Kolo’s resources.
- The server accepted it with HTTP 200.
- Afterward, Marta’s request for Kolo’s resource returned HTTP 200 with `{"result":true}`.
- Admin inspection confirmed the policy was associated with both resources and `Scope A`.
- Deleting the policy through Marta’s normal HTTP request restored the 403 denial.

Relevant source: [`ProtectionService.java`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java:88) exposes `/uma-policy` to authenticated identities. [`UserManagedPermissionService.java`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74) validates ownership for the route resource, then preserves additional resource references in the submitted representation. `checkRequest()` validates only the supplied route resource and does not enforce ownership across every referenced resource.

Root cause: incomplete cross-resource ownership validation during UMA policy creation, allowing an attacker-owned route context to create a policy affecting a victim-owned resource.