# Title: Reflected XSS in direct OIDC callback failure response

## Summary

OpenBao reflects attacker-controlled OIDC `error_description` data into an HTML error page served from the OpenBao origin without contextual escaping. In the validated direct-callback configuration, a harmless script marker executed in the local browser-like DOM.

## Threat Model

An identity provider or other party controlling callback failure data can inject markup into the callback response. A victim loading the resulting OpenBao-origin page may execute script with that origin’s browser privileges.

## Preconditions

- OIDC mount `oidc` is configured.
- Role `lab-direct` uses `callback_mode=direct`.
- The callback URI is `http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback`.
- A fresh state is issued by `auth_url`.

## Entry Point

`GET /v1/auth/oidc/oidc/callback`

Relevant input: `state` and `error_description` query parameters.

## Root Cause

`pathCallback` enables HTTP HTML responses for direct callbacks and passes `error_description` to `loginFailedResponse` (`/opt/openbao-source/builtin/credential/jwt/path_oidc.go:262-272`). `loginFailedResponse` passes the value directly to `errorHTML` (`:216-225`). `errorHTML` inserts `detail` into the HTML template using `fmt.Sprintf` without escaping (`/opt/openbao-source/builtin/credential/jwt/html_responses.go:172-178, 357`).

## Expected Behavior

Failure details must be HTML-escaped or replaced with a fixed message so they remain inert text.

## Actual Behavior

The callback returned `400 text/html` with `Cache-Control: no-store`. The supplied `<script>` appeared as raw HTML in `.message-body`; the local DOM oracle set `window.__local_marker` and changed the document title to `LOCAL_OIDC_XSS_POC_20261008`.

## Reproduction

Run `poc/run_poc.sh`. It:

1. Obtains two fresh states through `POST /v1/auth/oidc/oidc/auth_url`.
2. Sends a benign callback and an injected callback to `/v1/auth/oidc/oidc/callback`.
3. Parses both responses with the local DOM execution oracle.

The script exits successfully only when benign text is inert and the injected marker executes.

## Evidence And Oracle

- POC: `/home/playground/output/attempt_1/poc/run_poc.sh`
- Execution log: `/home/playground/output/attempt_1/evidence/run.log`
- Oracle result: `/home/playground/output/attempt_1/evidence/oracle.json`
- Raw injected response: `/home/playground/output/attempt_1/evidence/xss.callback.response.body`
- Headers/status: `/home/playground/output/attempt_1/evidence/xss.callback.response.headers` and `.status`

Pass condition: benign `script_executed=false`; injected case contains a raw script and reports `script_executed=true`.

## Impact

Demonstrated: same-origin JavaScript execution in the OpenBao callback error page.

Not demonstrated: access to specific OpenBao data, session takeover, persistence, or behavior outside this callback configuration.

## Limitations

Validation was limited to the local OpenBao v2.5.1 instance, role `lab-direct`, and `callback_mode=direct`. Other callback modes, deployments, browsers, CSP behavior, and identity providers were not tested.