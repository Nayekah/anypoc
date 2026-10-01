---
keywords:
- keycloak
- poc form
- bash harness
- curl
- jq
- evidence directory
- http artifacts
- jwt decode
- authorization bug
times_used: 0
times_useful: 0
---

A reusable Keycloak PoC form for authz issues is a standalone Bash runner that talks only to Keycloak's HTTP endpoints and preserves every request/response artifact under a timestamped evidence directory.

Useful structure from the successful run:

- Require only `curl` and `jq`.
- Create a per-run evidence directory like `evidence/<UTC timestamp>_<slug>/`.
- Wrap HTTP calls so each request writes three artifacts: response headers, response body, and a separate `.status` file containing the HTTP code.
- Perform a readiness wait before the first request.
- Capture a baseline authorization check before the state-changing request.
- Apply the state-changing request through the public API.
- Capture the post-condition authorization check after the change.
- Decode any returned JWT access token into a JSON file for stable assertions on `authorization.permissions`.
- Preserve a short `summary.txt` with the baseline status, mutation status, and post-condition status.

For deterministic reruns in the seeded Keycloak lab, the successful runner also removed attacker-owned preexisting UMA policies through the public protection API before checking the baseline. That keeps the PoC focused on the current run instead of leftover lab state.

This form is appropriate for server-side authorization bugs where the user capability is an HTTP client with valid credentials, not a browser-only workflow.