# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The report is confirmed as an exploitable cross-user authorization vulnerability.

Relevant source: [`UserManagedPermissionService.java`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:70).

Root cause:

- `create()` validates ownership only for the route `{resourceId}`.
- It then calls `representation.addResource(resourceId)` without removing or validating resource IDs already supplied in the policy body.
- `delegate.create(representation)` therefore accepts a policy routed through Marta’s resource while also referencing Kolo’s resource.

Local PoC:

1. Marta authenticated normally with a non-admin token.
2. Marta posted to:

   `/realms/anypoc/authz/protection/uma-policy/{MartaResourceId}`

   with a body containing Kolo’s resource ID in `resources` and `users: ["marta"]`.
3. The server returned `200 OK` and created the UMA policy.
4. Before the request, Marta’s UMA decision for Kolo’s resource and `Scope A` returned `403 access_denied`.
5. Afterward, the same UMA request returned `200 {"result":true}`.
6. The resulting RPT contained permission for:

   `ANYPOC Kolo Resource` / Kolo’s resource ID / `Scope A`.

This demonstrates a concrete cross-user authorization effect: Marta caused authorization state for Kolo’s victim-owned resource to grant Marta access, without Kolo granting it. No database edits, source modifications, or admin actions were used for the exploit itself.