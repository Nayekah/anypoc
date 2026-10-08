# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The seeded OIDC configuration uses the `lab-direct` role with direct callbacks. The unauthenticated `auth_url` endpoint produced a valid pending state, after which the callback endpoint returned attacker-controlled `error_description` data as `text/html`.

Evidence:

```html
<p class="message-body">
  <b data-poc="oidc-marker">OIDC_MARKER</b>
</p>
```

The benign control rendered plain text normally, confirming the markup was interpreted rather than inertly reflected.

Root cause:

- [`path_oidc.go:269`](/opt/openbao-source/builtin/credential/jwt/path_oidc.go:269) accepts `error_description` and passes it to `loginFailedResponse`.
- [`path_oidc.go:216`](/opt/openbao-source/builtin/credential/jwt/path_oidc.go:216) emits an HTML response in direct mode.
- [`html_responses.go:335`](/opt/openbao-source/builtin/credential/jwt/html_responses.go:335) inserts the detail using `%s`.
- [`html_responses.go:357`](/opt/openbao-source/builtin/credential/jwt/html_responses.go:357) uses `fmt.Sprintf` without HTML escaping.

The callback response lacked CSP and `X-Content-Type-Options` headers, so this is a reflected HTML/script-injection vulnerability in the OpenBao origin. Exploitation requires a pending OIDC state, but that state can be created through the unauthenticated `auth_url` flow. No destructive or external payloads were used.

Raw interaction is preserved at [oidc-xss-raw-interaction.txt](/home/playground/output/attempt_1/playground/oidc-xss-raw-interaction.txt).