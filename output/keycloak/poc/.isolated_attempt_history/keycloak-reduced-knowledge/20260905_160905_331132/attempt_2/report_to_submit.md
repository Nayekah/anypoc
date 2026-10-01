# Title: Cross-resource UMA policy creation grants unauthorized access to victim-owned resources

## Summary

`POST /realms/{realm}/authz/protection/uma-policy/{resourceId}` accepts a body whose `resources` set can include a different user's resource ID. In the vulnerable build, a normal user can create a user-managed UMA permission through their own resource path while smuggling a victim resource into the policy state, then obtain an RPT for the victim resource.

## Threat Model And Roles

Attacker: normal authenticated user `marta` with `uma_protection` and ownership of one OMA-enabled resource. Victim: normal user `kolo` owning a different OMA-enabled resource. The crossed boundary is per-resource ownership in UMA policy management and authorization issuance.

## Protected Asset Or Action

The protected asset is the victim-owned UMA resource and the permission state attached to it. The forbidden action is creating or influencing policy state for that victim resource, then receiving an RPT that grants `Scope A` on it.

## Entry Point

Route: `POST /realms/anypoc/authz/protection/uma-policy/{resourceId}`  
Handler: `UserManagedPermissionService.create(String resourceId, UmaPermissionRepresentation representation)`  
Model: `UmaPermissionRepresentation`

## Vulnerable Code Analysis

In [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74), `create(...)` calls `checkRequest(resourceId, representation)` and then unconditionally adds the path resource via [line 81](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:81). `checkRequest(...)` at [line 149](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) validates only the path resource: existence, owner, OMA, remote management, and scopes. It does not reject extra resource IDs already present in `representation.getResources()`. By contrast, `update(...)` already enforces resource consistency at [line 103](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:103). The existing test coverage in [UserManagedPermissionServiceTest.java](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:343) covers the update invariant, not an equivalent create-time check.

## Preconditions

- Vulnerable Keycloak build; lab instance is `26.5.6` per [server.log](/var/log/keycloak/server.log:10).
- Realm `anypoc`, client `resource-server-test`, client secret `secret`.
- Two normal users with distinct OMA-enabled resources: attacker `marta`, victim `kolo`.
- Attacker can obtain a normal bearer token for `resource-server-test` using password grant.
- Attached PoC uses seeded metadata from `/opt/keycloak-data/seed-info.json`.

## Reproduction Sketch

The attached PoC is [run_poc.sh](/home/playground/output/attempt_2/poc/run_poc.sh:1) invoking [poc.py](/home/playground/output/attempt_2/poc/poc.py:1). It performs only HTTP calls:

1. Obtain `marta`'s bearer token from `/realms/anypoc/protocol/openid-connect/token`.
2. Request an UMA ticket for `kolo`'s resource with `permission={victimResourceId}#Scope A`; expect `403`.
3. Send `POST /realms/anypoc/authz/protection/uma-policy/{martaResourceId}` with body containing `resources:[{victimResourceId}]`, `scopes:["Scope A"]`, and `users:["marta"]`; expect `200`.
4. Request the same UMA ticket again as `marta`; expect `200`.
5. Decode the returned access token and confirm `authorization.permissions[].rsid == victimResourceId`.

## Expected Vs Actual Authorization Behavior

Expected: the create call should reject any body whose `resources` set is non-empty and contains anything other than the path `resourceId`; `marta` should continue receiving `403` when requesting an RPT for `kolo`'s resource.

Actual: the create call succeeds even when the body references `kolo`'s resource, and the subsequent UMA-ticket request returns `200` with a token authorizing `marta` for the victim resource.

## Impact

This is a cross-user authorization bypass with both integrity and privilege-escalation impact. A low-privilege user can create effective permission state on another user's protected resource and then obtain a valid RPT for that victim-owned resource through standard UMA workflows.

## Desired PoC

A successful reproducer should prove all three points with captured artifacts: pre-exploit denial, successful cross-boundary policy creation, and post-exploit victim-resource authorization. The attached PoC already defines the expected oracles in its evidence files: `06_pre_auth_attempt.json` should show `403`, `07_policy_create_attempt.json` should show `200`, `08_post_auth_attempt.json` should show `200`, and `09_post_auth_token_payload.json` should contain the victim `rsid` under `authorization.permissions`.