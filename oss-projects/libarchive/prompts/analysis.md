# Bugs to reject

Immediately reject any bug report that satisfies any of the following:

1. The issue is only a normal parse failure on a malformed archive and `bsdtar` or `bsdcpio` exits cleanly with an expected error message.
2. The issue requires a custom C harness that calls libarchive APIs directly instead of reproducing through the shipped CLI tools.
3. The issue only affects disabled, test-only, or platform-specific code paths that are not exercised by the Linux CLI build in this container.
4. The report depends on intentionally invalid command-line usage rather than a crafted archive processed through a realistic `bsdtar` or `bsdcpio` invocation.
