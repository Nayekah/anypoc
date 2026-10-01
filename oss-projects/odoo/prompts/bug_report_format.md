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
