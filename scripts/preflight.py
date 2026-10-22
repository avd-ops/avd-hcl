#!/usr/bin/env python3
"""Read-only readiness check before the platform stage. See docs/knowledge/readiness.md.

    python3 scripts/preflight.py                 checks your .avd/answers.json
    python3 scripts/preflight.py --format md     a report to paste into a ticket
    python3 scripts/preflight.py --list          every check and the right it needs
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from readiness.main import main  # noqa: E402

if __name__ == "__main__":
    sys.exit(main())
