# Local validation evidence

Seeded configuration:

- Auth mount: `oidc/`
- Role: `lab-direct`
- Callback mode: `direct`
- Browser callback: `http://127.0.0.1:8200/ui/vault/auth/oidc/oidc/callback`

Sequence:

1. POST unauthenticated to `/v1/auth/oidc/oidc/auth_url` with role `lab-direct`,
   the seeded browser redirect URI, and a fresh client nonce.
2. Read the returned fresh `data.state`.
3. GET `/v1/auth/oidc/oidc/callback` with that state and
   `error_description` set to:

   ```text
   </p><script>document.title='ACTIVE_SAME_ORIGIN_20261008_7c1';document.documentElement.setAttribute('data-poc-marker','ACTIVE_SAME_ORIGIN_20261008_7c1');document.documentElement.setAttribute('data-poc-origin',location.origin)</script><p>
   ```

Observed response: HTTP `400`, `Content-Type: text/html`, 45087 bytes. The raw
response contains the marker in this context:

```html
<p class="message-body">
  </p><script>document.title='ACTIVE_SAME_ORIGIN_20261008_7c1';document.documentElement.setAttribute('data-poc-marker','ACTIVE_SAME_ORIGIN_20261008_7c1');document.documentElement.setAttribute('data-poc-origin',location.origin)</script><p>
```

Executing the returned HTML in the local HTML parser produced:

```json
{"title":"ACTIVE_SAME_ORIGIN_20261008_7c1","marker":"ACTIVE_SAME_ORIGIN_20261008_7c1","origin":"http://127.0.0.1:8200"}
```

Control: the same fresh-state sequence with `CONTROL_PLAIN_FAILURE_20261008_7c1`
returned HTTP 400 `text/html`, reflected the marker, and contained no script tag.
