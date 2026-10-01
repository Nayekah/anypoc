# POC Generation Prompts

---

## Step 1: PoC Generation

You are generating a proof-of-concept (PoC) for a validated security bug.


## Validated Bug Report:
## Summary

`read_var()` in `libarchive/archive_read_support_format_rar5.c` reads at most 8 bytes from the input buffer, but when all 8 bytes have the continuation bit set it reports or consumes 9 bytes. This desynchronizes the RAR5 parser by one byte.

In the reproduced sample, the overlong varint is placed in the MAIN header's `archive_flags` field. After parsing that field, libarchive consumes one byte from the following FILE block and the next block is parsed from the wrong offset.

The upstream report describes this as a parser correctness bug unless further impact is found.

## Affected Code

File: `libarchive/archive_read_support_format_rar5.c`

Relevant function:

```c
static int read_var(struct archive_read* a, uint64_t* pvalue,
    uint64_t* pvalue_len)
```

Relevant logic from the upstream report:

```c
if(!read_ahead(a, 8, &p))
    return 0;

for(shift = 0, i = 0; i < 8; i++, shift += 7) {
    ...
}

if(pvalue_len) {
    *pvalue_len = 9;
} else {
    if(ARCHIVE_OK != consume(a, 9)) {
        return 0;
    }
}
```

## Reproduction Materials

Upstream issue:

- https://github.com/libarchive/libarchive/issues/3300

Attached sample archives:

- https://github.com/user-attachments/files/30148859/c001_rar5_overlong_varint_samples.zip

The zip contains:

- `c001_normal_with_original_file_tail.rar`
- `c001_overlong_with_original_file_tail.rar`

## Observed Behavior On This Local Build

I manually reproduced this on Sunday, August 2, 2026 against the local AnyPoC-built image `anypoc-libarchive:latest`.

Control sample:

```bash
/opt/libarchive/build/bin/bsdtar -tvf /samples/c001_normal_with_original_file_tail.rar
```

Observed output:

```text
-rw-r--r--  0 0      0          29 Sep 26  2018 helloworld.txt
```

Mutated sample:

```bash
/opt/libarchive/build/bin/bsdtar -tvf /samples/c001_overlong_with_original_file_tail.rar
```

Observed output:

```text
bsdtar: Header CRC error
bsdtar: Error exit delayed from previous errors
```

## Expected Behavior

`read_var()` should reject an unterminated or overlong RAR5 variable-length integer without consuming or reporting more bytes than it actually read and decoded.

## Actual Behavior

When the first 8 bytes of a RAR5 varint all have the high bit set, `read_var()` treats the value as valid and advances or reports 9 bytes even though only 8 bytes were decoded. The parser becomes desynchronized and later fails with `Header CRC error`.

## Desired PoC

An acceptable PoC can be as simple as:

1. obtaining or reconstructing the minimal malformed RAR5 archive,
2. invoking `/opt/libarchive/build/bin/bsdtar -tvf <archive>`,
3. demonstrating that the malformed sample produces the parser desynchronization oracle while the control sample does not.

If a smaller or cleaner reproducer can be generated from scratch, prefer that over simply reusing the attached sample.

## Impact

Confirmed impact from the upstream report: the RAR5 parser can be desynchronized by one byte, causing subsequent header parsing to start at the wrong offset. In the tested sample this leads to `Header CRC error`. No memory-safety impact, crash, or infinite loop has been confirmed yet.


## Available Paths:
Path to source code: /opt/libarchive

Path to built binary: /opt/libarchive/build/bin/bsdtar


## Directories:
- **Playground (for experimentation):** /home/playground/output/attempt_5/playground
- **Final PoC (only when ready):** /home/playground/output/attempt_5/poc

## Your Approach:

1. **Experiment in playground first**: Use /home/playground/output/attempt_5/playground to test ideas,
try different approaches, and iterate on your PoC.
Create test files, run experiments, and verify your understanding of the bug.

2. **Verify the bug triggers**: Before finalizing, make sure you can actually trigger the bug.
Test your PoC in the playground and confirm it causes the expected behavior (crash, assertion failure, etc.).

3. **Finalize only when confident**: Once you have a working PoC that reliably triggers the bug, create a
**minimal, concise, end-to-end functional** version and copy it to /home/playground/output/attempt_5/poc.
The final PoC should be clean and self-contained.

## User-Triggerable PoC Principle

Your PoC must demonstrate something a **real user or attacker can do** through normal
interaction surfaces (file input, network request, API call, UI action, CLI arguments, etc.).

- **DO**: Craft a malicious input file, webpage, network payload, or API request that
  triggers the bug when processed by the target software in its normal mode of operation.
- **DO NOT**: Directly call internal functions, manipulate in-memory state, or write a
  test harness that bypasses the software's input path. Such PoCs prove the code is buggy
  but fail to show real-world exploitability.
- **Ask yourself**: "If I present this PoC to a triaging developer, would they immediately
  see that the bug is reachable from user-controlled input?" If not, improve the PoC to make this clearer.

## CRITICAL RULES:

- **NO dummy examples**: If you cannot trigger the real bug, do not create fake/simulated examples.
    Either create a real working PoC or declare it impossible.
- **Real bugs only**: The PoC must actually trigger the vulnerability in the target software,
    not just illustrate how it could theoretically work.
- **Do NOT kill the orchestrator**: Never run blanket kill commands like `pkill python`,
    `pkill -u`, or `kill -9 1` — they will terminate the poc runner/orchestrator
    process. Only terminate the specific test processes you started.

## If PoC is NOT Possible:

If after investigation you determine that creating a PoC is **impossible**,
write a file `/home/playground/output/attempt_5/poc/IMPOSSIBLE.md` explaining:

1. **Failure Category** (pick one):
   - `UNREACHABLE`: The vulnerable code path cannot be reached from user-controlled input
   - `ENVIRONMENT_DEPENDENT`: Requires special hardware, OS, or environment we cannot replicate
   - `INVALID_BUG`: Further analysis shows this is not actually a valid/exploitable bug
   - `OTHER`: Some other fundamental blocker

2. **Detailed Explanation**: Why the PoC cannot be created

Do NOT create dummy or fake demonstrations as a substitute.
If it's impossible, just write IMPOSSIBLE.md and stop.

## Project-Specific Instructions:
## Important Constraints

- Do not write a standalone C or C++ harness that links against libarchive directly.
- Reproduce bugs through the shipped CLI tools: `/opt/libarchive/build/bin/bsdtar` or `/opt/libarchive/build/bin/bsdcpio`.
- The bug should be triggered by the contents of a crafted archive file, not by obviously invalid flags or unrealistic operator behavior.
- Prefer the smallest possible crafted input and the shortest CLI invocation that still reproduces the issue.

## Build Instructions

The Docker image already builds libarchive with AddressSanitizer and UndefinedBehaviorSanitizer enabled.

To rebuild after source changes:
```bash
cd /opt/libarchive
cmake --build build -j "$(nproc)"
```

To do a clean rebuild:
```bash
cd /opt/libarchive
rm -rf build
cmake -S . -B build -G Ninja \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_BUILD_TYPE=Debug \
    -DENABLE_TEST=OFF \
    -DCMAKE_C_FLAGS="-g -O1 -fsanitize=address,undefined -fno-omit-frame-pointer" \
    -DCMAKE_EXE_LINKER_FLAGS="-fsanitize=address,undefined" \
    -DCMAKE_SHARED_LINKER_FLAGS="-fsanitize=address,undefined"
cmake --build build -j "$(nproc)"
```

## Running Instructions

List archive contents:
```bash
/opt/libarchive/build/bin/bsdtar -tvf sample.tar
```

Extract an archive:
```bash
mkdir -p out
/opt/libarchive/build/bin/bsdtar -xvf sample.tar -C out
```

Read from stdin with bsdtar:
```bash
cat sample.tar | /opt/libarchive/build/bin/bsdtar -tvf -
```

List cpio contents:
```bash
/opt/libarchive/build/bin/bsdcpio -it < sample.cpio
```

Extract cpio contents:
```bash
mkdir -p out
(cd out && /opt/libarchive/build/bin/bsdcpio -idmv < ../sample.cpio)
```

## Notes

- Favor parser-facing attack surfaces: tar, cpio, pax, zip, xar, ar, mtree, ISO, and compressed variants handled by libarchive.
- A valid PoC usually consists of one or more crafted archive files plus a short shell script that invokes `bsdtar` or `bsdcpio`.
- Cleanly rejected corrupt inputs are not enough; the PoC should yield a sanitizer finding, crash, abort, or other clearly incorrect behavior.
- Sanitizer output is the preferred oracle in this environment.



---

## Step 2: Execution & Evidence

Execute the PoC and gather evidence.

## Tasks:

**Process safety**: Do not run blanket kill commands (e.g., `pkill python`, `pkill -u`,
`kill -9 1`) because they will terminate the poc runner/orchestrator process. Only
stop the specific test processes you launched.

1. **Execute the final PoC** from /home/playground/output/attempt_5/poc
2. **Collect evidence** according to the oracle (crash logs, ASan output, screenshots, etc.)
3. **Save all evidence** to /home/playground/output/attempt_5/evidence

If you wrote IMPOSSIBLE.md in the previous step, explain your findings in your response and skip execution.


---

## Step 3: Generation Summary

Summarize the PoC generation progress and current status.

## Final Response Format:
Your final message MUST contain the summary directly using the following structure:
Please respond in Markdown format with the following sections.
Use the descriptions to guide your responses, but do not include the descriptions themselves.
Format:
```markdown
# Status
Overall status of the PoC generation effort.
Options: "Completed", "Partial", "NeedsHelp", "Impossible"

# Summary
What was attempted, current PoC behavior, and whether the bug appears triggered.

# Next Actions
Concrete next steps or support needed. Use 'None' if no additional help is required.

```

Keep the prose concise; the status field must pick one of the allowed options.
