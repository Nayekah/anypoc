# Title: OIDC direct callback reflects `error_description` as unescaped HTML

## Summary

The unauthenticated OIDC direct-callback flow reflects attacker-controlled `error_description` data into a `text/html` response without HTML escaping. A harmless `<b>` marker was rendered as markup in the OpenBao-origin callback page.

## Threat Model

An attacker creates a pending OIDC state and sends a crafted callback URL to a victim. The victim’s browser renders the response; the OpenBao UI origin and browser session are at risk.

## Preconditions

- OIDC mount `oidc` is configured.
- Role `lab-direct` uses `callback_mode=direct`.
- A fresh state is obtained from the unauthenticated `auth_url` endpoint.
- The victim requests the callback URL.

## Entry Point

`POST /v1/auth/oidc/oidc/auth_url` creates state.  
`GET /v1/auth/oidc/oidc/callback?state=<state>&error_description=<value>` reflects the supplied value.

## Root Cause

`path_oidc.go:269-271` passes `error_description` to `loginFailedResponse`. Direct mode selects an HTML response at `path_oidc.go:262-267`; `loginFailedResponse` calls `errorHTML` at `path_oidc.go:220-225`. `html_responses.go:333-337` inserts the detail with `%s`, and line 357 uses `fmt.Sprintf` without HTML escaping.

## Expected Behavior

User-controlled callback data should be HTML-escaped or returned as plain text, preventing it from being interpreted as markup.

## Actual Behavior

The callback returns HTTP 400 with `Content-Type: text/html` and emits:

```html
<p class="message-body">
  <b data-poc="oidc-marker">OIDC_MARKER</b>
</p>
```

The benign control value was also reflected, confirming the same output path.

## Reproduction

Run `poc/run_poc.sh` against the seeded local service. It:

1. Calls `POST /v1/auth/oidc/oidc/auth_url` with role `lab-direct`.
2. Uses the returned state in the callback.
3. Supplies `error_description=<b data-poc="oidc-marker">OIDC_MARKER</b>`.
4. Verifies HTTP 400, `text/html`, and unescaped marker output.

## Evidence And Oracle

- PoC: `/home/playground/output/attempt_1/poc/run_poc.sh`
- Raw interaction: `/home/playground/output/attempt_1/playground/oidc-xss-raw-interaction.txt`
- Response body: `/home/playground/output/attempt_1/evidence/run.c6HsRF/malicious-callback.body`
- Headers/status: corresponding `malicious-callback.headers` and `malicious-callback.status`
- Pass condition: the marker appears unescaped in a `text/html` response.

## Impact

Demonstrated: reflected attacker-controlled HTML in an OpenBao-origin response.  
Plausible: script execution or UI-origin session impact if an active script payload is accepted by the browser; script execution was not tested.

## Limitations

Validated only with the seeded `lab-direct` role and direct GET callback. Form-post, device, alternate roles, and actual script execution were not tested.