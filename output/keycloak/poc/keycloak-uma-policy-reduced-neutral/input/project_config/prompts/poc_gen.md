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
