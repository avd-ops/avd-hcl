# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/checks/avd.py; see CREDITS.md and NOTICE.
"""avd.*: the session host size, what it supports, zones and vCPU quota.

Changes: the host count comes from host_count, and the size is checked for what the
session-hosts module turns on (Trusted Launch, encryption at host, Premium SSD) and the zones.
"""

from __future__ import annotations

from ..model import check

KB = "docs/knowledge/readiness.md#checks"


def vm_sku(ctx):
    """The size's SKU row in the region: a dict, False when it isn't offered, None when az can't say."""
    location, size = ctx.values["location"], ctx.values["vm_size"]

    def read():
        skus = ctx.az(["vm", "list-skus", "-l", location, "--size", size, "--resource-type", "virtualMachines"])
        if skus is None:
            return None
        return next((s for s in skus if s.get("name", "").lower() == size.lower()), False)
    return ctx.cached(("sku", location, size), read)


def restricted(sku) -> bool:
    return any(r.get("type") == "Location" and r.get("reasonCode") == "NotAvailableForSubscription"
               for r in sku.get("restrictions") or [])


def usable_sku(ctx):
    """The SKU row when the size can be used here, else None (avd.vm_size says why)."""
    sku = vm_sku(ctx)
    return sku if sku and not restricted(sku) else None


def capabilities(sku) -> dict:
    # ARM leaves the list out when empty.
    return {x["name"]: x["value"] for x in sku.get("capabilities") or []}


@check("avd.vm_size", "VM size", needs="Reader on the subscription", kb=KB, inputs=["location", "vm_size"],
       source="https://learn.microsoft.com/azure/azure-resource-manager/troubleshooting/error-sku-not-available",
       reads=["az vm list-skus"])
def vm_size(ctx, c):
    location, size = ctx.values["location"], ctx.values["vm_size"]
    sku = vm_sku(ctx)
    if sku is None:
        return c.warn(f"couldn't look up {size} in {location}")
    if sku is False:
        return c.fail(f"{size} isn't offered in {location}", f"az vm list-skus -l {location} --size Standard_E -o table")
    if restricted(sku):
        return c.fail(f"{size} is restricted for this subscription in {location}",
                      "Pick another size, or open a support request to lift the restriction")
    return c.ok(f"{size} is offered in {location}")


@check("avd.vm_features", "VM size features", needs="Reader on the subscription", kb=KB, inputs=["location", "vm_size"],
       source="https://learn.microsoft.com/azure/virtual-machines/trusted-launch", reads=["az vm list-skus"])
def vm_features(ctx, c):
    """The session-hosts module asks for Trusted Launch, Premium SSD and, by default, encryption at host."""
    size = ctx.values["vm_size"]
    sku = usable_sku(ctx)
    if not sku:
        return c.skip(f"needs {size} to be usable here (see VM size)")
    caps = capabilities(sku)
    out = []
    if caps.get("TrustedLaunchDisabled", "False") == "True":
        out.append(c.fail(f"{size} doesn't support Trusted Launch", "Pick a Gen2 size that does", title="Trusted Launch"))
    else:
        out.append(c.ok("supported", title="Trusted Launch"))
    if caps.get("PremiumIO") != "True":
        out.append(c.fail(f"{size} can't use Premium SSD", "Pick an s size (for example Standard_E4as_v5)", title="Premium SSD"))
    else:
        out.append(c.ok("supported", title="Premium SSD"))
    if ctx.values.get("encryption_at_host") is not False:
        if caps.get("EncryptionAtHostSupported") == "True":
            out.append(c.ok("supported", title="Encryption at host size"))
        else:
            out.append(c.fail(f"{size} doesn't support encryption at host", "Pick another size, or turn encryption_at_host off",
                              title="Encryption at host size"))
    return out


@check("avd.zones", "Availability zones", needs="Reader on the subscription", kb=KB, inputs=["location", "vm_size", "availability_zones"],
       source="https://learn.microsoft.com/azure/reliability/availability-zones-region-support", reads=["az vm list-skus"])
def zones(ctx, c):
    size, location, wanted = ctx.values["vm_size"], ctx.values["location"], [str(z) for z in ctx.values["availability_zones"]]
    sku = usable_sku(ctx)
    if not sku:
        return c.skip(f"needs {size} to be usable here (see VM size)")
    offered = {str(z) for info in sku.get("locationInfo") or [] for z in info.get("zones") or []}
    for r in sku.get("restrictions") or []:
        if r.get("type") == "Zone":
            offered -= {str(z) for z in (r.get("restrictionInfo") or {}).get("zones") or []}
    missing = [z for z in wanted if z not in offered]
    if missing:
        return c.fail(f"{size} isn't offered in zone {', '.join(missing)} of {location} for this subscription"
                      + (f" (offered: {', '.join(sorted(offered))})" if offered else " (no zones offered)"),
                      "Change availability_zones, or leave it empty for regional hosts")
    return c.ok(f"{size} is offered in zones {', '.join(wanted)}")


@check("avd.vcpu", "vCPU quota", needs="Reader on the subscription", kb=KB, inputs=["location", "vm_size"],
       source="https://learn.microsoft.com/azure/quotas/per-vm-quota-requests", reads=["az vm list-skus", "az vm list-usage"])
def vcpu(ctx, c):
    """Family and regional vCPU quota for host_count hosts."""
    location, size = ctx.values["location"], ctx.values["vm_size"]
    hosts = int(ctx.values.get("host_count") or 0)
    if hosts == 0:
        return c.ok("no session hosts in this run")
    sku = usable_sku(ctx)
    if not sku:
        return c.skip(f"needs {size} to be usable in {location} (see VM size)")
    vcpus = int(capabilities(sku).get("vCPUs", "0") or 0)
    family = sku.get("family")
    if not vcpus:
        return c.warn(f"couldn't read how many vCPUs {size} has; check quota by hand")
    need = vcpus * hosts
    usage = ctx.az(["vm", "list-usage", "-l", location])
    if usage is None or not family:
        return c.warn(f"couldn't read quota; you need {need} vCPUs of {family or size}")
    out = []
    for key, label in ((family, f"{family} vCPUs"), ("cores", "Total regional vCPUs")):
        row = next((u for u in usage if (u.get("name") or {}).get("value") == key), None)
        if not row or row.get("limit") is None:
            out.append(c.warn(f"no quota row for {label}"))
            continue
        free = int(row["limit"]) - int(row.get("currentValue", 0))
        if free >= need:
            out.append(c.ok(f"{label}: {free} free, {need} needed for {hosts} hosts"))
        else:
            out.append(c.fail(f"{label}: {free} free, {need} needed for {hosts} hosts",
                              "Request more quota (Quotas > Compute in the portal), or lower host_count"))
    return out
