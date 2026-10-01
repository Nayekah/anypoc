---
keywords: []
times_used: 1
times_useful: 1
---

For Odoo business-logic and access-control issues, a strong user-triggerable PoC shape is a small shell runner plus a Python helper that stays entirely on the web surface:

1. Optionally wait for `/web/login` to return HTTP 200 so the runner does not race the lab startup.
2. Authenticate with `POST /web/session/authenticate`.
3. Reuse `auth.result.user_context` for later RPC calls, and optionally call `POST /web/session/get_session_info` to record the live session identity in the artifacts.
4. Prove the intended baseline with a normal `search_read`.
5. Create any transient or wizard record with `POST /web/dataset/call_kw/<wizard_model>/create`.
6. Invoke the wizard action with `POST /web/dataset/call_kw/<wizard_model>/<method>`.
7. If the action returns a `/web/content` URL, fetch it with the same authenticated session.
8. Save each request/response plus lightweight metadata such as method, path, status, and content type, and exit nonzero unless a concrete protected marker is present.

This PoC form demonstrates real user reachability without using `odoo shell`, direct database access, or browser automation.