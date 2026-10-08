# Title: Reflected XSS in OpenBao direct OIDC callback error handling

## Summary

OpenBao 2.5.1 renders attacker-controlled `error_description` as executable HTML in the `callback_mode=direct` OIDC failure page at the OpenBao origin. This crosses the browser same-origin boundary and permits script execution in that origin. Fixed in 2.5.2.

## Threat Model

An attacker supplies a crafted callback URL and causes a victim to open it. The attacker-controlled script executes in the OpenBao origin, exposing same-origin UI state and enabling same-origin actions.

## Preconditions

- OIDC/JWT authentication is enabled.
- The selected role uses `callback_mode=direct`.
- The victim opens an attacker-controlled callback URL.
- No prior authentication is required.

## Entry Point

`GET /v1/auth/<mount>/oidc/callback`

Relevant inputs are valid `state` and attacker-controlled `error_description`.

## Root Cause

`builtin/credential/jwt/path_oidc.go` passes the provider error detail to `loginFailedResponse`. `builtin/credential/jwt/html_responses.go` interpolates it into HTML without context-appropriate escaping.

## Expected Behavior

Provider error details must be rendered inertly, preferably using a static failure message or context-appropriate HTML escaping.

## Actual Behavior

The callback returns HTTP 400 `Content-Type: text/html` containing the raw `error_description`. The PoC payload executes during DOM parsing.

## Reproduction

Using the attached `run_poc.sh`:

1. Verify the local runtime reports OpenBao 2.5.1.
2. POST to `/v1/auth/oidc/oidc/auth_url` for role `lab-direct` and obtain fresh state.
3. Request `/v1/auth/oidc/oidc/callback` with that state and:
   `<script>document.body.setAttribute("data-xss","XSS_MARKER")</script>`
4. Run `verify_dom.js` against the captured response body.

## Evidence And Oracle

Raw requests, responses, headers, traces, and results are retained under `evidence/20261008T121253Z-1132/`. `summary.txt` records HTTP 400, `text/html`, one raw payload occurrence, and the DOM oracle. `dom-oracle.txt` reports `body_data_xss=XSS_MARKER`. The benign control also confirms ordinary marker reflection.

## Impact

Demonstrated: attacker-controlled script execution in a same-origin DOM.

Plausible: access to Web UI state and same-origin actions, including use of tokens available to that origin. Token extraction and authenticated actions were not performed by the PoC.

## Limitations

The PoC uses only the local OpenBao runtime and local OIDC provider, role `lab-direct`, and `callback_mode=direct`. Other callback modes, authentication methods, browser behavior beyond the `jsdom` oracle, and the fixed 2.5.2 behavior were not tested.