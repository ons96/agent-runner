# agent-runner rules

- Public repo. NEVER commit provider keys, API tokens, or any value
  matching `sk-`, `gho_`, `nvapi-`, `AIza`, `gsk_`, `pplx-`, `fe_oa_`.
- Secrets live in repo Settings -> Secrets (encrypted at rest) or repo
  Variables (plaintext, low-risk overrides only). Never in code.
- Workflow files must pass `gitleaks` locally before push.
- Single-purpose: hourly digest + optional forward-dispatch. Adding
  workflows that run `opencode` or shell out to model APIs here is
  explicitly rejected; see REPO.md for rationale.
- The hourly cron must remain at or under once per hour. Tightening is
  fine; loosening burns free minutes.
- This repo MUST stay under 1MB total. No fixtures, no binaries, no
  node_modules.
