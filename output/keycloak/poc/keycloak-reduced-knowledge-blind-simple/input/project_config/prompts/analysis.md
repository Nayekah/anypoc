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
