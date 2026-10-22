#!/usr/bin/env bash
# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/pipeline/bootstrap.sh; see CREDITS.md and NOTICE.
# Changes: no repository-settings module, answers from scripts/schema/answers.py, a stop before a
# private repository where GitHub wouldn't enforce the reviewer, and a simpler --adopt.
#
# One-time setup for the deploy pipeline, from Azure Cloud Shell (Bash).
#
#   ./scripts/pipeline/bootstrap.sh                 plan, then apply after you type yes
#   ./scripts/pipeline/bootstrap.sh --plan          plan only
#   ./scripts/pipeline/bootstrap.sh --answers-only  publish your .avd/answers.json again after a change
#   ./scripts/pipeline/bootstrap.sh --adopt         move 01-platform state you applied from Cloud
#                                                   Shell into the pipeline's storage
#
# Terraform (environments/example/00-pipeline) creates the state storage, the plan and apply
# identities with GitHub OIDC trust, and the GitHub environments <env>-plan and <env>-apply (which
# needs a reviewer's approval). This script is glue only: it reads IDs from `az account show`, the
# repository from git, and a GitHub token from `gh auth token`, which it hands to that one
# terraform process and never writes down.
#
#   AVD_ENV        kit environment (default sandbox). The first run saves this tenant and
#                  subscription for it; later runs stop if you're signed in somewhere else.
#   AVD_LOCATION   region for the state storage (default eastus2)
#   AVD_NAME       short name for the pipeline's resources (default avd-<first 3 of env>)
#   AVD_REVIEWERS  comma-separated GitHub logins who may approve applies (default: you)
#   AVD_GITHUB_ENTERPRISE=1  only on GitHub Enterprise, where a private repository's
#                  environments enforce reviewers
#
# You need: Owner (or Contributor + Role Based Access Control Administrator) on the
# subscription, Privileged Role Administrator to grant the identities their read-only Microsoft
# Graph roles (activate it with PIM first), and admin rights on the GitHub repository.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
env_dir="$root/environments/example"
stage="$env_dir/00-pipeline"
mode="${1:-apply}"
case "$mode" in apply | --plan | --answers-only | --adopt) ;; *) echo "usage: $0 [--plan|--answers-only|--adopt]" >&2; exit 64 ;; esac

env_name="${AVD_ENV:-sandbox}"
[[ "$env_name" =~ ^[a-z][a-z0-9-]{1,20}$ ]] || { echo "AVD_ENV must be lowercase letters, digits or hyphens" >&2; exit 64; }
location="${AVD_LOCATION:-eastus2}"
name="${AVD_NAME:-avd-${env_name:0:3}}"
config="${XDG_CONFIG_HOME:-$HOME/.config}/avd-hcl/$env_name.json"

say() { printf '\n== %s\n' "$*"; }

# The environment remembers its tenant and subscription, so a later run can't land in the wrong one.
check_account() {
  local tenant sub
  tenant="$(az account show --query tenantId -o tsv)"
  sub="$(az account show --query id -o tsv)"
  if [ -f "$config" ]; then
    if [ "$(jq -r .tenant "$config")" != "$tenant" ] || [ "$(jq -r .subscription "$config")" != "$sub" ]; then
      echo "You're signed in to a different tenant or subscription than $env_name used before." >&2
      echo "Switch with az account set, or remove $config if you mean to move $env_name." >&2
      exit 2
    fi
    return
  fi
  az account show --query '{subscription:name, signedInAs:user.name}' -o table
  read -r -p "Use this subscription for $env_name from now on? Type yes: " answer
  [ "$answer" = yes ] || { echo "Stopped; nothing changed."; exit 1; }
  mkdir -p "$(dirname "$config")"
  umask 077
  jq -n --arg t "$tenant" --arg s "$sub" '{tenant: $t, subscription: $s}' > "$config"
}

ensure_terraform() {
  local have=""
  command -v terraform >/dev/null 2>&1 && have="$(terraform version -json | jq -r .terraform_version)"
  if [ -n "$have" ] && [ "$(printf '%s\n' 1.11.0 "$have" | sort -V | head -n1)" = 1.11.0 ]; then
    return
  fi
  local want="${AVD_TF_VERSION:-1.16.6}" tmp
  echo "Terraform ${have:-not found}; installing $want to ~/bin"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/tf.zip" "https://releases.hashicorp.com/terraform/$want/terraform_${want}_linux_amd64.zip"
  curl -fsSL -o "$tmp/sums" "https://releases.hashicorp.com/terraform/$want/terraform_${want}_SHA256SUMS"
  (cd "$tmp" && grep "linux_amd64.zip" sums | sed "s/terraform_${want}_linux_amd64.zip/tf.zip/" | sha256sum --check -)
  mkdir -p "$HOME/bin"
  unzip -o -q "$tmp/tf.zip" -d "$HOME/bin"
  rm -rf "$tmp"
  export PATH="$HOME/bin:$PATH"
}

pipeline_output() { terraform -chdir="$stage" output -raw "$1"; }

# Role assignments take a minute or two to reach the data plane, so storage steps retry.
retry() { # $1 what, then the command
  local what="$1" i
  shift
  for i in 1 2 3 4 5 6 7 8; do
    if "$@"; then return 0; fi
    echo "Storage access isn't active yet ($what); retrying in 30s ($i/8)"
    sleep 30
  done
  return 1
}

# Moves this stage's local state into the storage account it just created. backend.tf is
# git-ignored and holds names only.
migrate_pipeline_state() {
  local rg sa
  rg="$(pipeline_output resource_group_name)"
  sa="$(pipeline_output storage_account_name)"
  cat > "$stage/backend.tf" <<TF
# Written by scripts/pipeline/bootstrap.sh. Git-ignored.
terraform {
  backend "azurerm" {
    resource_group_name  = "$rg"
    storage_account_name = "$sa"
    container_name       = "tfstate"
    key                  = "avd/$env_name/pipeline.tfstate"
    use_azuread_auth     = true
  }
}
TF
  if retry "state" terraform -chdir="$stage" init -input=false -migrate-state -force-copy >/dev/null; then
    echo "00-pipeline: state is now in the pipeline's storage (avd/$env_name/pipeline.tfstate)"
  else
    rm -f "$stage/backend.tf"
    echo "Couldn't move the state; it's still local and unchanged. Run $0 again in a few minutes." >&2
    exit 1
  fi
}

publish_answers() {
  local sa file="$root/.avd/answers.json"
  if [ ! -f "$file" ]; then
    echo "No answers yet. Run python3 scripts/schema/answers.py init, then $0 --answers-only."
    return
  fi
  # Check them here, so a mistake shows now instead of in the first plan.
  local check
  check="$(mktemp -d)"
  mkdir -p "$check/01-platform"
  python3 "$root/scripts/schema/answers.py" render --file "$file" --env-dir "$check" >/dev/null \
    || { rm -rf "$check"; echo "Fix the answers above, then run $0 --answers-only." >&2; exit 1; }
  rm -rf "$check"
  sa="$(pipeline_output storage_account_name)"
  if retry "answers" az storage blob upload --auth-mode login --only-show-errors --account-name "$sa" \
    --container-name answers --name "$env_name.json" --file "$file" --overwrite >/dev/null 2>&1; then
    echo "Published your answers for $env_name"
  else
    echo "Couldn't publish the answers. Run $0 --answers-only in a few minutes." >&2
    exit 1
  fi
}

say "Environment $env_name"
check_account
ensure_terraform

if [ "$mode" = --answers-only ] || [ "$mode" = --adopt ]; then
  pipeline_output storage_account_name >/dev/null 2>&1 \
    || { echo "Run $0 first; the pipeline's storage doesn't exist yet." >&2; exit 2; }
fi

if [ "$mode" = --answers-only ]; then
  publish_answers
  exit 0
fi

if [ "$mode" = --adopt ]; then
  platform="$env_dir/01-platform"
  say "Moving 01-platform state into the pipeline's storage"
  echo "Don't run this while a plan or apply is running for $env_name."
  umask 077
  printf 'resource_group_name  = "%s"\nstorage_account_name = "%s"\ncontainer_name       = "tfstate"\nkey                  = "avd/%s/platform.tfstate"\nuse_azuread_auth     = true\n' \
    "$(pipeline_output resource_group_name)" "$(pipeline_output storage_account_name)" "$env_name" > "$platform/pipeline.backend.hcl"
  retry "state" terraform -chdir="$platform" init -input=false -migrate-state -force-copy -backend-config=pipeline.backend.hcl >/dev/null \
    || { echo "Couldn't move the state; it's unchanged. Run $0 --adopt again in a few minutes." >&2; exit 1; }
  echo "01-platform: state is now in avd/$env_name/platform.tfstate"
  cat <<MSG

Before the pipeline takes over, make your answers describe what you deployed:
  python3 scripts/schema/answers.py render
  terraform -chdir=environments/example/01-platform plan
The plan must show no replacements. Then publish the answers with $0 --answers-only.
MSG
  exit 0
fi

say "GitHub"
command -v gh >/dev/null 2>&1 || { echo "The GitHub CLI (gh) isn't installed; Cloud Shell has it by default." >&2; exit 2; }
gh auth status >/dev/null 2>&1 || { echo "Sign in to GitHub first: gh auth login (choose the browser code option), then run this again." >&2; exit 2; }
remote="$(git -C "$root" remote get-url origin)"
slug="$(sed -E 's#(\.git)?$##; s#^.*github\.com[:/]##' <<<"$remote")"
owner="${slug%%/*}"
repo="${slug#*/}"
visibility="$(gh api "repos/$slug" --jq .visibility)"
enterprise=false
[ "${AVD_GITHUB_ENTERPRISE:-}" = 1 ] && enterprise=true
if [ "$visibility" != public ] && [ "$enterprise" != true ]; then
  echo "$slug is $visibility. GitHub enforces an apply reviewer only in a public repository (or on" >&2
  echo "GitHub Enterprise), so the pipeline would have no gate. Apply from Cloud Shell until it's public." >&2
  exit 2
fi
reviewers="${AVD_REVIEWERS:-$(gh api user --jq .login)}"
echo "Repository $slug; applies need approval from: $reviewers"

say "Variables"
umask 077
jq -n \
  --arg tenant "$(az account show --query tenantId -o tsv)" \
  --arg sub "$(az account show --query id -o tsv)" \
  --arg name "$name" --arg location "$location" --arg env "$env_name" \
  --arg owner "$owner" --arg repo "$repo" --arg reviewers "$reviewers" --argjson enterprise "$enterprise" \
  '{tenant_id: $tenant, subscription_id: $sub, name: $name, location: $location, environment: $env,
    github: {owner: $owner, repository: $repo, enterprise: $enterprise,
             reviewers: ($reviewers | split(",") | map(gsub("^\\s+|\\s+$"; "")))}}' > "$stage/pipeline.auto.tfvars.json"
echo "Wrote 00-pipeline/pipeline.auto.tfvars.json (git-ignored)"

say "00-pipeline: terraform"
GITHUB_TOKEN="$(gh auth token)"
export GITHUB_TOKEN
terraform -chdir="$stage" init -input=false >/dev/null
case "$mode" in
  --plan) terraform -chdir="$stage" plan -input=false; exit 0 ;;
  *) terraform -chdir="$stage" apply -input=false ;;
esac
unset GITHUB_TOKEN

[ -f "$stage/backend.tf" ] || { say "Moving this stage's state into the new storage"; migrate_pipeline_state; }

say "Answers"
publish_answers

cat <<MSG

Done. Next:
  - If you applied 01-platform from Cloud Shell already: $0 --adopt
  - Then in GitHub: Actions > Deploy > Run workflow. Pick $env_name; tick "apply" to apply
    after the plan. The apply waits for an approver's OK in the $env_name-apply environment.
MSG
