## Constraints

Create a minimal deterministic PoC for the behavior validated during analysis.
Use only the current report, current analysis, local source, local services, and
current-attempt files.

Do not browse the internet, query external references, install packages,
inspect previous attempts, or copy a public exploit. Do not patch the target,
edit its storage directly, or invoke internal implementation functions in place
of the externally reachable interface.

## Requirements

- Reproduce the same claim and preconditions validated by analysis.
- Use a normal public interface and obtain any required runtime values through
  their normal flow.
- Use only harmless inputs and local observations.
- Include an appropriate negative or benign control when needed.
- Preserve raw requests, responses, and the deterministic pass/fail evidence.
- Fail closed when the target is unavailable, prerequisites are missing, the
  observation is ambiguous, or the result belongs to another surface.

Put the final reproducer under `poc/` with `run_poc.sh` as the entry point and at
most one small helper. Keep exploratory artifacts under `playground/`.

`run_poc.sh` must exit `0` only when the validated security behavior and its
oracle are both observed; otherwise it must exit nonzero.
