# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.

## Analysis Summary (from Bug Analyzer)

The bug analyzer has already explored the codebase and provides the following context:

The vulnerability reproduces in the local OpenBao 2.5.1 lab.

- The `oidc` mount is configured with local issuer `http://127.0.0.1:9001`.
- Role `lab-direct` uses `callback_mode=direct`.
- An unauthenticated `POST /v1/auth/oidc/oidc/auth_url` returns a fresh OAuth state.
- An unauthenticated callback request with `error_description` returns `HTTP 400 Content-Type: text/html`.
- A benign marker is rendered as text, while this payload is returned verbatim inside the error paragraph:

  ```html
  <script>document.body.setAttribute("data-xss","XSS_MARKER")</script>
  ```

- Parsing the response with local `jsdom` executed the script and produced `body_data_xss=XSS_MARKER`.

Relevant source:

- `path_oidc.go:262-271`: direct mode enables HTML responses and passes `error_description` to `loginFailedResponse`.
- `path_oidc.go:216-225`: constructs the raw HTML response.
- `html_responses.go:332-357`: interpolates `detail` with `fmt.Sprintf` without HTML escaping.
- The UI stores non-root authentication token data in same-origin local storage via `ui/app/services/auth.js` and `ui/app/lib/token-storage.js`.

The report’s root cause and consequence are therefore confirmed: attacker-influenced OIDC error data becomes executable HTML/JavaScript in the OpenBao origin.

Use this information to guide your PoC development. The analyzer has already verified the bug is valid.



## Validated Bug Report:
## Summary

OpenBao installations using an OIDC/JWT authentication method with a role
configured for `callback_mode=direct` are vulnerable to reflected cross-site
scripting through the `error_description` value processed by the failed OIDC
authentication callback page.

The issue affects OpenBao versions through 2.5.1 and is fixed in 2.5.2.

## Preconditions

- An OIDC/JWT authentication method is enabled.
- The selected role uses `callback_mode=direct`.
- A victim opens an attacker-controlled authentication callback URL or follows an
  OIDC failure redirect carrying attacker-influenced error data.

No prior OpenBao authentication is required to reach the callback, although the
impact is greatest when the victim has a Web UI token in the same browser origin.

## Entry Point

The affected flow starts at the auth URL endpoint and completes at:

`GET /v1/auth/<mount>/oidc/callback`

The callback accepts OAuth state and an `error_description` value. For a direct
callback role, an authentication failure is rendered as HTML.

## Vulnerable Behavior

In `builtin/credential/jwt/path_oidc.go`, the direct callback path passes the
provider-controlled error description to `loginFailedResponse`. In
`builtin/credential/jwt/html_responses.go`, `errorHTML` interpolates the detail
into an HTML template without context-appropriate escaping.

An HTML or script payload can therefore become active markup in the OpenBao
origin instead of being displayed as inert error text.

## Expected Behavior

Provider error details must not be rendered as executable content. They should
be replaced with a static user-facing message or escaped for their precise HTML
context.

## Security Impact

Script execution in the OpenBao origin can read Web UI state available to that
origin, including non-root authentication tokens persisted by the UI, and can
perform same-origin actions as the victim.

## Desired PoC

Use the local OpenBao runtime and local OIDC provider only. Obtain fresh state
from the normal auth URL API, submit a harmless marker through the failed direct
callback, preserve the raw HTTP exchange, and prove that the marker is treated
as executable markup. Do not send data to an external server.

## Public Context

This report corresponds to CVE-2026-33758 and the public OpenBao advisory
GHSA-cpj3-3r2f-xj59. The public fix in 2.5.2 replaces the reflected provider
detail with a static error and adds context-appropriate escaping.


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
