# Verdict
Valid

# Rejection Reason
Other

# Analysis Details
The report describes a real authenticated cross-user authorization flaw.

I verified the vulnerable path in `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java`. In `create(@PathParam("resourceId") String resourceId, UmaPermissionRepresentation representation)`, the service calls `checkRequest(resourceId, representation)`, then unconditionally calls `representation.addResource(resourceId)` before delegating creation. `checkRequest()` validates ownership and scopes only for the URL path resource. It does not reject existing IDs in `representation.getResources()`. By contrast, the `update()` path explicitly rejects resource changes, which confirms the intended invariant.

I reproduced the impact through HTTP as low-privilege user `marta`:

- Before exploit: Marta requesting an UMA RPT for Kolo’s resource `05c947be-ecd7-402a-90e4-9fb674435809#Scope A` returned `403 not_authorized`.
- Marta created her own owner-managed resource through `POST /realms/anypoc/authz/protection/resource_set`.
- Marta then sent `POST /realms/anypoc/authz/protection/uma-policy/{martaResourceId}` with body `resources` containing both her path resource ID and Kolo’s victim resource ID, plus `users:["marta"]` and `scopes:["Scope A"]`.
- After that, Marta’s UMA ticket exchange for Kolo’s resource returned `200` with an RPT.
- Decoding the RPT showed:

```json
{
  "rsid": "05c947be-ecd7-402a-90e4-9fb674435809",
  "rsname": "ANYPOC Kolo Resource",
  "scopes": ["Scope A"]
}
```

Root cause: missing resource-id consistency validation in `UserManagedPermissionService.create()`. The URL resource is owner-checked, but body-supplied extra resource IDs are preserved into the created policy, allowing a normal authenticated user with `uma_protection` to bind a UMA policy to another user’s resource and obtain unauthorized access.