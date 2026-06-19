#!/usr/bin/env python3

import re
import sys
from pathlib import Path

PATTERNS = [
    r"github_pat_[A-Za-z0-9_]{20,}",
    r"gh[pousr]_[A-Za-z0-9]{20,}",
    r"AIza[0-9A-Za-z\-_]{20,}",
    r"sk-[A-Za-z0-9]{20,}",
    r"sk_live_[A-Za-z0-9]{20,}",
    r"rk_live_[A-Za-z0-9]{20,}",
    r"AKIA[A-Z0-9]{16}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"Bearer [A-Za-z0-9\-._~+/]+=*",
]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: secret_guard.py <file>")

    content = Path(sys.argv[1]).read_text()
    for pattern in PATTERNS:
        if re.search(pattern, content):
            raise SystemExit(f"Potential secret detected matching {pattern}")
    print("Secret guard passed")


if __name__ == "__main__":
    main()
