---
keywords:
- keycloak
- uma
- uma-ticket
- openid-connect
- token endpoint
- permission parameter
- authorization.permissions
- resource id
times_used: 0
times_useful: 0
---

For user-managed authorization checks, Keycloak can evaluate the request through the standard OIDC token endpoint using a form-encoded UMA ticket grant request.

Reusable request shape:

```text
POST /realms/{realm}/protocol/openid-connect/token
Authorization: Bearer <user access token>
Content-Type: application/x-www-form-urlencoded

grant_type=urn:ietf:params:oauth:grant-type:uma-ticket
audience=<resource-server-client-id>
permission=<resource-id>#<scope>
```

Notes from the successful run:

- The `permission` parameter used the `resource_id#scope_name` form.
- The externally meaningful oracle was the HTTP status plus the returned access token, not any internal server-side signal.
- To verify which resource was actually granted, decode `.access_token` and inspect `authorization.permissions` for `rsid`, `rsname`, and `scopes`.

This is a good default request form when reconstructing a user-triggerable UMA authorization flow from Keycloak's public HTTP APIs.