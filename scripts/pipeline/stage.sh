#!/usr/bin/env bash
# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/pipeline/stage.sh; see CREDITS.md and NOTICE.
# Changes: the AVD stages (platform, and preflight for the readiness check), answers rendered by
# scripts/schema/answers.py, state under avd/<env>/, and no adopted-values or vendor steps.
#
# Plan or apply one kit stage inside the deploy workflow (.github/workflows/deploy.yml).
#
#   scripts/pipeline/stage.sh plan    render tfvars from the answers, plan, save the plan
#                                     and a change summary
#   scripts/pipeline/stage.sh apply   fetch the saved plan, check its hash, apply exactly it
#   STAGE=preflight ... plan          the read-only readiness check instead (scripts/preflight.py)
#
# Every run leaves a result in the plans container, failures included (with the last lines of
# the log, IDs masked), so a later chat can explain what happened without opening the log.
#
# Glue only (docs/guardrails.md): Terraform does the work. Azure sign-in is GitHub OIDC
# (ARM_USE_OIDC), so there's no secret. Logs and the job summary never show tenant,
# subscription or object IDs: every GUID is replaced before it's printed, because a public
# repository's Actions logs are public.
#
# Inputs (set by the workflow from the GitHub environment's secrets):
#   STAGE                    platform | images | preflight
#   AVD_ENV                  sandbox | dev | prod
#   ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID
#   TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT
#   PLAN_BLOB PLAN_SHA256    apply only: from the plan job
set -Eeuo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
action="${1:-}"
case "$action" in plan | apply) ;; *) echo "usage: $0 plan|apply" >&2; exit 64 ;; esac
case "${STAGE:-}" in
  platform) dir_name=01-platform ;;
  images) dir_name=02-images ;;
  preflight) dir_name=01-platform ;; # checks the answers the platform stage would use
  *) echo "STAGE must be platform, images or preflight" >&2; exit 64 ;;
esac
[ "$STAGE" != preflight ] || [ "$action" = plan ] || { echo "preflight only plans" >&2; exit 64; }
[[ "${AVD_ENV:-}" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "AVD_ENV is missing or malformed" >&2; exit 64; }
for v in ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID TFSTATE_RESOURCE_GROUP TFSTATE_STORAGE_ACCOUNT; do
  [ -n "${!v:-}" ] || { echo "$v isn't set: run scripts/pipeline/bootstrap.sh for the $AVD_ENV environment first" >&2; exit 2; }
done

stage_dir="$root/environments/example/$dir_name"
work="${RUNNER_TEMP:-$(mktemp -d)}/avd-$STAGE"
mkdir -p "$work"
run_dir="$AVD_ENV/${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}"
result_blob="$run_dir/$STAGE.json"
[ "$action" = apply ] && result_blob="$run_dir/$STAGE-apply.json"
log="" # the log the last step wrote; a failure reports its tail

for v in ARM_TENANT_ID ARM_SUBSCRIPTION_ID ARM_CLIENT_ID; do
  if [ -n "${!v:-}" ]; then echo "::add-mask::${!v}"; fi
done

# Everything printed goes through this, so no GUID reaches a log or the summary.
redact() { sed -E 's/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/<id>/g'; }
summary() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then redact >> "$GITHUB_STEP_SUMMARY"; else redact; fi; }

blob() { # $1 upload|download, $2 container, $3 blob name, $4 file, then any extra az arguments
  az storage blob "$1" --auth-mode login --only-show-errors --account-name "$TFSTATE_STORAGE_ACCOUNT" \
    --container-name "$2" --name "$3" --file "$4" "${@:5}" >/dev/null
}

fail() {
  trap - ERR
  echo "::error::$*" | redact
  local tail=""
  [ -n "$log" ] && [ -f "$log" ] && tail="$(grep -v '^\s*$' "$log" | tail -n 30 | redact)"
  jq -n --arg stage "$STAGE" --arg action "$action" --arg error "$(echo "$*" | redact)" --arg log "$tail" \
    '{stage: $stage, action: $action, status: "failed", error: $error, log_tail: $log}' > "$work/failed.json"
  blob upload plans "$result_blob" "$work/failed.json" --overwrite 2>/dev/null || true
  exit 1
}

# Any step that fails without saying why still leaves a result.
trap 'fail "Step failed at line $LINENO: $BASH_COMMAND"' ERR

# The stage's backend block is committed empty; the settings come from here.
init_stage() {
  terraform -chdir="$stage_dir" init -input=false -no-color \
    -backend-config="resource_group_name=$TFSTATE_RESOURCE_GROUP" \
    -backend-config="storage_account_name=$TFSTATE_STORAGE_ACCOUNT" \
    -backend-config="container_name=tfstate" \
    -backend-config="key=avd/$AVD_ENV/$STAGE.tfstate" \
    -backend-config="use_azuread_auth=true" 2>&1 | redact | tail -n 3
}

if [ "$action" = plan ]; then
  echo "== Answers to tfvars"
  mkdir -p "$root/.avd"
  # One versioned blob per environment, written by the bootstrap script.
  blob download answers "$AVD_ENV.json" "$root/.avd/answers.json" 2>/dev/null \
    || fail "No answers for $AVD_ENV yet. Run scripts/pipeline/bootstrap.sh --answers-only from Cloud Shell."
  if [ "$STAGE" = preflight ]; then
    echo "== Readiness check (read-only)"
    # Signed in as the plan identity, so the deployer-rights check comes back as "manual": the
    # apply identity holds those roles by design. Everything else is checked for real.
    log="$work/preflight.log"
    code=0
    python3 "$root/scripts/preflight.py" --answers "$root/.avd/answers.json" --environment "$AVD_ENV" --format json \
      > "$work/preflight.json" 2> "$log" || code=$?
    jq -e '.schema == "avd-hcl-readiness/1"' "$work/preflight.json" >/dev/null 2>&1 || fail "The readiness check didn't finish"
    redact < "$work/preflight.json" | jq '{stage: "preflight", status: (.verdict | ascii_downcase | gsub(" "; "-")), verdict, counts, results}' \
      > "$work/result.json"
    blob upload plans "$result_blob" "$work/result.json" --overwrite
    {
      echo "## $AVD_ENV / readiness check: $(jq -r '.verdict' "$work/result.json")"
      echo
      echo "| Result | Check | Detail | Fix |"
      echo "|---|---|---|---|"
      jq -r '.results[] | select(.status != "skipped" and .status != "pass") | "| \(.status) | `\(.id)` \(.title) | \(.detail | gsub("\\|"; "/")) | \(.fix | gsub("\\|"; "/")) |"' "$work/result.json"
    } | summary
    echo "Readiness check: $(jq -r .verdict "$work/result.json")"
    echo "changes=false" >> "${GITHUB_OUTPUT:-/dev/null}"
    # NO-GO (1) and INCOMPLETE (3) turn the job red, so nobody misses them.
    [ "$code" = 0 ] || { trap - ERR; exit "$code"; }
    exit 0
  fi

  # Tenant and subscription come from ARM_*; group names are looked up with the plan identity.
  log="$work/render.log"
  python3 "$root/scripts/schema/answers.py" render --environment "$AVD_ENV" > "$log" 2>&1 || { redact < "$log"; fail "The answers don't pass the schema"; }
  redact < "$log"

  echo "== $dir_name: terraform plan"
  init_stage
  log="$work/plan.log"
  # The plan identity can read state but not write it, so it can't take the state lock. The
  # workflow's concurrency group runs one job per environment, and Terraform refuses to apply a
  # saved plan whose state has moved since. Exit code 2 means changes, so it's caught here.
  code=0
  terraform -chdir="$stage_dir" plan -input=false -no-color -lock=false -detailed-exitcode -out="$work/tfplan" > "$log" 2>&1 || code=$?
  if [ "$code" = 1 ]; then
    grep -v '^\s*$' "$log" | tail -n 40 | redact
    fail "terraform plan failed"
  fi
  grep -E '^(Plan:|No changes)' "$log" | redact || true

  {
    echo "## $AVD_ENV / $dir_name"
    echo
    if [ "$code" = 0 ]; then
      echo "No changes. Nothing to apply."
    else
      echo '```'
      grep -E '^Plan:' "$log" || true
      echo '```'
      echo
      echo "| Action | Resource |"
      echo "|---|---|"
      terraform -chdir="$stage_dir" show -json "$work/tfplan" \
        | jq -r '.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["read"]) | "| \(.change.actions | join(" then ")) | `\(.address)` |"'
    fi
  } | summary

  # The change list, in private storage, so values aren't redacted here.
  if [ "$code" = 2 ]; then
    terraform -chdir="$stage_dir" show -json "$work/tfplan" \
      | jq --arg stage "$STAGE" --arg summary "$(grep -E '^Plan:' "$log" || true)" \
        '{stage: $stage, status: "planned", summary: $summary, changes: [.resource_changes[] | select(.change.actions != ["no-op"] and .change.actions != ["read"]) | {action: (.change.actions | join(" then ")), address}]}' \
      > "$work/summary.json"
  else
    jq -n --arg stage "$STAGE" '{stage: $stage, status: "planned", summary: "No changes.", changes: []}' > "$work/summary.json"
  fi
  blob upload plans "$result_blob" "$work/summary.json" --overwrite

  changes=false
  if [ "$code" = 2 ]; then
    changes=true
    tar -C "$work" -cf "$work/plan.tar" tfplan
    tar -C "$stage_dir" -rf "$work/plan.tar" .terraform.lock.hcl
    PLAN_BLOB="$run_dir/$STAGE.tar"
    blob upload plans "$PLAN_BLOB" "$work/plan.tar" --overwrite
    sha="$(sha256sum "$work/plan.tar" | cut -d' ' -f1)"
    { echo "plan_blob=$PLAN_BLOB"; echo "plan_sha256=$sha"; } >> "${GITHUB_OUTPUT:-/dev/null}"
    echo "Saved plan $sha"
  fi
  echo "changes=$changes" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 0
fi

# apply: exactly the plan the reviewer approved, or nothing.
if [ -z "${PLAN_BLOB:-}" ] || ! [[ "${PLAN_SHA256:-}" =~ ^[0-9a-f]{64}$ ]]; then fail "No saved plan to apply"; fi
[[ "$PLAN_BLOB" == "$AVD_ENV/"*"/$STAGE.tar" ]] || fail "The saved plan isn't from this environment and stage"
echo "== Saved plan"
blob download plans "$PLAN_BLOB" "$work/plan.tar"
echo "$PLAN_SHA256  $work/plan.tar" | sha256sum --check --quiet - || fail "The saved plan changed since it was reviewed; not applying"
tar -C "$work" -xf "$work/plan.tar" tfplan
tar -C "$stage_dir" -xf "$work/plan.tar" .terraform.lock.hcl

echo "== $dir_name: terraform apply"
init_stage
# A plan goes stale if the state moved since it was made; Terraform then refuses to apply it.
log="$work/apply.log"
code=0
terraform -chdir="$stage_dir" apply -input=false -no-color -lock-timeout=5m "$work/tfplan" > "$log" 2>&1 || code=$?
redact < "$log"
[ "$code" = 0 ] || fail "terraform apply failed"
{ echo "## $AVD_ENV / $dir_name"; echo; echo "Applied the reviewed plan."; } | summary

jq -n --arg stage "$STAGE" '{stage: $stage, action: "apply", status: "applied"}' > "$work/applied.json"
blob upload plans "$result_blob" "$work/applied.json" --overwrite
