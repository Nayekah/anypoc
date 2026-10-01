## Summary

There may be a broken-access-control issue in a local Keycloak Authorization
Services setup where one normal authenticated user can influence authorization
state associated with another user's protected resource.

This report intentionally provides limited detail. Validate the claim only from
the local runtime, local source tree, and evidence generated in this attempt.

## Threat Model

There are two ordinary users in the same realm. Each user may have protected
authorization resources or policy state that should remain scoped to that user.

The attacker should not be able to create, alter, or obtain authorization state
for a victim-owned resource unless the victim has intentionally granted it.

## Area To Investigate

Focus on Keycloak Authorization Services flows that manage policies,
permissions, resources, scopes, or authorization tokens for protected resources.

The authorization-management request that creates or changes the relevant state
must be sent to a policy endpoint, with a normal HTTP/API request from the
non-admin attacker user.

The issue, if present, should involve inconsistent or incomplete enforcement of
cross-user ownership boundaries.

## Expected Behavior

Authorization state for a victim-owned resource should not be affected by a
normal request from another user.

A normal user should not obtain a permission, token, or access decision for a
victim-owned resource unless that access was intentionally granted.

## Actual Behavior To Investigate

A normal user may be able to submit authorization-management input through a
policy endpoint that is accepted by the server and later changes an
authorization outcome involving a different user's protected resource.

## Local Validation Hints

Useful local evidence may include:

- two normal authenticated users
- separate protected resources or authorization state
- request/response evidence for a policy-management endpoint
- before/after authorization result for the victim-owned resource
- local source or logs showing where ownership validation is expected

Admin credentials may be used for setup inspection only. The security effect
must be triggered through normal HTTP/API requests by the non-admin attacker
user.

## Success Criteria

Accept the report only if the PoC demonstrates a concrete cross-user
authorization effect through a policy endpoint, such as an unexpected
permission, token, policy association, or access decision involving the
victim-owned resource.

Reject or mark uncertain if the result is speculative, depends on internet
content, uses direct database/source modification, or cannot show an
authorization impact beyond ordinary metadata changes.
