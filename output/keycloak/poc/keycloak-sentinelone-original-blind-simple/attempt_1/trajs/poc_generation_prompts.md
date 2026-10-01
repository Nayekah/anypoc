# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

- I checked the authz service code in [ProtectionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java) and [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java).
- `UserManagedPermissionService` is owner-checked for UMA policy operations. In source, it calls `checkRequest(...)` and rejects non-owners with `Only resource owner can access policies for resource [...]`.
- I validated that behavior live: with `marta`'s token, `POST /realms/anypoc/authz/protection/uma-policy/29c256df-08c3-4b61-823b-cd45b8ee7ee9` returned `400` and the expected owner error for the victim-owned resource.
- The real issue is the resource-management path, implemented in `org.keycloak.authorization.protection.resource.ResourceService` inside [org.keycloak.keycloak-services-26.5.6.jar](/opt/keycloak/lib/lib/main/org.keycloak.keycloak-services-26.5.6.jar). That endpoint only requires the `uma_protection` role and trusts caller-controlled ownership data.
- Live proof with a normal authenticated user:
  - `marta` has the `resource-server-test` client role `uma_protection`; `kolo` does not.
  - `POST /realms/anypoc/authz/protection/resource_set` with body `{"name":"cross-owner-probe","ownerManagedAccess":true,"owner":"kolo","scopes":["Scope A"]}` returned `201 Created` and created a resource owned by `kolo`.
  - `GET`, `PUT`, and `DELETE` against `/realms/anypoc/authz/protection/resource_set/29c256df-08c3-4b61-823b-cd45b8ee7ee9` using `marta`'s token succeeded, including `DELETE 204 No Content` on a victim-owned resource.
- That means a low-privileged authenticated user can directly modify and delete another user's protected resource state through the normal UMA protection API. This is a real broken-access-control issue, not a test-only artifact.
- The report is slightly imprecise about the exact surface: the vulnerable behavior is in resource-set management, not UMA policy management. The consequence is stronger than simple “namespace pollution”: an attacker can take over or destroy victim-owned protected resources and thereby influence authorization state across the user boundary.

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

A normal authenticated user may be able to influence authorization state across a
user boundary in a local Keycloak authorization-services deployment.

## Threat Model

There are two ordinary users in the same realm. Each user has authorization state
or protected objects that should not be controlled by the other user.

## Suspected Issue

An authorization-management flow may trust caller-controlled request data too
much and allow state associated with one user or object to affect another user or
object.

## Expected Behavior

Actions performed by User A should remain limited to resources or authorization
state User A is allowed to manage.

## Actual Behavior To Validate

User A may be able to cause an authorization result involving User B's protected
state through normal product APIs.

## Impact

If confirmed, this is a broken-access-control issue that can grant unauthorized
cross-user access or permission effects.


## Available Paths:
Target runtime:

- Source tree: `/opt/keycloak-source`
- Keycloak distribution: `/opt/keycloak`
- Server launcher: `/opt/keycloak/bin/kc.sh`
- Admin CLI: `/opt/keycloak/bin/kcadm.sh`
- Health helper: `/opt/keycloak-lab/scripts/keycloak_status.sh`
- Base URL: `http://127.0.0.1:8080`
- Health URL: `http://127.0.0.1:9000/health/ready`

Lab credentials:

- Admin: `admin` / `adminpass`
- User A: `marta` / `password`
- User B: `kolo` / `password`
- Client: `resource-server-test`
- Client secret: `secret`
- Realm: `anypoc`

Experiment scope:

- Treat this as a local Keycloak authorization-services lab.
- Focus on business-logic and broken-access-control behavior between two normal users.
- Prefer normal HTTP/API flows over direct database edits or in-process Java calls.
- Do not use internet search or external documentation. Work only from the local runtime, local source tree, and local behavior.
- The report may be incomplete or wrong; validate the claim from local evidence.


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
## Constraints

Build a deterministic PoC against the running local Keycloak server at
`http://127.0.0.1:8080`.

Use only local inputs:

- the validated bug report
- the local source tree
- the running local service
- local files generated during this attempt

Do not browse the internet, query public vulnerability databases, or copy known
public reproduction steps. Do not inspect previous attempts. Treat this attempt
as independent.

## Required PoC Properties

- Use normal HTTP/API interactions a low-privilege authenticated user could make.
- Do not use direct Java invocation, database edits, or admin-only actions as the
  exploit step.
- It is acceptable to use admin credentials only for lab setup inspection or
  identifying seeded test objects, but the security effect must be triggered by
  the low-privilege actor.
- Save raw request/response evidence that proves the before and after state.
- Exit `0` only when the unauthorized cross-user effect is demonstrated.

## Output Shape

Put final files under `poc/`:

- `run_poc.sh` as the main runner
- one small helper script if needed
- a short README or comments only if required to run the PoC

Keep experiments under `playground/`. Move only the clean, reproducible version to
`poc/`.



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
