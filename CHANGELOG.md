# Changelog

All notable changes to Grackle are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/) from the first release.

## [Unreleased]

### Added

- The pm-framework starter kit (org edition, v1.0): `.github/project.yml` declaring the component labels, Grackle's own `state:*` and `size:*` labels, the meta and RFC labels, the three milestones and the Grackle 1.0 board's fields; `.github/labeler.yml`; issue forms and the PR template; the `labeler`, `pr-title-lint`, `auto-close-epics`, `project-sync`, `changelog` and `project-add` workflows; `scripts/project-sync.sh`; `docs/project-management.md`; this changelog (#5).
- The build skeleton: the Go module (`go 1.26.0`, `toolchain go1.26.9`), `cmd/grackle` with cobra and a `version` command (the ldflags version, else the module version Go recorded, else `dev`), a Makefile that pins golangci-lint v2.14.0, govulncheck v1.8.0 and templ v0.3.1070 into `.bin/` with `check` running format, tidy, vet, lint, vuln, generate and cgo checks and the race-enabled tests, `.golangci.yml` with the package import rules of the plan as depguard rules, and CI jobs `go`, `macos`, `lint`, `vuln` and `generate-check` (#6).
