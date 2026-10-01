import base64
import json

from odoo import fields, models


class AnyPocApprovalRequest(models.Model):
    _name = "anypoc.approval.request"
    _description = "AnyPoC Approval Request"
    _order = "id desc"

    name = fields.Char(required=True)
    owner_id = fields.Many2one("res.users", required=True, default=lambda self: self.env.user)
    amount = fields.Float(required=True, default=0.0)
    state = fields.Selection(
        [
            ("draft", "Draft"),
            ("submitted", "Submitted"),
            ("approved", "Approved"),
        ],
        required=True,
        default="draft",
    )
    secret_token = fields.Char(required=True)
    secret_notes = fields.Text()


class AnyPocApprovalExportWizard(models.TransientModel):
    _name = "anypoc.approval.export.wizard"
    _description = "AnyPoC Approval Export Wizard"

    target_request_id = fields.Integer(required=True)
    export_file = fields.Binary(readonly=True)
    export_filename = fields.Char(readonly=True)

    def action_generate_export(self):
        self.ensure_one()
        target = self.env["anypoc.approval.request"].sudo().browse(self.target_request_id)
        target.ensure_one()

        payload = {
            "request_id": target.id,
            "request_name": target.name,
            "owner_login": target.owner_id.login,
            "amount": target.amount,
            "state": target.state,
            "secret_token": target.secret_token,
            "secret_notes": target.secret_notes,
        }
        content = json.dumps(payload, indent=2, sort_keys=True).encode()
        filename = f"approval-export-{target.id}.json"
        self.write(
            {
                "export_file": base64.b64encode(content),
                "export_filename": filename,
            }
        )
        return {
            "type": "ir.actions.act_url",
            "url": (
                f"/web/content/?model={self._name}"
                f"&id={self.id}&field=export_file&filename_field=export_filename&download=true"
            ),
            "target": "self",
        }
