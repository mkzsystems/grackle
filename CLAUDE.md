# Grackle: notes for Claude Code sessions

Read `docs/DESIGN.md` first, then `docs/plan.md` (milestones, the issue index, the implementation decisions) and `docs/adr/`. Each task spec in `docs/tasks/` is self-contained: context, acceptance criteria, constraints, out-of-scope. Work the lowest-numbered unfinished task unless told otherwise.

## Conventions

- Go 1.26 (`go 1.26.0`, `toolchain go1.26.9` in `go.mod`), single module `github.com/mkzsystems/grackle`, entrypoint `cmd/grackle`.
- Packages under `internal/` (docs/plan.md section 3.1):
  - `task`: the model, the label grammar, the state derivation; imports nothing under `internal/`
  - `config`: `grackle.yaml`, validation, token resolution
  - `store`: SQLite; imports only `task`
  - `source`: the backend interface; `source/github` the GitHub adapter, imported only by `syncer` and `cli`; a source never imports `store`
  - `syncer`: a sync run (discovery, workers, cursors, the summary)
  - `board`: HTTP + templ + the JSON API; imports `store` and `task` only
  - `cli`: one file per command
  These import rules are `depguard` rules in `.golangci.yml`; change the rule with the design, never around it.
- SQLite via `modernc.org/sqlite`; no CGO anywhere.
- UI is server-rendered with templ + htmx. No JavaScript build step, no npm.
- Build: the Makefile pins every tool into `.bin/` and is the source of truth for their versions; `make help` lists the targets and `make check` runs everything CI runs on Linux. Run it before every PR. A `.templ` edit needs `make generate`; the generated `*_templ.go` is committed and CI fails on drift. htmx is vendored by `make vendor-htmx`, never loaded from a CDN.
- `cobra` for the CLI is fine; standard library `net/http` for the server.
- Tests next to the code; integration tests use recorded GraphQL fixtures under `testdata/`, never live GitHub.
- Must build and run on Fedora Linux and macOS.

## Working style

- Open a PR against `main` per task; do not push to `main` directly.
- Tick the acceptance criteria in the task spec as part of the PR.
- Every PR adds a `CHANGELOG.md` line under `[Unreleased]` (the `changelog` check), or carries the `no-changelog` label.
- Keep the `Source` interface minimal and let it grow from the GitHub adapter; do not design for backends that do not exist yet.
- No writes to GitHub until the task spec says so.
