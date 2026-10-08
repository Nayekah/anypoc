# Verdict

Valid

# Rejection Reason

Other

# Analysis Details

The vulnerability reproduces in the local OpenBao 2.5.1 lab.

- The `oidc` mount is configured with local issuer `http://127.0.0.1:9001`.
- Role `lab-direct` uses `callback_mode=direct`.
- An unauthenticated `POST /v1/auth/oidc/oidc/auth_url` returns a fresh OAuth state.
- An unauthenticated callback request with `error_description` returns `HTTP 400 Content-Type: text/html`.
- A benign marker is rendered as text, while this payload is returned verbatim inside the error paragraph:

  ```html
  <script>document.body.setAttribute("data-xss","XSS_MARKER")</script>
  ```

- Parsing the response with local `jsdom` executed the script and produced `body_data_xss=XSS_MARKER`.

Relevant source:

- `path_oidc.go:262-271`: direct mode enables HTML responses and passes `error_description` to `loginFailedResponse`.
- `path_oidc.go:216-225`: constructs the raw HTML response.
- `html_responses.go:332-357`: interpolates `detail` with `fmt.Sprintf` without HTML escaping.
- The UI stores non-root authentication token data in same-origin local storage via `ui/app/services/auth.js` and `ui/app/lib/token-storage.js`.

The report’s root cause and consequence are therefore confirmed: attacker-influenced OIDC error data becomes executable HTML/JavaScript in the OpenBao origin.