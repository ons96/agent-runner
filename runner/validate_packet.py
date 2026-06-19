#!/usr/bin/env python3
"""Validate task packet - supports both full and minimal formats."""

import json
import sys
from pathlib import Path
from typing import Any

# Full packet format requires all these keys
FULL_PACKET_KEYS = {
    "task_id",
    "staging_repo",
    "target_repo",
    "target_branch",
    "work_branch",
    "task_summary",
    "allowed_paths",
    "acceptance_criteria",
    "merge_policy",
}

# Minimal packet format (from code-task event) requires only these
MINIMAL_PACKET_KEYS = {
    "target_repo",
    "task",
}


def load_packet(path: str) -> dict[str, Any]:
    packet = json.loads(Path(path).read_text())
    if not isinstance(packet, dict):
        raise SystemExit("Packet must be a JSON object")
    return packet


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("Usage: validate_packet.py <packet.json>")

    packet = load_packet(sys.argv[1])
    
    # Check if it's a full packet or minimal packet
    has_full_keys = FULL_PACKET_KEYS.issubset(set(packet))
    has_minimal_keys = MINIMAL_PACKET_KEYS.issubset(set(packet))
    
    if has_full_keys:
        # Full packet validation
        if packet.get("merge_policy") == "blocked":
            raise SystemExit("Packet is blocked by merge policy")
        print("Full packet validation passed")
    elif has_minimal_keys:
        # Minimal packet - just needs repo and task
        repo = packet.get("target_repo", "")
        if not repo or "/" not in repo:
            raise SystemExit(f"Invalid target_repo: {repo}")
        print("Minimal packet validation passed")
    else:
        # Neither format matches
        missing_full = sorted(FULL_PACKET_KEYS - set(packet))
        missing_minimal = sorted(MINIMAL_PACKET_KEYS - set(packet))
        raise SystemExit(
            f"Invalid packet. Missing for full format: {', '.join(missing_full)}. "
            f"Missing for minimal format: {', '.join(missing_minimal)}"
        )


if __name__ == "__main__":
    main()
