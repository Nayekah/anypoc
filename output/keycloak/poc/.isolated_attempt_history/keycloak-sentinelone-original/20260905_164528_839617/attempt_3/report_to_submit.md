# Cross-owner UMA policy creation via resource list injection

## Summary

Keycloak UMA policy creation accepts a crafted request body that already contains resource IDs not owned by the caller. The server validates only the path resource, then persists a policy whose resource set can reference a different user's resource, breaking per-owner authorization isolation.

## Threat Model And Roles

The attacker is an authenticated non-admin user with normal UMA policy-management capability on their own resources. The victim is another ordinary user with owner-managed resources in the same realm. The crossed boundary is resource ownership during policy creation.

## Protected Asset Or Action

A user must not be able to create or influence authorization state for another user's protected resource. The forbidden state change is a UMA policy owned/created by user A that references user B's resource.

## Entry Point

`POST /realms/{realm}/authz/protection/uma-policy/{resourceId}` via [ProtectionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java:88), which routes to `UserManagedPermissionService.create(...)` in [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74). In the lab this was exposed at `POST /realms/anypoc/authz/protection/uma-policy/{resourceId}`.

## Vulnerable Code Analysis

In [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74), `create(...)` calls `checkRequest(resourceId, representation)` and then unconditionally `representation.addResource(resourceId)`. In [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149), `checkRequest(...)` verifies ownership, owner-managed access, and scopes for the path `resourceId`, but it never rejects foreign IDs already present in `representation.getResources()`. By contrast, update-time resource changes are explicitly rejected in [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:103) and exercised in [UserManagedPermissionServiceTest.java](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:343), which isolates the flaw to create-time validation.

## Preconditions

- Authorization Services enabled for the target client/resource server.
- Attacker can manage UMA policies for at least one owner-managed resource.
- Victim has an existing owner-managed resource in the same realm/client.
- Observed lab version: [keycloak_version.txt](/home/playground/output/attempt_3/reproduce/evidence/keycloak_version.txt:1) shows `Keycloak - Version 26.5.6`.
- Seeded lab resource IDs are recorded in [keycloak_status.txt](/home/playground/output/attempt_3/reproduce/evidence/keycloak_status.txt:7): attacker resource `307e56fe-1b29-4127-a989-e1fcbdd77238`, victim resource `6a0a015c-e34c-458c-a3a6-4fa886ce108b`.

## Reproduction Sketch

Obtain an access token as low-privilege user `marta` for authz-enabled client `resource-server-test`, then send `POST /realms/anypoc/authz/protection/uma-policy/{attackerResourceId}` with a JSON body whose `resources` array already contains `{victimResourceId}` plus otherwise valid scopes/subjects. The server should reject cross-owner resource references, but on the vulnerable build it accepts the create request and stores policy state referencing the victim resource. A follow-up policy read or authorization request should confirm that the foreign resource was bound into the attacker's policy.

## Expected Vs Actual Authorization Behavior

Expected: only the owner of `{resourceId}` can create UMA policy state scoped to that same resource, and any extra body-supplied resource IDs must be rejected.

Actual: the request is authorized based on the path resource only, while body-supplied foreign resource IDs survive creation and can affect authorization outcomes for another user's resource.

## Impact

This is an access-control failure with cross-user integrity and confidentiality impact. A normal authenticated user can create authorization state that applies to another user's protected resource, enabling unauthorized grants and potentially unauthorized access to application data or actions gated by Keycloak authorization decisions.

## Desired PoC

A successful PoC must prove create-time cross-owner resource injection over HTTP: submit a policy-create request for an attacker-owned resource whose body includes a victim-owned resource ID, then capture either the created policy JSON showing the victim resource reference or a subsequent authorization success against the victim resource that depends on that injected policy. The attached PoC bundle currently contains metadata only in [generation_summary.md](/home/playground/output/attempt_3/poc/generation_summary.md:1) and [generation_summary.json](/home/playground/output/attempt_3/poc/generation_summary.json:1); the security oracle should therefore be the HTTP response and persisted policy/authorization state, not those summaries alone.