# Project Management

How work is planned, tracked and prioritised in this repository. It follows the GitHub-native
**pm-framework** so there is one reference; the full spec, editions and rationale live in the
[pm-framework hub](https://github.com/mkzsystems/pm-framework).

> This repo uses the **`org` edition**. The desired state of labels, milestones, issue types and
> board fields lives in [`.github/project.yml`](../.github/project.yml) and is reconciled by
> [`scripts/project-sync.sh`](../scripts/project-sync.sh), non-destructively.

## Two axes: Phase × Epic

- **Phase = *when*:** a milestone per MVP step of [`DESIGN.md`](DESIGN.md). Match milestones by
  title prefix (`M1.0`), never by API number. Every issue gets its phase at triage; unscheduled
  work gets `backlog` and no milestone, with its eventual home named in the body.

| Milestone | Scope | Release |
| --- | --- | --- |
| M1.0 Sync and Board | sync every configured org into SQLite; the board, the JSON API, `grackle ls` | v0.1.0 |
| M2.0 Dependencies and Scheduler | `blocked-by` across repos, critical path, the queue, the forecast, label writes | v0.2.0 |
| M3.0 MCP Server and Dispatch | the MCP server, dispatch to a worktree, PR tracking | v0.3.0 |

  The plan behind the milestones is [`plan.md`](plan.md); its section 4 is the issue index.
- **Epic = *which initiative*:** one per milestone, decomposed into native sub-issues; the
  board's Sub-issues progress field rolls up. M2.0's and M3.0's issues are filed when issue 1.12
  has written their task specs.

## Kind of work

Set exactly one GitHub **issue type** on every issue (the source of truth): **Epic / Feature /
Task / Spike / Bug**. There are no `type:*` labels.

## Labels

Declared in [`.github/project.yml`](../.github/project.yml), four families:

- **`component:*`:** the package touched (`ci`, `cli`, `task`, `store`, `source`, `sync`,
  `board`, `mcp`, `docs`); mirrors the Conventional-Commit scope; auto-applied to PRs by
  [`.github/labeler.yml`](../.github/labeler.yml).
- **Grackle's task metadata:** `state:needs-spec`, `state:agent-ready`, `state:in-flight`,
  `state:needs-review` and `size:S`, `size:M`, `size:L`, the grammar Grackle reads from every repo
  it syncs ([ADR-0002](adr/0002-pull-requests-are-tasks-and-states-are-derived.md)). This repo
  dogfoods them: each open issue carries one `state:` label and, when sized, one `size:` label. A
  closed issue is Done, so there is no `state:done`. Move the label when the work moves; until
  M3.0 nothing moves it automatically, though an open PR that closes an issue already shows it in
  review on Grackle's board.
- **RFC workflow:** `rfc` + `status: under-discussion|accepted|rejected|implemented`, reserved for
  public contracts once frozen.
- **Meta:** `epic`, `backlog`, `needs-triage`, `needs-info`, `needs-decision`, `blocked`,
  `no-changelog`, `release`.

No `phase-*` labels (milestones are the phases); no priority labels (the Order field ranks).

## The board

The [Grackle 1.0 board](https://github.com/orgs/mkzsystems/projects/14) (#14) holds every open
item. Fields: **Status** (`Todo`/`In Progress`/`Done`), **Effort** (`XS`–`XL`, set at filing),
**Order** (number), **Start Date**, **Target Date**.

**Order convention:** rank × 100 + position. Epics sit at rank × 100 − 50 so they sort ahead of
their issues: M1.0's epic `50` and its issues `100`–`111`; M2.0's epic `150`, issues from `200`;
M3.0's epic `250`, issues from `300`. Backlog items carry no Order.

**Effort and `size:`:** Effort is the board's planning field and spans `XS`–`XL`; the `size:`
label is what Grackle forecasts with and spans `S`–`L`. Set both at filing: `XS` and `S` take
`size:S`; `XL` means the issue should be split.

**Adding items:** the [`project-add`](../.github/workflows/project-add.yml) workflow adds every
new issue and pull request, using `PROJECT_ADMIN_TOKEN`. The built-in auto-add workflow may be
on as well; adding an item twice is a no-op.

**UI-only setup (not scriptable, done once by hand):** the saved views **Roadmap** (timeline by
milestone), **Board** (kanban by Status) and **Open Items** (table sorted by Order).

## Triage checklist

- [ ] **Kind** (issue type)
- [ ] **Milestone** (or `backlog`)
- [ ] **`component:` label(s)**
- [ ] **`state:` label**, and **`size:`** when sized
- [ ] **Parent** (linked under its epic)
- [ ] **Board** on, Status `Todo`
- [ ] **Effort** `XS`–`XL` and **Order**

## Delivery loop

1. Branch off `main`: `<type>/<kebab>`.
2. Conventional Commits; scope = component.
3. PR `Closes #NNN`; title is Conventional-Commit form with a lowercase subject (enforced by
   `pr-title-lint`).
4. CHANGELOG `[Unreleased]` entry per closed issue (enforced by `changelog`), or the
   `no-changelog` label.
5. Squash-merge on green CI.

## Sync and the admin token

`bash scripts/project-sync.sh --dry-run` previews; without the flag it reconciles labels and
milestones and validates issue types and board fields. It runs locally with a `gh` session that
has `repo`, `project` and `admin:org`, or in the `project-sync` workflow on pushes to `main` that
touch `.github/project.yml`. The workflows need the repository secret **`PROJECT_ADMIN_TOKEN`**
(a fine-grained or classic PAT with those scopes) on `mkzsystems/grackle`; without it
`project-sync` degrades to a warn-only validation pass and `project-add` skips with a notice.

## Decision records & RFCs

ADRs in `docs/adr/` named `NNNN-slug.md`, each with a `Status` line (`Proposed`, then
`Accepted (who, date, how)`), pre-1.0; promote to the `rfc` workflow when a public contract
freezes. ADR-0001 and ADR-0002 were accepted with the work plan (#1).
