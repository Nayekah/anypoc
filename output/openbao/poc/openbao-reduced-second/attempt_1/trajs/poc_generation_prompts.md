# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

The vulnerability is reproducible on the seeded `oidc/` mount using role `lab-direct` with a fresh state.

A GET request to:

`/v1/auth/oidc/oidc/callback?state=<fresh-state>&error_description=<payload>`

returns HTTP 400 with `Content-Type: text/html`. The payload was inserted as:

```html
</p><script>...</script><p>
```

The returned HTML executed in a local HTML parser, setting a unique document title and marker while observing origin `http://127.0.0.1:8200`. A plain-marker control only reflected text and contained no script tag.

Relevant source:

- `builtin/credential/jwt/path_oidc.go:269-272` reads untrusted `error_description`.
- `path_oidc.go:216-225` routes it into an HTML response.
- `builtin/credential/jwt/html_responses.go:327-357` inserts `detail` using `fmt.Sprintf` without HTML escaping.

Root cause: attacker/authentication-peer-controlled failure text is emitted directly into an HTML response, enabling same-origin script injection. Evidence is preserved in [validation-evidence.md](/home/playground/output/attempt_1/playground/validation-evidence.md).

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

One browser-rendered response in the local OpenBao authentication workflow may
handle untrusted failure information as active content rather than inert text.

This report intentionally omits the exact route, field, affected configuration,
version, and source location. Discover or reject the claim using only the local
runtime and source tree.

## Trust Boundary

Data influenced by an authentication peer crosses into a response served from
the OpenBao origin. The browser must not interpret that data as application
markup or script.

## Expected Behavior

Failure information should be safely encoded or replaced before it is included
in browser-facing output.

## Actual Behavior To Investigate

Under a particular locally seeded authentication configuration, a normal
failure flow may preserve attacker-controlled syntax in a context that changes
how the browser interprets the page.

## Local Validation Hints

- Enumerate the seeded authentication configuration and its browser callbacks.
- Follow untrusted failure data through local source to the final output context.
- Use a fresh normal-flow state value and a harmless unique marker.
- Distinguish executable interpretation from plain reflection.

## Success Criteria

Accept only if a reproducible local HTTP sequence proves active same-origin
content injection and preserves raw evidence. Reject speculative source-only
claims, inert reflection, stale-state artifacts, harness-only behavior, and
findings on a different surface.

Do not search the internet or use external infrastructure.


## Available Paths:
Local target:

- Source tree: `/opt/openbao-source`
- Binary: `/usr/local/bin/bao`
- API and UI origin: `http://127.0.0.1:8200`
- Health endpoint: `http://127.0.0.1:8200/v1/sys/health`
- Service status helper: `/opt/openbao-lab/scripts/openbao_status.sh`
- Server logs: `/var/log/openbao`
- Seed summary: `/opt/openbao-data/seed-info.json`
- Root token for read-only setup inspection: `root`

Scope:

- This is an authorized, disposable local lab.
- Use only local services, local source, the current report, and files from the
  current attempt.
- Do not search the internet, access external documentation, query public
  vulnerability databases, install packages, or inspect other attempts.
- Exercise security claims through normal public interfaces.
- Keep all payloads non-destructive and do not contact external listeners.


## Directories:
- **Playground (for experimentation):** /home/playground/output/attempt_1/playground
- **Final PoC (only when ready):** /home/playground/output/attempt_1/poc

## Your Approach:

1. **Experiment in playground first**: Use /home/playground/output/attempt_1/playground to test ideas,
try different approaches, and iterate on your PoC.
Create test files, run experiments, and verify your understanding of the bug.

2. **Verify the bug triggers**: Before finalizing, make sure you can actually trigger the bug.
Test your PoC in the playground and confirm it causes the expected behavior (crash, assertion failure, etc.).

3. **Finalize only when confident**: Once you have a working PoC that reliably triggers the bug, create a
**minimal, concise, end-to-end functional** version and copy it to /home/playground/output/attempt_1/poc.
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
write a file `/home/playground/output/attempt_1/poc/IMPOSSIBLE.md` explaining:

1. **Failure Category** (pick one):
   - `UNREACHABLE`: The vulnerable code path cannot be reached from user-controlled input
   - `ENVIRONMENT_DEPENDENT`: Requires special hardware, OS, or environment we cannot replicate
   - `INVALID_BUG`: Further analysis shows this is not actually a valid/exploitable bug
   - `OTHER`: Some other fundamental blocker

2. **Detailed Explanation**: Why the PoC cannot be created

Do NOT create dummy or fake demonstrations as a substitute.
If it's impossible, just write IMPOSSIBLE.md and stop.

## Project-Specific Instructions:
## Constraints

Create a minimal deterministic PoC for the behavior validated during analysis.
Use only the current report, current analysis, local source, local services, and
current-attempt files.

Do not browse the internet, query external references, install packages,
inspect previous attempts, or copy a public exploit. Do not patch the target,
edit its storage directly, or invoke internal implementation functions in place
of the externally reachable interface.

## Requirements

- Reproduce the same claim and preconditions validated by analysis.
- Use a normal public interface and obtain any required runtime values through
  their normal flow.
- Use only harmless inputs and local observations.
- Include an appropriate negative or benign control when needed.
- Preserve raw requests, responses, and the deterministic pass/fail evidence.
- Fail closed when the target is unavailable, prerequisites are missing, the
  observation is ambiguous, or the result belongs to another surface.

Put the final reproducer under `poc/` with `run_poc.sh` as the entry point and at
most one small helper. Keep exploratory artifacts under `playground/`.

`run_poc.sh` must exit `0` only when the validated security behavior and its
oracle are both observed; otherwise it must exit nonzero.



---

## Step 2: Execution & Evidence

Execute the PoC and gather evidence.

## Tasks:

**Process safety**: Do not run blanket kill commands (e.g., `pkill python`, `pkill -u`,
`kill -9 1`) because they will terminate the poc runner/orchestrator process. Only
stop the specific test processes you launched.

1. **Execute the final PoC** from /home/playground/output/attempt_1/poc
2. **Collect evidence** according to the oracle (crash logs, ASan output, screenshots, etc.)
3. **Save all evidence** to /home/playground/output/attempt_1/evidence

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
