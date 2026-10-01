AnyPoC Odoo attempts can finish with a failing top-level status even when the delivered PoC and evidence are already usable. One observed pattern is `status.json` showing `generation.status: completed` while `evidence_check.status: error` blocks the overall attempt from being marked clean.

Before retrying from scratch, inspect:

- `poc/run_poc.sh`
- `evidence/final-run/`
- `evidence/poc_execution_clean_status.txt`
- `evidence/poc_exit_status.txt`

If the delivered runner exits `0` and `evidence/final-run/` contains the expected artifacts, treat those files as the source of truth. Non-fatal evaluation or evidence-postprocessing failures can leave the attempt marked unsuccessful even though the web-surface PoC itself already worked.