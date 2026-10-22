# Adapted from nerdio-hcl (Apache-2.0, commit 75f59bc), scripts/nerdio/readiness/report.py; see CREDITS.md and NOTICE.
"""Verdict, exit codes and the three outputs: JSON, Markdown and the console.

Changes: one stage, no legacy format, and every GUID and account name is masked here, so no
output needs a separate redaction step.
"""

from __future__ import annotations

import datetime as dt
import json
import re
from dataclasses import asdict
from pathlib import Path
from typing import Dict, List

from . import SCHEMA_ID, __version__
from .model import DOMAINS, FAIL, MANUAL, NO_ACCESS, PASS, SKIPPED, STATUSES, WARN, Result

GO, GO_WARN, NO_GO, INCOMPLETE = "GO", "GO WITH WARNINGS", "NO-GO", "INCOMPLETE"
EXIT = {GO: 0, GO_WARN: 0, NO_GO: 1, INCOMPLETE: 3}
USAGE = 2
# INCOMPLETE when every check in one of these domains came back no-access.
REQUIRED = ("identity", "subscription")
ICON = {PASS: "ok", WARN: "!", FAIL: "x", MANUAL: "?", NO_ACCESS: "no-access", SKIPPED: "-"}
GUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
PUBLIC_IDS = Path(__file__).resolve().parents[2] / ".github" / "public-ids.txt"
URL = re.compile(r"https?://\S+")
# Words the report itself uses; an account named only one of these is left alone, or the
# report's own titles and links would be masked.
OWN_WORDS = {"azure", "microsoft", "network", "virtual", "desktop", "sandbox", "contributor", "owner", "reader",
             "storage", "default", "subscription", "tenant", "production", "dev", "test", "user"}


def public_ids(path: Path = PUBLIC_IDS) -> set:
    """Microsoft's well-known IDs (the AVD app ID in a fix, say) stay readable."""
    try:
        return {line.strip().lower() for line in path.read_text().splitlines() if GUID.fullmatch(line.strip())}
    except OSError:
        return set()


def verdict(results: List[Result]) -> str:
    ran = [r for r in results if r.status != SKIPPED]
    if any(r.status == FAIL for r in ran):
        return NO_GO
    if not ran:
        return INCOMPLETE
    for domain in REQUIRED:
        seen = [r for r in ran if r.domain == domain]
        if seen and all(r.status == NO_ACCESS for r in seen):
            return INCOMPLETE
    if any(r.status in (WARN, MANUAL, NO_ACCESS) for r in ran):
        return GO_WARN
    return GO


def exit_code(result: str, results: List[Result], strict: bool = False) -> int:
    code = EXIT[result]
    if strict and code == 0 and any(r.status == WARN for r in results):
        return 1
    return code


def now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")


def document(ctx, results: List[Result], *, started: str) -> Dict:
    acct = ctx.acct or {}
    kind = (acct.get("user") or {}).get("type") or "unknown"
    return {
        "schema": SCHEMA_ID,
        "tool_version": __version__,
        "cloud": ctx.cloud or "unknown",
        "verdict": verdict(results),
        "started": started,
        "identity": {"type": kind, "rights_seen": sorted(r for r in ctx.rights if r)},
        "counts": {s: sum(1 for r in results if r.status == s) for s in STATUSES},
        "results": [asdict(r) for r in results],
    }


def ordered(results: List[Result]) -> List[Result]:
    """Grouped by domain in DOMAINS order, the most urgent first within each."""
    rank = {d: i for i, d in enumerate(DOMAINS.values())}
    sev = {s: i for i, s in enumerate(STATUSES)}
    return sorted(results, key=lambda r: (rank.get(r.domain, 99), sev.get(r.status, 99)))


def summary_line(doc: Dict) -> str:
    n = doc["counts"]
    parts = [f"{n[FAIL]} to fix"]
    if n[WARN]:
        parts.append(f"{n[WARN]} to look at")
    if n[NO_ACCESS]:
        parts.append(f"{n[NO_ACCESS]} you can't see")
    parts.append(f"{n[MANUAL]} to confirm yourself")
    return f"{doc['verdict']}: " + ", ".join(parts) + "."


def console(doc: Dict, results: List[Result]) -> str:
    lines = []
    domain = None
    for r in ordered(results):
        if r.status == SKIPPED:
            continue
        if r.domain != domain:
            domain = r.domain
            lines.append(f"[{domain}]")
        lines.append(f"{ICON[r.status]:>2} {r.title}: {r.detail}")
        if r.fix and r.status != PASS:
            lines.append(f"    fix: {r.fix}")
    skipped = doc["counts"][SKIPPED]
    lines.append("")
    lines.append(summary_line(doc) + (f" {skipped} skipped (--format json lists why)." if skipped else ""))
    return "\n".join(lines)


def _cell(text: str) -> str:
    return (text or "").replace("|", "\\|").replace("\n", " ")


def markdown(doc: Dict, results: List[Result]) -> str:
    """A short report to paste into a chat, a ticket or a change request."""
    head = [f"## AVD readiness: {doc['verdict']}", "",
            f"{doc['cloud']}, {doc['started']}, readiness {doc['tool_version']}. "
            + summary_line(doc).split(": ", 1)[1] + f" {doc['counts'][PASS]} passed.", ""]
    rows = [r for r in ordered(results) if r.status not in (PASS, SKIPPED)]
    if not rows:
        return "\n".join(head + ["Everything checked passed."]) + "\n"
    table = ["| Result | Check | Detail | Fix |", "|---|---|---|---|"]
    for r in rows:
        table.append(f"| {r.status} | `{r.id}` {_cell(r.title)} | {_cell(r.detail)} | {_cell(r.fix)} |")
    return "\n".join(head + table) + "\n"


def mask(text: str, terms: List[str]) -> str:
    """No GUID, subscription, tenant or user name in anything printed or saved. Links and
    Microsoft's public IDs are left as they are, so every fix stays usable."""
    keep = public_ids()
    terms = [t for t in terms if t.lower() not in OWN_WORDS]

    def outside_urls(part: str) -> str:
        part = GUID.sub(lambda m: m.group(0) if m.group(0).lower() in keep else "<id>", part)
        for t in terms:
            part = re.sub(r"(?<![\w@.-])" + re.escape(t) + r"(?![\w@-])", "<account>", part, flags=re.I)
        return part

    out, last = [], 0
    for m in URL.finditer(text):
        out.append(outside_urls(text[last:m.start()]))
        out.append(m.group(0))
        last = m.end()
    out.append(outside_urls(text[last:]))
    return "".join(out)


def as_text(doc: Dict, results: List[Result], fmt: str) -> str:
    if fmt == "json":
        return json.dumps(doc, indent=2)
    if fmt == "md":
        return markdown(doc, results)
    return console(doc, results)
