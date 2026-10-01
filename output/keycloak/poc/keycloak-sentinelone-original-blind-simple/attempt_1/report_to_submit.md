# Title: Cross-user resource-set CRUD bypasses ownership checks in Keycloak authz

## Summary

A normal authenticated user (`marta`) can create, read, and delete a UMA resource-set entry owned by another user (`kolo`) through the local Keycloak authorization-services API. The PoC shows the actor crossing a user ownership boundary on `/authz/protection/resource_set/{id}` and successfully deleting victim-owned state.

## Threat Model And Roles

Attacker: ordinary authenticated user `marta`.  
Victim: ordinary authenticated user `kolo`.  
Boundary crossed: ownership of a protected authorization resource owned by `kolo` but acted on by `marta`.

## Protected Asset Or Action

Resource-set metadata and lifecycle operations for a victim-owned authorization resource, including `GET` visibility and `DELETE` removal. These actions should be restricted to the resource owner or an authorized admin flow.

## Entry Point

`POST`, `GET`, and `DELETE` on `/realms/anypoc/authz/protection/resource_set/{resourceId}` in the UMA protection API.

## Vulnerable Code Analysis

`ProtectionService.resource()` routes `/resource_set` into the resource CRUD handler without any ownership check in the entry point: [ProtectionService.java#L57]( /opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java#L57 )-[ProtectionService.java#L63]( /opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java#L63 ).

The intended owner gate exists elsewhere in the authz protection stack, e.g. `UserManagedPermissionService.checkRequest()` rejects non-owners before policy access: [UserManagedPermissionService.java#L149]( /opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L149 )-[UserManagedPermissionService.java#L167]( /opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L167 ). The PoC shows that this ownership constraint is not enforced on the resource-set CRUD path.

The local test suite models separate owned resources for `marta` and `kolo`, confirming the boundary that should be preserved: [UserManagedPermissionServiceTest.java#L343]( /opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java#L343 )-[UserManagedPermissionServiceTest.java#L360]( /opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java#L360 ).

## Preconditions

- Realm: `anypoc`
- Client: `resource-server-test` with secret `secret`
- Authenticated low-privilege user: `marta`
- Separate victim user: `kolo`
- Authorization services enabled on the client
- Resource created with `ownerManagedAccess=true` and `owner=kolo`

## Reproduction Sketch

1. Authenticate as `marta` via password grant.
2. Create a resource-set entry while setting `owner` to `kolo`.
3. Use the returned resource id to `GET` the victim-owned resource as `marta`.
4. `DELETE` the same victim-owned resource as `marta`.
5. Confirm the resource is gone with a final `GET` returning `404`.

PoC evidence: [run_poc.sh](/home/playground/output/attempt_1/poc/run_poc.sh) and transcript [poc_20260905_110703.log](/home/playground/output/attempt_1/evidence/poc_20260905_110703.log).

## Expected Vs Actual Authorization Behavior

Expected: `marta` should be blocked from reading or deleting a resource owned by `kolo`.  
Actual: the API returns `201` on create with `owner=kolo`, then `200` on `GET`, `204` on `DELETE`, and `404` after deletion.

## Impact

Broken access control over UMA resource state. A low-privilege user can inspect and remove another user’s protected authorization resource, which can cause unauthorized privilege changes, loss of protected resources, and downstream authorization effects.

## Desired PoC

A successful AnyPoC should prove that:
- the actor is a normal authenticated user,
- the target resource is owned by a different user,
- the actor can still `GET` and `DELETE` that resource through the normal protection API,
- the transcript captures the cross-user owner value and the `200`/`204`/`404` outcome sequence.