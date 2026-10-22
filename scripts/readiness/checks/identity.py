# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/checks/identity.py; see CREDITS.md and NOTICE.
"""id.*: the deployer's rights, the AVD groups and the AVD service principal.

Changes: the platform stage creates no app registrations and grants no consent, so the Entra
role checks are gone; the groups and the AVD service principal are new.
"""

from __future__ import annotations

import re

from ..model import check

KB = "docs/knowledge/readiness.md#checks"
UUID = re.compile(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$")
# Owner, or Contributor plus one of these, can create the resources and the role assignments the stage makes.
RBAC_WRITERS = {"User Access Administrator", "Role Based Access Control Administrator"}
AVD_APP_ID = "9cdead84-a844-4324-93f2-b2e6bb768d07"  # Azure Virtual Desktop, the same in every tenant


@check("id.sub_owner", "Deployer rights", needs="Reader on the subscription", kb=KB,
       source="https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-overview",
       reads=["az ad signed-in-user show", "az role assignment list"])
def subscription_owner(ctx, c):
    if not ctx.is_user:
        return c.manual("signed in as a service principal; the pipeline's apply identity holds these roles by design")
    if not ctx.me_id():
        return c.warn("couldn't read the signed-in user's object ID", "az ad signed-in-user show")
    roles = ctx.roles_at(f"/subscriptions/{ctx.subscription_id}")
    if roles is None:
        return c.warn("couldn't list role assignments", "az role assignment list --assignee <you> --all")
    ctx.rights |= set(roles)
    if "Owner" in roles:
        return c.ok("Owner on the subscription")
    if "Contributor" in roles and RBAC_WRITERS & set(roles):
        return c.ok("Contributor plus a role that can assign roles, which covers what the platform stage needs")
    return c.fail("the platform stage needs Owner, or Contributor plus Role Based Access Control Administrator "
                  "(found: " + (", ".join(sorted(set(roles))) or "none") + ")",
                  "Activate an eligible role in PIM, then az login again; otherwise ask a subscription Owner")


CANT_SEARCH = "couldn't search the directory"


def find_group(ctx, value: str):
    """(object ID, None) for a group by ID or exact display name, or (None, why not). A list with
    a filter tells "not there" (empty) apart from "can't read" (az fails)."""
    by_id = UUID.match(value)
    field = "id" if by_id else "displayName"
    rows = ctx.az(["ad", "group", "list", "--filter", f"{field} eq '{value.replace(chr(39), chr(39) * 2)}'",
                   "--query", "[].id"])
    if rows is None:
        return None, CANT_SEARCH
    if by_id and not rows:
        return None, "no group with that object ID"
    if len(rows) != 1:
        return None, f"{len(rows)} groups have that name; use its object ID"
    return rows[0], None


@check("id.groups", "AVD groups", needs="Directory read (Group.Read.All for an identity)", kb=KB, inputs=["user_groups"],
       source="https://learn.microsoft.com/azure/virtual-desktop/assign-users-to-application-group",
       reads=["az ad group list"])
def groups(ctx, c):
    out = []
    for key, label in (("user_groups", "Users"), ("admin_groups", "Admins")):
        for value in ctx.values.get(key) or []:
            gid, why = find_group(ctx, value)
            shown = ctx.name("group", value)
            if gid:
                out.append(c.ok(f"{shown} found", title=f"{label} group"))
            elif why == CANT_SEARCH:
                out.append(c.no_access(f"{shown}: {why}", title=f"{label} group"))
            else:
                out.append(c.fail(f"{shown}: {why}", "Fix the name in your answers, or create the group first",
                                  title=f"{label} group"))
    return out


@check("id.avd_principal", "AVD service principal", needs="Directory read (Application.Read.All for an identity)",
       kb=KB, source="https://learn.microsoft.com/azure/virtual-desktop/service-principal-assign-roles",
       reads=["az ad sp list"])
def avd_principal(ctx, c):
    """Scaling plans and Start VM on Connect act through it, and the stage grants it a role."""
    found = ctx.az(["ad", "sp", "list", "--filter", f"appId eq '{AVD_APP_ID}'", "--query", "[].id"])
    if found is None:
        return c.no_access("couldn't search the directory for it")
    if found:
        return c.ok("present in the tenant")
    return c.fail("the Azure Virtual Desktop service principal isn't in this tenant",
                  f"Register Microsoft.DesktopVirtualization, or az ad sp create --id {AVD_APP_ID} as an admin")
