# Title: Keycloak resource_set allows attacker CRUD on another user's UMA resource

## Summary

A normal authenticated user can access and delete a different user’s protected UMA resource through `GET` and `DELETE /realms/anypoc/authz/protection/resource_set/{id}`. The PoC shows `marta` reading and removing `kolo`’s resource, which changes victim-owned authorization state without consent ([run_poc.sh](/home/playground/output/attempt_1/poc/run_poc.sh#L84), [summary.txt](/home/playground/output/attempt_1/evidence/summary.txt#L1)).

## Threat Model And Roles

Attacker: `marta`, a non-admin realm user with normal bearer-token access to the protection API. Victim: `kolo`, owner of the protected resource. The crossed boundary is resource ownership inside Keycloak Authorization Services.

## Protected Asset Or Action

The protected asset is the victim-owned UMA resource record and its authorization metadata, including existence in the resource set. The forbidden action is attacker-driven read or deletion of that victim-owned resource.

## Entry Point

`GET` and `DELETE` on `http://127.0.0.1:8080/realms/anypoc/authz/protection/resource_set/{resource_id}` as exercised by [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh#L84) and [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh#L118).

## Vulnerable Code Analysis

`ProtectionService.resource()` routes `/resource_set` to `ResourceService` via `ResourceSetService` ([ProtectionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java#L57-L63)). The adjacent `/uma-policy` path does enforce ownership in `checkRequest()` before any CRUD, rejecting non-owners and non-owner-managed resources ([UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L149-L182)). The PoC shows the `resource_set` path does not apply that same owner boundary.

## Scope Match

This is not a generic metadata issue. The PoC proves a cross-user authorization effect: `marta` can read and delete `kolo`’s protected resource, and the victim resource disappears from the admin listing afterward ([marta_get_victim.json](/home/playground/output/attempt_1/evidence/marta_get_victim.json#L1), [after_delete_admin_resources.json](/home/playground/output/attempt_1/evidence/after_delete_admin_resources.json#L1)).

## Preconditions

Two realm users exist: `marta` and `kolo`. The client `resource-server-test` is configured as a resource server, and `marta` can obtain a token that reaches the protection API. `kolo` lacks the needed protection scope and is blocked from the same endpoint ([kolo_get_victim.json](/home/playground/output/attempt_1/evidence/kolo_get_victim.json#L1)).

## Reproduction Sketch

1. List resources as admin to identify a victim-owned resource (`ANYPOC Kolo Resource 2`) ([before_admin_resources.json](/home/playground/output/attempt_1/evidence/before_admin_resources.json#L1)).
2. Call `GET /realms/anypoc/authz/protection/resource_set/{victim_id}` as `marta`; it returns `200` and the victim resource body ([marta_get_status.txt](/home/playground/output/attempt_1/evidence/marta_get_status.txt#L1), [marta_get_victim.json](/home/playground/output/attempt_1/evidence/marta_get_victim.json#L1)).
3. Call `DELETE /realms/anypoc/authz/protection/resource_set/{victim_id}` as `marta`; it returns `204` ([marta_delete_status.txt](/home/playground/output/attempt_1/evidence/marta_delete_status.txt#L1)).
4. Re-list resources as admin and confirm the victim resource is gone ([after_delete_admin_resources.json](/home/playground/output/attempt_1/evidence/after_delete_admin_resources.json#L1)).

## Expected Vs Actual Authorization Behavior

Expected: a non-owner should get denied when touching another user’s protected resource. Actual: `marta` gets `200` on victim read and `204` on victim delete, while `kolo` gets `403 invalid_scope` on the same protection API ([kolo_get_victim.json](/home/playground/output/attempt_1/evidence/kolo_get_victim.json#L1), [poc_execution.log](/home/playground/output/attempt_1/evidence/poc_execution.log#L1)).

## Impact

Integrity loss in Keycloak Authorization Services: one ordinary user can delete or otherwise manipulate another user’s protected resource and its authorization state. That can invalidate downstream permissions and access decisions for the victim-owned resource.

## Desired PoC

A successful PoC must show all three of these: victim-owned resource identity, attacker-authenticated request to the protection endpoint, and a post-action oracle proving the victim resource changed or disappeared. This PoC captures that with request status, returned body, and before/after admin listings ([summary.txt](/home/playground/output/attempt_1/evidence/summary.txt#L1)).

## Limitations

This report only claims the verified `resource_set` cross-user effect. I did not validate a broader `/uma-policy` ownership bypass; that path has an explicit ownership check in source ([UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L149-L182)).