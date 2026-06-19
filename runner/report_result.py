#!/usr/bin/env python3

import json
import sys
from pathlib import Path
from typing import Any


def main() -> None:
    if len(sys.argv) != 4:
        raise SystemExit("Usage: report_result.py <packet.json> <pr_url> <output.json>")

    packet = json.loads(Path(sys.argv[1]).read_text())
    pr_url = sys.argv[2]
    output_path = Path(sys.argv[3])

    result: dict[str, Any] = {
        "task_id": packet["task_id"],
        "target_repo": packet["target_repo"],
        "branch": packet["work_branch"],
        "pr_url": pr_url,
        "status": "opened_pr",
        "checks_passed": False,
    }
    output_path.write_text(json.dumps(result, indent=2) + "\n")
    print(output_path)


if __name__ == "__main__":
    main()
