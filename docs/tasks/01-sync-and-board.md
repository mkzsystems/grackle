# Task 1: GitHub sync and board

Build the first usable slice of Grackle: a Go binary that syncs issues, PRs and milestones from configured GitHub orgs and repos into SQLite and serves a local board showing every task's readiness state across all of them. No scheduler, dependencies or agent dispatch yet.

## Context

- New repo `grackle`, Go 1.23+, single module, `cmd/grackle` as the entrypoint.
- Read `docs/DESIGN.md` before starting; this task is the first of the three MVP steps.
- Readiness states come from labels: `state:needs-spec`, `state:agent-ready`, `state:in-flight`, `state:needs-review`. A closed issue is Done. An open issue with no `state:` label is treated as Needs spec.
- Sizes come from labels `size:S`, `size:M`, `size:L`; absent means unsized.
- Keep a backend interface (`Source`) between sync and store so a second backend can be added later, but implement only GitHub.

## Acceptance criteria

- [ ] `grackle init` writes a starter `grackle.yaml` with `orgs: []`, `repos: []` and `token_env: GITHUB_TOKEN`
- [ ] `grackle sync` pulls all open and recently closed (30 days) issues, PRs and milestones for every repo in the listed orgs plus the explicit repo allowlist, via the GitHub GraphQL API, and upserts into `grackle.db` (SQLite, `modernc.org/sqlite`, no CGO)
- [ ] Sync is incremental after the first run, using `updatedAt` cursors per repo, and finishes in under 60 s for 50 repos on a warm cache
- [ ] `grackle serve` starts an HTTP server on `localhost:7420` with a board page: columns per readiness state, cards showing repo, number, title, size and milestone, filterable by org, repo and milestone
- [ ] A JSON API backs the board: `GET /api/tasks` (same filters as query params) and `GET /api/repos`
- [ ] `grackle ls` prints the same task list to the terminal in a table, same filters as flags
- [ ] Rate-limit handling: back off on secondary rate limits and surface remaining quota in `grackle sync` output
- [ ] Unit tests for the label-to-state mapping and the incremental cursor logic; one integration test against recorded GraphQL fixtures
- [ ] README with install, config and the three commands

## Constraints

- Server-rendered UI with `templ` + htmx; no JavaScript build step.
- Standard library HTTP; `cobra` for the CLI is fine.
- No writes to GitHub in this task; read-only sync.
- Config, DB and token handling must work on Fedora Linux and macOS.

## Out of scope

- Dependencies (`blocked-by`), scheduler, forecasts, MCP server, agent dispatch, label writes, non-GitHub sources.

## Done when

A PR is open against `main` with all criteria ticked, CI green, and a screenshot of the board showing tasks from at least two orgs.
