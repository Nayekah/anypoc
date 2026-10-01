# RAR5 overlong varint parser desync PoC

This PoC demonstrates the libarchive RAR5 parser desynchronization through a crafted archive file processed by the shipped CLI.

Run:

```bash
./run_poc.sh
```

The script materializes two small RAR5 archives:

- `generated/c001_normal_with_original_file_tail.rar`: control archive that lists `helloworld.txt`.
- `generated/c001_overlong_with_original_file_tail.rar`: malformed archive with an overlong MAIN-header `archive_flags` varint. Processing it with `bsdtar -tvf` causes later parsing to start at the wrong offset and reports `Header CRC error`.

`BSDTAR=/path/to/bsdtar ./run_poc.sh` can be used to test another libarchive build.
