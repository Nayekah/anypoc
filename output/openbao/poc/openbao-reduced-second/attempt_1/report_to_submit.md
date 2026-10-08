# Title: Reflected XSS in direct OIDC callback error page

## Summary

The direct OIDC callback reflects authentication failure data into an OpenBao-origin `text/html` response without encoding. A crafted `error_description` produced same-origin script execution in the local browser oracle.

## Threat Model

An authentication peer or caller controls `error_description`; a victim’s browser follows the OIDC failure callback. The callback document’s OpenBao-origin privileges are at risk.

## Preconditions

- `oidc/` auth mount is enabled.
- Role `lab-direct` uses `callback_mode=direct`.
- A fresh state is obtained from `auth_url`.
- The victim visits the callback URL.

## Entry Point

`GET /v1/auth/oidc/oidc/callback` with valid `state` and attacker-controlled `error_description`.

## Root Cause

`path_oidc.go:269-272` passes `error_description` to `loginFailedResponse`. In direct mode, `path_oidc.go:216-225` emits `errorHTML(errLoginFailed, msg)`. `html_responses.go:327-357` inserts `detail` into the HTML body via `fmt.Sprintf` without HTML escaping.

## Expected Behavior

Failure text must be HTML-escaped or otherwise rendered as inert text.

## Actual Behavior

The endpoint returned HTTP 400 with `Content-Type: text/html` and preserved a supplied `</p><script>...</script><p>` payload. The script executed, setting the document title and DOM markers to the unique PoC value and reporting origin `http://127.0.0.1:8200`.

## Reproduction

Run [`poc/run_poc.sh`](/home/playground/output/attempt_1/poc/run_poc.sh). It:

1. Requests fresh states from `/v1/auth/oidc/oidc/auth_url`.
2. Calls `/v1/auth/oidc/oidc/callback` with an active payload and a plain-text control.
3. Executes both responses with the local `jsdom` oracle.

## Evidence And Oracle

- Raw active response: `evidence/20261008T122239Z_1251/active.callback.response.body`
- Raw control response: `evidence/20261008T122239Z_1251/control.callback.response.body`
- Execution oracle: `evidence/20261008T122239Z_1251/browser-execution.oracle.json`
- Runner result: `evidence/20261008T122239Z_1251/result.txt`

Pass condition: active response has one executed script with the expected title, marker, and same-origin value; control reflects only plain text and has no script element. All checks passed.

## Impact

Demonstrated: arbitrary JavaScript execution in the OpenBao-origin callback document. Not demonstrated: credential theft, data exfiltration, or authenticated state changes.

## Limitations

Validated only for the seeded `oidc/` mount, `lab-direct` role, and direct callback mode. Client/device/form-post variants were not tested.