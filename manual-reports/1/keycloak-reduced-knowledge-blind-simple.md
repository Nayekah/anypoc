---
identifier: keycloak-reduced-knowledge-blind-simple
title: Possible cross-user authorization boundary failure
strategy: manual
metadata:
  source: blind-simplified
  vendor: keycloak
  category: broken-access-control
---

## Summary

There may be a business-logic authorization flaw involving two normal users in a
Keycloak authorization-services setup.

## Minimal Context

The test should focus on whether a low-privilege user can affect access,
permission, or token outcomes that should remain scoped to another user or that
user's protected state.

## Expected Behavior

Cross-user authorization boundaries should hold for normal authenticated users.

## Actual Behavior To Investigate

Some authorization-management or token-related flow may allow a normal user to
obtain a result that should be denied.

## Impact

If reproducible, the issue would be an OWASP-style broken-access-control problem
with cross-user authorization impact.
