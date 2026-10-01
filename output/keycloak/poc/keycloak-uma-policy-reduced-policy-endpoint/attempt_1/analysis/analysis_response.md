# Verdict

Invalid

# Rejection Reason

Other

# Analysis Details

Normal-user testing found no cross-user authorization vulnerability:

- Marta’s POST to `/authz/protection/uma-policy/{KoloResourceId}` was rejected with HTTP 400: “Only resource owner can access policies.”
- Marta could not GET, update, or delete Kolo’s existing policy; all requests were rejected with the same ownership error.
- Attempts to move Marta’s policy onto Kolo’s resource were rejected with “Uma permission resource cannot be changed.”
- Kolo received an authorization decision and token for Kolo’s resource; Marta received HTTP 403 `not_authorized`, both before and after the rejected attacks.
- Kolo’s policy remained unchanged.

The local implementation in [UserManagedPermissionService.java](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:149) verifies that the authenticated identity owns the resource, and policy creation assigns ownership from the authenticated identity rather than request input. Updates also prevent changing associated resources at [lines 100–109](/opt/keycloak-source/services/src/main/java/org/keycloak/authorization/protection/policy/UserManagedPermissionService.java:100).

Marta could read some victim resource metadata through the resource endpoint, but this is outside the report’s acceptance criteria and produced no policy, permission, token, or access-decision impact.