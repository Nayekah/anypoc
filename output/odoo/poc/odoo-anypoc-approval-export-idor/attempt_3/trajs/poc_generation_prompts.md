# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

# Available Knowledge Base

Knowledge directory: `/home/playground/knowledge/content`

The index below is a **compact preview** — only top-rated entries and top-10 keywords are shown per category.
Use bash and search tools to explore the full directory and find additional entries.
Each markdown file has YAML front matter with keywords, times_used, and times_useful.

**Important**: After using any knowledge, call `rate_knowledge` with the file path
and a score from -10 (misleading) to 10 (directly helped).

## Enforced Category Structure

Shared knowledge (all projects):
- `command_line_tools/` - General CLI tools (gdb, valgrind, etc.). NOT project-specific tools.
- `language_specific/` - Language knowledge (`c/`, `cpp/`, `rust/`). General pitfalls, NOT project APIs.

Project-specific knowledge (`odoo/`):
- `odoo/build/` - Build system, compilation, flags. How to compile the project.
- `odoo/internal_tools/` - Project's specific tools. NOT general CLI tools.
- `odoo/test_frameworks/` - Testing approaches. NOT PoC formats (use poc_forms/).
- `odoo/code/` - General code facts/invariants. NOT bug-specific root causes or crash logs.
- `odoo/poc_forms/` - PoC formats and what user capabilities they represent. NOT bug patterns.

## Project Knowledge (odoo)

### code/ (1 entries)
Top keywords: odoo, call_kw, search_read, create, web/content, json-rpc contract
- `odoo/code/odoo_call_kw_download_contracts.md`

### internal_tools/ (3 entries)
Top keywords: evidence, final-run, attempt layout, POC_OUT_DIR, playground, poc, anypoc, status.json, generation error, workflow pitfall
- `odoo/internal_tools/attempt_directory_and_poc_out_dir.md`
- `odoo/internal_tools/attempt_status_vs_evidence.md`

### poc_forms/ (1 entries)
Top keywords: odoo, json-rpc, wizard, web/content, access control, poc form
- `odoo/poc_forms/odoo_jsonrpc_wizard_download_flow.md`


**IMPORTANT**: After reading the FULL content of ANY knowledge file, you MUST rate its
usefulness using the `rate_knowledge` tool with a score from -10 to 10:
- 10: directly helped solve/advance the task
- 0: irrelevant / provided no benefit
- -10: actively misleading / wasted time

If poc_forms/ knowledge entries exist, review them for reusable PoC format ideas.
The collection is not exhaustive — feel free to invent new PoC forms as needed.



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


## Available Paths:
Path to source code:

- `/opt/odoo`
- Core server entry point: `/opt/odoo/odoo-bin`
- Custom lab addon path: `/opt/odoo/addons/anypoc_lab`
- Request model implementation: `/opt/odoo/addons/anypoc_lab/models/approval.py`

Python environment:

- Odoo virtualenv: `/opt/odoo-venv`
- Run Odoo commands with: `/opt/odoo-venv/bin/python /opt/odoo/odoo-bin ...`

Runtime services:

- Odoo URL: `http://127.0.0.1:8069`
- PostgreSQL socket: `/var/run/postgresql`
- Odoo config: `/opt/odoo-lab/odoo.conf`
- Odoo log: `/var/log/odoo/server.log`

Helper scripts:

- Status and quick health check: `/opt/odoo-lab/scripts/odoo_status.sh`

Seeded lab users:

- Admin: `admin@lab.local` / `adminpass`
- Internal low-privilege user: `employee@lab.local` / `employeepass`
- Portal user: `portal@lab.local` / `portalpass`

Seeded approval markers:

- Admin-owned protected request name: `ANYPOC Admin Approval`
- Admin-owned protected secret token: `ANYPOC-APPROVAL-SECRET-9f4b3c`
- Employee-owned decoy request name: `ANYPOC Employee Decoy`
- Employee-owned decoy token: `ANYPOC-EMPLOYEE-DECOY`

Important notes:

- The container startup hook automatically starts PostgreSQL and the Odoo HTTP server before the AnyPoC pipeline begins.
- The Odoo base source commit is `9a06302`.
- The custom lab module `anypoc_lab` is intentionally vulnerable to a business-logic Broken Access Control flaw in its export wizard.
- Prefer business-logic reproduction through HTTP, JSON-RPC, XML-RPC, or the regular Odoo web stack. Do not use direct database access, `odoo shell`, or local Python imports as the exploit mechanism.


## Directories:
- **Playground (for experimentation):** /home/playground/output/attempt_3/playground
- **Final PoC (only when ready):** /home/playground/output/attempt_3/poc

## Your Approach:

1. **Experiment in playground first**: Use /home/playground/output/attempt_3/playground to test ideas,
try different approaches, and iterate on your PoC.
Create test files, run experiments, and verify your understanding of the bug.

2. **Verify the bug triggers**: Before finalizing, make sure you can actually trigger the bug.
Test your PoC in the playground and confirm it causes the expected behavior (crash, assertion failure, etc.).

3. **Finalize only when confident**: Once you have a working PoC that reliably triggers the bug, create a
**minimal, concise, end-to-end functional** version and copy it to /home/playground/output/attempt_3/poc.
The final PoC should be clean and self-contained.

## User-Triggerable PoC Principle

Your PoC must demonstrate something a **real user or attacker can do** through normal
interaction surfaces (file input, network request, API call, UI action, CLI arguments, etc.).

- **DO**: Craft a malicious input file, webpage, network payload, or API request that
  triggers the bug when processed by the target software in its normal mode of operation.
- **DO NOT**: Directly call internal functions, manipulate in-memory state, or write a
  test harness that bypasses the software's input path. Such PoCs prove the code is buggy
  but fail to show real-world exploitability.
- **Ask yourself**: "If I present this PoC to a triaging developer, would they immediately
  see that the bug is reachable from user-controlled input?" If not, improve the PoC to make this clearer.

## CRITICAL RULES:

- **NO dummy examples**: If you cannot trigger the real bug, do not create fake/simulated examples.
    Either create a real working PoC or declare it impossible.
- **Real bugs only**: The PoC must actually trigger the vulnerability in the target software,
    not just illustrate how it could theoretically work.
- **Do NOT kill the orchestrator**: Never run blanket kill commands like `pkill python`,
    `pkill -u`, or `kill -9 1` — they will terminate the poc runner/orchestrator
    process. Only terminate the specific test processes you started.

## If PoC is NOT Possible:

If after investigation you determine that creating a PoC is **impossible**,
write a file `/home/playground/output/attempt_3/poc/IMPOSSIBLE.md` explaining:

1. **Failure Category** (pick one):
   - `UNREACHABLE`: The vulnerable code path cannot be reached from user-controlled input
   - `ENVIRONMENT_DEPENDENT`: Requires special hardware, OS, or environment we cannot replicate
   - `INVALID_BUG`: Further analysis shows this is not actually a valid/exploitable bug
   - `OTHER`: Some other fundamental blocker

2. **Detailed Explanation**: Why the PoC cannot be created

Do NOT create dummy or fake demonstrations as a substitute.
If it's impossible, just write IMPOSSIBLE.md and stop.

## Project-Specific Instructions:
## Important Constraints

- Reproduce the bug through the running Odoo application on `http://127.0.0.1:8069`.
- Use realistic app interfaces such as HTTP, JSON-RPC, XML-RPC, or download endpoints.
- Do not use direct PostgreSQL queries, `odoo shell`, or in-process Python imports as the exploit path.
- Keep the PoC self-contained. Prefer a single `run_poc.sh` and, if needed, one small helper script such as `poc.py`.
- Use the seeded lab accounts unless the bug report explicitly requires another role.

## Seeded Lab Context

- Admin: `admin@lab.local` / `adminpass`
- Low-privilege internal user: `employee@lab.local` / `employeepass`
- Portal user: `portal@lab.local` / `portalpass`
- Health helper: `/opt/odoo-lab/scripts/odoo_status.sh`
- Odoo config: `/opt/odoo-lab/odoo.conf`
- Log file: `/var/log/odoo/server.log`

## Preferred PoC Shape

For business-logic and access-control issues, a good PoC usually does this:

1. Wait for the web service to be reachable.
2. Authenticate as the low-privilege user.
3. Perform the minimal privileged action over RPC or HTTP.
4. Retrieve the resulting protected artifact or state.
5. Assert on a concrete protected marker and exit `0` only on success.

## Odoo-Specific Guidance

- Odoo commonly exposes model methods via `/web/dataset/call_kw/...`.
- Wizard flows often need a record creation call first, then a method call on that wizard record id.
- If a method returns a `web/content` download URL, fetch it with the same authenticated session.
- Print the exact user, request path, response status, and a short excerpt of the protected data.

## Specific High-Signal Target In This Lab

The seeded lab target is a broken access control issue in the custom addon `anypoc_lab`:

- protected model: `anypoc.approval.request`
- vulnerable wizard model: `anypoc.approval.export.wizard`
- vulnerable method: `action_generate_export`
- code path: `/opt/odoo/addons/anypoc_lab/models/approval.py`

The intended access boundary is:

- `employee@lab.local` should only access approval requests they own
- the admin-owned request `ANYPOC Admin Approval` and its secret token should remain inaccessible

On the vulnerable build, a lower-privilege employee can still create an export wizard, supply the admin request id, trigger `action_generate_export`, and download a JSON export containing the protected secret.

If you target this issue, the PoC should prove all of the following:

- the session belongs to `employee@lab.local`
- direct access to the admin-owned request is not part of the intended authorization path
- the user can still obtain the export artifact through the wizard
- the downloaded content includes the seeded secret marker `ANYPOC-APPROVAL-SECRET-9f4b3c`

## Output Expectations

- Put the main runner at `poc/run_poc.sh`.
- Save any helper script under `poc/`.
- Save downloaded files, decoded responses, and debug logs under the working directory so the evidence step can preserve them.
- Keep dependencies minimal. `curl` or Python `requests` are preferred over browser automation unless the report clearly needs it.



---

## Step 2: Execution & Evidence

Execute the PoC and gather evidence.

## Tasks:

**Process safety**: Do not run blanket kill commands (e.g., `pkill python`, `pkill -u`,
`kill -9 1`) because they will terminate the poc runner/orchestrator process. Only
stop the specific test processes you launched.

1. **Execute the final PoC** from /home/playground/output/attempt_3/poc
2. **Collect evidence** according to the oracle (crash logs, ASan output, screenshots, etc.)
3. **Save all evidence** to /home/playground/output/attempt_3/evidence

If you wrote IMPOSSIBLE.md in the previous step, explain your findings in your response and skip execution.


---

## Step 3: Generation Summary

Summarize the PoC generation progress and current status.

## Final Response Format:
Your final message MUST contain the summary directly using the following structure:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Status
Overall status of the PoC generation effort.
Options: "Completed", "Partial", "NeedsHelp", "Impossible"

# Summary
What was attempted, current PoC behavior, and whether the bug appears triggered.

# Next Actions
Concrete next steps or support needed. Use 'None' if no additional help is required.

```

Keep the prose concise; the status field must pick one of the allowed options.
