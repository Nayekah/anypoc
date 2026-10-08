## Evidence Requirements

Independently replay the final PoC against the running local OpenBao service.
Pass only when the artifacts establish all of the following:

1. The PoC uses the report's actual externally reachable entry point and
   required preconditions.
2. Runtime-dependent values are obtained through the normal application flow.
3. Complete requests, responses, and the claimed security observation are
   preserved.
4. The pass/fail oracle distinguishes the reported behavior from its benign or
   expected control.
5. No target modification, direct internal invocation, stale artifact, external
   listener, or unrelated surface is needed.

Fail when evidence is incomplete, ambiguous, source-only, harness-dependent, or
does not match the current report and analysis.

Do not browse the internet, query external documentation, install packages, or
inspect other attempts. Use only current-attempt artifacts, local source, local
logs, and local service behavior.
