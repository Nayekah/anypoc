# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
## Summary

The custom Odoo lab addon `anypoc_lab` exposes an export wizard method, `anypoc.approval.export.wizard.action_generate_export()`, that accepts a raw target request id and uses `sudo()` to export the matching approval request without checking ownership. As a result, a low-privilege internal employee can download an admin-owned approval request and its embedded secret token over normal JSON-RPC and web download flows.

## Threat Model And Roles

The attacker is the seeded low-privilege internal user `employee@lab.local`. This user should only be able to access approval requests they own. The protected role is the admin user `admin@lab.local`, who owns the sensitive request that contains the secret export marker.

## Protected Asset Or Action

The protected asset is the admin-owned approval request `ANYPOC Admin Approval` and its secret token `ANYPOC-APPROVAL-SECRET-9f4b3c`. That data should not be readable or exportable by another ordinary employee.

## Entry Point

The vulnerable business action is exposed through the normal Odoo RPC surface:

- model: `anypoc.approval.export.wizard`
- method: `action_generate_export`
- likely reachable through crafted `/web/dataset/call_kw/...` requests after creating a wizard record

The method returns a `web/content` download URL for the generated JSON export.

## Vulnerable Code Analysis

The vulnerable implementation is in `/opt/odoo/addons/anypoc_lab/models/approval.py`.

- The protected record model is `anypoc.approval.request`.
- Internal users are restricted by record rule to their own approval requests.
- The export wizard stores a raw integer `target_request_id`.
- `action_generate_export()` performs `self.env['anypoc.approval.request'].sudo().browse(self.target_request_id)` and serializes the resulting record into `export_file`.

There is no ownership check, no group check, and no validation that the current user is allowed to export the target request. The `sudo()` call bypasses the record rule that would normally block access to the admin-owned request.

## Preconditions

The provided Docker image should already satisfy these:

1. Odoo is running on `http://127.0.0.1:8069`.
2. The custom addon `anypoc_lab` is installed.
3. Seeded users exist:
   `admin@lab.local/adminpass`, `employee@lab.local/employeepass`, `portal@lab.local/portalpass`.
4. The seeded admin-owned request exists with:
   - name: `ANYPOC Admin Approval`
   - secret token: `ANYPOC-APPROVAL-SECRET-9f4b3c`
5. The employee also has a decoy request named `ANYPOC Employee Decoy`.

## Reproduction Sketch

An acceptable PoC should:

1. authenticate as `employee@lab.local`
2. optionally show the employee can access their own decoy request but not rely on admin credentials
3. create an `anypoc.approval.export.wizard` record with `target_request_id` set to the admin-owned request id
4. call `action_generate_export` over JSON-RPC
5. follow the returned download URL or read the generated wizard binary through the normal application surface
6. prove the resulting JSON includes `ANYPOC-APPROVAL-SECRET-9f4b3c`

## Expected Vs Actual Authorization Behavior

Expected:

- `employee@lab.local` should be blocked from reading or exporting an approval request owned by `admin@lab.local`

Actual on the vulnerable build:

- the employee can create the export wizard, point it at the admin-owned request id, and retrieve the exported secret data

## Impact

This is a broken access control issue and an insecure direct object reference on a privileged export workflow. A normal employee can exfiltrate protected approval data and secrets belonging to another user, violating confidentiality and undermining workflow isolation.

## Desired PoC

Produce a deterministic PoC under `poc/run_poc.sh` that shows:

1. the session belongs to `employee@lab.local`
2. the exploit uses only normal Odoo web or RPC interfaces
3. `action_generate_export` still succeeds for the admin-owned request
4. the downloaded or returned JSON contains `ANYPOC-APPROVAL-SECRET-9f4b3c`


## POC Directory: /home/playground/output/attempt_4/poc
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