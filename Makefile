# grackle: build, test and check. Every tool is pinned and installed into .bin/ by `make tools`, so
# a clean machine needs only Go (and a C compiler for the race detector). CI runs the same targets.
SHELL := /usr/bin/env bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

GO ?= go
BIN := $(CURDIR)/.bin
export PATH := $(BIN):$(PATH)

# Pinned tool versions. Bump here; `make tools` reinstalls what changed. CI reads
# GOLANGCI_LINT_VERSION from here too (`make print-GOLANGCI_LINT_VERSION`).
GOLANGCI_LINT_VERSION ?= v2.14.0
GOVULNCHECK_VERSION ?= v1.8.0
TEMPL_VERSION ?= v0.3.1070
# Vendored into internal/board/static/vendor/ by `make vendor-htmx`; the board serves it from the binary.
HTMX_VERSION ?= 2.0.11
HTMX_DIR := internal/board/static/vendor

VERSION ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo dev)
LDFLAGS := -s -w -X main.version=$(VERSION)

# grackle is cgo-free (CLAUDE.md, docs/plan.md section 9): one runner cross-compiles every target.
RELEASE_TARGETS := linux/amd64 linux/arm64 darwin/amd64 darwin/arm64

# Paths `make generate` writes. generate-check fails if any differs from the commit, including
# generated files that are not committed yet.
GENERATED := '*_templ.go'

## ---- tools -------------------------------------------------------------------------------------

TOOLS := $(BIN)/golangci-lint $(BIN)/govulncheck $(BIN)/templ

.PHONY: tools
tools: $(TOOLS) ## Install the pinned CLIs into .bin/

$(BIN)/golangci-lint: Makefile
	GOBIN=$(BIN) $(GO) install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$(GOLANGCI_LINT_VERSION)
$(BIN)/govulncheck: Makefile
	GOBIN=$(BIN) $(GO) install golang.org/x/vuln/cmd/govulncheck@$(GOVULNCHECK_VERSION)
$(BIN)/templ: Makefile
	GOBIN=$(BIN) $(GO) install github.com/a-h/templ/cmd/templ@$(TEMPL_VERSION)

## ---- code --------------------------------------------------------------------------------------

.PHONY: generate
generate: $(BIN)/templ ## Regenerate the Go for every .templ file
	$(BIN)/templ generate -path .

.PHONY: generate-check
generate-check: generate ## Fail if generated code is stale or uncommitted
	@out="$$(git status --porcelain --untracked-files=all -- $(GENERATED))"; \
	  if [[ -n "$$out" ]]; then echo "generated code is stale: run make generate and commit"; echo "$$out"; exit 1; fi

.PHONY: vendor-htmx
vendor-htmx: ## Fetch htmx $(HTMX_VERSION) into internal/board/static/vendor/ (then commit it)
	mkdir -p $(HTMX_DIR)
	curl -sfL https://unpkg.com/htmx.org@$(HTMX_VERSION)/dist/htmx.min.js -o $(HTMX_DIR)/htmx.min.js
	curl -sfL https://unpkg.com/htmx.org@$(HTMX_VERSION)/LICENSE -o $(HTMX_DIR)/htmx.LICENSE
	printf 'htmx.org %s\nsource: https://unpkg.com/htmx.org@%s/dist/htmx.min.js\nsha256: %s\nlicence: 0BSD (htmx.LICENSE)\nrefresh: make vendor-htmx (HTMX_VERSION in the Makefile)\n' \
	  $(HTMX_VERSION) $(HTMX_VERSION) "$$(sha256sum $(HTMX_DIR)/htmx.min.js | cut -d' ' -f1)" > $(HTMX_DIR)/htmx.version

.PHONY: build
build: ## Build the grackle binary into .bin/ (CGO_ENABLED=0)
	CGO_ENABLED=0 $(GO) build -trimpath -ldflags '$(LDFLAGS)' -o $(BIN)/grackle ./cmd/grackle

.PHONY: cgo-check
cgo-check: ## Fail if any dependency carries cgo files or grackle does not build with CGO_ENABLED=0, per target
	@for t in $(RELEASE_TARGETS); do \
	  os="$${t%/*}"; arch="$${t#*/}"; \
	  cgo="$$(CGO_ENABLED=1 GOOS=$$os GOARCH=$$arch $(GO) list -deps -f '{{if and (not .Standard) .CgoFiles}}{{.ImportPath}}{{end}}' ./...)"; \
	  if [[ -n "$$cgo" ]]; then echo "$$t: these packages use cgo; grackle is cgo-free:"; echo "$$cgo"; exit 1; fi; \
	  CGO_ENABLED=0 GOOS=$$os GOARCH=$$arch $(GO) build -o /dev/null ./... || { echo "$$t: does not build with CGO_ENABLED=0"; exit 1; }; \
	  echo "$$t: cgo-free"; \
	done

.PHONY: fmt-check
fmt-check: ## Fail on unformatted Go
	@out="$$(gofmt -l .)"; if [[ -n "$$out" ]]; then echo "gofmt needed:"; echo "$$out"; exit 1; fi

.PHONY: mod-check
mod-check: ## Fail if go.mod or go.sum is not tidy
	$(GO) mod tidy -diff

.PHONY: vet
vet: ## go vet
	$(GO) vet ./...

.PHONY: test
test: ## Unit tests with the race detector (the race detector needs cgo; the shipped binary does not)
	CGO_ENABLED=1 $(GO) test -race -count=1 ./...

.PHONY: lint
lint: $(BIN)/golangci-lint ## golangci-lint, including the depguard import rules
	$(BIN)/golangci-lint run

.PHONY: vuln
vuln: $(BIN)/govulncheck ## govulncheck
	$(BIN)/govulncheck ./...

.PHONY: check
check: fmt-check mod-check vet lint vuln generate-check cgo-check test ## Everything CI runs on Linux

.PHONY: clean
clean: ## Remove build outputs (not the tools)
	rm -f $(BIN)/grackle
	rm -rf dist

.PHONY: print-%
print-%: ## Print a Makefile variable (CI reads the pinned versions this way)
	@echo '$($*)'

.PHONY: help
help: ## This help
	@grep -E '^[a-zA-Z_%-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-16s %s\n", $$1, $$2}'
