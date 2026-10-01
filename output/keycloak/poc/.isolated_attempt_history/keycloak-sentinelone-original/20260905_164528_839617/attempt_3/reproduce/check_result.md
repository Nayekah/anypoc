# Status
Passed

# Reproduction Summary
I reproduced the issue independently in `/home/playground/output/attempt_3/reproduce` against the live Keycloak lab on `Keycloak 26.5.6`, which is below the fixed `26.5.7` threshold.

The successful flow was entirely user-triggerable over normal HTTP surfaces:

1. Authenticated as low-privilege user `marta` via the OIDC token endpoint.
2. Created fresh attacker-owned and victim-owned UMA resources over the protection API to avoid relying on contaminated pre-seeded state.
3. Verified the clean baseline: `marta` requesting authorization for the fresh victim-owned resource returned `403 not_authorized`.
4. Sent the malicious HTTP request to `POST /realms/anypoc/authz/protection/uma-policy/{marta_resource_id}` while the JSON body also included `kolo`’s resource ID.
5. Keycloak accepted the mismatched policy creation with `200`.
6. Re-ran the same UMA authorization request as `marta` for the victim-owned resource, and it succeeded with `200`; the decoded token showed `preferred_username: "marta"` and `authorization.permissions[0].rsid` equal to the victim resource ID.

Saved evidence is under `/home/playground/output/attempt_3/reproduce/evidence`, including:
- `marta_access_token.payload.json`
- `resource_map.json`
- `baseline_authorization.*`
- `malicious_policy.path.txt`
- `malicious_policy.request.json`
- `malicious_policy_create.*`
- `post_authorization.access_token.payload.json`
- `summary.txt`

# Conclusion
`Passed` is the correct status because the bug manifested during my own run, with a clean before/after authorization oracle and a clear cross-user effect. This is a real user-triggerable scenario: an authenticated non-admin user exercised normal OIDC and UMA protection HTTP APIs, without admin-only exploit steps, Java internals, database edits, or test harness shortcuts.

The only notable difference from the provided artifact set is that `/home/playground/output/attempt_3/poc` did not contain a runnable PoC, and the seeded victim resource was already grantable due to prior lab state. I handled that by using fresh per-run resources and documented the difference in `reproduce/evidence/differences.txt`.