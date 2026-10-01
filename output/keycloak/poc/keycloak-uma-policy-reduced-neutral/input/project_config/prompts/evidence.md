## Evidence Requirements

The PoC passes only if it demonstrates a real broken-access-control or
business-logic authorization failure in the local Keycloak lab.

Required evidence:

1. The attack step is performed as a low-privilege authenticated user.
2. A separate victim user, victim-owned object, or protected authorization
   boundary is identified.
3. There is a denied or unauthorized baseline before the attack step, when
   practical.
4. After the attack step, the low-privilege user receives an authorization result
   or access effect that should belong only to the victim or owner.
5. Raw request/response artifacts are saved under the attempt output directory.

## Scope Match

Check that the PoC proves the same claim and success criteria described in the
bug report and analysis.

- Pass only when the final oracle demonstrates the required authorization effect.
- Fail when the PoC demonstrates a different endpoint, different trust boundary,
  or only metadata CRUD while the report requires policy, permission, token, or
  access-decision impact.
- Fail when the PoC has no clear attacker/victim distinction, no owned resource
  boundary, or no before/after authorization comparison.

Fail the attempt if the proof depends on internet content, direct source patching,
database edits, in-process Java calls, admin-only exploit steps, or stale files
from previous attempts.

Use only current-attempt files and the local Keycloak runtime when checking
evidence.
