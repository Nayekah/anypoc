# Bug Analyzer Prompt

Analyze this bug report to determine if it describes a real vulnerability.

## Bug Report:
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


## Your Tasks:

1. **Validity Check**: Determine if this bug report describes a real security issue or is likely a false positive.
   - Look for indicators of a real bug: clear reproduction steps, specific code paths, memory safety issues, etc.
   - Look for false positive indicators: misunderstanding of intended behavior, incomplete analysis, etc.
   - You may examine the codebase under the playground directory to verify claims.

2. **If the bug is VALID**: Confirm the bug appears real and exploitable.
   - In your analysis_details, summarize: key files/functions you examined, your understanding of the
     bug mechanism, the root cause location, and any relevant context that will help with PoC generation.

3. **If the bug is INVALID (likely false positive)**: Explain clearly why in analysis_details.

## Project-Specific Instructions:
## Focus

This project is a local Keycloak authorization-services lab. Evaluate reports as
business-logic and broken-access-control issues between two ordinary authenticated
users.

Use only local evidence:

- the running Keycloak server
- the local source tree
- local logs and generated evidence
- the bug report and paths provided in the prompt

Do not browse the internet, search public advisories, or rely on external
vulnerability-database knowledge. If you recognize the issue, still validate it
from local behavior and do not assume the exact root cause.

## Validity Criteria

Accept a report only when local testing or source inspection supports all of the
following:

1. There is a low-privilege authenticated actor.
2. There is a separate victim user, victim-owned object, protected operation, or
   authorization boundary.
3. The actor can influence or obtain access across that boundary through a normal
   Keycloak HTTP/API flow.
4. The behavior is not explained by intended admin privilege, test-only setup, or
   a purely local harness.

Reject or mark uncertain when the claim is only speculative, requires admin-only
actions as the exploit step, requires patching the server, or cannot be tied to a
real authorization impact.

## Analysis Approach

- Start from the report's high-level claim, not from known public vulnerability details.
- Discover relevant HTTP/API surfaces from the local server and local source.
- Compare expected and actual behavior for User A versus User B.
- Look for ownership, scope, permission, policy, token, and resource-boundary
  invariants.
- Preserve concise notes that help the PoC generator reproduce the issue without
  relying on previous attempts or external references.


## Final Response Format:
Your final message MUST include the structured analysis result:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Verdict
Whether the bug report is considered valid or invalid.
Options: "Valid", "Invalid"

# Rejection Reason
If invalid, pick the closest reason; use Other when the report is valid.
Options: "OutOfMemory", "HardwareLimitation", "UnsupportedOperatingSystem", "EnvironmentConstraint", "Other"

# Analysis Details
If invalid: brief reasoning for rejection. If valid: summary of exploration including key files/functions examined, understanding of the bug mechanism, root cause location, and relevant context for PoC generation.

```
