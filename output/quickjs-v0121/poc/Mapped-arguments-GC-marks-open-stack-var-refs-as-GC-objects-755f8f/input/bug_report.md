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
