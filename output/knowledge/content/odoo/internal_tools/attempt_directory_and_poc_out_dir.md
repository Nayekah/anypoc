---
keywords:
- attempt layout
- POC_OUT_DIR
- playground
- poc
- evidence
- final-run
times_used: 2
times_useful: 2
---

AnyPoC Odoo runs follow a stable attempt layout under `/home/playground/output/attempt_N/`:

- `playground/` for experimentation
- `poc/` for the final delivered PoC
- `evidence/` for preserved artifacts
- `trajs/` for agent history

A reusable runner should accept an output directory via `POC_OUT_DIR` so the same script can be tested in `playground/` and then verified from the final copy in `poc/`. The standard final verification shape is:

```bash
POC_OUT_DIR=/home/playground/output/attempt_N/evidence/final-run /home/playground/output/attempt_N/poc/run_poc.sh
```

Design helpers to write logs and downloaded responses into the caller-selected output directory so the evidence step preserves exactly what the delivered `poc/` copy produced.