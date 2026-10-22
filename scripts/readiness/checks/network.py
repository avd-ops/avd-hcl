# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/checks/network.py; see CREDITS.md and NOTICE.
"""net.*: the AVD address range, the hub and private DNS.

Changes: this kit's tag (avd-kit-role) and VNet name, the privatelink zones the platform stage
creates (file, blob and Key Vault), and a check that the egress choice is complete.
"""

from __future__ import annotations

import ipaddress

from ..model import check

KB = "docs/knowledge/readiness.md#checks"
PEERING = "https://learn.microsoft.com/azure/virtual-network/virtual-network-peering-overview"
HUB_ROLES = {"Owner", "Contributor", "Network Contributor"}
# The zones modules/network creates for the profile share's and Key Vault's private endpoints.
KIT_ZONES = {"privatelink.file.core.windows.net", "privatelink.blob.core.windows.net", "privatelink.vaultcore.azure.net"}


def kit_groups(ctx) -> set:
    """Resource groups an earlier run of the kit made (tagged avd-kit-role), so their VNet and DNS zones aren't flagged."""
    def read():
        rows = ctx.az(["group", "list", "--query", "[?tags.\"avd-kit-role\"].name"])
        return {r.lower() for r in rows or [] if r}
    return ctx.cached("kit_groups", read)


def avd_range(ctx):
    try:
        return ipaddress.IPv4Network(ctx.values["address_space"])
    except (KeyError, ValueError, TypeError):
        return None


@check("net.overlap", "Address range", needs="Reader on the subscription", kb=KB, source=PEERING, inputs=["address_space"],
       reads=["az network vnet list", "az group list"])
def overlap(ctx, c):
    """The AVD address range against what's already in the subscription."""
    space = avd_range(ctx)
    if space is None:
        return c.warn("no valid address_space to check")
    own_vnet = f"vnet-{ctx.values.get('prefix', '')}-avd".lower()
    kit = kit_groups(ctx)
    hub_id = (ctx.values.get("hub_vnet_id") or "").strip()
    vnets = ctx.az(["network", "vnet", "list", "--query",
                    "[].{name:name, id:id, rg:resourceGroup, prefixes:addressSpace.addressPrefixes}"])
    if vnets is None:
        return c.warn("couldn't list the subscription's virtual networks to check for overlaps", "az network vnet list -o table")
    clashes = []
    for v in vnets:
        if ((v.get("name") or "").lower() == own_vnet or (v.get("rg") or "").lower() in kit
                or (hub_id and (v.get("id") or "").lower() == hub_id.lower())):
            continue
        for pfx in v.get("prefixes") or []:
            try:
                if space.overlaps(ipaddress.IPv4Network(pfx, strict=False)):
                    clashes.append(f"{ctx.name('vnet', v['name'])} ({pfx})")
            except ValueError:
                pass
    if clashes:
        return c.warn(f"{space} overlaps existing networks: " + ", ".join(clashes),
                      "Pick a free range if these networks are, or will be, peered or connected to the AVD network")
    return c.ok(f"{space} doesn't overlap the subscription's other virtual networks")


@check("net.hub", "Hub network", needs="Reader on the hub VNet", kb=KB, inputs=["hub_vnet_id"], source=PEERING,
       reads=["az network vnet show", "az role assignment list"])
def hub(ctx, c):
    """The hub when peering: readable, no overlap, and rights to create the hub side of the peering."""
    space = avd_range(ctx)
    hub_id = ctx.values["hub_vnet_id"].strip()
    out = []
    data = ctx.az(["network", "vnet", "show", "--ids", hub_id, "--query", "{prefixes:addressSpace.addressPrefixes}"])
    if data is None:
        out.append(c.fail("can't read the hub VNet (wrong ID, another subscription you can't see, or no access)",
                          "Check hub_vnet_id, and ask for Network Contributor on the hub VNet"))
        return out
    bad = [p for p in data.get("prefixes") or [] if space and space.overlaps(ipaddress.IPv4Network(p, strict=False))]
    if bad:
        out.append(c.fail(f"{space} overlaps the hub ({', '.join(bad)}); peering would be refused",
                          "Pick an address range outside the hub's"))
    else:
        out.append(c.ok("the hub VNet is readable and doesn't overlap the AVD range"))
    if not ctx.is_user:
        out.append(c.manual("signed in as a service principal; check its rights on the hub by hand", title="Hub peering rights"))
        return out
    roles = ctx.roles_at(hub_id)
    if roles is None:
        out.append(c.warn("couldn't read your roles on the hub VNet", title="Hub peering rights"))
    elif HUB_ROLES & set(roles):
        out.append(c.ok("you can create the hub side of the peering", title="Hub peering rights"))
    else:
        out.append(c.fail("peering needs Network Contributor (or Contributor) on the hub VNet",
                          "Ask the hub's owner for Network Contributor on that VNet, or leave hub_vnet_id empty and peer later",
                          title="Hub peering rights"))
    return out


@check("net.private_dns", "Private DNS", needs="Reader on the private DNS zones' subscription", kb=KB,
       source="https://learn.microsoft.com/azure/private-link/private-endpoint-dns",
       reads=["az network private-dns zone list"])
def private_dns(ctx, c):
    zones = ctx.az(["network", "private-dns", "zone", "list", "--query", "[].{name:name, rg:resourceGroup}"])
    if zones is None:
        return c.skip("couldn't list private DNS zones")
    kit = kit_groups(ctx)
    found = sorted({f"{z['name']} ({ctx.name('rg', z.get('rg') or '')})" for z in zones if z.get("name") in KIT_ZONES
                    and (z.get("rg") or "").lower() not in kit})
    if found:
        return c.warn("privatelink zones already exist elsewhere: " + ", ".join(found),
                      "If those are your central DNS zones, link the AVD VNet to them instead of using the kit's own zones")
    return c.ok("no privatelink zones outside the kit's own")


@check("net.egress", "Way out to the internet", needs="none", kb=KB, account=False,
       source="https://learn.microsoft.com/azure/virtual-network/ip-services/default-outbound-access")
def egress(ctx, c):
    """The subnets have default outbound access off, so hosts need a NAT gateway or a firewall route."""
    nat, fw = ctx.values.get("create_nat_gateway", True), ctx.values.get("egress_firewall_ip")
    if nat and not fw:
        return c.ok("through the kit's NAT gateway")
    if fw and not nat:
        return c.manual(f"through the firewall at {fw}",
                        "Make sure it allows the AVD required URLs, or hosts can't register")
    return c.fail("pick exactly one way out: the NAT gateway, or egress_firewall_ip with create_nat_gateway off",
                  "Change create_nat_gateway or egress_firewall_ip in your answers")
