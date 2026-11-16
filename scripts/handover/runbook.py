#!/usr/bin/env python3
"""Generate a markdown handover runbook from Terraform outputs and deployment parameters."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


def _val(outputs: dict, key: str, default=None):
    entry = outputs.get(key)
    if isinstance(entry, dict) and "value" in entry:
        return entry["value"]
    return entry if entry is not None else default


def render_runbook(outputs: dict, tfvars: dict | None = None) -> str:
    tfvars = tfvars or {}
    prefix = tfvars.get("prefix", "<prefix>")
    location = tfvars.get("location", "<region>")
    identity_model = tfvars.get("identity_model", "entra_only")
    host_pool = _val(outputs, "host_pool_name", "<host-pool>")
    kv_name = _val(outputs, "key_vault_name", "<key-vault>")
    share_unc = _val(outputs, "profile_share_unc", "<profile-share-unc>")
    hosts = _val(outputs, "session_host_names", [])
    rgs = _val(outputs, "resource_group_names", {})

    host_lines = "\n".join(f"- `{h}` (break-glass secret: `{h}-localadmin`)" for h in hosts) or "- _(none deployed)_"
    rg_lines = "\n".join(f"- **{k}:** `{v}`" for k, v in sorted(rgs.items())) or "- _(not reported)_"

    return f"""# AVD Environment Handover Runbook ({prefix})

## 1. Environment Summary
- **Prefix / Region:** `{prefix}` / `{location}`
- **Identity Model:** `{identity_model}`
- **Host Pool:** `{host_pool}`
- **FSLogix Share:** `{share_unc}`
- **Break-glass Key Vault:** `{kv_name}` (username secret: `sessionhost-localadmin-username`)

## 2. Resource Groups
{rg_lines}

## 3. Session Hosts
{host_lines}

## 4. Day-2 Operations
- **Verify health (read-only):**
  `python3 scripts/verify/check.py --resource-group {rgs.get('control_plane', '<rg-avd>')} --host-pool-name {host_pool}`
- **Rotate session hosts (blue/green):** Toggle `host_generation` between `"a"` and `"b"` in tfvars and apply.
- **Monitoring:** Open Azure Monitor > AVD Insights in the Azure Portal for session diagnostics, RTT, and FSLogix events.
"""


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate an AVD handover runbook from Terraform outputs.")
    parser.add_argument("--outputs", type=Path, required=True, help="Path to `terraform output -json` file.")
    parser.add_argument("--tfvars", type=Path, help="Optional path to setup.auto.tfvars.json.")
    parser.add_argument("--out", type=Path, help="Optional output markdown file (defaults to stdout).")
    args = parser.parse_args(argv)

    outputs = json.loads(args.outputs.read_text(encoding="utf-8"))
    tfvars = json.loads(args.tfvars.read_text(encoding="utf-8")) if args.tfvars else {}
    md = render_runbook(outputs, tfvars)
    if args.out:
        args.out.write_text(md, encoding="utf-8")
    else:
        print(md)
    return 0


if __name__ == "__main__":
    sys.exit(main())
