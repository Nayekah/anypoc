# Employee can export admin approval requests via `sudo()`-backed export wizard

## Summary

The custom addon `anypoc_lab` exposes `anypoc.approval.export.wizard.action_generate_export()` to any internal user and trusts a caller-supplied `target_request_id`. The method uses `sudo()` to load and export the target approval request, so `employee@lab.local` can export `admin@lab.local`'s request and recover `ANYPOC-APPROVAL-SECRET-9f4b3c` through standard JSON-RPC and `/web/content` download flows.

## Threat Model And Roles

Attacker: seeded low-privilege internal user `employee@lab.local`. Protected role: `admin@lab.local`. The boundary crossed is per-user approval-request isolation enforced for internal users.

## Protected Asset Or Action

The protected asset is the admin-owned approval request `ANYPOC Admin Approval`, including `secret_token=ANYPOC-APPROVAL-SECRET-9f4b3c` and associated export content. A normal employee should not be able to read or export that record.

## Entry Point

Normal Odoo RPC/web endpoints:

- `/web/dataset/call_kw/anypoc.approval.export.wizard/create`
- `/web/dataset/call_kw/anypoc.approval.export.wizard/action_generate_export`
- returned download URL: `/web/content/?model=anypoc.approval.export.wizard&id=<wizard_id>&field=export_file&filename_field=export_filename&download=true`

Model/method: `anypoc.approval.export.wizard.action_generate_export`.

## Vulnerable Code Analysis

`/opt/odoo/addons/anypoc_lab/security/anypoc_lab_security.xml:3-11` defines an owner-only record rule for `anypoc.approval.request` with `domain_force=[('owner_id', '=', user.id)]`.

`/opt/odoo/addons/anypoc_lab/models/approval.py:28-63` implements the export wizard. The wizard accepts raw integer `target_request_id` (`line 32`) and `action_generate_export()` resolves it with `self.env["anypoc.approval.request"].sudo().browse(self.target_request_id)` (`line 38`). It then serializes sensitive fields including `owner_login`, `secret_token`, and `secret_notes` (`lines 41-49`) into `export_file` and returns a direct `web/content` download URL (`lines 58-63`).

There is no ownership check, no authorization revalidation, and no business check tying the exported request to the current user. The `sudo()` call bypasses the owner-only record rule.

## Preconditions

- Odoo reachable at `http://127.0.0.1:8069`
- `anypoc_lab` installed
- Seeded users exist: `admin@lab.local/adminpass`, `employee@lab.local/employeepass`, `portal@lab.local/portalpass`
- Admin-owned request `ANYPOC Admin Approval` exists with secret `ANYPOC-APPROVAL-SECRET-9f4b3c`
- Employee-owned decoy request `ANYPOC Employee Decoy` exists

## Reproduction Sketch

Use the attached PoC in `poc/run_poc.sh` and `poc/poc.py`.

1. Authenticate as `employee@lab.local` over `/web/session/authenticate`.
2. Confirm the employee session via `poc/output/session_info.json` and that `search_read` only exposes `ANYPOC Employee Decoy` via `poc/output/visible_requests.json`.
3. Create `anypoc.approval.export.wizard` with `target_request_id=1` using the request captured in `poc/output/04_create_wizard_request.json`.
4. Invoke `action_generate_export` using `poc/output/05_action_generate_export_request.json`.
5. Follow the returned `web/content` URL from `poc/output/action_generate_export.json`.
6. Observe the downloaded JSON in `poc/output/admin_export.json` containing the admin-owned request and secret token.

## Expected Vs Actual Authorization Behavior

Expected: `employee@lab.local` should only be able to read/export approval requests they own, and export of an admin-owned request should fail with access denial.

Actual: the employee can create the wizard with an arbitrary `target_request_id`, successfully invoke `action_generate_export`, and download JSON for `admin@lab.local`'s request. The captured PoC summary in `poc/output/SUMMARY.txt` shows `visible_request_names=ANYPOC Employee Decoy` but `export_owner_login=admin@lab.local` and `export_secret_token=ANYPOC-APPROVAL-SECRET-9f4b3c`.

## Impact

Broken access control / IDOR on a privileged export workflow. Any internal employee who can access the wizard can exfiltrate approval data and embedded secrets from other users' requests, violating confidentiality and defeating per-owner workflow isolation.

## Desired PoC

A valid reproducer should prove all of the following using only normal Odoo web/RPC interfaces:

- the active session is `employee@lab.local`
- the employee only sees their own decoy approval in normal listing
- `anypoc.approval.export.wizard.action_generate_export()` still succeeds when pointed at the admin request id
- the resulting export contains `ANYPOC-APPROVAL-SECRET-9f4b3c`

The attached PoC already captures those oracles in `poc/output/session_info.json`, `poc/output/visible_requests.json`, `poc/output/action_generate_export.json`, `poc/output/admin_export.json`, and `poc/output/SUMMARY.txt`.