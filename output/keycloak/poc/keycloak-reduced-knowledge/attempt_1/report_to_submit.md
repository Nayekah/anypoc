# Title: Cross-resource UMA policy creation grants access to another user's resource

## Summary

A non-admin UMA resource owner can create a user-managed policy on their own resource while injecting another user's resource ID in the request body, causing authorization state to apply across the victim's resource boundary.

## Threat Model And Roles

Attacker: normal user `marta` with `uma_protection` for client `resource-server-test`. Victim: normal user `kolo`, owner of a distinct owner-managed resource. The crossed boundary is resource ownership in UMA policy management.

## Protected Asset Or Action

The protected action is creating authorization policy state for `kolo`'s resource. `marta` should not be able to grant herself `Scope A` on a resource owned by `kolo`.

## Entry Point

`POST /realms/{realm}/authz/protection/uma-policy/{resourceId}`

PoC target:
`POST /realms/anypoc/authz/protection/uma-policy/{marta_resource_id}`

## Vulnerable Code Analysis

`/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java`

`create()` at lines 74-84 calls `checkRequest(resourceId, representation)` for only the path resource, then calls `representation.addResource(resourceId)` and delegates policy creation. `checkRequest()` at lines 149-181 validates ownership, owner-managed-access, remote management, and scopes only for the path `resourceId`; it does not reject pre-existing `representation.getResources()` entries that name other resources.

The update path has the missing invariant: lines 100-109 reject resource changes unless the body resources are empty or exactly the associated resource. The create path lacks the equivalent check.

## Preconditions

- Realm `anypoc`
- Authorization-enabled client `resource-server-test` with secret `secret`
- Remote resource management enabled
- `marta` and `kolo` are normal users
- `marta` has `uma_protection`
- Victim resource is owned by `kolo` and has `ownerManagedAccess=true`
- Attacker has a separate owner-managed resource

## Reproduction Sketch

Run `/home/playground/output/attempt_1/poc/run_poc.sh`.

The PoC:
1. Creates a victim-owned resource for `kolo`.
2. Confirms `marta` cannot obtain an RPT for `victim_resource_id#Scope A` (`pre_exploit_status: 403`).
3. Creates an attacker-owned resource for `marta`.
4. Sends `POST /authz/protection/uma-policy/{attacker_resource_id}` with body `resources: [attacker_resource_id, victim_resource_id]`, `users: ["marta"]`, `scopes: ["Scope A"]`.
5. Requests authorization again for `victim_resource_id#Scope A`.

Relevant artifacts:
`policy_creation_request.json`, `policy_creation_response.json`, `pre_exploit_authorization_response.json`, `post_exploit_authorization_response.json`, `post_exploit_rpt_payload.json`, `summary.json`.

## Expected Vs Actual Authorization Behavior

Expected: policy creation should reject body resource IDs outside the caller-owned path resource scope.

Actual: policy creation returns HTTP 200, and a later UMA authorization request by `marta` returns HTTP 200 with an RPT containing `kolo`'s resource ID and `Scope A`.

## Impact

Integrity and access-control violation: a regular user can grant herself access to another user's protected UMA resource through policy creation, bypassing ownership boundaries without admin privileges.

## Desired PoC

A successful PoC must prove all three conditions: initial authorization for the victim resource is denied, cross-resource UMA policy creation is accepted, and the resulting RPT for the attacker contains the victim `rsid` with the requested scope. The oracle is `post_exploit_rpt_payload.json` plus `summary.json` showing `result: VULNERABLE`, `pre_exploit_status: 403`, `policy_creation_status: 200`, and `post_exploit_status: 200`.