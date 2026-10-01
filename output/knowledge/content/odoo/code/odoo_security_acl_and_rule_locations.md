---
keywords:
- odoo
- security
- ir.model.access.csv
- ir.rule
- domain_force
- base.group_user
- search_read
- json-rpc
times_used: 0
times_useful: 0
---

For addon-level authorization in this Odoo codebase, inspect both security layers before deciding whether a normal-user JSON-RPC flow is realistic:

- `security/ir.model.access.csv` controls model-level CRUD rights by group.
- `security/*.xml` defines `ir.rule` records with `domain_force` filters that limit which rows a user can read or modify.

A user-triggerable PoC usually needs both layers to line up. Model code alone is not enough to answer whether a `base.group_user` session can create a wizard, read a record, or only operate on its own rows.

A practical workflow is:

- `rg` the addon for the model name to find both the Python model and the related security files.
- Read `ir.model.access.csv` first to see whether the target group has `create`, `write`, or `read` at all.
- Read the matching `ir.rule` definitions to see whether `domain_force` narrows record visibility to user-owned rows.
- Confirm the effective read surface with a baseline `search_read` under the low-privilege session before attempting any higher-level action.

This pattern is especially useful for wizard-style flows, where ordinary users may be allowed to create transient records even though their normal visibility into persistent business records is narrowed by record rules.