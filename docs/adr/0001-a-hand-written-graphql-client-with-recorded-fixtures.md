# ADR-0001: A hand-written GraphQL client, with recorded exchanges as fixtures

- Status: Proposed (2026-10-09)
- Deciders: John McKenzie

## Context

Grackle reads issues, pull requests, milestones and labels from every configured org through the
GitHub GraphQL API, and `CLAUDE.md` requires the integration tests to run against recorded GraphQL
fixtures, never live GitHub. The client is the one piece of the sync path that touches the network,
so how it is written decides how the fixtures are made, how rate limits are seen and how a schema
change is noticed.

Three ways to write it were weighed:

1. `shurcooL/githubv4`: typed query structs reflected into GraphQL; pagination written by hand per
   connection; last tagged release February 2026; recording its traffic means wrapping its
   `http.Client` anyway.
2. `cli/go-gh`: the `gh` CLI's own library, with a GraphQL client and token discovery; brings the
   `gh` configuration model into a tool that has its own config.
3. A client over `net/http`: one POST, the query documents as `.graphql` files embedded beside the
   code, variables as a map, a typed response struct per query.

## Decision

Option 3. The client is small enough to own:

- Each query is a file under `internal/source/github/queries/`, embedded, and asks for
  `rateLimit { cost remaining resetAt }` so every response carries the budget.
- GraphQL `errors[]` are surfaced with `path` and `type`; a `NOT_FOUND` for one repository fails
  that repository, and the run continues.
- Rate limits are a policy in the client: a reserve of 100 points below which a run stops cleanly
  with the reset time and exit code 2; `Retry-After` on a 403 or 429 is honoured (at least 60 s)
  and the request retried once; a 5xx is retried three times with exponential backoff and jitter.
- Fixtures are recorded exchanges. An `http.RoundTripper` under `go test -record` writes each
  exchange as the query's hash, its variables and the response body; headers are never written, so
  no token reaches a fixture. Replay matches on hash and variables and fails with a diff on a miss.
- The token comes from the environment variable named by `token_env`, then from `gh auth token`
  when `gh` is on the path, else an error naming both.

## Consequences

- No dependency for GitHub access; the schema facts the queries rely on are the ones verified on
  2026-10-09 (`issues.filterBy.since` exists, `pullRequests` has no `since`, `issueType`,
  `stateReason`, `isDraft`, `closingIssuesReferences`).
- A query change means re-recording its fixtures with a live token (`make record`); the diff on a
  replay miss says which query drifted.
- Pagination and cursors are explicit code in the syncer, where the cursor policy lives anyway.
