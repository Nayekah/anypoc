# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
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


## POC Directory: /home/playground/output/attempt_1/poc
Review the POC files and reference them in your report.

## Report Format:
Your response MUST be a markdown document following this exact format:

# Title: concise description of the validated issue

## Summary

<!-- State the verified behavior and security boundary in one paragraph. -->

## Threat Model

<!-- Identify attacker control, required victim or system action, and assets at risk. -->

## Preconditions

<!-- List only configuration and state requirements established by evidence. -->

## Entry Point

<!-- Name the externally reachable interface and relevant inputs. -->

## Root Cause

<!-- Trace the validated runtime behavior to the relevant local source. -->

## Expected Behavior

<!-- Describe the secure or intended behavior. -->

## Actual Behavior

<!-- Describe the observed behavior without extending beyond the evidence. -->

## Reproduction

<!-- Give the minimal deterministic local flow. -->

## Evidence And Oracle

<!-- Identify raw artifacts, controls, and the exact pass condition. -->

## Impact

<!-- State demonstrated impact separately from plausible impact. -->

## Limitations

<!-- Record configuration scope, untested variants, and uncertainty. -->


Fill in each section based on the bug report and POC artifacts.
Output ONLY the filled-in report, no additional commentary.

    Keep it short. No fluff.