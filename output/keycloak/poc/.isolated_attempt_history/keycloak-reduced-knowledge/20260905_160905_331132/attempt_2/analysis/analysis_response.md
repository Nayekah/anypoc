# Verdict
Valid

# Rejection Reason
Other

# Analysis Details
I validated this as a real authorization flaw in the vulnerable lab build.

Key evidence:
- The running server is `Keycloak 26.5.6` per [server.log](/var/log/keycloak/server.log:11), which matches the vulnerable version called out in the prompt.
- The vulnerable handler is [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:69). `create(@PathParam("resourceId") String resourceId, UmaPermissionRepresentation representation)` calls `checkRequest(resourceId, representation)` and then unconditionally `representation.addResource(resourceId)` before `delegate.create(...)`.
- [checkRequest(...)](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:146) validates only the path resource: existence, owner, OMA, remote management, and scopes. It does not reject extra resource IDs already present in `representation.getResources()`.
- By contrast, `update(...)` already contains a resource-consistency guard and rejects attempts to change the resource set unless it is empty or exactly the path resource, which makes the missing invariant in `create(...)` stand out as the bug.

HTTP-level reproduction:
- I normalized `marta`’s profile because the seeded lab initially returned `invalid_grant: Account is not fully set up`; that was a lab authentication issue, not a mitigation.
- Using `marta`’s bearer token, I sent a `POST` to:
  `http://127.0.0.1:8080/realms/anypoc/authz/protection/uma-policy/5ed97cee-2b7d-49dc-8970-de02b5dab5d1`
  with body including `resources:["b53673bd-a750-400b-8959-0b950302d91c"]` and `users:["marta"]`.
- That request succeeded with `HTTP 200` and created a UMA policy through `marta`’s own resource path while referencing `kolo`’s resource in the body.
- After that, `marta` requested an RPT for `kolo`’s resource via the token endpoint using `grant_type=urn:ietf:params:oauth:grant-type:uma-ticket` and `permission=b53673bd-a750-400b-8959-0b950302d91c#Scope A`. The server returned `HTTP 200` and the issued token contained `authorization.permissions` for `rsid = b53673bd-a750-400b-8959-0b950302d91c`, i.e. the victim resource.
- As a control, a separate ordinary user `eve` requesting the same victim resource received `HTTP 403 {"error":"access_denied","error_description":"not_authorized"}`. So this is not ambient/default access; it is specific unauthorized access for `marta`.

Root cause and exploit mechanics:
- Precise route: `POST /realms/{realm}/authz/protection/uma-policy/{resourceId}`.
- Precise flaw: path/body resource mismatch is not rejected on create. A low-privilege authenticated user with `uma_protection` can manage a policy under a resource they own in the URL path while smuggling another user’s resource ID in `representation.resources`.
- Consequence: unauthorized policy binding and unauthorized RPT issuance for the victim-owned resource.
- The likely fix location is [UserManagedPermissionService.create](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:69), by enforcing that any resource IDs in the body are either absent or exactly equal to the path `resourceId`.

Relevant nuance:
- I also observed some requests returning `400` on freshly created resources. That appears consistent with `create()` calling `findById(delegate.create(...).getId())` afterward, while [getAssociatedResourceId(...)](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:184) uses `getResources().iterator().next()`. That makes the post-create ownership check sensitive to which associated resource is encountered first. This affects response shape and reliability, but it does not negate the confirmed exploit on the seeded target pair.

Overall, this is a real cross-user authorization vulnerability with meaningful impact: `marta` can obtain authorization to `kolo`’s protected resource through the standard UMA policy-management HTTP surface.