# Title: Cross-resource UMA policy creation bypasses ownership validation

## Summary

A normal authenticated user can create a UMA policy on a resource they own while smuggling a different victim-owned resource in the request body. The server validates only the route resource, accepts the inconsistent association, and the resulting policy changes authorization for the victim resource.

## Threat Model And Roles

Attacker: normal user `marta` with `uma_protection` on the test client. Victim: normal user `kolo` who owns a separate protected resource. The crossed boundary is per-user ownership during UMA policy creation and the resulting authorization decision.

## Protected Asset Or Action

Forbidden action: binding or affecting `kolo`'s protected resource through a policy created under `marta`'s resource context. That includes creating a policy that later grants `marta` access to the victim resource.

## Entry Point

`POST /realms/anypoc/authz/protection/uma-policy/{resourceId}` via the protection API exposed from [`ProtectionService.policy()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java#L88).

## Vulnerable Code Analysis

[`UserManagedPermissionService.create()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L74) calls `checkRequest(resourceId, representation)`, then unconditionally does `representation.addResource(resourceId)` and `delegate.create(representation)`. `checkRequest()` enforces ownership only for the path resource at [`checkRequest()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L149), but it does not reject preexisting `representation.getResources()` from the body. The update path explicitly blocks cross-resource changes in [`update()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L91), and the existing test covers that invariant for updates in [`testUpdateResources()`](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java#L343).

## Scope Match

The PoC follows the exact create-time gap, not generic CRUD. `run_poc.sh` posts a policy to `marta`'s resource with `f872c1d2-a1e5-49b7-9548-b38d10a915e6` in the JSON body, the create returns `200 OK`, listing policies for the victim resource returns the new policy, and a follow-up UMA ticket request succeeds with `rsid` set to the victim resource. Evidence is in [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh#L68), [`02_baseline.response.headers`](/home/playground/output/attempt_1/evidence/poc_run/02_baseline.response.headers#L1), [`03_create.response.headers`](/home/playground/output/attempt_1/evidence/poc_run/03_create.response.headers#L1), [`04_lookup.response.body`](/home/playground/output/attempt_1/evidence/poc_run/04_lookup.response.body#L1), and [`05_authorize.decoded.json`](/home/playground/output/attempt_1/evidence/poc_run/05_authorize.decoded.json#L1).

## Preconditions

- Realm: `anypoc`
- Client: `resource-server-test`
- Attacker credentials: `marta` / `password`
- Victim credentials: `kolo` / `password`
- Attacker has `uma_protection`
- Separate owner-managed resources exist for both users
- Local Keycloak is running on `http://127.0.0.1:8080`

## Reproduction Sketch

1. Get an access token for `marta`.
2. Confirm baseline UMA access to the victim resource returns `403 access_denied not_authorized`.
3. `POST /realms/anypoc/authz/protection/uma-policy/a10797fc-7b38-4d82-807f-dbda2d32576a` with body `{"name":"cross-boundary-poc","users":["marta"],"resources":["f872c1d2-a1e5-49b7-9548-b38d10a915e6"]}`.
4. Query `GET /realms/anypoc/authz/protection/uma-policy?resource=f872c1d2-a1e5-49b7-9548-b38d10a915e6&name=cross-boundary-poc`.
5. Repeat UMA ticket request for the victim resource and observe `200 OK` plus an authorization token containing the victim `rsid`.

## Expected Vs Actual Authorization Behavior

Expected: the server rejects the body-supplied victim resource or leaves the victim resource unauthorized, so `marta` stays denied. Actual: the create succeeds, the policy is associated with the victim resource, and the follow-up UMA grant returns an access token that includes the victim resource permission.

## Impact

A low-privilege user can cause a policy they create in their own resource context to apply to another user’s protected resource, resulting in unauthorized authorization grants across user ownership boundaries.

## Desired PoC

A successful reproducer must capture:
- `marta` authenticated as a normal user
- victim resource owned by another user
- baseline denial for the victim resource
- create request with mismatched route resource and body resource
- `200 OK` create response and victim-resource policy listing
- follow-up UMA token showing `authorization.permissions[].rsid == f872c1d2-a1e5-49b7-9548-b38d10a915e6`

## Limitations

This report is limited to the create-time UMA policy association flaw proven by the local POC. It does not claim broader admin-only impact or any unrelated resource metadata behavior.