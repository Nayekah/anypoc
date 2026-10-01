# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

I confirmed this is a real cross-user authorization flaw in the UMA policy creation path.

Key code path examined:
- `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74-84`
- `/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149-180`
- `/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java:343-406`

Root cause:
- `create(resourceId, representation)` calls `checkRequest(resourceId, representation)`, but `checkRequest(...)` only validates the resource in the URL path: existence, ownership, owner-managed access, remote management, and scopes.
- It does not reject extra resource IDs already present in `representation.getResources()`.
- After that, `create(...)` unconditionally runs `representation.addResource(resourceId)`.
- Result: a caller can post to `/uma-policy/{theirResourceId}` while smuggling a victim resource ID in the JSON body, producing a UMA policy associated with both resources.

The contrast with `update()` is important:
- `update()` explicitly rejects resource changes unless the resource set is empty or exactly the original resource.
- The existing regression test only covers that update-time invariant. There is no equivalent create-time guard in this vulnerable version.

HTTP validation on the live lab:
- Server is Keycloak `26.5.6` per `/var/log/keycloak/server.log`.
- `marta` initially hit a normal `VERIFY_PROFILE` required action, so I completed that standard login workflow once. After that, `marta` could authenticate normally.
- I created a fresh victim-owned resource `ANYPOC Kolo Resource 2` with ID `56d24373-dba4-439f-8ecb-4c479654f149`, owned by `kolo`.
- Before the exploit, `marta` requested a UMA token for that victim resource via `POST /realms/anypoc/protocol/openid-connect/token` with `grant_type=urn:ietf:params:oauth:grant-type:uma-ticket`, `audience=resource-server-test`, `permission=56d24373-dba4-439f-8ecb-4c479654f149` and got `403` with `{"error":"access_denied","error_description":"not_authorized"}`.
- Then `marta` sent `POST /realms/anypoc/authz/protection/uma-policy/fd1f69f8-dec4-467f-9541-0b172738bdf5` using her own resource in the path, with body `{"name":"cross-boundary-poc-2","users":["marta"],"resources":["56d24373-dba4-439f-8ecb-4c479654f149"]}`.
- That request succeeded and created policy `8f2838df-66be-4a80-aa21-684ab2a9bb8c`.
- `GET /realms/anypoc/authz/protection/uma-policy?resource=56d24373-dba4-439f-8ecb-4c479654f149` then returned that Marta-owned UMA policy, showing the victim resource had been bound into her policy state.
- After the policy create, the same UMA token request returned `200` and issued an access token whose `authorization.permissions` included `rsid=56d24373-dba4-439f-8ecb-4c479654f149` and `rsname="ANYPOC Kolo Resource 2"`.

Consequence:
- A low-privilege authenticated user can create permission state affecting a victim-owned resource and then obtain UMA authorization for that victim resource.
- This is a meaningful cross-user privilege escalation, not just a validation bug or 4xx-only issue.

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

There appears to be an authorization flaw in managed-resource policy creation. A regular authenticated user may be able to create or influence permission state for a resource they do not own by sending a policy-management request that crosses resource boundaries.

## Threat Model And Roles

Assume two normal users exist in the same deployment and each owns distinct protected resources. One user should not be able to manipulate authorization state for the other user's resource through standard product workflows.

## Protected Asset Or Action

The protected asset is another user's resource and the authorization decision attached to it. The protected action is any ability to grant, inherit, or obtain access that should remain scoped to the resource owner.

## Suspected Boundary Failure

The likely issue is not raw authentication bypass, but a broken access-control condition inside the authorization-management flow. The system may accept a request whose visible context belongs to one resource while some of the effective permission state ends up attached to a different resource.

## Minimal Context

- the issue should be testable through standard product functionality
- the attacker is not assumed to be an admin
- the behavior should be evaluated as a cross-user authorization problem

## Expected Vs Actual Behavior

Expected:

- authorization-management operations should remain bound to the caller's own resource scope
- references that escape that scope should be rejected

Actual:

- authorization state may cross from one user's resource boundary into another's
- the caller may receive access that violates normal ownership expectations

## Impact

If confirmed, this would allow one user to influence or obtain access to another user's protected resource through normal authorization features rather than through direct administrative control.


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
- **Playground (for experimentation):** /home/playground/output/attempt_1/playground
- **Final PoC (only when ready):** /home/playground/output/attempt_1/poc

## Your Approach:

1. **Experiment in playground first**: Use /home/playground/output/attempt_1/playground to test ideas,
try different approaches, and iterate on your PoC.
Create test files, run experiments, and verify your understanding of the bug.

2. **Verify the bug triggers**: Before finalizing, make sure you can actually trigger the bug.
Test your PoC in the playground and confirm it causes the expected behavior (crash, assertion failure, etc.).

3. **Finalize only when confident**: Once you have a working PoC that reliably triggers the bug, create a
**minimal, concise, end-to-end functional** version and copy it to /home/playground/output/attempt_1/poc.
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
write a file `/home/playground/output/attempt_1/poc/IMPOSSIBLE.md` explaining:

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

1. **Execute the final PoC** from /home/playground/output/attempt_1/poc
2. **Collect evidence** according to the oracle (crash logs, ASan output, screenshots, etc.)
3. **Save all evidence** to /home/playground/output/attempt_1/evidence

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
