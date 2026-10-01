The PoC must reproduce through `/opt/libarchive/build/bin/bsdtar` or `/opt/libarchive/build/bin/bsdcpio`, not through a standalone program linked against libarchive.

Acceptable evidence is one of:

- An AddressSanitizer or UndefinedBehaviorSanitizer report with a clear stack trace in libarchive code.
- A deterministic crash or abort in the CLI binary caused by a crafted archive.
- Clearly incorrect archive-processing behavior that violates the bug report's stated oracle and is observable from the CLI output.

Handled errors such as "truncated archive", "unsupported format", checksum failures, or other clean rejection paths are not valid evidence by themselves.
