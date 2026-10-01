from datetime import date


def ensure_password(user, password):
    user.with_context(no_reset_password=True).write({"password": password})


company = env.company
france = env.ref("base.fr")
company.write(
    {
        "name": "AnyPoC France Lab",
        "country_id": france.id,
        "account_fiscal_country_id": france.id,
        "vat": "FR40303265045",
    }
)
company._onchange_country_id()
env.ref("l10n_fr.l10n_fr_pcg_chart_template").try_loading(company=company)

admin = env.ref("base.user_admin")
admin.write(
    {
        "login": "admin@lab.local",
        "email": "admin@lab.local",
        "company_id": company.id,
        "company_ids": [(6, 0, [company.id])],
    }
)
ensure_password(admin, "adminpass")

employee_group = env.ref("base.group_user")
portal_group = env.ref("base.group_portal")

employee = env["res.users"].search([("login", "=", "employee@lab.local")], limit=1)
if not employee:
    employee = env["res.users"].create(
        {
            "name": "AnyPoC Employee",
            "login": "employee@lab.local",
            "email": "employee@lab.local",
            "company_id": company.id,
            "company_ids": [(6, 0, [company.id])],
            "groups_id": [(6, 0, [employee_group.id])],
        }
    )
else:
    employee.write(
        {
            "company_id": company.id,
            "company_ids": [(6, 0, [company.id])],
            "groups_id": [(6, 0, [employee_group.id])],
        }
    )
ensure_password(employee, "employeepass")

portal = env["res.users"].search([("login", "=", "portal@lab.local")], limit=1)
if not portal:
    portal = env["res.users"].create(
        {
            "name": "AnyPoC Portal",
            "login": "portal@lab.local",
            "email": "portal@lab.local",
            "company_id": company.id,
            "company_ids": [(6, 0, [company.id])],
            "groups_id": [(6, 0, [portal_group.id])],
        }
    )
else:
    portal.write(
        {
            "company_id": company.id,
            "company_ids": [(6, 0, [company.id])],
            "groups_id": [(6, 0, [portal_group.id])],
        }
    )
ensure_password(portal, "portalpass")

partner = env["res.partner"].search([("name", "=", "AnyPoC Customer")], limit=1)
if not partner:
    partner = env["res.partner"].create({"name": "AnyPoC Customer", "email": "customer@lab.local"})

journal = env["account.journal"].search([("company_id", "=", company.id), ("type", "=", "general")], limit=1)
receivable_account = env["account.account"].search(
    [("company_id", "=", company.id), ("deprecated", "=", False), ("user_type_id.type", "=", "receivable")],
    limit=1,
)
payable_account = env["account.account"].search(
    [("company_id", "=", company.id), ("deprecated", "=", False), ("user_type_id.type", "=", "payable")],
    limit=1,
)

assert journal and receivable_account and payable_account, "Missing seeded accounting primitives"

existing_move = env["account.move"].search([("ref", "=", "ANYPOC-SEED-REF")], limit=1)
if not existing_move:
    move = env["account.move"].create(
        {
            "move_type": "entry",
            "date": date(2025, 1, 15),
            "ref": "ANYPOC-SEED-REF",
            "journal_id": journal.id,
            "line_ids": [
                (
                    0,
                    0,
                    {
                        "name": "AnyPoC seeded debit",
                        "partner_id": partner.id,
                        "account_id": receivable_account.id,
                        "debit": 250.0,
                        "credit": 0.0,
                    },
                ),
                (
                    0,
                    0,
                    {
                        "name": "AnyPoC seeded credit",
                        "partner_id": partner.id,
                        "account_id": payable_account.id,
                        "debit": 0.0,
                        "credit": 250.0,
                    },
                ),
            ],
        }
    )
    move.action_post()

approval_model = env["anypoc.approval.request"]

admin_request = approval_model.search([("name", "=", "ANYPOC Admin Approval")], limit=1)
if not admin_request:
    admin_request = approval_model.create(
        {
            "name": "ANYPOC Admin Approval",
            "owner_id": admin.id,
            "amount": 1337.0,
            "state": "approved",
            "secret_token": "ANYPOC-APPROVAL-SECRET-9f4b3c",
            "secret_notes": "Admin-only export marker for AnyPoC approval lab",
        }
    )

employee_request = approval_model.search([("name", "=", "ANYPOC Employee Decoy")], limit=1)
if not employee_request:
    employee_request = approval_model.create(
        {
            "name": "ANYPOC Employee Decoy",
            "owner_id": employee.id,
            "amount": 25.0,
            "state": "submitted",
            "secret_token": "ANYPOC-EMPLOYEE-DECOY",
            "secret_notes": "Non-sensitive decoy request owned by employee",
        }
    )

env.cr.commit()
print("Seed complete: admin@lab.local, employee@lab.local, portal@lab.local")
print(f"Admin approval request id: {admin_request.id}")
