## Reproduction Result

Succeeded.

## Provided PoC Input

The provided PoC directory `/home/playground/output/attempt_1/poc` did not contain a runnable exploit.
It only contained:

- `generation_summary.json`
- `generation_summary.md`

Those files state that no working PoC had been generated.

## Execution Difference

Because there was no runnable PoC to copy and execute verbatim, the reproduction used the independently
created HTTP-based runner:

- `/home/playground/output/attempt_1/reproduce/run_repro.sh`

This runner reproduces the validated Keycloak UMA issue through normal network requests against the live
lab instance.

## What This Run Demonstrates

1. Authentication as low-privilege user `marta`
2. Identification of attacker and victim resources
3. Cross-boundary UMA policy creation where:
   - the URL path uses `marta`'s resource
   - the JSON body references a fresh `kolo`-owned resource
4. Unauthorized authorization success for the victim resource after policy injection

## Key Evidence Files

- `attacker_token_response.json`
- `create_resource_response.json`
- `create_policy_request.json`
- `create_policy_response.json`
- `query_policy_response.json`
- `before_uma_response.json`
- `after_uma_response.json`
- `after_uma_access_token_payload.json`
- `summary.json`

## Key Result

From `summary.json`:

- `before_status`: `403`
- `create_status`: `200`
- `after_status`: `200`
- `outcome`: `reproduced`
