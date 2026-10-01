# Evidence Checker Prompts

---

## Step 1: Evidence Analysis

Read the provided evidence only to understand what was claimed and what signals to expect.

Do **not** decide validity based on the evidence alone — the only thing that matters is whether reproduction
succeeds. Treat the evidence as a hint about expected behavior, not as proof.

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


## Inputs to read:
- Evidence files: /home/playground/output/attempt_1/evidence
- POC artifacts: /home/playground/output/attempt_1/poc

Provide a concise summary of what the evidence claims should happen and what signals to look for during reproduction.

---

## Step 2: Reproduction

Attempt to reproduce the POC independently. The provided evidence may be incomplete or even incorrect,
so rely on your own execution results.

Use the validated bug report context established in the previous step.

## POC Location: /home/playground/output/attempt_1/poc

## Your Tasks:

1. Copy the POC to your reproduction workspace: /home/playground/output/attempt_1/reproduce
2. Execute the POC following the same steps as the original
3. Collect new evidence of the reproduction attempt
4. Save reproduction evidence to: /home/playground/output/attempt_1/reproduce/evidence/

## Important:
- Follow the exact same execution steps
- Record all outputs, logs, and any crashes
- Note any differences from the original evidence
- If the POC requires specific setup, document it

## Project-Specific Instructions:
## Evidence Requirements

A PoC only passes if it demonstrates a real cross-user authorization failure in the vulnerable Keycloak UMA workflow.

Required evidence:

1. The script authenticates as the low-privilege attacker user `marta`, not as admin.
2. The script identifies both the attacker-owned resource and the victim-owned resource.
3. The script sends the vulnerable UMA policy request over HTTP to the Keycloak protection API.
4. The evidence captures the body/path mismatch:
   the path references `marta`'s resource while the request body references `kolo`'s resource.
5. The resulting authorization state proves unauthorized access, such as successful authorization or token issuance for the victim-owned resource.

## Failure Cases

Mark the attempt as failed if any of these are true:

- The exploit depends on direct Java execution, database edits, or admin-only actions as the attack step.
- The PoC never demonstrates cross-user effect on the victim-owned resource.
- The result is only a 400, 403, or parsing error.
- The script uses a patched Keycloak version at or above 26.5.7 for the exploit.

## Good Evidence Patterns

- Show the token subject or username is `marta`.
- Save the malicious policy creation request body and response.
- Save a successful authorization response for `kolo`'s resource after the policy injection.
- Save enough metadata to correlate resource names to ids.

## Local Validation Tips

- Use `/opt/keycloak-lab/scripts/keycloak_status.sh` if readiness is unclear.
- Prefer deterministic requests against seeded resource names from `/opt/keycloak-data/seed-info.json`.
- If you obtain an RPT or authorization response, save the raw token or response body and a decoded excerpt if practical.


Report whether the reproduction succeeded or failed.

---

## Step 3: Status Determination

Based on your reproduction attempt, determine the final status. Trust your own run results over any
claimed evidence.

## Reproduction workspace: /home/playground/output/attempt_1/reproduce

## Allowed statuses:
- PASSED: Reproduction succeeded and bug manifested
- FLAKY: Reproduction is inconsistent but signals suggest the bug is real
- NOT_REPRODUCIBLE: Reproduction failed and the PoC appears invalid
- INVALID_EVIDENCE: Reproduction failed and prior evidence looks incorrect/misleading
- IMPOSSIBLE: Fundamental blocker prevents reproduction (environment, missing hardware, etc.)

## User-Triggerability Check

In addition to reproduction, evaluate whether the PoC clearly represents something a
real user or attacker could trigger through normal interaction surfaces (file input,
network request, API call, etc.).

- A good PoC makes it obvious to a triaging developer that the bug is reachable from
  user-controlled input, without requiring them to trace code paths.
- If the PoC only calls internal functions in a way that simulates state that users cannot reach,
  reject the PoC as invalid or impossible.
- You should NOT reject all internal tests or PoCs with code modifications.
  Some such PoCs are genuinely useful if they clearly demonstrate a user-triggerable scenario that is hard to set up otherwise.

## Final Response Format:
Your final message MUST contain the full check result directly using the following structure:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Status
Result after attempting to reproduce the PoC.
Options: "Passed", "Flaky", "NotReproducible", "InvalidEvidence", "Impossible"

# Reproduction Summary
Key steps and observations from the reproduction attempt, including whether the bug manifested.

# Conclusion
Why this status was chosen and any follow-up actions for the PoC or environment.

```
