import json
import tempfile
import unittest
from pathlib import Path

import answers

TENANT = "00000000-0000-0000-0000-000000000001"
SUB = "00000000-0000-0000-0000-000000000002"
USERS = "00000000-0000-0000-0000-000000000003"


def source(kind):
    return {"tenant": TENANT, "subscription": SUB}[kind]


def group(name):
    if name == "AVD Users":
        return USERS
    raise answers.AnswerError(f"group '{name}': expected one Entra group with that name, found 0")


class AnswersTest(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads(answers.SCHEMA.read_text())

    def resolve(self, given):
        return answers.resolve(self.schema, given, source=source, group=group)

    def test_minimal_answers_render_the_platform_stage(self):
        out = answers.tfvars(self.schema, self.resolve({"user_groups": [USERS]}))["platform"]
        self.assertEqual(out["tenant_id"], TENANT)
        self.assertEqual(out["prefix"], "avd-sandbox")
        self.assertEqual(out["address_space"], ["10.50.0.0/20"])
        self.assertEqual(out["subnets"], {"session_hosts": "10.50.0.0/22", "private_endpoints": "10.50.4.0/27"})
        self.assertNotIn("hub_vnet_id", out)
        self.assertNotIn("egress_firewall_ip", out)

    def test_rendered_variables_exist_in_the_root(self):
        import check
        declared = check.root_variables(answers.ROOT / "environments" / "example" / "01-platform")
        out = answers.tfvars(self.schema, self.resolve({"user_groups": [USERS]}))["platform"]
        self.assertEqual(sorted(set(out) - set(declared)), [])

    def test_group_names_are_looked_up(self):
        values = self.resolve({"user_groups": "AVD Users"})
        self.assertEqual(values["user_groups"], [USERS])

    def test_unknown_group_name_is_an_error(self):
        with self.assertRaisesRegex(answers.AnswerError, "found 0"):
            self.resolve({"user_groups": ["Nobody"]})

    def test_user_groups_are_required(self):
        with self.assertRaisesRegex(answers.AnswerError, "user_groups: needs an answer"):
            self.resolve({})

    def test_tenant_is_never_saved(self):
        with self.assertRaisesRegex(answers.AnswerError, "never saved"):
            self.resolve({"user_groups": [USERS], "tenant_id": TENANT})

    def test_unknown_answer_is_an_error(self):
        with self.assertRaisesRegex(answers.AnswerError, "not a parameter"):
            self.resolve({"user_groups": [USERS], "vm_szie": "Standard_D2s_v5"})

    def test_unsupported_choice_says_why(self):
        with self.assertRaisesRegex(answers.AnswerError, "isn't built yet"):
            self.resolve({"user_groups": [USERS], "identity_model": "ad_ds"})

    def test_prefix_rules_match_terraform(self):
        with self.assertRaisesRegex(answers.AnswerError, "prefix"):
            self.resolve({"user_groups": [USERS], "prefix": "avd--dev"})
        with self.assertRaisesRegex(answers.AnswerError, "prefix"):
            self.resolve({"user_groups": [USERS], "prefix": "a-very-long-prefix"})

    def test_subnet_outside_address_space(self):
        with self.assertRaisesRegex(answers.AnswerError, "outside address_space"):
            self.resolve({"user_groups": [USERS], "session_hosts_subnet": "10.60.0.0/22"})

    def test_overlapping_subnets(self):
        with self.assertRaisesRegex(answers.AnswerError, "overlap"):
            self.resolve({"user_groups": [USERS], "private_endpoints_subnet": "10.50.0.0/27"})

    def test_firewall_only_when_no_nat(self):
        out = answers.tfvars(self.schema, self.resolve({
            "user_groups": [USERS], "create_nat_gateway": False, "egress_firewall_ip": "10.0.0.4"}))["platform"]
        self.assertEqual(out["egress_firewall_ip"], "10.0.0.4")
        skipped = self.resolve({"user_groups": [USERS], "egress_firewall_ip": "10.0.0.4"})
        self.assertNotIn("egress_firewall_ip", skipped)

    def test_typed_text_is_coerced(self):
        values = self.resolve({"user_groups": USERS, "host_count": "2", "encryption_at_host": "no"})
        self.assertEqual((values["host_count"], values["encryption_at_host"]), (2, False))

    def test_render_writes_the_output_file(self):
        with tempfile.TemporaryDirectory() as d:
            written = answers.render(self.schema, {"user_groups": [USERS]}, Path(d), source=source, group=group)
            self.assertEqual([p.name for p in written], ["setup.auto.tfvars.json"])
            self.assertEqual(json.loads(written[0].read_text())["host_count"], 1)

    def test_render_pins_the_environment(self):
        with tempfile.TemporaryDirectory() as d:
            written = answers.render(self.schema, {"user_groups": [USERS]}, Path(d), "dev", source=source, group=group)
            out = json.loads(written[0].read_text())
            self.assertEqual((out["environment"], out["prefix"]), ("dev", "avd-dev"))
            with self.assertRaisesRegex(answers.AnswerError, "this run deploys dev"):
                answers.render(self.schema, {"user_groups": [USERS], "environment": "sandbox"}, Path(d), "dev", source=source, group=group)

    def test_min_length_alone_is_a_message_not_a_crash(self):
        p = {"id": "x", "type": "string", "min_length": 3}
        self.assertEqual(answers.validate(p, "ab"), ["x: must be 3 to any number of characters"])

    def test_init_saves_only_what_was_typed(self):
        replies = iter(["", "1", "", "", "", "AVD Users", "", "3", "", "", ""])
        saved = answers.init(self.schema, prompt=lambda _: next(replies, ""), say=lambda *_: None)
        self.assertEqual(saved, {"identity_model": "entra_joined", "user_groups": ["AVD Users"], "host_count": 3})

    def test_init_asks_again_after_a_bad_answer(self):
        replies = iter(["prod", "", "", "", "", "", "AVD Users", "", "x", "2"])
        said = []
        saved = answers.init(self.schema, prompt=lambda _: next(replies, ""), say=said.append)
        self.assertEqual(saved["host_count"], 2)
        self.assertTrue(any("not a whole number" in s for s in said))


if __name__ == "__main__":
    unittest.main()
