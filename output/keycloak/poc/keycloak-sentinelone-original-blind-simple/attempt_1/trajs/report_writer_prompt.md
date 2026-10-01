# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
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