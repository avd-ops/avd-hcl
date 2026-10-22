# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/checks/op.py; see CREDITS.md and NOTICE.
"""op.*: the operator's tools, cloud and sign-in.

Changes: Terraform 1.11 because the kit's roots use ephemeral resources and write-only
attributes, python3 for the schema tools, and no Cloud Shell storage check: state lives in a
storage account from the first run, never on the clouddrive.
"""

from __future__ import annotations

import json
import sys

from ..model import check

KB = "docs/knowledge/readiness.md#checks"
CLOUD_SHELL_TOOLS = "https://learn.microsoft.com/azure/cloud-shell/features"


def version_at_least(have: str, want: str) -> bool:
    def parts(v: str):
        return [int(x) for x in v.split("-")[0].split(".")[:3]]
    try:
        return parts(have) >= parts(want)
    except ValueError:
        return False


@check("op.cloud", "Azure cloud", needs="none", kb=KB, account=False, reads=["az cloud show"],
       source="https://learn.microsoft.com/cli/azure/manage-clouds-azure-cli")
def azure_cloud(ctx, c):
    data = ctx.az(["cloud", "show", "--query", "name"])
    if not data:
        ctx.cloud = "AzureCloud (assumed)"
        return c.warn("couldn't read the active cloud from az; assuming AzureCloud", "az cloud show")
    ctx.cloud = data
    if data == "AzureCloud":
        return c.ok("AzureCloud (commercial)")
    ctx.stopped = f"{data} isn't a cloud this kit supports yet"
    return c.fail(f"{data} isn't a cloud this kit supports yet", "az cloud set --name AzureCloud")


@check("op.tools", "Tools", needs="none", kb=KB, account=False, reads=["PATH"], source=CLOUD_SHELL_TOOLS)
def tools(ctx, c):
    out = []
    if not ctx.which("terraform"):
        out.append(c.fail("terraform isn't on PATH",
                          "Cloud Shell includes it; elsewhere see https://developer.hashicorp.com/terraform/install",
                          title="Terraform"))
    else:
        try:
            ver = json.loads(ctx.run_tool(["terraform", "version", "-json"]))["terraform_version"]
        except (ValueError, KeyError, TypeError):
            ver = "unknown"
        if version_at_least(ver, "1.11.0"):
            out.append(c.ok(f"{ver} (the kit needs 1.11 or later)", title="Terraform"))
        else:
            out.append(c.fail(f"{ver} is older than 1.11, which the kit's ephemeral values need",
                              "AVD_TF_VERSION=1.16.6 ./scripts/pipeline/bootstrap.sh --plan installs one to ~/bin",
                              title="Terraform"))
    have = ctx.python_version or sys.version_info[:2]
    out.append(c.ok(f"{have[0]}.{have[1]}", title="python3") if tuple(have) >= (3, 9)
               else c.fail(f"{have[0]}.{have[1]} is older than 3.9", "Use Azure Cloud Shell, which has 3.9 or later",
                           title="python3"))
    for tool in ("az", "jq", "git"):
        out.append(c.ok("found", title=tool) if ctx.which(tool)
                   else c.fail("not on PATH", f"Install {tool}; Azure Cloud Shell already has it", title=tool))
    return out


@check("op.signin", "Azure sign-in", needs="none", kb=KB, account=False, reads=["az account show"],
       source="https://learn.microsoft.com/cli/azure/authenticate-azure-cli")
def signin(ctx, c):
    acct = ctx.az(["account", "show"])
    if not acct:
        return c.fail("az isn't signed in", "az login")
    ctx.acct = acct
    user = acct.get("user", {})
    return c.ok(f"subscription \"{ctx.name('subscription', acct.get('name') or '')}\" as a {user.get('type', 'user')}")
