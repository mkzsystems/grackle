# Grackle — Work plan

Drafted 9 October 2026 from [`DESIGN.md`](DESIGN.md) and
[`tasks/01-sync-and-board.md`](tasks/01-sync-and-board.md). The design decisions are settled
there; this document is the delivery plan: what ships in which milestone, the issue index with its
board order, the architecture for the first milestone at the level an execution session needs, the
CI gates, the test strategy, the deferred items and the decisions John confirms before the first
issue starts. It is written to the recommendations in bold in section 11; any other answer changes
the named issues only.

A ⚑ marks a deviation from, or an addition to, the task spec or `CLAUDE.md`.

## 1. What ships, in what order

| Milestone | Task spec | Release | Usable on its own as |
| --- | --- | --- | --- |
| M1.0 Sync and Board | `tasks/01-sync-and-board.md` | v0.1.0 | one board and one terminal list over every org, refreshed by `grackle sync` |
| M2.0 Dependencies and Scheduler | `tasks/02-…` (written in 1.12) | v0.2.0 | the same board with a critical path per milestone, a ranked queue of what can start now, and a forecast |
| M3.0 MCP Server and Dispatch | `tasks/03-…` (written in 1.12) | v0.3.0 | a Claude Code session that can ask for its task, claim it and attach its PR; dispatch from the board |

Each milestone is one epic; its issues are the PR train. M1.0 is serial (each PR builds on the
last). M2.0 starts when 1.12 has produced its spec and 1.9 has landed; M3.0 after 2.4 (the first
label writes) and once the board has been in daily use, as the design asks.

⚑ The task spec's "Done when: a PR is open against `main` with all criteria ticked" becomes the
**epic's** closing condition. The house rule is one issue, one branch, one PR, no stacking, so
M1.0 lands as twelve PRs; each ticks the criteria it satisfies in the task spec, and the screenshot
of the board with tasks from two orgs goes on the epic when 1.8 lands.

## 2. Release gate for v0.1.0

Measured, not asserted. All of these on earth (Fedora) and on the Mac, from the release archive,
against John's real configuration (section 3.7):

1. `grackle init`, `grackle sync`, `grackle serve` run in that order with no other setup than the
   token. The first sync completes and reports every repo, its counts, the points it cost and the
   quota left.
2. The second `grackle sync` finishes in under 60 s and under 100 points. The timing printed by the
   tool is checked against `time`.
3. The board shows tasks from at least two orgs in at least three columns; the `org`, `repo` and
   `milestone` filters narrow it; `grackle ls` with the same filters prints the same set as
   `GET /api/tasks` (checked by count and by the first and last row).
4. A planted fault (a repo in the config that does not exist; a token without `read:org`) makes
   `grackle sync` exit non-zero, name the repo, and leave every other repo's cursor advanced and the
   failed repo's cursor unchanged.
5. CI green on Linux and macOS; `make check` green locally on both.

## 3. Architecture for M1.0

The design's architecture table stands. This section is the level below it.

### 3.1 Packages and import rules

```
cmd/grackle               cobra root; subcommands wire internal/cli
internal/cli              one file per command: init, sync, serve, ls, version
internal/config           grackle.yaml model, load and validate, token resolution
internal/task             the domain: Task, Kind, State, Size; the label grammar; the derivation rules
internal/store            SQLite (modernc.org/sqlite): embedded migrations, upsert, query with filters
internal/source           the Source interface and its page and cursor types
internal/source/github    the GraphQL client, the query documents, rate limits, the recorder, labels → task
internal/syncer           a sync run: discovery, worker pool, cursors, the summary (⚑ see below)
internal/board            the HTTP server: templ pages, htmx partials, the JSON API, embedded static assets
```

⚑ `CLAUDE.md` lists five packages (`config`, `store`, `source`, `board`, `cli`). Two more are
needed: `task` holds the model that `store`, `source/github` and `board` all use, so none of them
has to import another for it; `syncer` holds the orchestration, which needs both `source` and
`store` and belongs in neither (`source` must not import `store`). It is `syncer`, not `sync`, to
avoid aliasing the standard library in every file that uses both. 1.2 updates `CLAUDE.md`.

Import rules, enforced by `depguard` in `.golangci.yml`:

- `internal/task` imports nothing under `internal/`.
- `internal/store` imports only `task`.
- `internal/source/github` is the only package that talks to GitHub; nothing else imports it except
  `syncer` and `cli`.
- `internal/board` imports `store` and `task`, never `source`, `syncer` or `config`; it is given a
  store and an address.

### 3.2 The model (`internal/task`)

```go
type Kind  string // "issue" | "pr"
type State string // needs-spec | agent-ready | in-flight | needs-review | done
type Size  string // "" | S | M | L

type Task struct {
    Repo        string    // owner/name
    Org         string    // owner
    Number      int
    Kind        Kind
    Title, Body string
    URL         string
    Author      string
    Labels      []string
    Assignees   []string
    Milestone   *Milestone
    IssueType   string    // GitHub issue type name, "" when none
    GitHubState string    // open | closed
    StateReason string    // completed | not_planned | reopened | duplicate | ""
    IsDraft     bool      // PRs
    MergedAt, ClosedAt, UpdatedAt, CreatedAt time.Time
    LinkedPRs   []Ref     // for issues: PRs whose closingIssuesReferences name this issue
    State       State     // derived; see below
    Size        Size      // from a size: label
}
```

The label grammar is the design's: `state:needs-spec`, `state:agent-ready`, `state:in-flight`,
`state:needs-review`; `size:S`, `size:M`, `size:L`. Matching is case-insensitive on the value
(`size:m` is M) and exact on the prefix. The derivation rules, in order, first match wins:

| Kind | Condition | State |
| --- | --- | --- |
| issue | closed | Done |
| issue | an open, non-draft linked PR exists (⚑) | Needs review |
| issue | exactly one `state:` label | that state |
| issue | two or more `state:` labels | Needs spec, and the conflict is reported by `sync` and shown on the card |
| issue | no `state:` label | Needs spec |
| pr (⚑) | merged or closed | Done |
| pr (⚑) | draft | In flight |
| pr (⚑) | open | Needs review |

⚑ The task spec maps issues only. Pull requests are synced too, and a board that hides them loses
the "Needs review" column's main content until M3.0 writes labels. ADR-0002 records this: PRs are
tasks of their own kind, and an issue with an open linked PR is in review whatever its label says,
because the label write-back that would say so arrives only in M3.0. An unknown `state:` value is
ignored and reported.

### 3.3 The store (schema v1)

One SQLite file, WAL mode, `busy_timeout` 5 s, foreign keys on, opened through
`modernc.org/sqlite` with these pragmas in the DSN. Timestamps are RFC 3339 UTC text (SQLite has
no datetime type; lexical order is time order). The file is created `0600`: it holds issue bodies
from private repos.

| Table | Columns (abridged) | Notes |
| --- | --- | --- |
| `repos` | `id`, `node_id` UNIQUE, `owner`, `name`, `name_with_owner` UNIQUE, `is_archived`, `pushed_at`, `issues_cursor`, `prs_cursor`, `last_synced_at` | keyed by node id so a rename updates the row |
| `milestones` | `id`, `repo_id`, `number`, `node_id` UNIQUE, `title`, `state`, `due_on`, `closed_at`, `updated_at` | |
| `tasks` | `id`, `repo_id`, `kind`, `number`, `node_id` UNIQUE, `title`, `body`, `url`, `author`, `labels` (JSON), `assignees` (JSON), `milestone_id` NULL, `issue_type`, `github_state`, `state_reason`, `is_draft`, `merged_at`, `closed_at`, `updated_at`, `created_at`, `size`, `label_state` | `label_state` is the state from labels alone; the PR override is applied in the query |
| `task_links` | `pr_task_id`, `issue_repo`, `issue_number` | from `closingIssuesReferences`; cross-repo capable, resolved at query time |
| `sync_runs` | `id`, `started_at`, `finished_at`, `ok`, `repos`, `failed_repos` (JSON), `upserted`, `points_used`, `remaining`, `reset_at`, `error` | the board header and the quota line read the last row |

Indexes: `tasks(repo_id, github_state)`, `tasks(milestone_id)`, `tasks(updated_at)`,
`task_links(issue_repo, issue_number)`.

Migrations are numbered SQL files under `internal/store/migrations/`, embedded, applied in a
transaction each, tracked with `PRAGMA user_version`. ⚑ Not goose, which gravel uses: it brings a
dependency tree for what is forty lines over a single-user file, and SQLite's own version pragma is
the natural ledger. Section 11 has the decision.

Bodies are stored now although nothing in M1.0 renders them: M3.0 assembles prompts from them, the
GraphQL cost does not change (cost counts nodes, not fields), and a second sync pass to add them
later would re-fetch everything.

### 3.4 The GitHub source

A hand-written client over `net/http`, ADR-0001: one `POST https://api.github.com/graphql`, the
query documents as `.graphql` files embedded beside the code, variables as a map, a typed response
struct per query, GraphQL `errors[]` surfaced with their `path` and `type` so a `NOT_FOUND` for one
repo is one repo's failure and not the run's. `User-Agent: grackle/<version>`.

Verified against the live schema on 9 October 2026 (fighters-legacy/fighters-legacy, 149 open
issues: one page with labels, milestone, assignees, the recent-closed set, open PRs with their
closing references, and all milestones cost **4 points** and took **1.9 s**):

- `repository.issues(filterBy: {since, states}, orderBy: {field: UPDATED_AT})` exists, and
  `issues` never returns pull requests (unlike REST).
- `repository.pullRequests` takes `states`, `labels`, `headRefName`, `baseRefName`, `orderBy` and
  pagination only: **there is no `since` filter for pull requests**. Incremental PR sync pages by
  `UPDATED_AT` descending and stops at the first node older than the cursor.
- `issue.issueType { name }`, `issue.stateReason`, `pullRequest.isDraft`,
  `pullRequest.closingIssuesReferences`, `milestones(states: [OPEN, CLOSED])` all resolve.
- `organization.repositories(isArchived: false, isFork: false, ownerAffiliations: [OWNER])` is
  the discovery query.

Rate limits: every query asks for `rateLimit { cost remaining resetAt }`. The client keeps a
reserve (100 points): when `remaining` falls below it the run stops cleanly with the reset time and
exit code 2, and no cursor moves for an unfinished repo. A 403 or 429 with `Retry-After` (the
secondary limit) sleeps for that long, at least 60 s, then retries once; a 5xx retries three times
with exponential backoff and jitter. The primary budget is 5,000 points an hour and the secondary
limit is 2,000 points a minute and 100 concurrent requests; at 4 points a page and four workers
neither is reachable.

The recorder: an `http.RoundTripper` that, under `go test -record` with a live token on a
developer's machine, writes each exchange to `testdata/<fixture>/<nn>.json` as the query's hash,
its variables and the response body, headers excluded, so no token can reach a fixture. Replay
matches by hash and variables and fails the test with a diff on a miss. CI never has a token.

Token resolution: the environment variable named by `token_env` (default `GITHUB_TOKEN`); ⚑ when it
is empty and `gh` is on the path, `gh auth token` (two-second timeout); otherwise an error that names
both. The token needs `repo` (private repos) and `read:org`. A fine-grained token scoped to the
listed orgs is the recommendation in section 11; John's `gh` token is shared with everything else
he runs and had 4,437 of 5,000 points left when measured.

### 3.5 The sync run (`internal/syncer`)

1. **Discovery.** Every non-archived, non-fork repo of each org in `orgs`, plus `repos`, minus
   `exclude`. A repo that is in the store but no longer configured is kept and hidden (the board
   and `ls` show configured repos only); `sync --prune` is a follow-on.
2. **Per repo**, four workers (`golang.org/x/sync/errgroup` with a limit), one request in flight
   per repo:
   - First run (no cursor): open issues, every page; closed issues with `since = now − 30 d`; open
     PRs, every page; merged and closed PRs by `UPDATED_AT` descending until older than 30 days;
     all milestones.
   - Incremental: issues with `since = cursor − 5 min` in both states; PRs by `UPDATED_AT`
     descending until older than `cursor − 5 min`; all milestones. The overlap absorbs clock skew
     between GitHub's `updatedAt` and the page's fetch time; upserts are idempotent so it is free.
   - The cursor is the greatest `updatedAt` seen for that repo and kind, written in the same
     transaction as the last page's upsert. Nothing seen means the cursor stays.
3. **Summary.** One line per repo (`owner/name  issues +12 ~3  prs +1  1.9 s`), totals, the quota
   line (`quota: 4,437 of 5,000 left, resets 17:24 UTC`), and elapsed. The counts come from the
   store's transaction results, not from response sizes. Any repo that failed is listed with its
   error, its cursors are untouched, and the exit code is 1; the run is never reported as a success
   with a failed repo in it. The last row of `sync_runs` records all of it.

Deleted and transferred issues are invisible to an incremental run (they stop appearing; nothing
says so). `sync --full` re-fetches the open set and closes rows that are gone; running it weekly is
documented and a timer is a follow-on.

### 3.6 The board (`internal/board`)

`grackle serve` binds **`127.0.0.1:7420`** (⚑ the spec says `localhost`; binding the IPv4 loopback
explicitly avoids the `localhost` → `::1` ambiguity on macOS, and the printed URL is
`http://127.0.0.1:7420`), flag `--addr`. Graceful shutdown on SIGINT and SIGTERM.

| Route | Returns |
| --- | --- |
| `GET /` | the board page; with `HX-Request` the board fragment only |
| `GET /api/tasks?org=&repo=&milestone=&state=&kind=` | JSON: `tasks[]`, `generated_at`, `last_sync` |
| `GET /api/repos` | JSON: configured repos with org, counts per state, last sync |
| `GET /api/milestones` (⚑ addition) | JSON: distinct milestones with counts; the filter dropdown's source |
| `GET /static/…` | embedded `app.css`, `vendor/htmx.min.js` |
| `GET /healthz` | 200 and the last sync's age |

Five columns in state order; cards carry the repo, the number as a link to GitHub, the title, the
size chip, the milestone chip, a PR badge (number and draft marker) for issues with an open linked
PR, and a conflict marker when two `state:` labels disagree. Within a column: milestone due date
ascending, then `updatedAt` descending. The filters are three `<select>`s in a `<form method="get">`
with a submit button; htmx enhances them (`hx-get="/"`, `hx-push-url`) so the page works without
JavaScript and the URL stays bookmarkable. The header shows the last sync's time and quota, and a
"stale" warning after an hour.

As in gravel (ADR-0005 there): htmx 2.0.11 is vendored by `make vendor-htmx` with its licence and
provenance file; the content security policy allows no inline script or style
(`default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'self'`);
htmx runs with `selfRequestsOnly` and without `eval`; templates are templ components under
`internal/board/templates`, generated Go committed, CI fails on drift; `make a11y` runs axe over the
rendered board and CI runs it with gravel's browser-driver recipe. ⚑ `serve --sync-every <d>` runs
the syncer in the background on that interval (the design's "polled every few minutes"); it is off
by default in M1.0, where `grackle sync` is the documented way.

### 3.7 Config and CLI

```yaml
# grackle.yaml, written by `grackle init`
orgs: []            # every non-archived, non-fork repo of each org
repos: []           # owner/name, added to the set
exclude: []         # owner/name, removed from the set            (⚑ addition)
token_env: GITHUB_TOKEN
db: grackle.db      # relative to this file                        (⚑ addition)
# sync:
#   closed_window: 720h   # how far back closed items are fetched on a first run
#   concurrency: 4
```

John's set, from the inventory of 9 October 2026 (section 11 confirms it):

```yaml
orgs: [mkzsystems, uio-project, fighters-legacy, terrella-project, astrocyte-project,
       hidden-token-gaming, gravel-project, galatea-labs]
repos: [jomkz/infra, jomkz/fighters-codex, jomkz/h2r-trackrabbit]
exclude: [fighters-legacy/.github, hidden-token-gaming/.github,
          fighters-legacy/fighters-legacy.github.io, mkzsystems/legal]
```

That is 28 repos today, 620 open issues and 45 open PRs across the orgs, 493 items updated in the
last 30 days. A first run is roughly 150–400 points; a warm run under 30. The 50-repo, 60-second
criterion is met with margin.

Commands (`cobra`), global flag `--config` (default `./grackle.yaml`, env `GRACKLE_CONFIG`):

| Command | Flags | Exit codes |
| --- | --- | --- |
| `grackle init` | `--force` to overwrite | 1 if the file exists |
| `grackle sync` | `--full`, `--repo owner/name` | 0, 1 any repo failed, 2 quota or auth |
| `grackle serve` | `--addr`, `--sync-every` | |
| `grackle ls` | `--org`, `--repo`, `--milestone`, `--state`, `--kind`, `--json` (⚑ addition) | 1 with a hint to run `sync` when there is no store |
| `grackle version` | | |

`ls` prints with `text/tabwriter`: `REPO`, `#`, `KIND`, `STATE`, `SIZE`, `MILESTONE`, `TITLE`.
`grackle.yaml` is not committed; the README carries the example.

## 4. Milestones, epics and issues

Three epics, one per milestone. *Order* follows the board convention `rank × 100 + position`, the
epic at `rank × 100 − 50`; *Effort* uses the framework's `XS`–`XL`. The component is the PR
title's scope and the `component:` label. Acceptance criteria are the issue body; this table is the
index. M2.0 and M3.0 are outlines: their epics are filed now, their issues when 1.12 has written
the specs (section 11).

### M1.0 Sync and Board: epic "One board over every org" (Order 50)

| # | Title | Component | Effort | Order |
| --- | --- | --- | --- | --- |
| 1.1 | chore(ci): adopt the pm-framework starter kit (`project.yml` with the components, state and size labels for this repo, labeler, issue forms, PR template, the labeler, pr-title-lint, auto-close-epics, project-sync and changelog workflows), `docs/project-management.md`, `CHANGELOG.md` | ci | S | 100 |
| 1.2 | build: Go module (`go 1.26.0`, `toolchain go1.26.9`), `cmd/grackle` with `version`, Makefile with pinned tools (golangci-lint v2.14.0, govulncheck v1.8.0, templ v0.3.1070, htmx 2.0.11 vendor target), `.golangci.yml` with the depguard rules of 3.1, `ci.yml` (go, lint, vuln, generate-check, cgo-check, macos), `.gitignore`, `.gitattributes`; `CLAUDE.md` package list | ci | S | 101 |
| 1.3 | feat(config): the `grackle.yaml` model, load and validate with precise errors, `grackle init`, token resolution with the `gh` fallback | cli | S | 102 |
| 1.4 | feat(task): the model, the label grammar, the derivation rules, table-driven tests for every row of 3.2 | task | S | 103 |
| 1.5 | feat(store): SQLite store, schema v1, embedded migrations, upsert and query with filters, tests on a temp file | store | M | 104 |
| 1.6 | feat(source): the `Source` interface, the GitHub GraphQL client, the queries, rate-limit handling and backoff, the recorder and replayer, repo discovery, labels to task | source | L | 105 |
| 1.7 | feat(syncer): `grackle sync` first and incremental runs, the worker pool, cursors, the summary and quota line, integrity rules; the integration test on recorded fixtures from two orgs | sync | L | 106 |
| 1.8 | feat(board): `grackle serve`, the board page and fragment, filters, vendored htmx, CSP, templ generation, the a11y job, `--sync-every` | board | L | 107 |
| 1.9 | feat(api): `GET /api/tasks`, `/api/repos`, `/api/milestones`; `grackle ls` with the same filters and `--json` | board | M | 108 |
| 1.10 | docs: README for users (install, token, config, the three commands, a screenshot), tick the task-1 criteria, screenshot on the epic | docs | S | 109 |
| 1.11 | build(release): goreleaser (linux and darwin, amd64 and arm64 archives, checksums, SBOM, cosign keyless), `release.yml`, `docs/releasing.md`, the release gate of section 2, tag `v0.1.0` | ci | M | 110 |
| 1.12 | docs(tasks): the agent-ready specs `tasks/02-dependencies-and-scheduler.md` and `tasks/03-mcp-and-dispatch.md` from the outlines below, against the real model | docs | M | 111 |

1.1 to 1.11 are serial. 1.12 can start after 1.7 and must land before M2.0's issues are filed.

### M2.0 Dependencies and Scheduler: epic "What can start now, and when does it land" (Order 150)

| # | Title | Component | Effort |
| --- | --- | --- | --- |
| 2.1 | feat(task): the `blocked-by:owner/repo#N` grammar, a `task_deps` table, cross-repo resolution, dangling references surfaced on the card and in `sync` | task | M |
| 2.2 | feat(graph): `internal/graph`: build the DAG per milestone, detect cycles, topological order, longest path by size (S, M, L as half a day, one day, three days), the unblocked set; property tests | sync | M |
| 2.3 | feat(sched): ranking by downstream unblock count then milestone date, the `capacity` setting, the forecast per milestone at that parallelism, the needs-spec flag on a critical path | sync | M |
| 2.4 | feat(source): the first writes, behind a dry-run default and `--yes`: `grackle labels ensure` creates the state and size labels in every configured repo; `grackle set` writes state, size and blocked-by labels, updating the row optimistically and confirming on the next sync | source | M |
| 2.5 | feat(board): the graph view per milestone, the queue view, the programme rollup with forecast dates, inline state and size edits | board | L |
| 2.6 | feat(api): dependency, queue and forecast endpoints; `grackle next`, `grackle block` | board | M |
| 2.7 | docs and release v0.2.0 | docs | S |

### M3.0 MCP Server and Dispatch: epic "A session can ask for its task" (Order 250)

| # | Title | Component | Effort |
| --- | --- | --- | --- |
| 3.1 | feat(mcp): `grackle mcp`, a stdio MCP server on the official Go SDK (`modelcontextprotocol/go-sdk` v1.8.0): `list_tasks`, `get_task`, `claim_task` (to In flight), `attach_pr`; the `.mcp.json` snippet | mcp | L |
| 3.2 | feat(dispatch): prompt assembly from the issue body, acceptance criteria, the repo's `CLAUDE.md` and linked context; a worktree under a configured root; launch the `claude` CLI; state to In flight | sync | L |
| 3.3 | feat(track): a PR naming the issue moves it to Needs review with the diff summary and the `statusCheckRollup` inline; the bounce counter and its flag | sync | M |
| 3.4 | feat(board): the dispatch action, session status, the review panel | board | L |
| 3.5 | docs and release v0.3.0 | docs | S |

## 5. CI gates

Every PR runs, on `ubuntu-latest` unless noted. The Makefile is the source of truth for tool
versions and `make check` runs everything CI runs except the macOS and a11y jobs.

| Job | What it runs | Satisfied by |
| --- | --- | --- |
| `go` | `make fmt-check mod-check vet build cgo-check test` (`go test -race -count=1 ./...`) | gofmt-clean, tidy `go.mod`, vet-clean, no cgo in any dependency and a `CGO_ENABLED=0` build for linux and darwin on amd64 and arm64, tests green |
| `macos` | `make build test` on `macos-latest` (free: the repo is public) | the same, on the Mac's platform |
| `lint` | golangci-lint v2.14.0 with the depguard rules of 3.1 | the import rules hold |
| `vuln` | `govulncheck ./...` | no known vulnerable path |
| `generate-check` | `templ generate` then a clean tree over `internal/board/templates` | generated Go committed |
| `a11y` | axe over the rendered board, gravel's browser-driver recipe (from 1.8) | no violations |
| `changelog` | a `CHANGELOG.md` line added under `[Unreleased]`, or the `no-changelog` label (viceroy's workflow) | one entry per closed issue |
| `pr-title-lint` | Conventional Commit title, lowercase subject | from the framework |
| `labeler` | `component:*` by path | advisory |
| `project-sync` | on `main` pushes touching `.github/project.yml` | needs `PROJECT_ADMIN_TOKEN` |
| `release-config` | `goreleaser check` (from 1.11) | the release config parses |

Not on every PR: `release` on `v*` tags (1.11), which pins `sigstore/cosign-installer@v4.1.2`
exactly because no floating `v4` tag exists, and runs at the tag's commit, so `main` must carry the
fix before a re-tag.

The ruleset on `main` mirrors gravel's: pull request required, squash only, linear history, no
deletion, no force push. Section 11.

## 6. Test strategy

Unit tests by package, table-driven, next to the code; the integration test on recorded fixtures.
The edge cases each issue must cover, not only the happy path:

- *Label grammar and derivation (1.4):* no label; one of each state; two state labels (conflict
  reported, Needs spec); an unknown `state:` value (ignored, reported); `size:m` and `Size:M`
  (case on the value only); a closed issue with `state:agent-ready` (Done wins); an open issue
  with a draft linked PR (label state stands) and with an open one (Needs review); a PR that is
  draft, open, merged, closed unmerged; an issue whose linked PR is in another repo.
- *Config (1.3):* missing file; a repo without a slash; an org listed twice; an exclude that is not
  in the set (warning, not error); `token_env` naming an unset variable with and without `gh` on the
  path; `db` relative and absolute; `init` on an existing file with and without `--force`.
- *Store (1.5):* upsert twice is one row; a repo rename (same node id) updates `name_with_owner`;
  a milestone removed from an issue sets `milestone_id` null; labels beyond the first page (the
  query asks for 50; more is reported); a query with every filter empty, with an unknown state
  (error), with a milestone title shared by two repos (both); ordering is stable across runs; the
  PR override applies through `task_links` to an issue in another repo; migrations apply from
  zero and are idempotent at the current version; a store at a newer version than the binary is
  refused with a clear message.
- *Client (1.6):* a response with `errors[]` and partial `data` (one repo `NOT_FOUND`: that repo
  fails, the others proceed); a 401 (exit 2, names the token source); a 403 with `Retry-After`
  (sleeps, retries once, then fails); a 429; a 502 (three backoffs then fail); `remaining` under
  the reserve before a page (stops cleanly, cursor unchanged); the replayer on a query hash
  mismatch (fails with a diff); the recorder writes no header.
- *Syncer (1.7):* a first run; an incremental run with no changes (cursors unchanged, cost 1 per
  repo); an item updated inside the overlap window (upserted again, one row); a repo added to the
  config between runs (first run for that repo only); a repo archived between runs (skipped,
  reported); a failure on page two of three (cursor unchanged, pages one and two's rows kept
  because upserts are idempotent); the worker pool never exceeds its limit (a counting fake
  source); PR paging stops at the cursor on an exact `updatedAt` tie; milestones closed between
  runs.
- *Board and API (1.8, 1.9):* an empty store (the page renders, every column empty, the header
  says never synced); a filter value that matches nothing (empty columns, the filter stays
  selected); an unknown `state` query value (400 with a message); `HX-Request` returns the fragment
  and a plain request the page; the CSP header on every response; the static route serves the
  vendored htmx with its hash; `ls` and `/api/tasks` agree on the same filters (one test drives
  both from one store); `--json` output round-trips through the API's types.
- *Measurement integrity (1.7, section 2):* `sync` refuses to print the summary's "ok" line if any
  repo failed, counts from the store not the responses, and prints the configuration it ran
  against (repo count, workers, windows) beside the numbers.

The integration test: fixtures recorded from two orgs (one of them `mkzsystems`, so grackle's own
issues are on the board), a first run then an incremental run into a temp store, then the API and
the rendered board checked against golden JSON and a few HTML assertions.

## 7. Documentation

| File | Change |
| --- | --- |
| `README.md` | this PR: links this plan; 1.10 rewrites it for users (install from the release archive, the token and its scopes, the config example of 3.7, the three commands, a screenshot) |
| `CLAUDE.md` | this PR: points at this plan; 1.2: the package list of 3.1 and the Makefile line (`make check` before every PR, `make generate` after a `.templ` edit) |
| `docs/DESIGN.md` | unchanged; the design stands. Its "still to do: write the org names and the allowlist into the config" is done by 3.7 and the README |
| `docs/tasks/01-sync-and-board.md` | criteria ticked by the PR that satisfies each; the "Done when" reading of section 1 noted at the top |
| `docs/tasks/02-…`, `docs/tasks/03-…` | 1.12 |
| `docs/adr/0001`, `docs/adr/0002` | this PR, *Proposed*; *Accepted* on approval |
| `docs/project-management.md` | 1.1, from the framework's org edition, with the state and size labels explained |
| `docs/releasing.md` | 1.11, from gravel's |
| `CHANGELOG.md` | 1.1, Keep a Changelog, `[Unreleased]` from then on, one entry per closed issue |

## 8. Deferred items and follow-on issues

Filed on approval as `backlog` with their eventual milestone, so nothing lives in a TODO file:

- **Webhooks** (design: "optional"): a `grackle serve` endpoint for `issues`, `pull_request` and
  `milestone` events, needs a public URL; polling covers the MVP.
- **`sync --prune` and a timer:** remove rows of repos no longer configured; a systemd user timer
  on earth and a launchd agent on the Mac for `sync` every few minutes and `sync --full` weekly.
- **The `search` API as a cross-repo incremental path:** one query per org for everything updated
  since a time, instead of one per repo; capped at 1,000 results and its own rate limit, so it is
  an optimisation to measure, not a default.
- **Projects v2 fields as a second source of state and size:** every org on the pm-framework
  already has Status and Effort on its board; reading them when no label is present would make the
  board right without label writes. Needs a decision against the design's "labels survive without
  the tool".
- **GitHub App installation token instead of a personal token**, with its own rate limit.
- **Non-GitHub sources** (markdown task files, GitLab), per the design: after M3.0.
- **Remote dispatch from the phone** (design): after local worktrees work.
- **Windows build:** `CGO_ENABLED=0` makes it free; not a target of `CLAUDE.md`, so it is not
  tested until someone needs it.
- **Packaging:** a Homebrew tap and a COPR, after v0.1.0 has been used from the archive.
- **Transferred and deleted issues detected incrementally:** needs the REST events feed or a
  periodic full reconcile; `sync --full` is the MVP answer.

## 9. Platform notes

- **Go:** `go 1.26.0` with `toolchain go1.26.9` as gravel and semblance; earth runs
  `GOTOOLCHAIN=local` with Go 1.26.8, which builds this (the `go` line is the floor), and CI gets
  1.26.9 from `go.mod` through `actions/setup-go`. `CLAUDE.md`'s "Go 1.23+" is a floor, kept.
- **SQLite:** `modernc.org/sqlite` v1.60.1 is pure Go on linux and darwin, amd64 and arm64;
  `CGO_ENABLED=0` for the shipped binary, `CGO_ENABLED=1` only for `go test -race`, which both
  runners can do. WAL on APFS and on Btrfs is fine; the DB and its `-wal`/`-shm` siblings sit next
  to the config.
- **Network:** bind `127.0.0.1`, print that URL; no `localhost` resolution on either OS.
- **Paths:** the config path is made absolute at load; `db` resolves against the config's
  directory; no `~` expansion (documented). The DB is created `0600`; the config `0644` (it holds
  no secret).
- **Time:** RFC 3339 UTC in the store and the API; local time in `ls` and on the board.
- **The `gh` fallback** works on both OSs; a two-second timeout keeps a hung keyring prompt from
  hanging `sync`.
- **templ:** generated `*_templ.go` committed, `linguist-generated` in `.gitattributes`, golangci's
  generated-file exclusion on; `make generate` after any `.templ` edit (gravel's lesson).
- **htmx:** 2.0.11, vendored. htmx 4.0.0 is published and is a different API; not for now.
- **Actions:** `actions/checkout@v7`, `actions/setup-go@v7`, `golangci/golangci-lint-action@v9`,
  `actions/labeler@v5`, `amannn/action-semantic-pull-request@v5`, `goreleaser/goreleaser-action@v7`,
  `sigstore/cosign-installer@v4.1.2`, each resolved as an existing ref before use.

## 10. Risks and the mitigation built into the plan

1. **The token's budget is shared.** John's `gh` token serves every other tool he runs. The reserve,
   the quota line and exit code 2 keep a sync from eating the budget silently; a fine-grained token
   of grackle's own (section 11) removes the sharing.
2. **Label writes in M2.0 touch thirty repos.** Dry-run by default, `--yes` to apply, one line per
   change, and `labels ensure` creates only the seven known labels.
3. **Private content in a local file.** `0600`, documented; the file is not in any backup set until
   John puts it in one.
4. **The board's "Needs review" column depends on `closingIssuesReferences`.** A PR that does not
   name its issue is a card of its own in that column, so it is never lost; the M3.0 tracker adds
   the link from the branch name.
5. **Schema drift on GitHub's side.** Fixtures are recorded exchanges; a `make record` target with
   a live token re-records them, and the plan says to re-record when a query changes.
6. **The empty-board effect.** No repo has `state:` labels yet, so until M2.0's `labels ensure`
   every open issue is Needs spec. grackle's own repo gets the labels from `project.yml` in 1.1 and
   its seeded issues carry them, so the board shows real states from the first sync, in two orgs
   once John labels a handful of issues elsewhere by hand.
7. **A second tool called grackle.** John's own `jomkz/grackle` (2019, a tweet ingester) and
   `jomkz/grackle-operator` sit in `gh` search results beside this one. Section 11.

## 11. Decisions John confirms before execution starts

The plan is written to the recommendation in bold; any other answer changes the named issues only.

| Decision | Recommendation | Alternative | Changes |
| --- | --- | --- | --- |
| Go version | **`go 1.26.0`, `toolchain go1.26.9`** (gravel, semblance) | `go 1.23` as the spec's floor | 1.2 |
| GitHub client | **hand-written over `net/http`, embedded query documents, recorded exchanges as fixtures** (ADR-0001) | `shurcooL/githubv4` (typed, manual pagination, last release February 2026); `cli/go-gh` | 1.6, 1.7 |
| Pull requests | **synced as tasks of their own kind; an issue with an open linked PR is Needs review** (ADR-0002) | issues only, PRs invisible until M3.0 | 1.4, 1.5, 1.8 |
| Token | **`token_env`, then `gh auth token`**; a fine-grained token for grackle named by `token_env: GRACKLE_GITHUB_TOKEN` in John's config | environment only; the shared `gh` token | 1.3, 1.10 |
| Config set | **the eight orgs, three personal repos and four excludes of 3.7** | all of `jomkz` (fifty repos, most dormant) | the README example, the release gate |
| Migrations | **embedded SQL with `PRAGMA user_version`** | goose, as gravel | 1.5 |
| The board | **a new org project "Grackle 1.0" created by GraphQL with Effort `XS`–`XL`, Order, Start Date, Target Date** (as semblance, 9 October) | copy the `[TEMPLATE] MKZ Project v1` board (#10), whose Effort is High/Medium/Low | 1.1, seeding |
| Ruleset on `main` | **gravel's: PR required, squash only, linear history, no deletion or force push**, set now (public repos get rulesets on the free plan) | none until v0.1.0 | John sets it in the UI, or the execution session does with his token |
| Licence | **none for now, as gravel and astrocyte** (public, all rights reserved); decided before v0.1.0 | Apache-2.0 now | 1.2, 1.11 |
| M2.0 and M3.0 issues | **epics now, issues when 1.12 has the specs** | all now from the outlines | seeding |
| Background sync | **`serve --sync-every`, off by default** | not in M1.0 | 1.8 |
| `jomkz/grackle` (2019) | **archive it and rename it `grackle-tweets`**, with `grackle-operator` | leave both | nothing in this repo |
| Package names | **`task` and `syncer` added to `CLAUDE.md`'s list** | fold `task` into `source` and `syncer` into `cli` | 1.2 |

## 12. What the execution session does first, on approval

1. Flip the two ADRs to *Accepted* and merge this PR.
2. Create the org project "Grackle 1.0" with its four fields by GraphQL. John, in the UI: the
   three views (Roadmap, Board, Open Items), the auto-add workflow **including pull requests**
   (semblance's board matched issues only until John widened it), the `PROJECT_ADMIN_TOKEN` secret,
   the ruleset on `main`.
3. Issue 1.1: adopt the framework; `project-sync.sh` creates the labels (components, meta, and the
   seven state and size labels) and the three milestones.
4. Seed the three epics and the twelve M1.0 issues from section 4 by an idempotent scratchpad
   script (reuse by exact title, Order numbers, parent links, Effort, the state and size labels on
   grackle's own issues); file the section 8 follow-ons as `backlog`.
5. Issue 1.2 onwards, one PR each, `make check` before every PR, a CHANGELOG entry per issue, the
   task spec's criteria ticked as they are met.
