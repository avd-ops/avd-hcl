# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/checks/subscription.py; see CREDITS.md and NOTICE.
"""sub.*: the subscription: providers, region, encryption at host, policy and licenses.

Changes: the providers come from the platform root itself, so the two lists can't drift; the
App Service and SQL checks are gone; encryption at host and the license reminder are new.
"""

from __future__ import annotations

import re
from pathlib import Path

from ..model import check

KB = "docs/knowledge/readiness.md#checks"
UUID_IN_TEXT = re.compile(r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}", re.I)
PLATFORM_VERSIONS = Path(__file__).resolve().parents[3] / "environments" / "example" / "01-platform" / "versions.tf"


def platform_providers(path: Path = PLATFORM_VERSIONS) -> list:
    """The resource_providers_to_register list from the platform root's provider block."""
    m = re.search(r"resource_providers_to_register\s*=\s*\[(.*?)\]", path.read_text(), re.S)
    return re.findall(r'"([^"]+)"', m.group(1)) if m else []


@check("sub.providers", "Resource providers", needs="Reader on the subscription", kb=KB,
       source="https://learn.microsoft.com/azure/azure-resource-manager/management/resource-providers-and-types",
       reads=["az provider list"])
def providers(ctx, c):
    wanted = platform_providers()
    rows = ctx.az(["provider", "list", "--query", "[].{ns:namespace, state:registrationState}"])
    if rows is None:
        return c.warn("couldn't list resource providers", "az provider list -o table")
    state = {r["ns"].lower(): r.get("state") for r in rows}
    missing = [ns for ns in wanted if state.get(ns.lower()) != "Registered"]
    if not missing:
        return c.ok(f"all {len(wanted)} registered")
    # Terraform registers them when it starts, but only with rights to; the pipeline's read-only
    # plan identity can't, so its first plan fails until they're registered.
    return c.warn("not registered yet: " + ", ".join(missing) + ". A Cloud Shell run as Owner registers them; "
                  "a pipeline plan can't", " && ".join(f"az provider register -n {ns}" for ns in missing))


@check("sub.region", "Region", needs="Reader on the subscription", kb=KB, inputs=["location"],
       source="https://learn.microsoft.com/cli/azure/account#az-account-list-locations", reads=["az account list-locations"])
def region(ctx, c):
    location = ctx.values["location"]
    names = ctx.az(["account", "list-locations", "--query", "[].name"])
    if names is None:
        return c.warn(f"couldn't list regions to check {location}")
    if location in names:
        return c.ok(f"{location} is available to this subscription")
    return c.fail(f"{location} isn't a region this subscription can use", "az account list-locations -o table")


@check("sub.encryption_at_host", "Encryption at host", needs="Reader on the subscription", kb=KB,
       source="https://learn.microsoft.com/azure/virtual-machines/disks-enable-host-based-encryption-portal",
       reads=["az feature show"])
def encryption_at_host(ctx, c):
    """The platform stage stops at plan without it (its own precondition); this says so sooner."""
    if ctx.values.get("encryption_at_host") is False:
        return c.ok("not needed (encryption_at_host is off)")
    state = ctx.az(["feature", "show", "--namespace", "Microsoft.Compute", "--name", "EncryptionAtHost",
                    "--query", "properties.state"])
    if state is None:
        return c.warn("couldn't read the EncryptionAtHost feature")
    if state == "Registered":
        return c.ok("the EncryptionAtHost feature is registered")
    return c.fail(f"the EncryptionAtHost feature is {state}",
                  "az feature register --namespace Microsoft.Compute --name EncryptionAtHost, wait for Registered, "
                  "then az provider register -n Microsoft.Compute")


@check("sub.policy_list", "Azure Policy", needs="Reader on the subscription", kb=KB,
       source="https://learn.microsoft.com/azure/governance/policy/overview", reads=["az policy assignment list"])
def policy_list(ctx, c):
    """Deny policies (allowed locations, allowed SKUs, no public access, required tags) fail an apply late."""
    rows = ctx.az(["policy", "assignment", "list", "--scope", f"/subscriptions/{ctx.subscription_id}",
                   "--disable-scope-strict-match", "--query", "[?enforcementMode=='Default'].displayName"])
    if rows is None:
        return c.warn("couldn't list the policy assignments that apply to this subscription")
    # Some built-in assignment names carry the subscription ID; keep it out of output people paste.
    rows = sorted({UUID_IN_TEXT.sub("<id>", r) for r in rows if r})
    if not rows:
        return c.ok("no enforced policy assignments on this subscription")
    shown = ", ".join(rows[:8]) + (f" and {len(rows) - 8} more" if len(rows) > 8 else "")
    return c.manual(f"{len(rows)} enforced assignments apply: {shown}",
                    "Check none of them deny the kit's region, VM size, public endpoints or missing tags; a deny "
                    "otherwise shows up only at apply time")


@check("sub.licenses", "AVD user licenses", needs="none", kb=KB, account=False,
       source="https://learn.microsoft.com/azure/virtual-desktop/prerequisites")
def licenses(ctx, c):
    return c.manual("Users need an eligible license (Microsoft 365 E3/E5, Business Premium and others; check the "
                    "current list)", "https://learn.microsoft.com/azure/virtual-desktop/prerequisites")
