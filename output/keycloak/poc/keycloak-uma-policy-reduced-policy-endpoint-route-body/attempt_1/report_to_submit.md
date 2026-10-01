# Title: UMA policy creation bypasses cross-resource ownership checks

## Summary

A normal user can create a UMA policy through their own resource route while referencing a victim’s resource, changing the victim resource’s authorization result.

## Threat Model And Roles

Attacker: `marta`, an ordinary authenticated user. Victim/resource owner: `kolo`. The crossed boundary is ownership of authorization state for Kolo’s protected resource.

## Protected Asset Or Action

The victim resource `291c1f42-cb7a-46cd-be79-d6851533d448` and `Scope A` authorization decision must remain inaccessible to Marta unless Kolo grants access.

## Entry Point

`POST /realms/anypoc/authz/protection/uma-policy/{resourceId}` in `ProtectionService.policy()` and `UserManagedPermissionService.create()`.

## Vulnerable Code Analysis

[`ProtectionService.java:88-92`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java:88) exposes the UMA policy service to the authenticated identity.

[`UserManagedPermissionService.java:74-84`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74) validates only the route `resourceId`, then preserves submitted resource references and delegates policy creation.

[`UserManagedPermissionService.java:149-179`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) checks ownership and scopes only for the route resource. It does not validate ownership of every resource in `representation.getResources()`.

## Scope Match

The attached [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh) uses Marta’s bearer token and normal HTTP requests. It posts a policy on Marta’s resource route containing both Marta’s and Kolo’s resource IDs. The evidence shows Kolo’s decision changing from `403` to `200 {"result":true}`, then returning to `403` after policy deletion.

## Preconditions

- Running local Keycloak authorization-services realm `anypoc`
- Resource server `resource-server-test` with remote resource management enabled
- Ordinary users `marta` and `kolo`
- Owner-managed resources with `Scope A`
- Marta-owned and Kolo-owned protected resources

## Reproduction Sketch

Run [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh):

1. Authenticate as Marta.
2. Request Kolo’s resource with `Scope A`; record `403 access_denied`.
3. `POST` to Marta’s policy route with `resources` containing both resource IDs.
4. Request Kolo’s resource again; observe `200 {"result":true}`.
5. Delete the created policy and confirm the decision returns to `403`.

## Expected Vs Actual Authorization Behavior

Expected: Marta’s policy request cannot affect Kolo’s resource.

Actual: The policy is accepted with HTTP 200, and Marta’s authorization decision for Kolo’s resource changes from denied to allowed.

## Impact

An ordinary user can alter authorization state across ownership boundaries and obtain an authorization decision for another user’s protected resource, potentially enabling unauthorized access to the protected resource.

## Desired PoC

A successful reproducer must capture:

- Normal attacker authentication
- Baseline denial for the victim resource
- Policy creation through the attacker-owned route
- Policy representation referencing the victim resource
- Post-creation authorization success
- Restoration of denial after policy deletion

These artifacts are recorded under [`evidence/`](/home/playground/output/attempt_1/evidence), including `baseline_decision`, `exploit_create`, `after_decision`, `exploit_delete`, and `restored_decision`.

## Limitations

Validated only against the supplied local Keycloak runtime and source tree. The PoC does not claim impact to unrelated endpoints or persistence beyond the created policy.