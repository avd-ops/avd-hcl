#!/usr/bin/env python3
"""Read-only post-deploy verification for an avd-hcl platform or host-pool deployment.

Runs Azure CLI queries (never writes) and reports pass/fail/skip for:
  1. Host pool exists and matches expected type
  2. Session hosts are registered and Available (when host_count > 0)
  3. Scaling plan exists (when Pooled)
  4. FSLogix storage account and file share exist

Offline unit tests inject a mock command runner; no Azure calls are needed for tests.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from dataclasses import asdict, dataclass
from typing import Callable


Runner = Callable[[list[str]], tuple[int, str, str]]


@dataclass
class CheckResult:
    id: str
    status: str  # pass | fail | skip
    detail: str


def default_runner(cmd: list[str]) -> tuple[int, str, str]:
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    return proc.returncode, proc.stdout, proc.stderr


def _az_json(runner: Runner, args: list[str]) -> tuple[bool, object, str]:
    rc, out, err = runner(["az", *args, "-o", "json"])
    if rc != 0:
        return False, None, (err or out).strip() or f"az exited {rc}"
    try:
        return True, json.loads(out) if out.strip() else None, ""
    except json.JSONDecodeError as exc:
        return False, None, f"invalid JSON from az: {exc}"


def verify_deployment(
    *,
    resource_group: str,
    host_pool_name: str,
    expected_host_count: int = 0,
    scaling_plan_name: str | None = None,
    storage_rg: str | None = None,
    storage_account_name: str | None = None,
    share_name: str = "profiles",
    runner: Runner = default_runner,
) -> list[CheckResult]:
    results: list[CheckResult] = []

    ok, hp, err = _az_json(
        runner,
        ["desktopvirtualization", "hostpool", "show", "-g", resource_group, "-n", host_pool_name],
    )
    if not ok or not isinstance(hp, dict):
        results.append(CheckResult("avd.host_pool", "fail", f"host pool {host_pool_name} not found: {err}"))
        return results
    hp_type = hp.get("hostPoolType", "unknown")
    results.append(CheckResult("avd.host_pool", "pass", f"{host_pool_name} ({hp_type})"))

    ok, hosts, err = _az_json(
        runner,
        ["desktopvirtualization", "sessionhost", "list", "-g", resource_group, "--host-pool-name", host_pool_name],
    )
    if expected_host_count == 0:
        results.append(CheckResult("avd.session_hosts", "skip", "expected_host_count is 0"))
    elif not ok or not isinstance(hosts, list):
        results.append(CheckResult("avd.session_hosts", "fail", f"could not list session hosts: {err}"))
    else:
        available = [h for h in hosts if h.get("status") == "Available"]
        if len(available) >= expected_host_count:
            results.append(
                CheckResult("avd.session_hosts", "pass", f"{len(available)}/{expected_host_count} Available")
            )
        else:
            results.append(
                CheckResult(
                    "avd.session_hosts",
                    "fail",
                    f"only {len(available)}/{expected_host_count} session hosts Available (found {len(hosts)} total)",
                )
            )

    if hp_type != "Pooled" or not scaling_plan_name:
        results.append(CheckResult("avd.scaling_plan", "skip", f"not applicable (hostPoolType={hp_type})"))
    else:
        ok, sp, err = _az_json(
            runner,
            ["desktopvirtualization", "scaling-plan", "show", "-g", resource_group, "-n", scaling_plan_name],
        )
        if ok and isinstance(sp, dict):
            results.append(CheckResult("avd.scaling_plan", "pass", scaling_plan_name))
        else:
            results.append(CheckResult("avd.scaling_plan", "fail", f"scaling plan {scaling_plan_name} missing: {err}"))

    if not storage_rg or not storage_account_name:
        results.append(CheckResult("fslogix.share", "skip", "storage account not specified"))
    else:
        ok, share, err = _az_json(
            runner,
            [
                "storage",
                "share-rm",
                "show",
                "--resource-group",
                storage_rg,
                "--storage-account",
                storage_account_name,
                "--name",
                share_name,
            ],
        )
        if ok and isinstance(share, dict):
            results.append(CheckResult("fslogix.share", "pass", f"{storage_account_name}/{share_name}"))
        else:
            results.append(CheckResult("fslogix.share", "fail", f"share {storage_account_name}/{share_name} missing: {err}"))

    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Read-only post-deploy AVD verifier.")
    parser.add_argument("--resource-group", required=True)
    parser.add_argument("--host-pool-name", required=True)
    parser.add_argument("--expected-host-count", type=int, default=0)
    parser.add_argument("--scaling-plan-name")
    parser.add_argument("--storage-rg")
    parser.add_argument("--storage-account-name")
    parser.add_argument("--share-name", default="profiles")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    results = verify_deployment(
        resource_group=args.resource_group,
        host_pool_name=args.host_pool_name,
        expected_host_count=args.expected_host_count,
        scaling_plan_name=args.scaling_plan_name,
        storage_rg=args.storage_rg,
        storage_account_name=args.storage_account_name,
        share_name=args.share_name,
    )
    failed = any(r.status == "fail" for r in results)
    if args.json:
        print(json.dumps({"ok": not failed, "checks": [asdict(r) for r in results]}, indent=2))
    else:
        for r in results:
            print(f"[{r.status.upper()}] {r.id}: {r.detail}")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
