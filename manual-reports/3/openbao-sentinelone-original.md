---
identifier: openbao-sentinelone-original
title: Reflected XSS in OpenBao OIDC authentication error message
strategy: manual
metadata:
  vendor: openbao
  category: cross-site-scripting
  experiment_profile: sentinelone-original
  cve: CVE-2026-33758
  advisory: GHSA-cpj3-3r2f-xj59
---

## Summary

OpenBao installations using an OIDC/JWT authentication method with a role
configured for `callback_mode=direct` are vulnerable to reflected cross-site
scripting through the `error_description` value processed by the failed OIDC
authentication callback page.

The issue affects OpenBao versions through 2.5.1 and is fixed in 2.5.2.

## Preconditions

- An OIDC/JWT authentication method is enabled.
- The selected role uses `callback_mode=direct`.
- A victim opens an attacker-controlled authentication callback URL or follows an
  OIDC failure redirect carrying attacker-influenced error data.

No prior OpenBao authentication is required to reach the callback, although the
impact is greatest when the victim has a Web UI token in the same browser origin.

## Entry Point

The affected flow starts at the auth URL endpoint and completes at:

`GET /v1/auth/<mount>/oidc/callback`

The callback accepts OAuth state and an `error_description` value. For a direct
callback role, an authentication failure is rendered as HTML.

## Vulnerable Behavior

In `builtin/credential/jwt/path_oidc.go`, the direct callback path passes the
provider-controlled error description to `loginFailedResponse`. In
`builtin/credential/jwt/html_responses.go`, `errorHTML` interpolates the detail
into an HTML template without context-appropriate escaping.

An HTML or script payload can therefore become active markup in the OpenBao
origin instead of being displayed as inert error text.

## Expected Behavior

Provider error details must not be rendered as executable content. They should
be replaced with a static user-facing message or escaped for their precise HTML
context.

## Security Impact

Script execution in the OpenBao origin can read Web UI state available to that
origin, including non-root authentication tokens persisted by the UI, and can
perform same-origin actions as the victim.

## Desired PoC

Use the local OpenBao runtime and local OIDC provider only. Obtain fresh state
from the normal auth URL API, submit a harmless marker through the failed direct
callback, preserve the raw HTTP exchange, and prove that the marker is treated
as executable markup. Do not send data to an external server.

## Public Context

This report corresponds to CVE-2026-33758 and the public OpenBao advisory
GHSA-cpj3-3r2f-xj59. The public fix in 2.5.2 replaces the reflected provider
detail with a static error and adds context-appropriate escaping.
