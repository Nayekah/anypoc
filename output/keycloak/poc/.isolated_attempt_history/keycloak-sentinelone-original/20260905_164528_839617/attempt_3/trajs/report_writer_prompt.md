# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
## Summary

Keycloak contains an authorization flaw in its User-Managed Access policy handling. An authenticated user who is allowed to manage UMA policies can bypass validation during policy creation and cause a policy to reference resources owned by a different user. This can lead to unauthorized permissions being granted across user boundaries.

## Threat Model And Roles

The attacker is an authenticated non-admin user operating through normal authorization-management capabilities. The victim is another ordinary user who owns protected resources under the same Keycloak deployment. The boundary that should hold is per-resource ownership during policy management.

## Protected Asset Or Action

The protected asset is any resource owned by one user that should only be governed by that owner's authorization state. The protected action is the ability to create or influence permission state for another user's resource.

## Observed Boundary Failure

Policy creation is expected to remain scoped to the resource being managed by the caller. Instead, a crafted policy-creation request can carry identifiers for resources owned by another user, and the system accepts that state instead of rejecting it.

## Entry Point

The issue is reachable through the normal Keycloak Authorization Services and UMA policy-management flow used by authenticated users and clients that manage owner-controlled resources.

## Preconditions

This behavior matters when:

1. authorization services are enabled for the affected client or application
2. users are allowed to manage owner-controlled resources and their policies
3. victim-owned protected resources already exist

## Expected Vs Actual Behavior

Expected:

- policy creation should only affect resources the caller is allowed to manage
- cross-user resource references should be rejected during validation

Actual:

- validation can be bypassed during policy creation
- policy state can end up referencing another user's resource
- the attacker can obtain permissions that should never be granted across users

## Impact

This is a business-logic and access-control failure. A normal authenticated user can influence authorization outcomes for another user's protected resource, which can result in unauthorized access to application data or actions guarded by Keycloak authorization decisions.


## POC Directory: /home/playground/output/attempt_3/poc
Review the POC files and reference them in your report.

## Report Format:
Your response MUST be a markdown document following this exact format:

# Title: should be within 100 characters

## Summary

<!-- Describe the broken authorization or business rule in one short paragraph. -->

## Threat Model And Roles

<!-- State the attacker role, victim or protected role, and what boundary is crossed. -->

## Protected Asset Or Action

<!-- Explain exactly what data, workflow step, export, payment, or state transition should be forbidden. -->

## Entry Point

<!-- Name the route, RPC endpoint, model, and method when known. -->

## Vulnerable Code Analysis

<!-- Point to the relevant files and lines. Explain the missing check, wrong sudo(), missing ownership check, or broken business precondition. -->

## Preconditions

<!-- List the minimum lab setup required: modules, roles, sample records, or credentials. -->

## Reproduction Sketch

<!-- Describe the minimal end-to-end flow the PoC should automate. Prefer HTTP/JSON-RPC/XML-RPC over local shell access. -->

## Expected Vs Actual Authorization Behavior

<!-- Explain what should happen for the low-privilege user, and what actually happens instead. -->

## Impact

<!-- Describe the confidentiality, integrity, or privilege-escalation consequence in concrete application terms. -->

## Desired PoC

<!-- Define what a successful AnyPoC reproducer must prove and what artifact or oracle it should capture. -->


Fill in each section based on the bug report and POC artifacts.
Output ONLY the filled-in report, no additional commentary.

    Keep it short. No fluff.