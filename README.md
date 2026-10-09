# Grackle

A control tower for personal projects spread across many GitHub orgs and repos.

Grackle syncs issues, PRs and milestones from every org and repo you point it at into a local SQLite file, shows them on one board with a readiness state per task, and (later) plans what gets done when and hands agent-ready work to Claude Code sessions. GitHub stays the source of truth; Grackle is a lens and a planner over it.

## Status

Design complete, implementation not started. See:

- [`docs/DESIGN.md`](docs/DESIGN.md), the design doc and settled decisions
- [`docs/tasks/`](docs/tasks/), agent-ready specs for each MVP step, in order
- [`docs/plan.md`](docs/plan.md), the work plan: milestones, the issue index, CI gates, tests and the decisions to confirm
- [`docs/adr/`](docs/adr/), decision records for choices the design doc leaves open

## Planned shape

- Single Go binary: `grackle init`, `grackle sync`, `grackle serve`, `grackle ls`
- SQLite store, no CGO
- Server-rendered board with templ and htmx, no JS build step
- Task state and size live as GitHub labels (`state:agent-ready`, `size:M`, `blocked-by:owner/repo#123`)
- MCP server so Claude Code sessions can read and update tasks directly

## MVP steps

1. GitHub sync and board
2. Cross-repo dependencies and scheduler
3. MCP server and agent dispatch

Each step is usable on its own.
