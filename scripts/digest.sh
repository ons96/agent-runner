#!/usr/bin/env bash
# digest.sh - read ons96/task-board queue, append hourly digest as a comment
# to a SINGLE rolling digest issue. Never creates a second issue.
#
# Idempotency by construction: there is exactly ONE open "hourly digest ..."
# issue. Each run appends a comment. If the open one is missing (manually
# closed), a new one is created with the current top-N as body, then commented
# on subsequent runs.
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
    --json number,title,labels,createdAt,reactionGroups \
    --jq 'sort_by(
        (.labels | map(select(.name | startswith("priority:P"))) | .[0].name) // "priority:P9",
        .createdAt
      ) | .[0:'"$TOP_N"']'
}

build_body() {
  local issues_json="$1"
  local context="$2" # "body" for first issue, "comment" for appends
  echo "$issues_json" | jq -r --arg marker "$MARKER" --arg run_at "$RUN_AT" --arg top_n "$TOP_N" --arg repo "$REPO" --arg ctx "$context" '
    def section: [
      ($marker),
      "",
      ("**Top \($top_n) status:new from \($repo) at \($run_at) (sorted by priority, oldest first):**"),
      ""
    ];
    def items:
      (.[] | [
          "- #\(.number) — \(.title) [\((.labels | map(select(.name | startswith("priority:"))) | .[0].name) // "P9")]",
          "  created: \(.createdAt), reactions: \(([.reactionGroups[]?.users.total // 0] | add) // 0)"
        ] | join("\n"));
    if $ctx == "body" then
      ([
        "## Hourly task-board digest (rolling)",
        "",
        "_This single issue accumulates \($top_n)-item snapshots of ons96/task-board `status:new` queue, sorted by priority (P0 first) then oldest. One issue per open lifetime; every hourly cron posts one comment here. Manual close -> next run creates a new rolling issue._",
        "",
        (section | join("\n")),
        (items)
      ] | join("\n"))
    else
      ([
        "",
        ("--- \($run_at) ---"),
        ""
      ] + (section) + [items] | join("\n"))
    end
  '
}

find_rolling_issue() {
  gh issue list \
    --repo "$REPO" \
    --state open \
    --label "tag:automation" \
    --limit 100 \
    --json number,title \
    --jq '[.[] | select(.title | startswith("hourly digest "))] | .[0].number // empty'
}

post_or_dry() {
  local issues_json="$1"
  local rolling_issue
  rolling_issue="$(find_rolling_issue)"

  if [[ -n "$rolling_issue" ]]; then
    # Append a new comment to the existing rolling issue.
    local comment
    comment="$(build_body "$issues_json" "comment")"
    if [[ "$DRY_RUN" == "true" ]]; then
      log "DRY_RUN: would POST COMMENT on #$rolling_issue:"
      echo "$comment" >&2
      return 0
    fi
    log "Appending comment to rolling digest issue #$rolling_issue"
    echo "$comment" | gh issue comment "$rolling_issue" --repo "$REPO" --body-file -
    return 0
  fi

  # No rolling issue open -> create first one, body = current digest.
  local body
  body="$(build_body "$issues_json" "body")"
  if [[ "$DRY_RUN" == "true" ]]; then
    log "DRY_RUN: would CREATE rolling digest issue in $REPO:"
    echo "$body" >&2
    return 0
  fi
  log "Creating first rolling digest issue in $REPO"
  echo "$body" | gh issue create \
    --repo "$REPO" \
    --title "hourly digest (rolling — open one)" \
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
