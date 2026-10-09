# Grackle: notes for Claude Code sessions

Read `docs/DESIGN.md` first, then `docs/plan.md` (milestones, the issue index, the implementation decisions) and `docs/adr/`. Each task spec in `docs/tasks/` is self-contained: context, acceptance criteria, constraints, out-of-scope. Work the lowest-numbered unfinished task unless told otherwise.

## Conventions

- Go 1.23+, single module `github.com/mkzsystems/grackle`, entrypoint `cmd/grackle`.
- Packages under `internal/`: `config`, `store` (SQLite), `source` (backend interface + `source/github`), `board` (HTTP + templ), `cli`.
- SQLite via `modernc.org/sqlite`; no CGO anywhere.
- UI is server-rendered with templ + htmx. No JavaScript build step, no npm.
- `cobra` for the CLI is fine; standard library `net/http` for the server.
- Tests next to the code; integration tests use recorded GraphQL fixtures under `testdata/`, never live GitHub.
- Must build and run on Fedora Linux and macOS.

## Working style

- Open a PR against `main` per task; do not push to `main` directly.
- Tick the acceptance criteria in the task spec as part of the PR.
- Keep the `Source` interface minimal and let it grow from the GitHub adapter; do not design for backends that do not exist yet.
- No writes to GitHub until the task spec says so.
