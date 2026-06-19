#!/usr/bin/env bash
set -euo pipefail

PACKET_FILE="${1:?Usage: checkout_target.sh <packet.json>}"
TARGET_ROOT="${2:-target-repo}"
read -r TARGET_REPO TARGET_BRANCH WORK_BRANCH < <(python3 - <<'PY' "$PACKET_FILE"
import json, sys
from pathlib import Path
packet = json.loads(Path(sys.argv[1]).read_text())
repo = packet.get('target_repo', packet.get('repo', ''))
target = packet.get('target_branch', 'main')
work = packet.get('work_branch', packet.get('branch', f"agent/auto-{repo.split('/')[-1][:20]}"))
print(f"{repo}\t{target}\t{work}")
PY
)

if [ -z "${TARGET_REPO_TOKEN:-}" ]; then
    echo "ERROR: TARGET_REPO_TOKEN must be set" >&2
    exit 1
fi

if [ -n "${ALLOWED_TARGET_REPOS:-}" ]; then
    if ! echo "$ALLOWED_TARGET_REPOS" | grep -qF "$TARGET_REPO"; then
        echo "ERROR: target_repo '$TARGET_REPO' not in ALLOWED_TARGET_REPOS allowlist" >&2
        exit 1
    fi
fi

rm -rf "$TARGET_ROOT"
git clone --quiet "https://x-access-token:${TARGET_REPO_TOKEN}@github.com/${TARGET_REPO}.git" "$TARGET_ROOT" >&2
cd "$TARGET_ROOT"
git checkout --quiet "$TARGET_BRANCH" >&2 || git checkout --quiet -b "$TARGET_BRANCH" >&2
git checkout --quiet -b "$WORK_BRANCH" >&2
echo "$TARGET_ROOT"
