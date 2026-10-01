---
identifier: FinalizationRegistry-can-enqueue-callbacks-with-collected-callback-or-held-value-954b7c
title: FinalizationRegistry can enqueue callbacks with collected callback or held
  value
strategy: focused
metadata:
  instruction: Audit-QuickJS-NG-v0.12.1-runtime-GC-arguments-closures-eval-async-generator-for-deterministic-memory-safety-crashes-via-qjs-or-qjsc-small-JavaScript-ASan-abort-assertion-evidence-ignore-flaky-OOM-bytecode-only
---

# FinalizationRegistry can enqueue callbacks with collected callback or held value

## Location

- `quickjs.c:59320`-`quickjs.c:59331` (`js_finrec_mark()` marks the registry callback, held values, and unregister tokens while the registry is live)
- `quickjs.c:59468`-`quickjs.c:59533` (`reset_weak_ref()` removes finalization entries and enqueues `fre->cb` / `fre->held_val` during GC)
- Specifically `quickjs.c:59521`-`quickjs.c:59529`, which only checks `JS_IsLiveObject(rt, fre->held_val)` and does not check whether the held value or callback is currently being collected as part of a cycle

## Why this is a bug

When a finalization target dies, `reset_weak_ref()` removes the `JS_WEAK_REF_KIND_FINALIZATION_REGISTRY_ENTRY` and may enqueue a finalization job using the registry callback and held value. In v0.12.1 the enqueue guard is:

`!rt->in_free && (!JS_IsObject(fre->held_val) || JS_IsLiveObject(rt, fre->held_val))`

This is insufficient during cycle collection. Objects that are part of a cycle being collected can still look live enough for this check, but have `free_mark` or `header.mark` state indicating they are being swept. The code also fetches the callback through the registry data and never verifies that the callback object is not itself in the same collected cycle.

As a result, QuickJS can enqueue a job whose callback or held value points to an object that the same GC cycle is collecting. When jobs are later executed, the runtime calls into freed memory or passes a freed held value, producing a heap-use-after-free under ASan.

The post-v0.12.1 fix avoids enqueueing if the held value or callback object has `free_mark` or `header.mark` set while cycles are being freed.

## How to confirm / reproduce

Build v0.12.1 with ASan and run with `qjs`:

```js
import * as std from "qjs:std";

let target = {};
let fr = new FinalizationRegistry(function() {});
fr.register(target, fr);
fr.ref = target;
target.ref = fr;
target = null;
fr = null;
std.gc();
```

A second variant puts the callback itself in the collected cycle:

```js
import * as std from "qjs:std";

let target = {};
let cb = function() {};
let fr = new FinalizationRegistry(cb);
fr.register(target, 42);
fr.ref = target;
target.ref = fr;
target.cb = cb;
target = null;
fr = null;
cb = null;
std.gc();
```

Both programs are small JavaScript inputs and do not depend on bytecode loading or OOM. The post-v0.12.1 regression file `tests/bug1318.js` contains these same patterns and is annotated to run under ASan.
