# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

A normal Marta bearer token successfully submitted:

`POST /realms/anypoc/authz/protection/uma-policy/{marta-resource}`

with a policy representation referencing Kolo’s resource. The request returned `200` and created a UMA policy.

Admin inspection confirmed the policy was associated with both Marta’s resource and Kolo’s victim-owned resource. Before creation, Kolo’s UMA decision for `KoloResource#Scope A` returned `403 access_denied`; afterward it returned `200 {"result":true}`.

Root cause is in [`UserManagedPermissionService.java:74-84`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74): `checkRequest()` validates ownership only for the route `resourceId`, while caller-supplied `representation.resources` are not ownership-validated. `representation.addResource(resourceId)` then preserves the foreign reference and persists the policy for both resources.

The policy endpoint is exposed to the authenticated identity without requiring the protection-scope check in [`ProtectionService.java:88-92`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java:88). The ownership checks in [`UserManagedPermissionService.java:149-179`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) therefore do not prevent this cross-user association. This is a concrete authorization-impacting broken-access-control issue, not merely metadata modification.