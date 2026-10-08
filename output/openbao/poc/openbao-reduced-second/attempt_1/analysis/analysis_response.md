# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The vulnerability is reproducible on the seeded `oidc/` mount using role `lab-direct` with a fresh state.

A GET request to:

`/v1/auth/oidc/oidc/callback?state=<fresh-state>&error_description=<payload>`

returns HTTP 400 with `Content-Type: text/html`. The payload was inserted as:

```html
</p><script>...</script><p>
```

The returned HTML executed in a local HTML parser, setting a unique document title and marker while observing origin `http://127.0.0.1:8200`. A plain-marker control only reflected text and contained no script tag.

Relevant source:

- `builtin/credential/jwt/path_oidc.go:269-272` reads untrusted `error_description`.
- `path_oidc.go:216-225` routes it into an HTML response.
- `builtin/credential/jwt/html_responses.go:327-357` inserts `detail` using `fmt.Sprintf` without HTML escaping.

Root cause: attacker/authentication-peer-controlled failure text is emitted directly into an HTML response, enabling same-origin script injection. Evidence is preserved in [validation-evidence.md](/home/playground/output/attempt_1/playground/validation-evidence.md).