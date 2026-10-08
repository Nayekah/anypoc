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
