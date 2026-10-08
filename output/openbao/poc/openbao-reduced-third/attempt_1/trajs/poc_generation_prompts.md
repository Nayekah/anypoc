# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

The seeded flow is the `auth/oidc` mount, role `lab-direct`, configured for direct callbacks through the local OIDC issuer.

Runtime reproduction:

- Normal `auth_url` request generated a valid OIDC state.
- Callback request supplied a benign `error_description`; the marker appeared in the HTML response.
- A second callback supplied `</p><script>document.title='OPENBAO-LAB-XSS-7F'</script><p>`.
- The service returned `400 text/html` without a CSP header, and the raw response contained the script verbatim.

Root cause:

- [`path_oidc.go:269-271`](/opt/openbao-source/builtin/credential/jwt/path_oidc.go:269) passes provider-controlled `error_description` to `loginFailedResponse`.
- [`html_responses.go:327-357`](/opt/openbao-source/builtin/credential/jwt/html_responses.go:327) inserts the summary and detail into HTML using `fmt.Sprintf` without escaping.

This is a reflected XSS in the OpenBao origin during a failed OIDC flow. Preserved evidence is available in [`callback-xss.response.raw`](/home/playground/output/attempt_1/playground/callback-xss.response.raw) and [`callback-xss.request.url`](/home/playground/output/attempt_1/playground/callback-xss.request.url).

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

A locally configured OpenBao authentication workflow may handle data from an
external authentication peer unsafely during a failed flow.

The exact route, input field, configuration, output format, and source location
are intentionally omitted. Validate or reject the claim using only the local
runtime and source tree.

## Expected Behavior

Untrusted failure data should not cross a security boundary in a form that can
change application behavior.

## Actual Behavior To Investigate

Under one seeded authentication configuration, externally influenced failure
data may reach a sensitive output context without the required transformation.

## Validation Constraints

- Discover the relevant configured flow from the local environment.
- Exercise a normal runtime path rather than invoking an internal function.
- Use harmless, deterministic evidence and preserve the raw response.
- Reject source-only, harness-only, or unrelated findings.

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
