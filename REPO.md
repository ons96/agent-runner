# REPO.md - design notes for ons96/agent-runner

## Purpose

Backup scheduler for `/work` that runs even when the always-on VPS is down.
Public GitHub Actions minutes are free for public repos, so the cost of this
fallback is zero; the only "price" is the slight delay between schedule
fires and dispatch-to-runner.

## What this is

Thin cron + dispatcher. Reads `ons96/task-board`, posts a digest of the top
`status:new` issues every hour. Anyone (user, bot, another workflow) can
read that digest and pick a job.

## What this is NOT

- Not a self-contained AI agent runner. Public GitHub runners cannot reach
  the Tailscale-only vps-gateway at 100.71.95.75:8000, so the workflow does
  not call `opencode run` directly.
- Not a replacement for VPS-side cron. The VPS task-board-loop is the
  primary work runner (faster, direct gateway access, can hold long
  sessions). GH Actions is a backup when that VPS is offline.

## Why two layers?

| need                    | VPS cron (primary)     | GH Actions (backup)     |
| ----------------------- | ---------------------- | ----------------------- |
| uptime                  | depends on 1GB VPS     | GitHub-managed, ~99.9%  |
| minutes / month         | free (own machine)     | free (public repo)      |
| secrets storage         | local .env             | GH Secrets              |
| gateway reach           | direct                 | unreachable             |
| full agent capability   | yes (opencode run)     | no (digest only)        |
| max session length      | unbounded              | 5-90 min/job (free)     |
| dispatch latency        | seconds                | minute after cron fire  |
| rate limit handling     | direct model fallback  | n/a (digest only)       |

The GH Actions tier cannot replace the VPS tier for heavy work, but it can
guarantee the queue gets read every hour even when the VPS is down. When a
digest comment appears, a human (or a self-hosted runner) can take over.

## Future extension

Two low-effort upgrades if a self-hosted runner ever exists:

1. Replace `post_or_dry` with a `repository_dispatch` to a private runner
   repo (e.g. `ons96/agent-executor`). The runner repo has the
   opencode config + secrets + Tailscale access. The public repo keeps
   the cron + free minutes.
2. Add a `reactions` listener: when a human adds :eyes: to a digest
   comment, the workflow creates a new status:done for that work; same
   inverse path on :+1:.

## Anti-features (rejected)

- `opencode run` directly in this workflow. Requires shipping the full
  opencode config + provider keys into the public runner image, which
  leaks the model roster and is gratuitous churn. Digest + dispatch is
  enough.
- Per-issue PR creation. Bursty, noisy, easy to spam. One digest is one
  comment.
- Database / Redis / state. Idempotency via stable comment marker; no
  extra infra.
