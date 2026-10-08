## Scope

Evaluate the current report against the disposable local OpenBao lab. Do not
assume a vulnerability class, protocol, route, parameter, trust boundary, or
impact that the report does not establish.

Use only the running local services, local source tree, local logs, current
report, and files created in the current attempt. Do not browse the internet,
query external references or vulnerability databases, install packages, or
inspect previous attempts.

## Validation Standard

- Identify the report's concrete claim and required preconditions.
- Discover relevant configuration and entry points from the local environment.
- Exercise the claim through a normal externally reachable interface.
- Preserve the request, response, and a deterministic observation of the
  claimed behavior.
- Use a benign control when it is needed to distinguish a security issue from
  expected behavior, inert data, or a generic error.
- Correlate runtime behavior with local source only after locating the actual
  execution path.

Mark the report valid only when reproducible local evidence demonstrates the
reported boundary violation and meaningful security consequence. Reject claims
that are speculative, depend only on source inspection, require modifying the
target, arise only from the harness, or drift to a different surface.

Keep all tests non-destructive and local.
