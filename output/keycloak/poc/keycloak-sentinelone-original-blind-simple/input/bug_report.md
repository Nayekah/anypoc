## Summary

A normal authenticated user may be able to influence authorization state across a
user boundary in a local Keycloak authorization-services deployment.

## Threat Model

There are two ordinary users in the same realm. Each user has authorization state
or protected objects that should not be controlled by the other user.

## Suspected Issue

An authorization-management flow may trust caller-controlled request data too
much and allow state associated with one user or object to affect another user or
object.

## Expected Behavior

Actions performed by User A should remain limited to resources or authorization
state User A is allowed to manage.

## Actual Behavior To Validate

User A may be able to cause an authorization result involving User B's protected
state through normal product APIs.

## Impact

If confirmed, this is a broken-access-control issue that can grant unauthorized
cross-user access or permission effects.
