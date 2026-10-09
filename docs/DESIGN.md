# Grackle — Design Doc

Drafted 8 Oct 2026. Decisions in the final section are settled; see docs/tasks/ for agent-ready specs.

## Problem

John's work is spread across many GitHub repos and orgs (fighters-legacy, Torella, UIO, TrackPro, gravel, Semblance, Viceroy and more), and no single view shows what is next, what is blocked, and what an agent could pick up today.

GitHub Issues and Projects work per repo or per org, not across all of them. Jira and similar tools solve this for teams at the cost of heavy ceremony that a solo developer never recoups.

Grackle is that tool, a control tower: one place to see every project's state, plan what gets done when, and hand agent-ready work to Claude Code sessions.

## Principles

GitHub stays the source of truth; the tool is a lens and a planner over it, never a second place to maintain.

- Local-first: a single binary and a SQLite file, no hosted service required.
- Thin: sync issues, PRs, milestones and labels; add only what GitHub lacks (cross-repo dependencies, readiness, scheduling).
- Write-through: anything edited in the tool (state, dependencies) is stored as GitHub labels or issue metadata where possible, so other tools still see it.
- Agent-native: every task carries enough spec for a Claude Code session to start without a conversation.

## Core model

A task is a GitHub issue plus three things GitHub does not track across repos: a readiness state, dependencies, and a target window.

| Readiness state | Meaning | Who moves it on |
| --- | --- | --- |
| Needs spec | Idea or bug noted; not enough detail for anyone to start | John writes the spec |
| Agent-ready | Spec, acceptance criteria and repo context are complete | Scheduler or John dispatches it |
| In flight | A Claude Code session or John is working on it | The worker opens a PR |
| Needs review | PR open; waiting on John's judgement | John reviews and merges |
| Done | Merged and closed | Sync from GitHub |

Dependencies link any two tasks across any repos ("blocked by"). Milestones group tasks per project with a target date, and a programme-level view rolls milestones up across all projects.

States and dependencies are stored as issue labels (`state:agent-ready`, `blocked-by:owner/repo#123`), so they survive without the tool.

## Planning

Planning answers two questions: what can start now, and when will each milestone land given how much runs in parallel.

1. The dependency graph per milestone shows the critical path across repos; a task is unblocked when every blocked-by task is Done.
2. The scheduler lists unblocked Agent-ready tasks, ranked by how many downstream tasks they unblock, then by milestone date.
3. A capacity setting (for example, three concurrent agent sessions and one of John) drives a rough forecast: milestone date = longest chain of remaining tasks at the configured parallelism.
4. The Needs-spec queue is John's own to-do list: the forecast flags any milestone where the critical path runs through an unspecified task.

Forecasts use a simple size on each task (S, M, L mapped to half a day, one day, three days) rather than hour estimates; precision beyond that is false.

## Agent integration

From the board, one action dispatches an Agent-ready task to a Claude Code session; the session works in a Git worktree and reports back through the PR.

1. Dispatch: the tool assembles a prompt from the issue body, acceptance criteria, repo conventions (CLAUDE.md) and linked context, and starts a Claude Code session (Dispatch remotely from the phone, or a local worktree on the Mac).
2. Track: the task moves to In flight; the tool watches for a PR referencing the issue and surfaces session status.
3. Review: when the PR opens, the task moves to Needs review with the diff summary and CI result inline; John merges or sends it back with a comment that becomes the next prompt.
4. Learn: tasks that bounce back more than once are flagged so the spec template improves.

The tool never merges on its own; review stays with John.

## Architecture

A single Go binary serves a local web UI and syncs GitHub into SQLite; the same binary is the CLI.

| Layer | Choice | Why |
| --- | --- | --- |
| Sync | GitHub GraphQL API + webhooks (optional), polled every few minutes | GraphQL pulls issues, PRs, milestones and labels across orgs in few calls |
| Store | SQLite via `modernc.org/sqlite` | Single file, no CGO, easy backup |
| Graph and scheduler | Pure Go package, no external deps | Topological sort and longest-path are small; keep it testable |
| API | HTTP + JSON on localhost | Lets the UI, CLI and Claude Code hooks share one surface |
| UI | htmx + templ server-rendered pages | No frontend build step; board, graph and queue views |
| Agent bridge | Shell out to `claude` CLI or call Dispatch; MCP server exposing the task list | Claude sessions can read and update tasks directly |
| Config | One YAML file listing orgs, repos and capacity | Add a repo by adding a line |

The MCP server is the piece that makes the tool agent-native: a Claude Code session can ask "what is my task", mark it In flight, and attach the PR, with no custom glue per repo.

## Open questions and MVP scope

The MVP is the cross-repo board plus the scheduler; agent dispatch comes second, once the board is in daily use.

- [x] Decided: Grackle (binary `grackle`); only notable collision is an astrophysics chemistry library, different world
- [x] Decided in principle: sync all personal orgs and all business orgs, plus a hand-picked allowlist of personal repos (not every repo under the user). Confirmed starters: fighters-legacy, Torella, UIO, TrackPro. Still to do: write the org names and the personal-repo allowlist into the config
- [x] Decided: labels store state and dependencies (work across all orgs, survive without the tool)
- [x] Decided: dispatch runs in local worktrees on the Mac for the MVP; remote Dispatch from the phone comes later
- [x] Decided: task sizes (S/M/L) are stored as `size:` labels on GitHub. Grackle defines its own metadata (state, size, blocked-by) and each backend adapter decides where it lives: labels on GitHub and GitLab, a front-matter block per task in markdown files
- [x] Decided: non-GitHub sources (markdown task files for the RV builds, GitLab) are deferred past the MVP. Build the GitHub adapter first and let the backend interface emerge from it

MVP in three steps: sync and board (one week), dependencies and scheduler (one week), MCP server and dispatch (one week). Each step is usable on its own.

Agent-ready spec for the first MVP step: [Task 1: Sync and board](tasks/01-sync-and-board.md).
