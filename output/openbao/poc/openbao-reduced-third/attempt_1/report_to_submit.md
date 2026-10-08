# Title: Reflected XSS in direct OIDC callback error handling

## Summary

OpenBao reflects attacker-controlled OIDC `error_description` data into an HTML error response without escaping. In the seeded direct-callback flow, this crosses the OIDC-to-browser security boundary and permits HTML/script injection.

## Threat Model

An OIDC provider or attacker controlling the authentication redirect supplies `error_description`. A victim initiates OIDC login and follows the resulting callback. The victim’s OpenBao browser session and UI origin are at risk.

## Preconditions

- OIDC mount `oidc` is configured.
- Role `lab-direct` uses `callback_mode: direct`.
- A valid OIDC state is obtained from `auth_url`.
- The victim follows the callback in a browser.

## Entry Point

`GET /v1/auth/oidc/oidc/callback`

Relevant inputs:

- `state`
- `error_description`

The preceding flow uses `POST /v1/auth/oidc/oidc/auth_url` with role `lab-direct`.

## Root Cause

[`path_oidc.go:269`](/opt/openbao-source/builtin/credential/jwt/path_oidc.go:269) reads `error_description` and passes it to `loginFailedResponse`. For direct callbacks, [`path_oidc.go:216`](/opt/openbao-source/builtin/credential/jwt/path_oidc.go:216) inserts it into `errorHTML`. [`html_responses.go:357`](/opt/openbao-source/builtin/credential/jwt/html_responses.go:357) uses `fmt.Sprintf` without HTML escaping.

## Expected Behavior

Failure data must be HTML-escaped or replaced with a fixed safe error message before rendering.

## Actual Behavior

The callback returns `400 text/html` and reflects the supplied markup verbatim. The payload `</p><script>document.title='OPENBAO-LAB-XSS-7F'</script><p>` appeared unescaped in the response body.

## Reproduction

Run [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh). It:

1. Requests an authorization URL and state for `lab-direct`.
2. Calls the callback with a control marker.
3. Calls it again with the deterministic script marker.
4. Verifies the `400 text/html` response and exact reflection.

## Evidence And Oracle

- POC: [`run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh)
- Raw callback URL: [`xss-callback.request.url`](/home/playground/output/attempt_1/evidence/20261008T122858Z-1031/xss-callback.request.url)
- Raw headers: [`xss-callback.response.headers`](/home/playground/output/attempt_1/evidence/20261008T122858Z-1031/xss-callback.response.headers)
- Raw response: [`xss-callback.response.raw`](/home/playground/output/attempt_1/evidence/20261008T122858Z-1031/xss-callback.response.raw)
- Control response: [`control-callback.response.raw`](/home/playground/output/attempt_1/evidence/20261008T122858Z-1031/control-callback.response.raw)

Pass condition: HTTP 400, `Content-Type: text/html`, no CSP header, and exact unescaped script-marker reflection.

## Impact

Demonstrated: attacker-controlled HTML/script is injected into an OpenBao-origin HTML response.

Plausible: browser script execution in the victim’s OpenBao origin, potentially enabling UI/session actions. Browser execution was not automated by the POC.

## Limitations

Only the seeded direct-callback role was tested. Client, device, and form-post callback modes were not evaluated. No authentication bypass or token issuance was demonstrated.