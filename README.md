# agent-runner

Thin **public** GitHub Actions scheduler for [ons96/task-board](../task-board).
Runs every hour, posts a digest of the top `status:new` issues as a single
issue comment. Designed as a backup runner when the always-on VPS cron is
down.

Public so the workflow minutes stay free (no burn of private 1000 min/mo).
Secrets live in repo Settings -> Secrets and never in code.

## What it does

- Hourly cron (24 runs/day = 720/month, well under 2000 free tier).
- Lists `status:new` issues on `ons96/task-board`, sorts by priority then
  oldest first, picks top N (default 5).
- Posts a markdown digest as a single issue comment with a stable
  UUID marker so re-runs never duplicate.
- Manual dispatch (Run workflow button) for on-demand digests.
- `repository_dispatch` event so other repos can ping for a digest.

## What it does NOT do

- Run `opencode` itself. Public GitHub runners cannot reach the
  Tailscale-only vps-gateway. See [REPO.md](./REPO.md) for why this
  is a backup tier, not a primary.
- Hold long sessions. Free jobs cap at ~5-90 min; the primary VPS
  task-board-loop handles long work.

## Setup

1. Repo is already public and workflow is on. To customize:
   - Edit [`.github/workflows/hourly-digest.yml`](./.github/workflows/hourly-digest.yml).
   - Override `TASKBOARD_REPO` via repo Variables (Settings -> Variables)
     if you fork this for a different board.
2. Add a fine-grained PAT to repo Secrets named `GITHUB_DISPATCH_TOKEN`
   only if you flip the design to dispatch forward to a private runner
   repo. Default digest posts here and needs nothing beyond the built-in
   `GITHUB_TOKEN`.

## Manual trigger

`Actions -> hourly-digest -> Run workflow`. Optional inputs:

| input    | default | meaning                          |
| -------- | ------- | -------------------------------- |
| `top_n`  | `5`     | how many top issues to digest    |
| `dry_run`| `false` | log only, no API writes          |

## Local dry run

```bash
export TASKBOARD_REPO=ons96/task-board
export DIGEST_TOP_N=5
export DIGEST_DRY_RUN=true
export GH_TOKEN=ghp_xxx
bash scripts/digest.sh
```

## License

MIT. This repo contains no secrets, no provider keys, no model metadata,
and no per-device config. Safe to keep public.
