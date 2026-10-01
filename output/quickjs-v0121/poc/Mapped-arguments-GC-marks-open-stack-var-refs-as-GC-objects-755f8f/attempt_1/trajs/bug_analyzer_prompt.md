# Bug Analyzer Prompt

Analyze this bug report to determine if it describes a real vulnerability.

## Bug Report:
# Mapped arguments GC marks open stack var refs as GC objects

## Location

- `quickjs.c:15979`-`quickjs.c:15993` (`js_mapped_arguments_mark()`)
- `quickjs.c:16022`-`quickjs.c:16027` (`js_build_mapped_arguments()` stores `get_var_ref()` results for mapped parameters)
- `quickjs.c:16749`-`quickjs.c:16771` (`get_var_ref()` returns non-detached/open var refs for captured arguments)

## Why this is a bug

Sloppy functions with simple parameters create mapped `arguments` objects whose indexed entries are `JSVarRef`s back to the live argument slots. For formal parameters, `js_build_mapped_arguments()` stores the result of `get_var_ref(ctx, sf, i, true)`. Those var refs are usually open (`is_detached = false`) and are not on the GC object list; they are just reference-counted helpers pointing into the current stack frame.

`js_mapped_arguments_mark()` unconditionally does:

`mark_func(rt, &var_refs[i]->header);`

for every mapped entry. That is only valid for detached var refs created as GC objects. When the entry is an open stack var ref, the GC receives a pointer to an object that is not in the GC list. The cycle collector then interprets non-GC memory as a `JSGCObjectHeader`, which can corrupt GC traversal or crash/assert under ASan/debug builds.

The post-v0.12.1 fix changed this marker to only mark `var_refs[i]` when `var_refs[i]->is_detached`, matching the representation used elsewhere for `JSVarRef`.

## How to confirm / reproduce

Build v0.12.1 with ASan/debug assertions and run:

```js
function f(a) {
    arguments;
    gc();
}
f(0);
```

`qjs` exposes global `gc()` from `qjs.c:199`-`qjs.c:219`. The crash is triggered during GC marking of the mapped arguments object, before the function frame has returned, so the argument var ref is still open and not a valid GC object.

The upstream regression test added after v0.12.1 uses the same shape:

```js
function f3(a) {
    arguments;
    gc();
}
f3(0);
```


## Available Paths:
Path to source code: /opt/quickjs

Path to built binary: /opt/quickjs/build/qjs


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
# Bugs to Reject

Immediately reject any bug report that satisfies any of the following condition:

1. About not saving cur_pc for some opcode handler

# Target Focus

This project targets QuickJS-NG v0.12.1. Focus analysis on memory-safety bugs
reachable through normal QuickJS command-line execution, especially runtime
object lifetime, function arguments behavior, closures, async/generator
execution, eval, and garbage-collection marking paths.

Accept only findings that are reproducible locally with the `qjs` or `qjsc`
command-line binaries and produce deterministic crash, abort, assertion failure,
or AddressSanitizer evidence. Do not pursue arbitrary code execution payloads.
Reject flaky resource exhaustion, bugs requiring custom embedders, and bytecode
loading from untrusted external binary blobs.


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
