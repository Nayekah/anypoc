# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

I validated this as a real cross-user authorization flaw in Keycloak `26.5.6` on the intended HTTP surface.

Key code path examined:
- [`UserManagedPermissionService.create()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74) only calls `checkRequest(resourceId, representation)` for the path resource, then unconditionally appends the path resource with `representation.addResource(resourceId)` and creates the policy.
- [`checkRequest(...)`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) validates ownership and scopes for the URL path resource only. It does not reject extra resource IDs already present in `representation.getResources()`.
- [`getAssociatedResourceId()`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:184) later picks an arbitrary first resource from the persisted policy set, which explains why some crafted requests return `400` and roll back while others succeed.
- The existing regression area in [`testUpdateResources()`](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:344) covers `PUT` resource changes but not the vulnerable `POST` create path.

HTTP validation:
1. Baseline: before the attack, `marta` requesting UMA authorization for victim resource `6a0a015c-e34c-458c-a3a6-4fa886ce108b` and scope `Scope A` via `POST /realms/anypoc/protocol/openid-connect/token` with `grant_type=urn:ietf:params:oauth:grant-type:uma-ticket` returned `403 {"error":"access_denied","error_description":"not_authorized"}`.
2. Sanity check: a normal UMA policy created by `marta` on her own resource successfully granted `kolo` access, confirming the policy format and oracle were correct.
3. Exploit: `marta` created a new attacker-owned UMA resource (`8f9c2ba5-6a5c-446e-93b4-439209153eca`) and sent:
   - `POST /realms/anypoc/authz/protection/uma-policy/8f9c2ba5-6a5c-446e-93b4-439209153eca`
   - body: `{"name":"fuzz-pol-1","resources":["8f9c2ba5-6a5c-446e-93b4-439209153eca","6a0a015c-e34c-458c-a3a6-4fa886ce108b"],"scopes":["Scope A"],"users":["marta"]}`
4. Result: the policy creation returned `200`, appeared in `GET /authz/protection/uma-policy?name=fuzz-pol-1`, and a follow-up UMA authorization request by `marta` for the victim resource returned `200` with an access token whose decoded `authorization.permissions[0].rsid` was the victim resource ID `6a0a015c-e34c-458c-a3a6-4fa886ce108b`.

Consequence refinement:
- The meaningful impact is not just malformed policy state. A low-privilege authenticated user with normal UMA management rights can cause Keycloak to issue authorization for another user’s owner-managed resource.
- The clean oracle is RPT issuance for the victim resource: before exploit `403 not_authorized`, after exploit `200` and the token contains the victim resource in `authorization.permissions`.

Nuance:
- Exploitability is somewhat order-dependent. Using the seeded attacker resource produced a `400` and rollback, but attacker-controlled creation of another owned resource made the smuggled cross-user policy succeed immediately. That does not negate the bug; it means the practical exploit is “create an owned UMA resource and use it as the path resource until the persisted resource ordering favors the attacker-owned one.”

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

Keycloak contains an authorization flaw in its User-Managed Access policy handling. An authenticated user who is allowed to manage UMA policies can bypass validation during policy creation and cause a policy to reference resources owned by a different user. This can lead to unauthorized permissions being granted across user boundaries.

## Threat Model And Roles

The attacker is an authenticated non-admin user operating through normal authorization-management capabilities. The victim is another ordinary user who owns protected resources under the same Keycloak deployment. The boundary that should hold is per-resource ownership during policy management.

## Protected Asset Or Action

The protected asset is any resource owned by one user that should only be governed by that owner's authorization state. The protected action is the ability to create or influence permission state for another user's resource.

## Observed Boundary Failure

Policy creation is expected to remain scoped to the resource being managed by the caller. Instead, a crafted policy-creation request can carry identifiers for resources owned by another user, and the system accepts that state instead of rejecting it.

## Entry Point

The issue is reachable through the normal Keycloak Authorization Services and UMA policy-management flow used by authenticated users and clients that manage owner-controlled resources.

## Preconditions

This behavior matters when:

1. authorization services are enabled for the affected client or application
2. users are allowed to manage owner-controlled resources and their policies
3. victim-owned protected resources already exist

## Expected Vs Actual Behavior

Expected:

- policy creation should only affect resources the caller is allowed to manage
- cross-user resource references should be rejected during validation

Actual:

- validation can be bypassed during policy creation
- policy state can end up referencing another user's resource
- the attacker can obtain permissions that should never be granted across users

## Impact

This is a business-logic and access-control failure. A normal authenticated user can influence authorization outcomes for another user's protected resource, which can result in unauthorized access to application data or actions guarded by Keycloak authorization decisions.


## Available Paths:
Path to source code:

- `/opt/keycloak-source`
- Vulnerable class: `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java`
- Upstream regression test: `/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java`

Key runtime paths:

- Keycloak distribution: `/opt/keycloak`
- Server launcher: `/opt/keycloak/bin/kc.sh`
- Admin CLI: `/opt/keycloak/bin/kcadm.sh`
- Service health helper: `/opt/keycloak-lab/scripts/keycloak_status.sh`
- Seed script: `/opt/keycloak-lab/scripts/seed_lab.sh`
- Seed metadata: `/opt/keycloak-data/seed-info.json`
- Server log: `/var/log/keycloak/server.log`

Runtime endpoints:

- Base URL: `http://127.0.0.1:8080`
- Health: `http://127.0.0.1:9000/health/ready`
- Master realm token: `http://127.0.0.1:8080/realms/master/protocol/openid-connect/token`
- Lab realm token: `http://127.0.0.1:8080/realms/anypoc/protocol/openid-connect/token`
- Protection API base: `http://127.0.0.1:8080/realms/anypoc/authz/protection`
- Resource registration endpoint: `http://127.0.0.1:8080/realms/anypoc/authz/protection/resource_set`
- Vulnerable UMA policy endpoint shape: `http://127.0.0.1:8080/realms/anypoc/authz/protection/uma-policy/{resourceId}`

Seeded credentials:

- Admin: `admin` / `adminpass`
- Attacker user: `marta` / `password`
- Victim user: `kolo` / `password`
- Protected client: `resource-server-test`
- Protected client secret: `secret`

Seeded lab facts:

- Realm: `anypoc`
- Authz-enabled client: `resource-server-test`
- Attacker-owned resource name: `ANYPOC Marta Resource`
- Victim-owned resource name: `ANYPOC Kolo Resource`
- Common scope names: `Scope A`, `Scope B`, `Scope C`
- Both resources are created with `ownerManagedAccess=true`
- The attacker user `marta` has the client role `uma_protection` on `resource-server-test`

Relevant behavior from the vulnerable implementation:

- `create(@PathParam("resourceId") String resourceId, UmaPermissionRepresentation representation)` calls `checkRequest(resourceId, representation)` and then unconditionally `representation.addResource(resourceId)`.
- On vulnerable versions before 26.5.7, `checkRequest(...)` validates the path resource ownership and scopes but does not reject extra resource ids already present in `representation.getResources()`.
- The fix for CVE-2026-4636 adds a guard that rejects requests when the body contains any resource id other than the one in the URL path.


## Directories:
- **Playground (for experimentation):** /home/playground/output/attempt_3/playground
- **Final PoC (only when ready):** /home/playground/output/attempt_3/poc

## Your Approach:

1. **Experiment in playground first**: Use /home/playground/output/attempt_3/playground to test ideas,
try different approaches, and iterate on your PoC.
Create test files, run experiments, and verify your understanding of the bug.

2. **Verify the bug triggers**: Before finalizing, make sure you can actually trigger the bug.
Test your PoC in the playground and confirm it causes the expected behavior (crash, assertion failure, etc.).

3. **Finalize only when confident**: Once you have a working PoC that reliably triggers the bug, create a
**minimal, concise, end-to-end functional** version and copy it to /home/playground/output/attempt_3/poc.
The final PoC should be clean and self-contained.

## User-Triggerable PoC Principle

Your PoC must demonstrate something a **real user or attacker can do** through normal
interaction surfaces (file input, network request, API call, UI action, CLI arguments, etc.).

- **DO**: Craft a malicious input file, webpage, network payload, or API request that
  triggers the bug when processed by the target software in its normal mode of operation.
- **DO NOT**: Directly call internal functions, manipulate in-memory state, or write a
  test harness that bypasses the software's input path. Such PoCs prove the code is buggy
  but fail to show real-world exploitability.
- **Ask yourself**: "If I present this PoC to a triaging developer, would they immediately
  see that the bug is reachable from user-controlled input?" If not, improve the PoC to make this clearer.

## CRITICAL RULES:

- **NO dummy examples**: If you cannot trigger the real bug, do not create fake/simulated examples.
    Either create a real working PoC or declare it impossible.
- **Real bugs only**: The PoC must actually trigger the vulnerability in the target software,
    not just illustrate how it could theoretically work.
- **Do NOT kill the orchestrator**: Never run blanket kill commands like `pkill python`,
    `pkill -u`, or `kill -9 1` — they will terminate the poc runner/orchestrator
    process. Only terminate the specific test processes you started.

## If PoC is NOT Possible:

If after investigation you determine that creating a PoC is **impossible**,
write a file `/home/playground/output/attempt_3/poc/IMPOSSIBLE.md` explaining:

1. **Failure Category** (pick one):
   - `UNREACHABLE`: The vulnerable code path cannot be reached from user-controlled input
   - `ENVIRONMENT_DEPENDENT`: Requires special hardware, OS, or environment we cannot replicate
   - `INVALID_BUG`: Further analysis shows this is not actually a valid/exploitable bug
   - `OTHER`: Some other fundamental blocker

2. **Detailed Explanation**: Why the PoC cannot be created

Do NOT create dummy or fake demonstrations as a substitute.
If it's impossible, just write IMPOSSIBLE.md and stop.

## Project-Specific Instructions:
## Important Constraints

- Reproduce the bug through the running Keycloak server on `http://127.0.0.1:8080`.
- Use HTTP requests to Keycloak endpoints. Do not use in-process Java calls as the exploit path.
- Keep the PoC self-contained. Prefer `poc/run_poc.sh` plus one small helper such as `poc.py`.
- Use the seeded realm, users, and client unless the bug report explicitly requires otherwise.
- Do not change the server version or patch the vulnerable code during exploitation.

## Seeded Lab Context

- Realm: `anypoc`
- Admin: `admin` / `adminpass`
- Attacker: `marta` / `password`
- Victim: `kolo` / `password`
- Authorization-enabled client: `resource-server-test`
- Client secret: `secret`
- Attacker-owned resource name: `ANYPOC Marta Resource`
- Victim-owned resource name: `ANYPOC Kolo Resource`
- Seed metadata file: `/opt/keycloak-data/seed-info.json`
- Health helper: `/opt/keycloak-lab/scripts/keycloak_status.sh`

## Preferred PoC Shape

For this CVE, a good PoC usually does this:

1. Wait for Keycloak readiness.
2. Obtain an access token as `marta` for the `resource-server-test` client.
3. Discover the attacker-owned and victim-owned resource ids from the seeded environment.
4. Call the UMA policy creation endpoint with the URL path bound to `marta`'s resource id while including `kolo`'s resource id in the request body.
5. Request authorization as `marta` for the victim-owned resource and prove the authorization now succeeds.
6. Save the raw request, raw response, and resulting token or authorization evidence.

## Keycloak-Specific Guidance

- The vulnerable source path is `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java`.
- The protection API base is `http://127.0.0.1:8080/realms/anypoc/authz/protection`.
- The vulnerable endpoint shape is `POST /realms/anypoc/authz/protection/uma-policy/{resourceId}`.
- The token endpoint is `POST /realms/anypoc/protocol/openid-connect/token`.
- The fix added in 26.5.7 rejects mismatched or extra resource ids in `representation.getResources()`. A vulnerable run should still accept the injected victim resource id.
- If `seed-info.json` exists, use it to confirm resource names and ids, but still execute the exploit entirely over HTTP.

## Output Expectations

- Put the main runner at `poc/run_poc.sh`.
- Save helper code under `poc/`.
- Save raw token responses, policy creation requests and responses, and authorization results under the working directory for evidence preservation.
- Exit `0` only when the exploit demonstrates unauthorized cross-user authorization.



---

## Step 2: Execution & Evidence

Execute the PoC and gather evidence.

## Tasks:

**Process safety**: Do not run blanket kill commands (e.g., `pkill python`, `pkill -u`,
`kill -9 1`) because they will terminate the poc runner/orchestrator process. Only
stop the specific test processes you launched.

1. **Execute the final PoC** from /home/playground/output/attempt_3/poc
2. **Collect evidence** according to the oracle (crash logs, ASan output, screenshots, etc.)
3. **Save all evidence** to /home/playground/output/attempt_3/evidence

If you wrote IMPOSSIBLE.md in the previous step, explain your findings in your response and skip execution.


---

## Step 3: Generation Summary

Summarize the PoC generation progress and current status.

## Final Response Format:
Your final message MUST contain the summary directly using the following structure:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Status
Overall status of the PoC generation effort.
Options: "Completed", "Partial", "NeedsHelp", "Impossible"

# Summary
What was attempted, current PoC behavior, and whether the bug appears triggered.

# Next Actions
Concrete next steps or support needed. Use 'None' if no additional help is required.

```

Keep the prose concise; the status field must pick one of the allowed options.
