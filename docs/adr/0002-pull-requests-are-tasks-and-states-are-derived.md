# ADR-0002: Pull requests are tasks, and a task's state is derived

- Status: Accepted (John, 2026-10-09, approving the work plan in #28)
- Deciders: John McKenzie

## Context

The design makes a task "a GitHub issue plus three things GitHub does not track": a readiness
state, dependencies and a target window, with the state stored as a `state:` label so it survives
without the tool. The first task spec maps labels to states for issues, says a closed issue is
Done and an unlabelled open issue is Needs spec, and syncs pull requests without saying what the
board does with them.

Until M3.0 writes labels, nothing moves an issue to `state:needs-review` when its PR opens, so a
board that shows issues only has an empty review column for the whole of M1.0 and M2.0, and a PR
that closes no issue is invisible.

## Decision

1. **Pull requests are tasks** of kind `pr`, synced from the same repositories with their draft
   flag, merge state and `closingIssuesReferences`. Their state is derived: merged or closed is
   Done, draft is In flight, open is Needs review. A PR that names no issue is a card of its own.
2. **An issue's state is derived in this order**, first match wins: closed is Done; an open,
   non-draft linked PR makes it Needs review; exactly one `state:` label gives that state; two or
   more `state:` labels is a conflict, shown on the card and reported by `sync`, and reads as
   Needs spec; no label is Needs spec. An unknown `state:` value is ignored and reported.
3. **The label grammar** is the design's: `state:needs-spec`, `state:agent-ready`,
   `state:in-flight`, `state:needs-review`, `size:S`, `size:M`, `size:L`; the prefix matches
   exactly and the value case-insensitively.
4. **The store keeps the label-derived state** on the row and applies the PR override in the query,
   through the link table, so a PR in another repository can put an issue in review and the rule
   lives in one place.

## Consequences

- The review column is right from the first sync, in every repository, before any label is written.
- When M3.0 writes `state:needs-review`, the label and the derivation agree; when they disagree
  (a label left behind after a merge), the derivation wins and the next label write repairs it.
- The `Source` interface yields tasks of both kinds; a later backend decides what a "pull request"
  is for it (a merge request on GitLab, nothing for markdown task files).
