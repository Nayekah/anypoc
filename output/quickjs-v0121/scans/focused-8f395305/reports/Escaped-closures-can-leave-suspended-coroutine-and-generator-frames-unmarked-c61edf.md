---
identifier: Escaped-closures-can-leave-suspended-coroutine-and-generator-frames-unmarked-c61edf
title: Escaped closures can leave suspended coroutine and generator frames unmarked
strategy: focused
metadata:
  instruction: Audit-QuickJS-NG-v0.12.1-runtime-GC-arguments-closures-eval-async-generator-for-deterministic-memory-safety-crashes-via-qjs-or-qjsc-small-JavaScript-ASan-abort-assertion-evidence-ignore-flaky-OOM-bytecode-only
---

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
