#!/usr/bin/env bash
#
# pm-framework v1.0
# project-sync.sh — reconcile GitHub PM objects from .github/project.yml.
# See docs/framework/pm-framework.md for the model.
#
# Reconciles (non-destructively):
#   * repo labels        (create / update color+description / rename via `from`)
#   * phase milestones   (create / update description)
#   * org issue types    (org edition only; validate-only — warns if any are missing)
#   * project fields     (validate-only — warns if missing)
#
# It never deletes labels or milestones that are absent from the spec, so Dependabot's
# auto-labels and any ad-hoc milestones are left untouched.
#
# Edition is read from `mode:` in the spec ("org" | "personal", default "org"):
#   * org      — validates org-level issue types under orgs/<owner>/issue-types.
#   * personal — skips issue-type validation entirely (personal accounts have none);
#                the project owner is a user, and epics are marked with the `epic` label.
#
# Auth: uses `gh` with the ambient token. In CI, the `project-sync` workflow exports
# PROJECT_ADMIN_TOKEN as GH_TOKEN (a maintainer PAT — org issue types and Projects v2
# cannot be written by the default token; user-scoped Projects also need `project`
# scope). Run locally with a `gh auth login` session that has the needed scopes.
#
# Usage: bash scripts/project-sync.sh [--dry-run] [path/to/project.yml]

set -euo pipefail

DRY_RUN=false
SPEC=".github/project.yml"
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
    *) SPEC="$arg" ;;
  esac
done

run() {
  if $DRY_RUN; then
    echo "  DRY-RUN: $*"
  else
    "$@"
  fi
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------
if [[ ! -f "$SPEC" ]]; then
  echo "::error::spec file not found: $SPEC" >&2
  exit 1
fi

if [[ -n "${PROJECT_ADMIN_TOKEN:-}" ]]; then
  export GH_TOKEN="$PROJECT_ADMIN_TOKEN"
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "::warning::no GitHub auth available (PROJECT_ADMIN_TOKEN unset and no gh session); skipping project sync." >&2
  exit 0
fi

REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

py() { python3 -c "$1" "$SPEC"; }

MODE="$(py 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])) or {}).get("mode","org"))')"

echo "Reconciling PM objects for ${REPO} from ${SPEC} (mode=${MODE})$($DRY_RUN && echo ' (dry run)')"

# ----- Labels --------------------------------------------------------------
echo "== Labels =="
existing_labels="$(gh label list --repo "$REPO" --limit 200 --json name --jq '.[].name')"
py '
import sys, yaml
for l in yaml.safe_load(open(sys.argv[1])).get("labels", []) or []:
    print("\t".join([l["name"], l.get("color",""), l.get("description",""), l.get("from","")]))
' | while IFS=$'\t' read -r name color desc from; do
  # Rename in place if `from` exists as a label and the target does not.
  if [[ -n "$from" ]] && grep -qxF "$from" <<<"$existing_labels"; then
    if grep -qxF "$name" <<<"$existing_labels"; then
      echo "  rename skipped (target exists): $from -> $name"
    else
      echo "  rename: $from -> $name"
      run gh label edit "$from" --repo "$REPO" --name "$name" --color "$color" --description "$desc" >/dev/null
      continue
    fi
  fi
  # Create or update.
  if grep -qxF "$name" <<<"$existing_labels"; then
    run gh label edit "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null
    echo "  update: $name"
  else
    run gh label create "$name" --repo "$REPO" --color "$color" --description "$desc" >/dev/null
    echo "  create: $name"
  fi
done

# ----- Milestones ----------------------------------------------------------
echo "== Milestones =="
existing_ms="$(gh api "repos/${REPO}/milestones?state=all&per_page=100" --jq '.[].title')"
py '
import sys, yaml
for m in yaml.safe_load(open(sys.argv[1])).get("milestones", []) or []:
    print("\t".join([m["title"], m.get("description","")]))
' | while IFS=$'\t' read -r title desc; do
  if grep -qxF "$title" <<<"$existing_ms"; then
    number="$(gh api "repos/${REPO}/milestones?state=all&per_page=100" --jq ".[] | select(.title==\"$title\") | .number")"
    run gh api -X PATCH "repos/${REPO}/milestones/${number}" -f description="$desc" >/dev/null
    echo "  update: $title"
  else
    run gh api -X POST "repos/${REPO}/milestones" -f title="$title" -f description="$desc" >/dev/null
    echo "  create: $title"
  fi
done

# ----- Issue types (org edition only; validate-only) -----------------------
if [[ "$MODE" == "personal" ]]; then
  echo "== Issue types == (skipped — personal edition uses the \`epic\` label)"
else
  echo "== Issue types (validate-only) =="
  owner="${REPO%%/*}"
  org_types="$(gh api "orgs/${owner}/issue-types" --jq '.[].name' 2>/dev/null || true)"
  if [[ -z "$org_types" ]]; then
    echo "  ::warning::could not read org issue types for ${owner} (needs org read scope); skipping validation"
  else
    py '
import sys, yaml
for t in yaml.safe_load(open(sys.argv[1])).get("issue_types", []) or []:
    print(t["name"])
' | while read -r t; do
      if grep -qxF "$t" <<<"$org_types"; then
        echo "  ok: $t"
      else
        echo "  ::warning::issue type missing on org ${owner}: $t"
      fi
    done
  fi
fi

# ----- Project fields (validate-only) --------------------------------------
echo "== Project fields (validate-only) =="
powner="$(py 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])).get("project") or {}).get("owner",""))')"
pnum="$(py 'import sys,yaml; print((yaml.safe_load(open(sys.argv[1])).get("project") or {}).get("number",""))')"
[[ -z "$powner" ]] && powner="${REPO%%/*}"
if [[ -z "$pnum" || "$pnum" == "0" ]]; then
  echo "  ::warning::project.number not set in ${SPEC}; create the board (see docs/framework/adoption-checklist.md) and fill it in"
else
  if fields="$(gh project field-list "$pnum" --owner "$powner" --format json --jq '.fields[].name' 2>/dev/null)"; then
    py '
import sys, yaml
for f in ((yaml.safe_load(open(sys.argv[1])).get("project") or {}).get("fields") or []):
    print(f["name"])
' | while read -r f; do
      if grep -qxF "$f" <<<"$fields"; then
        echo "  ok: $f"
      else
        echo "  ::warning::project #${pnum} missing field: $f"
      fi
    done
  else
    echo "  ::warning::could not read project #${pnum} for owner ${powner} (needs project scope); skipping validation"
  fi
fi

echo "Done."
