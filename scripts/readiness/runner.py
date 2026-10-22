# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/runner.py; see CREDITS.md and NOTICE.
"""Pick the checks that apply and run them."""

from __future__ import annotations

from typing import Iterable, List, Optional

from . import checks  # noqa: F401  (registers every check)
from .context import Ctx, WriteRefused
from .model import REGISTRY, Check, Result


class UsageError(Exception):
    """Bad --only or --skip."""


def parse_ids(text: str) -> List[str]:
    items = [i.strip() for i in (text or "").split(",") if i.strip()]
    unknown = [i for i in items if i not in REGISTRY]
    if unknown:
        raise UsageError("unknown check " + ", ".join(unknown) + "; --list shows them")
    return items


def select(only: Iterable[str] = (), skip: Iterable[str] = ()) -> List[Check]:
    only, skip = set(only), set(skip)
    return [c for c in REGISTRY.values() if (not only or c.id in only) and c.id not in skip]


def missing_input(ctx: Ctx, c: Check) -> Optional[str]:
    gone = [k for k in c.inputs if ctx.values.get(k) in (None, "", [])]
    return ", ".join(gone) if gone else None


def run_check(ctx: Ctx, c: Check) -> List[Result]:
    if ctx.stopped:
        return [c.skip(f"stopped: {ctx.stopped}")]
    if c.account and not ctx.acct:
        return [c.skip("needs a signed-in az account")]
    gone = missing_input(ctx, c)
    if gone:
        return [c.skip(f"needs input: {gone}")]
    try:
        got = c.run(ctx, c)
    except WriteRefused:
        raise
    except Exception as exc:  # a broken check must never turn into a pass or end the run
        return [c.warn(f"the check stopped unexpectedly ({type(exc).__name__})", "Rerun; if it repeats, report it")]
    return [got] if isinstance(got, Result) else list(got or [])


def run(ctx: Ctx, selected: List[Check]) -> List[Result]:
    results: List[Result] = []
    for c in selected:
        results += run_check(ctx, c)
    return results
