#!/usr/bin/env bash
# Is the daily drift check set up? Called by .github/workflows/github-drift.yml (job precheck) with
# the repository variables in the environment; tested by test_drift_precheck.py with a fake gh.
# Writes state=ready|unset|partial and missing=<names> to $GITHUB_OUTPUT. When nothing is set, it
# writes the setup steps to $GITHUB_STEP_SUMMARY and closes an open "check failed" issue.
# Keep NAMES equal to the vars.* the plan job reads.
set -euo pipefail

NAMES="DRIFT_KEY_URL DRIFT_CLIENT_ID AZURE_TENANT_ID AZURE_SUBSCRIPTION_ID TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT"
FAILED_TITLE="GitHub settings drift check failed"
DRIFT_TITLE="GitHub settings drift"

missing=""
total=0
gone=0
for name in $NAMES; do
  total=$((total + 1))
  if [ -z "${!name:-}" ]; then
    missing="${missing:+$missing }$name"
    gone=$((gone + 1))
  fi
done
if [ "$gone" -eq 0 ]; then state="ready"
elif [ "$gone" -eq "$total" ]; then state="unset"
else state="partial"; fi
echo "state=$state" >> "$GITHUB_OUTPUT"
echo "missing=$missing" >> "$GITHUB_OUTPUT"
echo "Drift check: $state${missing:+ (missing: $missing)}"
[ "$state" = unset ] || exit 0

{
  echo "## GitHub drift check: not set up, skipped"
  echo
  echo "None of the repository variables the check needs is set, so nothing ran. To set it up"
  echo "(docs/knowledge/github-settings-spec.md, sections 8 and 11, step 5, after a written"
  echo "estimate and the owner's go): run the bootstrap, create and install the settings reader"
  echo "App, import its key into Key Vault, then set these repository variables (not secrets):"
  echo
  for name in $NAMES; do echo "- \`$name\`"; done
  echo
  echo "Then start this workflow by hand from main; the first run must be clean."
} >> "$GITHUB_STEP_SUMMARY"

# Assigned first, so a failing gh call stops the step instead of looping over nothing.
open=$(gh issue list --label drift --state open --json number,title --jq '.[] | "\(.number)\t\(.title)"')
while IFS=$'\t' read -r number title; do
  [ -n "$number" ] || continue
  if [ "$title" = "$FAILED_TITLE" ]; then
    # Can't be confirmed or cleared while the check isn't set up; don't leave it open forever.
    gh issue comment "$number" --body "The drift check isn't set up (no repository variables), so it was skipped and can't confirm this failure. Closing; the next failing run after setup opens a new issue."
    gh issue close "$number" --reason "not planned"
  elif [ "$title" = "$DRIFT_TITLE" ]; then
    # Real drift stays open, but say loudly that nothing checks it any more.
    echo "::warning::Drift issue #$number is open, but the drift check isn't set up, so nothing confirms or clears it."
  fi
done <<< "$open"
