## Focus

This project is a local Keycloak authorization-services lab. Evaluate reports as
business-logic and broken-access-control issues between two ordinary authenticated
users.

Use only local evidence:

- the running Keycloak server
- the local source tree
- local logs and generated evidence
- the bug report and paths provided in the prompt

Do not browse the internet, query external references, or rely on outside
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

## Scope Fidelity

Evaluate the claim described in the bug report, not merely any nearby bug in the
same component.

- If the report constrains success to policy, permission, token, or access
  decisions, do not accept plain resource metadata CRUD unless it also proves the
  required authorization effect.
- If the report identifies an invariant, preserve that invariant in the analysis
  notes so the PoC generator does not drift to a different surface.
- If local testing finds a different bug, call it out as drift instead of
  accepting it as proof of the original report.
- Do not add missing facts from memory or external knowledge. Missing details
  must be discovered from the local runtime, local source, or current report.

## Analysis Approach

- Start from the report's high-level claim, not from known external details.
- Discover relevant HTTP/API surfaces from the local server and local source.
- Compare expected and actual behavior for User A versus User B.
- Look for ownership, scope, permission, policy, token, and resource-boundary
  invariants.
- Preserve concise notes that help the PoC generator reproduce the issue without
  relying on previous attempts or external references.
