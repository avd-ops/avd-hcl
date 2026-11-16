import unittest

from handover import runbook


class HandoverTests(unittest.TestCase):
    def test_render_runbook_contains_key_sections(self):
        outputs = {
            "host_pool_name": {"value": "vdpool-avd-dev"},
            "key_vault_name": {"value": "kv-avd-dev-123456"},
            "profile_share_unc": {"value": "\\\\stavddev123456.file.core.windows.net\\profiles"},
            "session_host_names": {"value": ["avdsh-001", "avdsh-002"]},
            "resource_group_names": {"value": {"control_plane": "rg-avd-dev-avd", "session_hosts": "rg-avd-dev-hosts"}},
        }
        tfvars = {"prefix": "avd-dev", "location": "eastus2", "identity_model": "ad_ds"}
        md = runbook.render_runbook(outputs, tfvars)

        self.assertIn("# AVD Environment Handover Runbook (avd-dev)", md)
        self.assertIn("`ad_ds`", md)
        self.assertIn("`vdpool-avd-dev`", md)
        self.assertIn("`avdsh-001-localadmin`", md)
        self.assertIn("scripts/verify/check.py --resource-group rg-avd-dev-avd --host-pool-name vdpool-avd-dev", md)


if __name__ == "__main__":
    unittest.main()
