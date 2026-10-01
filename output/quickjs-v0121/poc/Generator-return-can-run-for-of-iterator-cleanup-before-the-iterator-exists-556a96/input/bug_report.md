# Generator return can run for-of iterator cleanup before the iterator exists

## Location

- `quickjs.c:27929`-`quickjs.c:27933` (`js_parse_for_in_of()` sets `break_entry.has_iterator` and increments `drop_count` as soon as it sees `of`)
- `quickjs.c:27947`-`quickjs.c:27963` (the iterable expression is parsed and only then emits `OP_for_of_start` / `OP_for_await_of_start` that actually creates the iterator record)

## Why this is a bug

For `for (... of EXPR)`, the parser records that the active break/return cleanup has an iterator before compiling `EXPR`. If `EXPR` contains `yield`, a generator can suspend while evaluating the iterable expression, before `OP_for_of_start` has executed and before any iterator record exists on the VM stack.

If the caller then invokes `Generator.prototype.return()`, QuickJS runs the pending break/return cleanup for the suspended frame. Because `break_entry.has_iterator` was set too early and `drop_count` was already incremented by 2, the cleanup bytecode attempts to close/drop an iterator record that is not present. That causes VM stack underflow / invalid stack access from a small JavaScript program.

The post-v0.12.1 fix moves `break_entry.has_iterator = true` and `break_entry.drop_count += 2` until after parsing the iterable expression, immediately before emitting `OP_for_of_start`, so a suspension during the expression does not advertise a nonexistent iterator to the unwinder.

## How to confirm / reproduce

Build v0.12.1 with ASan/debug assertions and run:

```js
function* x() {
    for (var e of yield []);
}

var g = x();
g.next();
g.return("test");
```

The first `next()` suspends inside the iterable expression (`yield []`). At that point no iterator record has been pushed, but the function's break-entry metadata says one exists. `g.return()` then takes the cleanup path and underflows the stack while trying to close/drop the nonexistent iterator.

The same reproducer was added after v0.12.1 as `tests/bug488-upstream.js` together with the fix that delays setting `has_iterator`.
