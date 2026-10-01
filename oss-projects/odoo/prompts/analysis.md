## Focus

This project is for business-logic and authorization failures in Odoo, with emphasis on OWASP A01 Broken Access Control and closely related workflow abuses.

Accept reports only when the bug can be exercised through a realistic application surface such as:

- HTTP controllers
- JSON-RPC or XML-RPC methods
- portal or employee workflows
- export, report, download, payment, order, subscription, or approval flows
- record-level or field-level access control mistakes

## Reject These Reports

Immediately reject any report that falls into one of these categories:

1. The issue requires direct database access, `psql`, `odoo shell`, monkey-patching, or editing server files to trigger the impact.
2. The issue is purely memory-safety, dependency hygiene, XSS-only, CSRF-only, rate-limit-only, or generic information leakage without an authorization boundary violation.
3. The issue depends on admin privileges, developer mode with admin rights, or a user already holding the accounting or target high-privilege group.
4. The report has no concrete low-privilege role, no concrete protected action, or no specific target record/data that should be forbidden.
5. The issue is only a validation error, traceback, or benign 4xx/5xx response without proving unauthorized read, write, export, approval, payment, or state transition.

## What A Valid Report Must Establish

Before approving a report, confirm all of the following:

1. There is a clear low-privilege actor such as an employee or portal user.
2. There is a clear higher-privilege capability or protected data set that this actor should not reach.
3. The vulnerable path is identified precisely:
   model, method, controller, route, or RPC entry point.
4. The authorization invariant is explicit:
   which group, record rule, ownership check, company boundary, or business precondition is missing or bypassed.
5. The impact is application-level and meaningful:
   unauthorized export, report generation, payment, order manipulation, approval, session takeover, or privilege escalation.

## Guidance For Odoo

- Prefer end-to-end reasoning from the request surface down to the model method.
- Inspect group checks such as `has_group(...)`, `env.is_admin()`, record rules, `sudo()`, and controller code that browses records by id.
- Watch for wizard models (`TransientModel`) that expose privileged actions after ordinary users create a record and call a method over RPC.
- Treat missing checks on export or download actions as high-signal if they expose real accounting, payment, customer, or credential data.

## Specific High-Signal Path In This Lab

The seeded lab now contains a purpose-built business-logic target in the custom addon:

- vulnerable file: `/opt/odoo/addons/anypoc_lab/models/approval.py`
- protected model: `anypoc.approval.request`
- vulnerable wizard model: `anypoc.approval.export.wizard`
- vulnerable method: `action_generate_export`

The intended invariant is simple:

- a low-privilege internal employee should only be able to read or export approval requests they own
- admin-owned requests and their secret export contents should stay inaccessible

Approve the report only when the PoC can show that an authenticated low-privilege user can still export an admin-owned request or its secret marker through the normal Odoo web or RPC surface.
