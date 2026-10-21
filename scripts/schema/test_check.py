import copy
import json
import unittest

import check


class SchemaTest(unittest.TestCase):
    def setUp(self):
        self.schema = json.loads((check.ROOT / "schema" / "parameters.json").read_text())

    def param(self, pid):
        return next(p for p in self.schema["parameters"] if p["id"] == pid)

    def test_repo_schema_passes(self):
        self.assertEqual(check.check(self.schema), [])

    def test_unknown_variable_is_caught(self):
        self.param("vm_size")["tfvars"][0]["path"] = "no_such_variable"
        self.assertTrue(any("no_such_variable is not a variable" in e for e in check.check(self.schema)))

    def test_unanswered_required_variable_is_caught(self):
        self.schema["parameters"] = [p for p in self.schema["parameters"] if p["id"] != "user_groups"]
        self.assertTrue(any("user_group_object_ids is not answered" in e for e in check.check(self.schema)))

    def test_default_outside_range_is_caught(self):
        self.param("host_count")["default"] = 5000
        self.assertTrue(any("outside min/max" in e for e in check.check(self.schema)))

    def test_default_not_matching_pattern_is_caught(self):
        self.param("prefix")["default"] = "Not_Valid"
        self.assertTrue(any("does not match pattern" in e for e in check.check(self.schema)))

    def test_template_default_is_not_checked(self):
        self.assertEqual(check.check_default({"type": "string", "pattern": "^[a-z]+$", "default": "avd-{environment}"}), [])

    def test_unsupported_choice_needs_reason(self):
        choice = self.param("identity_model")["choices"][1]
        del choice["reason"]
        self.assertTrue(any("needs a reason" in e for e in check.check(self.schema)))

    def test_form_limit(self):
        for p in self.schema["parameters"]:
            p["form"] = True
        self.assertTrue(any("Actions form" in e for e in check.check(self.schema)))

    def test_root_variables_reads_defaults(self):
        variables = check.root_variables(check.ROOT / "environments" / "example" / "01-platform")
        self.assertFalse(variables["location"])
        self.assertTrue(variables["host_count"])


if __name__ == "__main__":
    unittest.main()
