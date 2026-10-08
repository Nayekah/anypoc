# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The live lab reproduces reflected XSS in direct callback mode.

- Role `lab-direct` is configured with `callback_mode=direct`.
- A fresh state from `/v1/auth/oidc/oidc/auth_url` was used.
- `/v1/auth/oidc/oidc/callback` returned `400 text/html`.
- Benign error text rendered inertly.
- A harmless `<script>` marker was reflected unescaped and executed in a local browser-like DOM.

Root cause:

- [`path_oidc.go`]( /opt/openbao-source/builtin/credential/jwt/path_oidc.go:262 ) enables HTML responses for direct callbacks.
- [`loginFailedResponse`]( /opt/openbao-source/builtin/credential/jwt/path_oidc.go:216 ) passes `error_description` directly to `errorHTML`.
- [`errorHTML`]( /opt/openbao-source/builtin/credential/jwt/html_responses.go:335 ) inserts the detail into HTML using `fmt.Sprintf` without contextual escaping.

This confirms executable same-origin script injection in the OpenBao origin, subject to a valid authentication state and direct callback mode. Evidence is preserved in [`validation.md`](/home/playground/output/attempt_1/validation.md).