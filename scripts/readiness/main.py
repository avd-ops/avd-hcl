"""The command line: python3 scripts/preflight.py [--answers FILE] [--format console|md|json]

Reads the answers (scripts/schema/answers.py init), runs every check read-only and prints a
verdict. Exit codes: 0 go (with or without warnings), 1 no-go (or a warning with --strict),
2 usage, 3 incomplete.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from . import report, runner
from .context import Ctx
from .model import REGISTRY

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts" / "schema"))
import answers as answers_mod  # noqa: E402


def values_from(answers: dict, environment=None) -> dict:
    """Every parameter's value from the answers and the schema's defaults. Tenant and
    subscription come from the sign-in check instead, and group names are looked up by
    id.groups, so neither is resolved here."""
    schema = json.loads(answers_mod.SCHEMA.read_text())
    answers = answers_mod.pin_environment(answers, environment)
    return answers_mod.resolve(schema, answers, source=lambda kind: None, group=lambda name: name)


def evaluate(values: dict, *, only=(), skip=(), show_names: bool = False, az=None, **ctx_kw):
    ctx = Ctx(values, az=az, show_names=show_names, **ctx_kw)
    started = report.now()
    results = runner.run(ctx, runner.select(only, skip))
    return ctx, results, started


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Read-only readiness check for the AVD platform stage")
    ap.add_argument("--answers", type=Path, default=answers_mod.DEFAULT_ANSWERS)
    ap.add_argument("--format", choices=["console", "md", "json"], default="console")
    ap.add_argument("--only", default="", help="comma-separated check IDs")
    ap.add_argument("--skip", default="", help="comma-separated check IDs")
    ap.add_argument("--environment", help="the environment this run checks; the answers must match it")
    ap.add_argument("--strict", action="store_true", help="exit 1 on warnings too")
    ap.add_argument("--names", action="store_true", help="show resource and group names (they are masked by default)")
    ap.add_argument("--list", action="store_true", help="list the checks and exit")
    args = ap.parse_args(argv)

    if args.list:
        for c in REGISTRY.values():
            print(f"{c.id:<24} {c.title} (needs {c.needs})")
        return 0
    if not args.answers.exists():
        print(f"No answers at {args.answers}. Run python3 scripts/schema/answers.py init first.", file=sys.stderr)
        return report.USAGE
    try:
        only, skip = runner.parse_ids(args.only), runner.parse_ids(args.skip)
        values = values_from(json.loads(args.answers.read_text()), args.environment)
    except (runner.UsageError, answers_mod.AnswerError, ValueError) as e:
        for line in str(e).splitlines():
            print(f"x {line}", file=sys.stderr)
        return report.USAGE
    ctx, results, started = evaluate(values, only=only, skip=skip, show_names=args.names)
    doc = report.document(ctx, results, started=started)
    print(report.mask(report.as_text(doc, results, args.format), ctx.account_terms()))
    return report.exit_code(doc["verdict"], results, args.strict)
