"""Offline tests for drift_precheck.sh: a fake gh on PATH, no network, no GitHub."""

import os
import subprocess
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, "drift_precheck.sh")
NAMES = [
    "DRIFT_KEY_URL",
    "DRIFT_CLIENT_ID",
    "AZURE_TENANT_ID",
    "AZURE_SUBSCRIPTION_ID",
    "TFSTATE_RESOURCE_GROUP",
    "TFSTATE_STORAGE_ACCOUNT",
]

# Records every call; "issue list" prints $GH_ISSUES (number<TAB>title lines) or fails on demand.
FAKE_GH = """#!/bin/sh
echo "$*" >> "$GH_LOG"
case "$1 $2" in
  "issue list") [ -n "$GH_FAIL" ] && exit 1; printf '%b' "$GH_ISSUES" ;;
esac
"""


class Precheck(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.TemporaryDirectory()
        d = self.dir.name
        gh = os.path.join(d, "gh")
        with open(gh, "w") as f:
            f.write(FAKE_GH)
        os.chmod(gh, 0o755)
        self.files = {k: os.path.join(d, k) for k in ("output", "summary", "log")}
        for path in self.files.values():
            open(path, "w").close()

    def tearDown(self):
        self.dir.cleanup()

    def run_script(self, values, issues="", fail=False):
        env = {
            "PATH": self.dir.name + os.pathsep + os.environ["PATH"],
            "GITHUB_OUTPUT": self.files["output"],
            "GITHUB_STEP_SUMMARY": self.files["summary"],
            "GH_LOG": self.files["log"],
            "GH_ISSUES": issues,
            "GH_FAIL": "1" if fail else "",
        }
        env.update(values)
        result = subprocess.run(["bash", SCRIPT], env=env, capture_output=True, text=True)
        read = {}
        for key, path in self.files.items():
            with open(path) as f:
                read[key] = f.read()
        outputs = dict(line.split("=", 1) for line in read["output"].splitlines())
        return result, outputs, read

    def test_ready_when_every_variable_is_set(self):
        result, out, read = self.run_script({n: "x" for n in NAMES})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(out, {"state": "ready", "missing": ""})
        self.assertEqual(read["summary"], "")
        self.assertEqual(read["log"], "")

    def test_partial_names_the_missing_and_touches_no_issue(self):
        result, out, read = self.run_script({"DRIFT_KEY_URL": "x", "AZURE_TENANT_ID": "x"})
        self.assertEqual(result.returncode, 0)
        self.assertEqual(out["state"], "partial")
        self.assertEqual(
            out["missing"],
            "DRIFT_CLIENT_ID AZURE_SUBSCRIPTION_ID TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT",
        )
        self.assertEqual(read["log"], "")

    def test_empty_string_counts_as_unset(self):
        _, out, _ = self.run_script({n: "" for n in NAMES})
        self.assertEqual(out["state"], "unset")

    def test_unset_writes_setup_steps_and_closes_only_the_failure_issue(self):
        issues = "7\\tGitHub settings drift check failed\\n9\\tGitHub settings drift\\n"
        result, out, read = self.run_script({}, issues=issues)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(out["state"], "unset")
        for name in NAMES:
            self.assertIn(f"`{name}`", read["summary"])
        self.assertIn("issue close 7 --reason not planned", read["log"])
        self.assertNotIn(" 9 ", read["log"].replace("\n", " "))
        self.assertIn("Drift issue #9 is open", result.stdout)

    def test_unset_with_no_open_issue_closes_nothing(self):
        result, _, read = self.run_script({})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("close", read["log"])

    def test_a_failing_gh_fails_the_step(self):
        result, _, _ = self.run_script({}, fail=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
