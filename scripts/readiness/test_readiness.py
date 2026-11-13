"""Offline tests: recorded az answers, shaped the way ARM returns them (empty properties left out).

    python3 -m unittest discover -s scripts/readiness -t scripts
"""

import json
import unittest

from readiness import model, report, runner
from readiness.checks import subscription
from readiness.context import WriteRefused, is_read_only
from readiness.main import evaluate, values_from

SUB = "00000000-0000-0000-0000-000000000002"
USERS = "00000000-0000-0000-0000-000000000003"

SKU = {
    "name": "Standard_E4as_v5", "family": "standardEASv5Family",
    "locationInfo": [{"location": "eastus2", "zones": ["1", "2", "3"]}],
    "capabilities": [{"name": "vCPUs", "value": "4"}, {"name": "PremiumIO", "value": "True"},
                     {"name": "EncryptionAtHostSupported", "value": "True"}],
    # no "restrictions": ARM leaves an empty list out
}


class FakeAz:
    """Answers az by the first words of the command line; unknown commands fail like az does."""

    def __init__(self, overrides=None):
        self.answers = {
            "cloud show": "AzureCloud",
            "account show": {"id": SUB, "name": "Contoso Sandbox", "user": {"type": "user", "name": "admin@contoso.com"}},
            "ad signed-in-user show": "00000000-0000-0000-0000-000000000004",
            "role assignment list": ["Owner"],
            "ad group list": [USERS],
            "ad sp list": ["00000000-0000-0000-0000-000000000005"],
            "network vnet show": {"prefixes": ["10.0.0.0/16", "fd00:db8::/48"]},
            "provider list": [{"ns": ns, "state": "Registered"} for ns in subscription.platform_providers()],
            "account list-locations": ["eastus2", "centralus"],
            "feature show": "Registered",
            "policy assignment list": [],
            "group list": [],
            "network vnet list": [],
            "network private-dns zone list": [],
            "vm list-skus": [SKU],
            "vm list-usage": [{"name": {"value": "standardEASv5Family"}, "limit": 20, "currentValue": 0},
                              {"name": {"value": "cores"}, "limit": 20, "currentValue": 4}],
        }
        self.answers.update(overrides or {})

    def __call__(self, args):
        words = " ".join(a for a in args if not a.startswith("-")).split(" ")
        for n in range(len(words), 0, -1):
            key = " ".join(words[:n])
            if key in self.answers:
                return self.answers[key]
        return None


def run(fake=None, **answers):
    values = values_from({"user_groups": [USERS], **answers})
    ctx, results, _ = evaluate(values, az=fake or FakeAz(), which=lambda t: f"/usr/bin/{t}",
                               run_tool=lambda cmd: json.dumps({"terraform_version": "1.16.6"}), python_version=(3, 12))
    return ctx, results


def by_id(results, cid):
    return [r for r in results if r.id == cid]


class ReadinessTest(unittest.TestCase):
    def test_every_check_meets_the_contract(self):
        self.assertEqual(model.contract_problems(list(model.REGISTRY.values())), [])

    def test_a_ready_subscription_is_go(self):
        ctx, results = run()
        self.assertEqual(report.verdict(results), report.GO_WARN)  # licenses are always for a person to confirm
        self.assertEqual({r.status for r in results} - {"pass", "manual", "skipped"}, set())

    def test_checks_only_read(self):
        ctx, _ = run()
        self.assertTrue(ctx.calls)
        self.assertTrue(all(is_read_only(c) for c in ctx.calls))
        with self.assertRaises(WriteRefused):
            ctx.az(["provider", "register", "-n", "Microsoft.Compute"])

    def test_write_verbs_are_refused(self):
        self.assertFalse(is_read_only(["rest", "--method", "post", "--url", "x"]))
        self.assertFalse(is_read_only(["rest", "--url", "x", "--body", "{}"]))
        self.assertTrue(is_read_only(["rest", "--url", "x"]))
        self.assertFalse(is_read_only(["feature", "register", "--name", "x"]))
        self.assertFalse(is_read_only(["rest", "-m", "post", "--url", "x"]))
        self.assertFalse(is_read_only(["rest", "--method=put", "--url", "x"]))
        self.assertFalse(is_read_only(["rest", "--method", "get", "--body=x", "--url", "x"]))
        self.assertTrue(is_read_only(["rest", "--method=GET", "--url", "x"]))

    def test_missing_size_is_no_go(self):
        _, results = run(FakeAz({"vm list-skus": []}))
        self.assertEqual(by_id(results, "avd.vm_size")[0].status, "fail")
        self.assertEqual(report.verdict(results), report.NO_GO)

    def test_size_without_encryption_at_host_fails_only_when_it_is_on(self):
        sku = {**SKU, "capabilities": [c for c in SKU["capabilities"] if c["name"] != "EncryptionAtHostSupported"]}
        _, results = run(FakeAz({"vm list-skus": [sku]}))
        self.assertIn("fail", {r.status for r in by_id(results, "avd.vm_features")})
        _, results = run(FakeAz({"vm list-skus": [sku]}), encryption_at_host=False)
        self.assertEqual({r.status for r in by_id(results, "avd.vm_features")}, {"pass"})

    def test_feature_not_registered(self):
        _, results = run(FakeAz({"feature show": "NotRegistered"}))
        self.assertEqual(by_id(results, "sub.encryption_at_host")[0].status, "fail")

    def test_zone_not_offered(self):
        sku = {**SKU, "restrictions": [{"type": "Zone", "reasonCode": "NotAvailableForSubscription",
                                        "restrictionInfo": {"zones": ["3"]}}]}
        _, results = run(FakeAz({"vm list-skus": [sku]}), availability_zones=["1", "3"])
        self.assertEqual(by_id(results, "avd.zones")[0].status, "fail")
        self.assertIn("zone 3", by_id(results, "avd.zones")[0].detail)

    def test_zones_skipped_for_regional_hosts(self):
        _, results = run()
        self.assertEqual(by_id(results, "avd.zones")[0].status, "skipped")

    def test_quota_is_per_host(self):
        _, results = run(host_count=3)
        self.assertEqual({r.status for r in by_id(results, "avd.vcpu")}, {"pass"})
        _, results = run(host_count=5)
        self.assertEqual([r.status for r in by_id(results, "avd.vcpu")], ["pass", "fail"])  # 20 needed, 16 free regionally

    def test_no_hosts_needs_no_quota(self):
        _, results = run(FakeAz({"vm list-usage": None}), host_count=0)
        self.assertEqual(by_id(results, "avd.vcpu")[0].status, "pass")

    def test_unknown_group_name_fails(self):
        _, results = run(FakeAz({"ad group list": []}), user_groups=["AVD Users"])
        self.assertEqual(by_id(results, "id.groups")[0].status, "fail")

    def test_unreadable_directory_is_no_access(self):
        _, results = run(FakeAz({"ad group list": None}), user_groups=["AVD Users"])
        self.assertEqual(by_id(results, "id.groups")[0].status, "no-access")

    def test_contributor_alone_is_not_enough(self):
        _, results = run(FakeAz({"role assignment list": ["Contributor"]}))
        self.assertEqual(by_id(results, "id.sub_owner")[0].status, "fail")
        _, results = run(FakeAz({"role assignment list": ["Contributor", "Role Based Access Control Administrator"]}))
        self.assertEqual(by_id(results, "id.sub_owner")[0].status, "pass")

    def test_service_principal_sign_in_is_manual(self):
        acct = {"id": SUB, "name": "Contoso Sandbox", "user": {"type": "servicePrincipal", "name": USERS}}
        _, results = run(FakeAz({"account show": acct}))
        self.assertEqual(by_id(results, "id.sub_owner")[0].status, "manual")

    def test_unregistered_provider_warns(self):
        _, results = run(FakeAz({"provider list": [{"ns": "Microsoft.Compute", "state": "Registered"}]}))
        r = by_id(results, "sub.providers")[0]
        self.assertEqual(r.status, "warn")
        self.assertIn("Microsoft.DesktopVirtualization", r.detail)

    def test_overlap_ignores_the_kits_own_network(self):
        vnets = [{"name": "vnet-avd-sandbox-avd", "rg": "rg-x", "prefixes": ["10.50.0.0/20"]},
                 {"name": "vnet-other", "rg": "rg-y", "prefixes": ["10.50.8.0/24"]}]
        _, results = run(FakeAz({"network vnet list": vnets}))
        r = by_id(results, "net.overlap")[0]
        self.assertEqual(r.status, "warn")
        self.assertIn("<vnet-1>", r.detail)
        self.assertNotIn("vnet-other", r.detail)

    def test_firewall_egress_is_for_a_person_to_confirm(self):
        _, results = run(create_nat_gateway=False, egress_firewall_ip="10.0.0.4")
        self.assertEqual(by_id(results, "net.egress")[0].status, "manual")
        _, results = run(create_nat_gateway=False)
        self.assertEqual(by_id(results, "net.egress")[0].status, "fail")

    def test_unsupported_cloud_stops_the_rest(self):
        _, results = run(FakeAz({"cloud show": "AzureUSGovernment"}))
        self.assertEqual(by_id(results, "op.cloud")[0].status, "fail")
        self.assertTrue(all(r.status == "skipped" for r in results if r.domain == "avd"))

    def test_not_signed_in_skips_azure_checks(self):
        _, results = run(FakeAz({"account show": None}))
        self.assertEqual(by_id(results, "op.signin")[0].status, "fail")
        self.assertEqual(by_id(results, "sub.region")[0].status, "skipped")

    def test_old_terraform_fails(self):
        values = values_from({"user_groups": [USERS]})
        _, results, _ = evaluate(values, az=FakeAz(), which=lambda t: t, python_version=(3, 12),
                                 run_tool=lambda cmd: json.dumps({"terraform_version": "1.9.8"}))
        tf = [r for r in by_id(results, "op.tools") if r.title == "Terraform"][0]
        self.assertEqual(tf.status, "fail")

    def test_a_broken_check_warns_instead_of_passing(self):
        _, results = run(FakeAz({"vm list-skus": [{"name": "Standard_E4as_v5", "capabilities": "not a list"}]}))
        self.assertEqual(by_id(results, "avd.vm_features")[0].status, "warn")

    def test_output_masks_ids_and_account_names(self):
        ctx, results = run()
        doc = report.document(ctx, results, started="2026-10-22T00:00:00Z")
        for fmt in ("console", "md", "json"):
            text = report.mask(report.as_text(doc, results, fmt), ctx.account_terms())
            self.assertNotIn(SUB, text)
            self.assertNotIn("Contoso Sandbox", text)
            self.assertNotIn("admin@contoso.com", text)

    def test_strict_turns_warnings_into_no_go(self):
        _, results = run(FakeAz({"provider list": []}))
        verdict = report.verdict(results)
        self.assertEqual(report.exit_code(verdict, results), 0)
        self.assertEqual(report.exit_code(verdict, results, strict=True), 1)

    def test_providers_come_from_the_platform_root(self):
        self.assertIn("Microsoft.DesktopVirtualization", subscription.platform_providers())

    def test_every_check_is_on_the_kb_page(self):
        from pathlib import Path
        page = (Path(__file__).resolve().parents[2] / "docs" / "knowledge" / "readiness.md").read_text()
        self.assertEqual([c for c in model.REGISTRY if f"| `{c}` |" not in page], [])

    def test_unreadable_service_principal_is_no_access_not_no_go(self):
        _, results = run(FakeAz({"ad sp list": None}))
        self.assertEqual(by_id(results, "id.avd_principal")[0].status, "no-access")
        _, results = run(FakeAz({"ad sp list": []}))
        self.assertEqual(by_id(results, "id.avd_principal")[0].status, "fail")

    def test_unreadable_group_by_id_is_no_access(self):
        _, results = run(FakeAz({"ad group list": None}))
        self.assertEqual(by_id(results, "id.groups")[0].status, "no-access")
        _, results = run(FakeAz({"ad group list": []}))
        self.assertEqual(by_id(results, "id.groups")[0].status, "fail")

    def test_dual_stack_hub_is_checked(self):
        hub = "/subscriptions/x/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
        _, results = run(hub_vnet_id=hub)
        self.assertEqual([r.status for r in by_id(results, "net.hub")], ["pass", "pass"])
        _, results = run(FakeAz({"network vnet show": {"prefixes": ["10.50.0.0/16"]}}), hub_vnet_id=hub)
        self.assertEqual(by_id(results, "net.hub")[0].status, "fail")

    def test_restricted_size_skips_what_depends_on_it(self):
        sku = {**SKU, "restrictions": [{"type": "Location", "reasonCode": "NotAvailableForSubscription"}]}
        _, results = run(FakeAz({"vm list-skus": [sku]}), availability_zones=["1"])
        self.assertEqual(by_id(results, "avd.vm_size")[0].status, "fail")
        for cid in ("avd.vm_features", "avd.zones", "avd.vcpu"):
            self.assertEqual(by_id(results, cid)[0].status, "skipped", cid)

    def test_unknown_vcpu_count_is_a_warning(self):
        sku = {**SKU, "capabilities": [c for c in SKU["capabilities"] if c["name"] != "vCPUs"]}
        _, results = run(FakeAz({"vm list-skus": [sku]}))
        self.assertEqual(by_id(results, "avd.vcpu")[0].status, "warn")

    def test_mask_keeps_links_and_public_ids(self):
        avd_app = "9cdead84-a844-4324-93f2-b2e6bb768d07"
        text = f"see https://learn.microsoft.com/azure/x, az ad sp create --id {avd_app}, sub {SUB}, Azure Network"
        masked = report.mask(text, ["Azure", "Network"])
        self.assertIn("https://learn.microsoft.com/azure/x", masked)
        self.assertIn(avd_app, masked)
        self.assertNotIn(SUB, masked)
        self.assertIn("Azure Network", masked)
        self.assertEqual(report.mask("tenant Contoso Ltd, admin@contoso.com", ["Contoso Ltd", "admin@contoso.com"]),
                         "tenant <account>, <account>")

    def test_unreadable_cloud_is_recorded_as_assumed(self):
        ctx, results = run(FakeAz({"cloud show": None}))
        self.assertEqual(ctx.cloud, "AzureCloud (assumed)")

    def test_unknown_check_id_is_a_usage_error(self):
        with self.assertRaises(runner.UsageError):
            runner.parse_ids("avd.nope")

    def test_az_command_resolves_windows_cmd(self):
        import tempfile
        from pathlib import Path
        from unittest import mock
        from readiness import context
        with tempfile.TemporaryDirectory() as d:
            root = Path(d)
            (root / "bin").mkdir()
            az_cmd = root / "bin" / "az.cmd"
            az_cmd.write_text("@echo off\n")
            py_exe = root / "python.exe"
            py_exe.write_text("")
            with mock.patch("readiness.context.shutil.which", return_value=str(az_cmd)):
                self.assertEqual(context._az_command(), [str(py_exe.resolve()), "-IBm", "azure.cli"])


if __name__ == "__main__":
    unittest.main()
