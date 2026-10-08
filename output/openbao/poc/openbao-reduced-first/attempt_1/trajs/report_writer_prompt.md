# Report Writer Prompt

Write a concise bug report for submission to the security team.

## Validated Bug Report:
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


## POC Directory: /home/playground/output/attempt_1/poc
Review the POC files and reference them in your report.

## Report Format:
Your response MUST be a markdown document following this exact format:

# Title: concise description of the validated issue

## Summary

<!-- State the verified behavior and security boundary in one paragraph. -->

## Threat Model

<!-- Identify attacker control, required victim or system action, and assets at risk. -->

## Preconditions

<!-- List only configuration and state requirements established by evidence. -->

## Entry Point

<!-- Name the externally reachable interface and relevant inputs. -->

## Root Cause

<!-- Trace the validated runtime behavior to the relevant local source. -->

## Expected Behavior

<!-- Describe the secure or intended behavior. -->

## Actual Behavior

<!-- Describe the observed behavior without extending beyond the evidence. -->

## Reproduction

<!-- Give the minimal deterministic local flow. -->

## Evidence And Oracle

<!-- Identify raw artifacts, controls, and the exact pass condition. -->

## Impact

<!-- State demonstrated impact separately from plausible impact. -->

## Limitations

<!-- Record configuration scope, untested variants, and uncertainty. -->


Fill in each section based on the bug report and POC artifacts.
Output ONLY the filled-in report, no additional commentary.

    Keep it short. No fluff.