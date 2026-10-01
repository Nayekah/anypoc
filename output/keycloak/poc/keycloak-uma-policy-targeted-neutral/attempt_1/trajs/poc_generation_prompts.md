# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

- I inspected the protection API entrypoint in [`ProtectionService.java`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/ProtectionService.java#L88) and the user-managed policy handler in [`UserManagedPermissionService.java`](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java#L74).
- The root cause is in `UserManagedPermissionService.create()`: it validates only the path resource via `checkRequest(resourceId, representation)`, then unconditionally appends that route resource with `representation.addResource(resourceId)` and calls `delegate.create(representation)`. It does not validate or strip any preexisting `representation.getResources()` supplied in the request body.
- The update path is different: `update()` explicitly rejects resource changes when the body contains a resource set that does not match the associated resource. That makes the missing create-time validation the relevant gap, not an intended feature.
- The existing test suite reinforces the intended invariant for updates in [`UserManagedPermissionServiceTest.java`](/opt/keycloak-source/testsuite/integration-arquillian/tests/base/src/test/java/org/keycloak/testsuite/authz/UserManagedPermissionServiceTest.java#L343), but it does not cover the create-time cross-resource case.
- Live validation on the running lab confirmed the impact:
  - Baseline UMA authorization for Marta against the victim resource `f872c1d2-a1e5-49b7-9548-b38d10a915e6` returned `403 access_denied not_authorized`.
  - Baseline authorization for Marta against her own resource `a10797fc-7b38-4d82-807f-dbda2d32576a` was also denied before the policy was created.
  - A POST to `/realms/anypoc/authz/protection/uma-policy/a10797fc-7b38-4d82-807f-dbda2d32576a` with body `{"name":"cross-boundary","users":["marta"],"resources":["f872c1d2-a1e5-49b7-9548-b38d10a915e6"]}` succeeded with `200 OK`.
  - After creation, listing policies filtered by `resource=f872c1d2-a1e5-49b7-9548-b38d10a915e6` returned that same policy id `6d8c905a-7056-4c27-8ecf-2f2a5f2c3665`.
  - A follow-up UMA ticket grant for the victim resource returned `200 OK` and the issued token contained an authorization permission whose `rsid` was the victim resource id, proving the policy now affected the other user’s protected resource.
- Conclusion: the report is real. The inconsistent ownership validation in `UserManagedPermissionService.create()` lets a normal authenticated user create a policy on their own resource context while also binding it to a victim-owned resource from the request body, which changes authorization outcomes across the user boundary.

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

A normal authenticated user may be able to influence an authorization policy
decision for another user's protected resource by submitting inconsistent
resource identity data through a Keycloak Authorization Services policy-management
flow.

This report is intentionally written without external identifiers, version
claims, or copied public guidance. Validate only against the local runtime and
local source tree.

## Threat Model And Roles

The attacker is a normal authenticated user in the local realm who has the
minimum role needed to use the authorization protection API for the test client.
The victim is a different normal user who owns a separate protected resource.

The boundary under test is per-user resource ownership during policy creation,
policy association, and the resulting authorization decision.

## Protected Asset Or Action

The protected asset is the victim user's authorization-managed resource and any
policy, permission, token, or access decision that should apply only when the
victim has intentionally granted access.

The attacker should not be able to cause a policy created through the attacker's
resource context to also apply to a victim-owned resource.

## Entry Point

Investigate the Keycloak Authorization Services protection API, specifically the
user-managed permission or policy-management surface that accepts:

- a resource selected by the request path or route context
- a policy representation or request body that may contain one or more resource
  identifiers
- scopes, claims, users, or requester metadata that influence authorization
  outcomes

Do not treat ordinary resource metadata CRUD as sufficient by itself. A valid
finding must involve policy creation or policy association and then show an
authorization effect.

## Security Invariant

For any policy-management request, all resource identifiers that influence the
created policy must be owned by, or otherwise legitimately manageable by, the
authenticated caller. The server must not validate only one resource context and
then trust additional resource identifiers supplied elsewhere in the same
request.

## Expected Behavior

If User A submits a policy request in the context of User A's resource, the
server should reject any request body that tries to bind, reference, or affect a
resource owned by User B unless User B has already granted the relevant
permission.

Follow-up authorization requests by User A for User B's resource should remain
denied.

## Actual Behavior To Validate

The suspected failure mode is inconsistent ownership validation between resource
identity sources in the same policy-management flow. A request may validate the
resource selected by the route while failing to reject a different victim-owned
resource supplied in the policy representation.

If this occurs, the attacker may be able to create authorization state that
references the victim resource and then obtain an authorization result that
should not be available.

## Local Validation Hints

Use only local sources and runtime behavior. Useful local evidence may include:

- two ordinary users with separate protected resources
- a low-privilege token for the attacker user
- resource ownership before the attempted policy operation
- the policy-management request body and response
- the resulting policy or permission state
- a denied baseline for victim-resource access before the policy operation
- a successful authorization result, permission decision, or token after the
  policy operation

The report should be rejected if the only demonstrated behavior is that the
attacker can create, read, update, or delete resource metadata without proving a
policy or authorization-decision effect.

## Preconditions

The local lab should provide:

- a running Keycloak server on localhost
- a realm dedicated to the experiment
- an authorization-services client
- two normal users
- separate owner-managed resources for those users
- credentials and local seed data sufficient to discover the relevant objects

Admin credentials may be used for setup inspection only. The exploit effect must
be triggered by the normal authenticated attacker user through normal HTTP/API
requests.

## Desired PoC Properties

A successful PoC should prove all of the following:

1. The attacker is authenticated as a normal user.
2. The victim resource is owned by a different normal user.
3. A baseline authorization attempt for the victim resource is denied or lacks
   the unauthorized grant.
4. The attacker submits a policy-management request where the route-selected
   resource and body-referenced resource set are not the same ownership domain.
5. The server accepts or persists the inconsistent policy association.
6. A follow-up authorization request shows the attacker obtained access,
   permission, or token state for the victim resource that should have remained
   denied.

Save raw request and response transcripts for each step. Exit successfully only
when the final authorization effect is demonstrated.

## Non-Goals And Drift Guards

Do not claim success for:

- internet-derived information or copied external text
- direct database writes, source patching, or in-process Java calls
- admin-only exploit steps
- resource metadata CRUD without a policy or authorization-decision effect
- a test that uses only one user or does not prove a cross-user ownership
  boundary


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
