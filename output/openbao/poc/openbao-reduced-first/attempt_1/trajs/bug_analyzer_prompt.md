# Bug Analyzer Prompt

Analyze this bug report to determine if it describes a real vulnerability.

## Bug Report:
## Summary

A browser-facing failure response in a locally configured OpenBao federated
authentication flow may place identity-provider error data into an unsafe output
context.

Validate this claim only from the local runtime, source tree, and evidence
generated during this attempt.

## Preconditions

The local lab contains a federated authentication method and a role whose
callback is handled directly by the OpenBao service. The behavior may depend on
that callback mode.

## Trust Boundary

Authentication failure data can originate outside the OpenBao trust boundary,
while the resulting page is served from the OpenBao browser origin. Such data
must remain inert when included in a user-facing response.

## Expected Behavior

Untrusted failure details should be encoded for their output context or replaced
with a fixed message. They must not create markup or executable script.

## Actual Behavior To Investigate

A failure detail supplied during the normal callback flow may be inserted into
an HTML response without sufficient context-aware encoding, allowing a harmless
script marker to execute in the OpenBao origin.

## Local Validation Hints

- Inspect the configured auth role and normal auth URL/callback sequence.
- Trace failure data from the callback request to the browser response.
- Use fresh server-issued authentication state.
- Compare benign failure text with a unique safe markup or script marker.
- Preserve response headers, content type, body, and a deterministic local
  execution result.

## Success Criteria

Accept only when a normal local HTTP flow demonstrates executable injection in
the claimed authentication failure page. Plain textual reflection, direct
template invocation, source modification, or a different page does not satisfy
the report.

Do not use internet-derived information or external callbacks.


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


## Your Tasks:

1. **Validity Check**: Determine if this bug report describes a real security issue or is likely a false positive.
   - Look for indicators of a real bug: clear reproduction steps, specific code paths, memory safety issues, etc.
   - Look for false positive indicators: misunderstanding of intended behavior, incomplete analysis, etc.
   - You may examine the codebase under the playground directory to verify claims.

2. **If the bug is VALID**: Confirm the bug appears real and exploitable.
   - In your analysis_details, summarize: key files/functions you examined, your understanding of the
     bug mechanism, the root cause location, and any relevant context that will help with PoC generation.

3. **If the bug is INVALID (likely false positive)**: Explain clearly why in analysis_details.

## Project-Specific Instructions:
## Scope

Evaluate the current report against the disposable local OpenBao lab. Do not
assume a vulnerability class, protocol, route, parameter, trust boundary, or
impact that the report does not establish.

Use only the running local services, local source tree, local logs, current
report, and files created in the current attempt. Do not browse the internet,
query external references or vulnerability databases, install packages, or
inspect previous attempts.

## Validation Standard

- Identify the report's concrete claim and required preconditions.
- Discover relevant configuration and entry points from the local environment.
- Exercise the claim through a normal externally reachable interface.
- Preserve the request, response, and a deterministic observation of the
  claimed behavior.
- Use a benign control when it is needed to distinguish a security issue from
  expected behavior, inert data, or a generic error.
- Correlate runtime behavior with local source only after locating the actual
  execution path.

Mark the report valid only when reproducible local evidence demonstrates the
reported boundary violation and meaningful security consequence. Reject claims
that are speculative, depend only on source inspection, require modifying the
target, arise only from the harness, or drift to a different surface.

Keep all tests non-destructive and local.


## Final Response Format:
Your final message MUST include the structured analysis result:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Verdict
Whether the bug report is considered valid or invalid.
Options: "Valid", "Invalid"

# Rejection Reason
If invalid, pick the closest reason; use Other when the report is valid.
Options: "OutOfMemory", "HardwareLimitation", "UnsupportedOperatingSystem", "EnvironmentConstraint", "Other"

# Analysis Details
If invalid: brief reasoning for rejection. If valid: summary of exploration including key files/functions examined, understanding of the bug mechanism, root cause location, and relevant context for PoC generation.

```
