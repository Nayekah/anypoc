`/opt/odoo-lab/scripts/odoo_status.sh` is the quick readiness check for the Odoo lab container. Run it before debugging an HTTP or JSON-RPC PoC to confirm the web service and supporting lab state are up.

When bootstrapping a helper in the lab, pair that check with the other standard runtime paths used in the environment:

- `/opt/odoo-lab/odoo.conf` to confirm database and service settings instead of guessing defaults.
- `/opt/odoo-venv/bin/python` to run PoC helpers against the lab's installed dependencies.

The repo copy at `projects/odoo/scripts/odoo.conf` is a useful local source of truth for those lab defaults. In this snapshot it sets `db_name = anypoc_odoo`, `http_port = 8069`, `db_user = playground`, and `addons_path = /opt/odoo/addons,/opt/odoo/odoo/addons`.

This is a good first step when a PoC that only uses normal Odoo endpoints appears to fail for environmental reasons rather than application logic.