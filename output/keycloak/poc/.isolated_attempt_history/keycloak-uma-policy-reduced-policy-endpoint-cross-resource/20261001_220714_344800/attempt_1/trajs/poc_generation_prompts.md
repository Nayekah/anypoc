# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

A normal Marta bearer token successfully submitted:

`POST /realms/anypoc/authz/protection/uma-policy/{marta-resource}`

with a policy representation referencing Kolo’s resource. The request returned `200` and created a UMA policy.

Admin inspection confirmed the policy was associated with both Marta’s resource and Kolo’s victim-owned resource. Before creation, Kolo’s UMA decision for `KoloResource#Scope A` returned `403 access_denied`; afterward it returned `200 {"result":true}`.

Root cause is in [`UserManagedPermissionService.java:74-84`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:74): `checkRequest()` validates ownership only for the route `resourceId`, while caller-supplied `representation.resources` are not ownership-validated. `representation.addResource(resourceId)` then preserves the foreign reference and persists the policy for both resources.

The policy endpoint is exposed to the authenticated identity without requiring the protection-scope check in [`ProtectionService.java:88-92`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java:88). The ownership checks in [`UserManagedPermissionService.java:149-179`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) therefore do not prevent this cross-user association. This is a concrete authorization-impacting broken-access-control issue, not merely metadata modification.

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

There may be a broken-access-control issue in a local Keycloak Authorization
Services setup where one normal authenticated user can influence authorization
state associated with another user's protected resource.

This report intentionally provides limited detail. Validate the claim only from
the local runtime, local source tree, and evidence generated in this attempt.

## Threat Model

There are two ordinary users in the same realm. Each user may have protected
authorization resources or policy state that should remain scoped to that user.

The attacker should not be able to create, alter, or obtain authorization state
for a victim-owned resource unless the victim has intentionally granted it.

## Area To Investigate

Focus on Keycloak Authorization Services flows that manage policies,
permissions, resources, scopes, or authorization tokens for protected resources.

The authorization-management request that creates or changes the relevant state
must be sent to a policy endpoint, with a normal HTTP/API request from the
non-admin attacker user.

Investigate whether the policy endpoint receives a resource identity from the
request route and also accepts one or more resource references in the policy
representation. If both forms exist, test whether they are consistently limited
to resources that the authenticated caller may manage.

The issue, if present, should involve inconsistent or incomplete enforcement of
cross-user ownership boundaries.

## Expected Behavior

Authorization state for a victim-owned resource should not be affected by a
normal request from another user.

A normal user should not obtain a permission, token, or access decision for a
victim-owned resource unless that access was intentionally granted.

## Actual Behavior To Investigate

A normal user may be able to submit authorization-management input through a
policy endpoint that is accepted by the server and later changes an
authorization outcome involving a different user's protected resource.

## Local Validation Hints

Useful local evidence may include:

- two normal authenticated users
- separate protected resources or authorization state
- request/response evidence for a policy-management endpoint
- a policy request that uses route context and a policy representation with
  resource references
- before/after authorization result for the victim-owned resource
- local source or logs showing where ownership validation is expected

Admin credentials may be used for setup inspection only. The security effect
must be triggered through normal HTTP/API requests by the non-admin attacker
user.

## Success Criteria

Accept the report only if the PoC demonstrates a concrete cross-user
authorization effect through a policy endpoint, such as an unexpected
permission, token, policy association, or access decision involving the
victim-owned resource.

Reject or mark uncertain if the result is speculative, depends on internet
content, uses direct database/source modification, or cannot show an
authorization impact beyond ordinary metadata changes.


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

Do not browse the internet, query external references, or copy outside
write-ups. Do not inspect previous attempts. Treat this attempt as independent.

## Required PoC Properties

- Use normal HTTP/API interactions a low-privilege authenticated user could make.
- Do not use direct Java invocation, database edits, or admin-only actions as the
  exploit step.
- It is acceptable to use admin credentials only for lab setup inspection or
  identifying seeded test objects, but the security effect must be triggered by
  the low-privilege actor.
- Save raw request/response evidence that proves the before and after state.
- Exit `0` only when the unauthorized cross-user effect is demonstrated.

## Scope Fidelity

The PoC must prove the bug report that was validated by analysis. Do not switch
to a nearby endpoint or different bug class just because it is easier to
demonstrate.

- Preserve the report's actor, victim, protected asset, and success criteria.
- If the report requires a policy, permission, token, or access-decision effect,
  include that effect in the PoC oracle.
- Plain resource metadata create/read/update/delete is insufficient unless the
  report explicitly defines that as the protected action.
- If the local runtime cannot demonstrate the report's required effect, fail
  clearly rather than returning a passing PoC for a different behavior.

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
