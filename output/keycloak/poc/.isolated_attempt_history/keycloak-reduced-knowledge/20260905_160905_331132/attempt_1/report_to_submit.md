# Title: Cross-resource UMA policy creation grants unauthorized access to another user's resource

## Summary

`POST /realms/{realm}/authz/protection/uma-policy/{resourceId}` appears to trust the path resource for ownership checks but also accepts attacker-controlled `resources[]` in the JSON body. A low-privilege user can submit a request against their own resource while injecting another user's resource ID into the policy, then obtain UMA access to that victim resource.

## Threat Model And Roles

Attacker: normal authenticated user with standard UMA protection capability for their own resource. Victim: another normal user who owns a different owner-managed resource. Boundary crossed: per-resource ownership in the UMA policy-management flow.

## Protected Asset Or Action

The protected asset is the victim user's UMA-protected resource and its attached authorization state. The forbidden action is creating or influencing a sharing policy that grants the attacker access to that victim resource without the victim's involvement.

## Entry Point

Route: `POST /realms/{realm}/authz/protection/uma-policy/{resourceId}`

Handler: [`UserManagedPermissionService#create`](</opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74>)

Model: `UmaPermissionRepresentation`

## Vulnerable Code Analysis

[`UserManagedPermissionService#create`](</opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74>) calls `checkRequest(resourceId, representation)` and then unconditionally `representation.addResource(resourceId)` at line 81 before `delegate.create(...)` at line 84.

[`checkRequest`](</opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149>) validates only the path resource: existence, owner match, owner-managed-access, remote management, and scopes. It does not reject foreign resource IDs already present in `representation.getResources()`.

By contrast, [`update`](</opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:100>) explicitly rejects resource changes unless the policy remains bound to the associated resource. `create` is missing the same invariant, so a request scoped to attacker resource `A` can persist a UMA policy that also targets victim resource `B`.

## Preconditions

- Two non-admin users in the same realm, each with distinct resources.
- Victim resource is `ownerManagedAccess=true`.
- Attacker can use normal UMA protection APIs for their own resource.
- In the validated lab: realm `anypoc`, attacker `marta`, victim `kolo`, client `resource-server-test`.

## Reproduction Sketch

1. Obtain an access token as the low-privilege attacker.
2. Confirm a UMA ticket request for the victim resource returns `403`.
3. Send `POST /realms/anypoc/authz/protection/uma-policy/{attacker_resource_id}` with a body like the validated `create_policy_request.json`, where `users=["marta"]` and `resources=[victim_resource_id]`.
4. Observe `200` on policy creation.
5. Repeat the UMA ticket request for `permission={victim_resource_id}` and observe `200`; the returned token payload should include `authorization.permissions[].rsid == victim_resource_id`.

Validated artifacts show:
- `before_uma_status.txt`: `403`
- `create_policy_status.txt`: `200`
- `after_uma_status.txt`: `200`

## Expected Vs Actual Authorization Behavior

Expected: the server should reject any policy-creation request where the body references resources outside the caller-owned path resource scope.

Actual: the server accepts a request whose URL targets the attacker's resource while the body references the victim's resource, and the attacker then receives a valid UMA authorization token for that victim resource.

## Impact

This is a cross-user authorization integrity failure with direct privilege-escalation impact. A normal user can inject policy state onto another user's resource and then obtain authorized access to that resource through standard UMA flows, bypassing normal ownership boundaries.

## Desired PoC

A successful AnyPoC should prove both the write and the access grant:

- The create request uses attacker resource ID in the path and victim resource ID in `resources[]`.
- Pre-exploit UMA authorization for the victim resource is denied.
- Post-exploit UMA authorization succeeds and the returned token contains the victim `rsid`.

Note: the attached `/home/playground/output/attempt_1/poc` bundle currently contains only `generation_summary.md` and `generation_summary.json`, both stating no runnable PoC was generated there. The desired PoC should instead capture the HTTP request/response sequence above.