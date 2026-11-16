import json
import unittest

from verify import check


def fake_runner(responses: dict[tuple[str, ...], tuple[int, object, str]]):
    def run(cmd: list[str]) -> tuple[int, str, str]:
        for key, (rc, payload, err) in responses.items():
            if all(part in cmd for part in key):
                out = json.dumps(payload) if payload is not None else ""
                return rc, out, err
        return 1, "", f"unexpected command: {cmd}"

    return run


class VerifyTests(unittest.TestCase):
    def test_all_checks_pass(self):
        runner = fake_runner(
            {
                ("hostpool", "show"): (0, {"name": "vdpool-avd", "hostPoolType": "Pooled"}, ""),
                ("sessionhost", "list"): (
                    0,
                    [{"name": "avdsh-001", "status": "Available"}, {"name": "avdsh-002", "status": "Available"}],
                    "",
                ),
                ("scaling-plan", "show"): (0, {"name": "vdscaling-avd"}, ""),
                ("share-rm", "show"): (0, {"name": "profiles"}, ""),
            }
        )
        results = check.verify_deployment(
            resource_group="rg-avd",
            host_pool_name="vdpool-avd",
            expected_host_count=2,
            scaling_plan_name="vdscaling-avd",
            storage_rg="rg-storage",
            storage_account_name="stavd01",
            runner=runner,
        )
        self.assertEqual([r.status for r in results], ["pass", "pass", "pass", "pass"])

    def test_unavailable_hosts_fail(self):
        runner = fake_runner(
            {
                ("hostpool", "show"): (0, {"name": "vdpool-avd", "hostPoolType": "Pooled"}, ""),
                ("sessionhost", "list"): (0, [{"name": "avdsh-001", "status": "Unavailable"}], ""),
                ("scaling-plan", "show"): (0, {"name": "vdscaling-avd"}, ""),
            }
        )
        results = check.verify_deployment(
            resource_group="rg-avd",
            host_pool_name="vdpool-avd",
            expected_host_count=1,
            scaling_plan_name="vdscaling-avd",
            runner=runner,
        )
        statuses = {r.id: r.status for r in results}
        self.assertEqual(statuses["avd.session_hosts"], "fail")
        self.assertEqual(statuses["fslogix.share"], "skip")

    def test_personal_pool_skips_scaling_plan(self):
        runner = fake_runner(
            {
                ("hostpool", "show"): (0, {"name": "vdpool-pers", "hostPoolType": "Personal"}, ""),
                ("sessionhost", "list"): (0, [], ""),
            }
        )
        results = check.verify_deployment(
            resource_group="rg-avd",
            host_pool_name="vdpool-pers",
            expected_host_count=0,
            scaling_plan_name="vdscaling-pers",
            runner=runner,
        )
        statuses = {r.id: r.status for r in results}
        self.assertEqual(statuses["avd.session_hosts"], "skip")
        self.assertEqual(statuses["avd.scaling_plan"], "skip")


if __name__ == "__main__":
    unittest.main()
