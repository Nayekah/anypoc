# Status
Passed

# Reproduction Summary
The bug reproduced successfully in `/home/playground/output/attempt_1/reproduce` using the live Keycloak lab on version `26.5.6`.

Key observations from my run:
- The provided `poc/` directory did not contain a runnable exploit; it only contained summary files saying no PoC had been generated.
- I therefore relied on the independently executed runner in [`run_repro.sh`](/home/playground/output/attempt_1/reproduce/run_repro.sh) and saved fresh evidence under [`reproduce/evidence/`](/home/playground/output/attempt_1/reproduce/evidence).
- The attacker authenticated as low-privilege user `marta`.
- A fresh victim-owned resource for `kolo` was created to avoid contaminated prior lab state.
- Before the exploit, `marta`’s UMA request for the victim resource returned `403`.
- The exploit then sent a normal HTTP request to `POST /realms/anypoc/authz/protection/uma-policy/{martaResourceId}` while the JSON body referenced `kolo`’s victim resource ID.
- That policy creation request succeeded with `200`.
- Querying policies by the victim resource returned the newly created Marta-owned UMA policy.
- After the policy injection, the same UMA authorization request for the victim resource succeeded with `200`, and the decoded token payload contained the victim resource `rsid`.

Supporting evidence is in:
- [`summary.json`](/home/playground/output/attempt_1/reproduce/evidence/summary.json)
- [`create_policy_request.json`](/home/playground/output/attempt_1/reproduce/evidence/create_policy_request.json)
- [`query_policy_response.json`](/home/playground/output/attempt_1/reproduce/evidence/query_policy_response.json)
- [`after_uma_access_token_payload.json`](/home/playground/output/attempt_1/reproduce/evidence/after_uma_access_token_payload.json)
- [`REPRO_NOTES.md`](/home/playground/output/attempt_1/reproduce/evidence/REPRO_NOTES.md)

# Conclusion
`Passed` is the correct status because reproduction succeeded and the bug manifested as a real cross-user authorization failure. The attacker gained authorization for a victim-owned resource through standard HTTP API calls, so the scenario is clearly user-triggerable through normal network request surfaces and does not depend on internal-only function calls.

The only caveat is that the original `poc/` directory did not contain a runnable PoC, so the reproduced evidence comes from an independently executed HTTP-based PoC rather than from replaying an upstream script verbatim. That affects provenance of the supplied PoC, but not the validity of the reproduced bug.