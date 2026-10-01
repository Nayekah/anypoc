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
