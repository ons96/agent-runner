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

## What this is NOT (yet)

- Not a self-contained AI agent runner. Public GitHub runners cannot reach
  the Tailscale-only vps-gateway at 100.71.95.75:8000 over Tailscale, so the
  workflow does not call `opencode run` directly. (The public IP
  40.233.101.233:8000 IS reachable from public runners, but the scaffold
  leaves that as a deployment choice via `secrets.PROXY_API_KEY` + baseURL.)
- Not a replacement for VPS-side cron. The VPS task-board-loop is the
  primary work runner (faster, direct gateway access, can hold long
  sessions). GH Actions is a backup when that VPS is offline.

## Workflows

| workflow              | trigger                          | what it does                                |
| --------------------- | -------------------------------- | ------------------------------------------- |
| `hourly-digest.yml`   | cron (hourly)                    | post digest of `status:new` top 5 issues    |
| `runner-dispatch.yml` | `repository_dispatch:task-packet`| run full Option B pipeline (validate + run + push + PR) |
| `runner-execute.yml`  | `workflow_dispatch` (manual)     | same as runner-dispatch but manual entry    |

## Option B pipeline (runner-dispatch.yml)

A VPS (or any client) POSTs a `repository_dispatch` event of type
`task-packet` to this repo with a stringified JSON `packet_json` payload.
The workflow:

1. Validates the packet (full or minimal format)
2. Scans the packet for leaked secrets
3. Clones the target repo, checks out base branch, creates work branch
4. Runs the agent (opencode > oh-my-opencode > direct LLM cascade)
5. Scans generated files for secrets
6. Pushes work branch, opens PR against target_repo
7. Reports result metadata back to caller via artifact

Per-dispatch secrets required (configure in repo Settings -> Secrets):

- `TARGET_REPO_TOKEN` — PAT with `repo` scope to clone/push target repos
- `PROXY_API_KEY` — gateway API key (VPS gateway or equivalent)
- `GROQ_API_KEY` — optional Groq fallback
- `LLM_API_KEY` — optional direct LLM provider key

Per-dispatch vars (configure in repo Settings -> Variables):

- `ALLOWED_TARGET_REPOS` — newline-separated list of `owner/repo` strings.
  Empty = allow all (insecure). Recommended: allowlist target repos.

## Why two layers?

| need                    | VPS cron (primary)     | GH Actions (backup)     |
| ----------------------- | ---------------------- | ----------------------- |
| uptime                  | depends on 1GB VPS     | GitHub-managed, ~99.9%  |
| minutes / month         | free (own machine)     | free (public repo)      |
| secrets storage         | local .env             | GH Secrets              |
| gateway reach           | direct (Tailscale)     | public IP only          |
| full agent capability   | yes (opencode run)     | yes (Option B)          |
| max session length      | unbounded              | 5-90 min/job (free)     |
| dispatch latency        | seconds                | minute after cron fire  |
| rate limit handling     | direct model fallback  | same (gateway cascade)  |

The GH Actions tier is now a full fallback: when the VPS is down, the
Option B dispatch still produces work via the public runner, just slower
and on a longer time budget.

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
