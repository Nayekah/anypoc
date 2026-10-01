---
identifier: Reentrant-thenable-lookup-can-resume-a-completed-async-generator-cc6b65
title: Reentrant thenable lookup can resume a completed async generator
strategy: focused
metadata:
  instruction: Audit-QuickJS-NG-v0.12.1-runtime-GC-arguments-closures-eval-async-generator-for-deterministic-memory-safety-crashes-via-qjs-or-qjsc-small-JavaScript-ASan-abort-assertion-evidence-ignore-flaky-OOM-bytecode-only
---

# Reentrant thenable lookup can resume a completed async generator

## Location

- `quickjs.c:20880`-`quickjs.c:20910` (`js_async_generator_resume_next()` schedules awaits and leaves resume callbacks live)
- `quickjs.c:20931`-`quickjs.c:20964` (`js_async_generator_resolve_function()` unconditionally resumes for `magic < 2` and asserts `state == EXECUTING`)

## Why this is a bug

`js_async_generator_resolve_function()` is the callback used to continue an async generator after an `await`. In v0.12.1, for normal await resume callbacks (`magic < 2`) it assumes the generator is still in `JS_ASYNC_GENERATOR_STATE_EXECUTING`:

`assert(s->state == JS_ASYNC_GENERATOR_STATE_EXECUTING);`

That assumption is invalid because resolving an awaited promise performs thenable assimilation and can run user code via a `then` getter. That user code can reenter the same async generator with `return()` or `next()` while an earlier await-resume callback is still queued. By the time the stale callback runs, the generator state may already be `COMPLETED` or in another non-executing state.

In a debug/assert build this is a deterministic abort. In a release build with assertions disabled, the stale callback continues anyway and writes to `s->func_state.frame.cur_sp[-1]` before calling `js_async_generator_resume_next()`, even though the generator is no longer in the expected execution state. That is state-machine memory corruption against a completed or otherwise stale generator frame.

The post-v0.12.1 fix changes the `else` arm to `else if (s->state == JS_ASYNC_GENERATOR_STATE_EXECUTING)`, ignoring stale await callbacks once reentrant operations have moved the generator out of the executing state.

## How to confirm / reproduce

Build v0.12.1 with debug assertions and run this small program with `qjs`:

```js
function deferred() {
    let resolve;
    const promise = new Promise(f => { resolve = f; });
    return { promise, resolve };
}

let it, a, b, c;
let getterHit = 0;
let inGetter = false;

Object.defineProperty(Object.prototype, "then", {
    configurable: true,
    get() {
        if (inGetter || !it) return undefined;
        inGetter = true;
        try {
            if (getterHit === 0) {
                it.return(0);
            } else if (getterHit === 1) {
                it.next(1);
                it.return(1);
            }
            getterHit++;
        } catch (_) {}
        inGetter = false;
        return undefined;
    },
});

async function* g() {
    try {
        await a.promise;
        yield 1;
        await b.promise;
        yield 2;
        await c.promise;
    } finally {
        await c.promise;
    }
}

(async () => {
    a = deferred();
    b = deferred();
    c = deferred();
    it = g();

    it.next();
    a.resolve({});
    await Promise.resolve();
    await Promise.resolve();
    b.resolve({});
    c.resolve({});
    await Promise.resolve();
})();
```

On v0.12.1 this reaches the invalid `assert(s->state == JS_ASYNC_GENERATOR_STATE_EXECUTING)` in `js_async_generator_resolve_function()`. The same script was added as `tests/bug1355.js` with the post-v0.12.1 fix.
