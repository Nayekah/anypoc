# Bug Analyzer Prompt

Analyze this bug report to determine if it describes a real vulnerability.

## Bug Report:
# Escaped closures can leave suspended coroutine and generator frames unmarked

## Location

- `quickjs.c:361`-`quickjs.c:375` (`JSStackFrame` has no owning GC-object backpointer for suspended coroutine frames)
- `quickjs.c:16749`-`quickjs.c:16771` (`get_var_ref()` creates open `JSVarRef`s that point directly into the stack frame)
- `quickjs.c:6446`-`quickjs.c:6465` (`js_bytecode_function_mark()` only marks detached var refs held by closures)
- `quickjs.c:6744`-`quickjs.c:6749` (`mark_children()` only marks detached `JS_PROP_VARREF` properties)
- `quickjs.c:20129`-`quickjs.c:20167`, `quickjs.c:20368`-`quickjs.c:20395`, `quickjs.c:20567`-`quickjs.c:20599`, `quickjs.c:21011`-`quickjs.c:21042` (async/generator frames are heap-suspended across yield/await)

## Why this is a bug

A closure that captures a local or argument from a running function receives an open `JSVarRef`: `get_var_ref()` stores `is_detached = false`, `stack_frame = sf`, and `pvalue` pointing into `sf->arg_buf` or `sf->var_buf`. For an ordinary running function, that frame is a C-stack root. For a suspended generator, async function, or async generator, the frame is stored in heap data and can participate in GC cycles.

In v0.12.1, open var refs are not GC objects and are not traced by their holders. `js_bytecode_function_mark()` only calls `mark_func()` when `var_ref->is_detached`, and object var-ref properties have the same detached-only check. Therefore the collector cannot see the edge:

`escaped closure -> open JSVarRef -> suspended coroutine/generator frame`

If the suspended coroutine/generator is otherwise only reachable through that captured local, the cycle collector can collect it while the closure is still live. Collection closes/frees the frame, but the escaped closure still contains an open var ref whose `pvalue` points into the freed frame. Calling the closure or resuming the generator then reads/writes freed memory.

This is a deterministic memory-safety issue reachable from small JavaScript through `qjs` with an explicit GC.

## How to confirm / reproduce

Build v0.12.1 with ASan/debug assertions, then run this with `qjs`:

```js
import * as std from "qjs:std";

globalThis.leaked = null;

(function () {
    let g;
    function* gen() {
        const o = {};
        o.g = g;
        globalThis.leaked = () => o;
        yield;
    }
    g = gen();
    g.next();
    g = null;
})();

std.gc();

const o = leaked();
o.g.next();
```

A second async-function form exercises the same open-var-ref edge without a sync generator:

```js
import * as std from "qjs:std";

function deferred() {
    let resolve;
    const promise = new Promise(r => { resolve = r; });
    return { promise, resolve };
}

globalThis.leaked = null;

(function () {
    async function step() {
        const d = deferred();
        globalThis.leaked = () => d;
        await d.promise;
    }
    step();
})();

std.gc();
const d = leaked();
if (typeof d.resolve !== "function") throw new Error("corrupt captured value");
```

The fix is to make open var refs that capture coroutine/generator locals visible to the GC and make them retain the owning coroutine/generator object while open; a post-v0.12.1 local branch named `origin/fix-uaf-gc-async-coro` implements exactly that by adding coroutine ownership tracking and marking those open var refs from closures/properties.


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
