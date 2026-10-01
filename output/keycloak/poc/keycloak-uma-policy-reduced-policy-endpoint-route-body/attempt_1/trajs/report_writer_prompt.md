# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
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

Investigate whether the policy endpoint receives a resource identity from the
request route and also accepts one or more resource references in the policy
representation. If both forms exist, test whether they are consistently limited
to resources that the authenticated caller may manage.

In particular, compare a request made in the context of a resource the caller
may manage with a policy representation that references a different protected
resource. The request must not cause that other resource's authorization state
to change without a grant from its owner.

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
- a policy request that uses route context and a policy representation with
  resource references
- a baseline authorization result recorded before the state-changing request
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


## POC Directory: /home/playground/output/attempt_1/poc
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

## Scope Match

<!-- Explain why the PoC proves this report specifically, not just a nearby authorization issue. -->

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

## Limitations

<!-- State any uncertainty, drift risk, or behavior that was intentionally not claimed. -->


Fill in each section based on the bug report and POC artifacts.
Output ONLY the filled-in report, no additional commentary.

    Keep it short. No fluff.