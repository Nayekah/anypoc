# Evidence Checker Prompts

---

## Step 1: Evidence Analysis

Read the provided evidence only to understand what was claimed and what signals to expect.

Do **not** decide validity based on the evidence alone — the only thing that matters is whether reproduction
succeeds. Treat the evidence as a hint about expected behavior, not as proof.

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


## Inputs to read:
- Evidence files: /home/playground/output/attempt_3/evidence
- POC artifacts: /home/playground/output/attempt_3/poc

Provide a concise summary of what the evidence claims should happen and what signals to look for during reproduction.

---

## Step 2: Reproduction

Attempt to reproduce the POC independently. The provided evidence may be incomplete or even incorrect,
so rely on your own execution results.

Use the validated bug report context established in the previous step.

## POC Location: /home/playground/output/attempt_3/poc

## Your Tasks:

1. Copy the POC to your reproduction workspace: /home/playground/output/attempt_3/reproduce
2. Execute the POC following the same steps as the original
3. Collect new evidence of the reproduction attempt
4. Save reproduction evidence to: /home/playground/output/attempt_3/reproduce/evidence/

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

## Reproduction workspace: /home/playground/output/attempt_3/reproduce

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
