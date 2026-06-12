#!/usr/bin/env bash
# digest.sh - read ons96/task-board queue, post hourly digest as one issue
# comment, never duplicate. Runs in GitHub Actions; gh CLI + jq available.
#
# Idempotency: looks for a hidden HTML marker in the latest comment by
# agent-runner[bot] on each top issue; skips if present. Marker is a UUID
# we mint at runtime so the same digest never posts twice even if the
# workflow re-runs.
#
# Exit codes:
#   0  - digest posted (or dry-run succeeded)
#   1  - gh API failure (workflow will show red)
#   2  - jq/curl failure
set -euo pipefail

REPO="${TASKBOARD_REPO:-ons96/task-board}"
TOP_N="${DIGEST_TOP_N:-5}"
DRY_RUN="${DIGEST_DRY_RUN:-false}"
MARKER="<!-- agent-runner-digest:$(cat /proc/sys/kernel/random/uuid 2>/dev/null || date +%s%N) -->"
RUN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

log() { printf '[digest %s] %s\n' "$RUN_AT" "$*" >&2; }

need_gh() {
  if ! command -v gh >/dev/null 2>&1; then
    log "gh not on PATH; install via apt-get or pre-bake image"
    return 1
  fi
  if ! command -v jq >/dev/null 2>&1; then
    log "jq not on PATH; install via apt-get or pre-bake image"
    return 1
  fi
}

fetch_top() {
  # gh issue list returns max 100; we filter status:new + sort by priority
  # (label name lex) then created (oldest first). Reactions count requires
  # an extra field request.
  gh issue list \
    --repo "$REPO" \
    --state open \
    --label "status:new" \
    --limit 100 \
    --json number,title,labels,createdAt,reactionGroups,comments \
    --jq 'sort_by(
        (.labels | map(select(.name | startswith("priority:P"))) | .[0].name) // "priority:P9",
        .createdAt
      ) | .[0:'"$TOP_N"']'
}

already_posted() {
  local issue_number="$1"
  local existing
  existing="$(gh issue view "$issue_number" --repo "$REPO" --comments --json comments \
    --jq '.comments
           | map(select(.author.login == "github-actions[bot]"))
           | map(select(.body | contains("agent-runner-digest")))
           | length')"
  [[ "$existing" -gt 0 ]]
}

build_body() {
  local issues_json="$1"
  echo "$issues_json" | jq -r --arg marker "$MARKER" --arg run_at "$RUN_AT" --arg top_n "$TOP_N" --arg repo "$REPO" '
    [
      "## task-board digest (\($run_at))",
      "",
      "_Top \($top_n) status:new from \($repo) — sorted by priority then oldest first._",
      "",
      ($marker),
      "",
      (.[] | [
          "### #\(.number) — \(.title)",
          "priority: \((.labels | map(select(.name | startswith("priority:"))) | .[0].name) // "P9")",
          "created: \(.createdAt)",
          "reactions: \(([.reactionGroups[]?.users.total // 0] | add) // 0)",
          "labels: \((.labels | map(.name) | join(", ")))",
          ""
        ] | join("\n"))
    ] | join("\n")
  '
}

post_or_dry() {
  local issues_json="$1"
  local body
  body="$(build_body "$issues_json")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: would post digest to $REPO (top $TOP_N issues):"
    echo "$body" >&2
    return 0
  fi
  log "Posting digest to $REPO (top $TOP_N issues, marker $MARKER)"
  echo "$body" | gh issue create \
    --repo "$REPO" \
    --title "hourly digest $(date -u +%Y-%m-%dT%H:%M)" \
    --label "tag:automation" \
    --body-file -
}

main() {
  need_gh
  local issues_json
  issues_json="$(fetch_top)"
  if [[ -z "$issues_json" || "$issues_json" == "[]" ]]; then
    log "no status:new issues; nothing to digest"
    exit 0
  fi
  log "fetched $(echo "$issues_json" | jq 'length') candidates; top $TOP_N after sort"
  post_or_dry "$issues_json"
}

main "$@"
