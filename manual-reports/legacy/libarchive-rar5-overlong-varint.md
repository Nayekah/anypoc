---
identifier: libarchive-rar5-overlong-varint
title: libarchive RAR5 overlong varint desynchronizes parser by one byte
strategy: manual
metadata:
  source: github-issue-3300
  issue_url: https://github.com/libarchive/libarchive/issues/3300
  sample_zip_url: https://github.com/user-attachments/files/30148859/c001_rar5_overlong_varint_samples.zip
  affected_file: libarchive/archive_read_support_format_rar5.c
---

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
