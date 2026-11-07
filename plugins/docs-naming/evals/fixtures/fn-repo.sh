#!/usr/bin/env bash
# Seeds a docs-naming eval repository in the current directory, one mode per case.
#   audit-tree              three offending names cited across the current, historical and released tiers
#   collision               audit-tree plus docs/BETA.md beside docs/beta.md
#   plan-pending            audit-tree plus the audit's plan, every finding pending
#   plan-moved              plan-pending, then docs/Release_Notes.md moved and committed elsewhere
#   setup-malformed         a tracked team layer whose line 2 is a flow mapping
#   setup-empty             a repository with no docs-naming layer
#   setup-personal-tier     a tracked team layer plus an ignored personal layer declaring one tier
#   setup-retired-team      an old .claude/docs-hygiene.json team file and no team YAML
#   setup-retired-personal  an ignored personal YAML and an old .claude/docs-hygiene.local.json
set -euo pipefail
set -o noclobber
mode="${1:?mode}"

here="$(pwd -P)"
case "${here}" in
/ | "${HOME:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
# The eval workspace sits inside the run's temporary home, which is itself a repository, so a
# repository above the workspace is expected there. Allow only that one; refuse a workspace that
# is already a repository and any other enclosing repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
if top="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  tmp="$(cd "${TMPDIR:-/nonexistent}" 2>/dev/null && pwd -P || true)"
  if [[ "${top}" == "${here}" ]]; then
    echo "refusing to scaffold: ${here} is already a repository" >&2
    exit 3
  fi
  run="$(dirname "${tmp:-/}")"
  if [[ -z "${tmp}" || "$(basename "${tmp}")" != tmp || "$(basename "${run}")" != claude-eval-* || "${top}" != "${run}/home" || "${here}/" != "${top}/"* ]]; then
    echo "refusing to scaffold inside ${top}, a repository outside TMPDIR (${TMPDIR:-unset})" >&2
    exit 3
  fi
fi
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c tag.gpgsign=false \
    -c user.name='Fabrikam Fixture' -c user.email='fixture@fabrikam.example' "$@"
}
g -c init.defaultBranch=main init -q --template=
if [[ "$(git rev-parse --show-toplevel)" != "${here}" ]]; then
  echo "git did not create a repository here: ${PWD}" >&2
  exit 3
fi
printf '.work/\ndocs/conventions/*.local.*\n.claude/*.local.json\n' >.gitignore
printf '# Harbor\n\nShipment tracking service. Start with [getting started](docs/getting-started.md).\n' >README.md
mkdir -p docs/conventions
printf '# Getting started\n\nInstall the service, then read the [release notes](Release_Notes.md) and the [catalog](CATALOG.md).\n' >docs/getting-started.md

team_layer() {
  cat >docs/conventions/docs-naming.yaml <<'YAML'
# File-name convention for the docs tree.
roots:
  - "docs"
rule: "lower-kebab"
tiers:
  - name: "released"
    paths:
      - "CHANGELOG.md"
    forms: "none"
  - name: "historical"
    paths:
      - "docs/adr/**"
    forms: "links-and-paths"
YAML
}

audit_tree() {
  team_layer
  mkdir -p docs/adr
  printf '# Release notes\n\n## 1.4.0\n\nFaster label printing.\n' >docs/Release_Notes.md
  printf '# Catalog\n\nEvery shipment type we track.\n' >docs/CATALOG.md
  printf '# Rate limits\n\nRequests per minute, per client.\n' >docs/Rate_Limits.md
  cat >docs/index.md <<'MD'
# Docs index

| Page | Covers |
|---|---|
| [Release notes](Release_Notes.md) | what shipped |
| `docs/Rate_Limits.md` | request budgets |

The catalog lists every shipment type; see CATALOG for the full list.
Ask in the docs channel before you edit CATALOG by hand.
MD
  cat >docs/adr/0001-split-docs.md <<'MD'
# 1. Split the docs

We moved the notes into docs/Release_Notes.md so the [release notes](../Release_Notes.md) sit with the guides.
The catalog page stays short.
MD
  cat >CHANGELOG.md <<'MD'
# Changelog

## 1.4.0

- Added `docs/Release_Notes.md` and linked the [rate limits](docs/Rate_Limits.md).
- Linked the [catalog](docs/CATALOG.md) from the guide.
MD
}

plan() {
  mkdir -p .work/docs-hygiene/main
  printf '*\n' >.work/.gitignore
  head="$(git rev-parse HEAD)"
  sed "s/@HEAD@/${head}/" >.work/docs-hygiene/main/file-names.md <<'PLAN'
---
type: docs-naming-file-name-findings
schema: 1
date: 20261107T090000Z
branch: main
head: @HEAD@
config: resolved
roots: docs
files_scanned: 7
findings: 3
collisions: 0
---

# File-name rename plan

One record per file this tree would rename. `head` is recorded for the
evidence trail and is never checked: a consumer commits between accepted
renames. What a realign checks per record is that the old path is still in
the index and that each site still carries the old name.

Statuses move `pending` to `accepted`, `applying`, `applied`, `declined`, or
`blocked`. Only the realign writes a forward move. A re-audit merges into
this file by id and never resurrects a decision.

### FN-c60eb30e `docs/Release_Notes.md` to `docs/release-notes.md`

- **Status:** pending
- **Collision:** none
- **References:** 5 site(s) in 4 file(s)
- **By tier:** 2 current (edit), 1 historical (edit), 1 historical (report), 1 released (report)
- **Needs a human:** 0 site(s) marked review
- **Generated touched:** none
- **Sites:**

| file | line | form | tier | action | excerpt |
|---|---|---|---|---|---|
| `CHANGELOG.md` | 5 | backtick-path | released | report | - Added `docs/Release_Notes.md` and linked the [rate limits](docs/Rate_Limits.md). |
| `docs/adr/0001-split-docs.md` | 3 | md-link | historical | edit | We moved the notes into docs/Release_Notes.md so the [release notes](../Release_Notes.md) sit with the guides. |
| `docs/adr/0001-split-docs.md` | 3 | plain | historical | report | We moved the notes into docs/Release_Notes.md so the [release notes](../Release_Notes.md) sit with the guides. |
| `docs/getting-started.md` | 3 | md-link | current | edit | Install the service, then read the [release notes](Release_Notes.md) and the [catalog](CATALOG.md). |
| `docs/index.md` | 5 | md-link | current | edit | \| [Release notes](Release_Notes.md) \| what shipped \| |

### FN-c5a4747f `docs/CATALOG.md` to `docs/catalog.md`

- **Status:** pending
- **Collision:** none
- **References:** 4 site(s) in 3 file(s)
- **By tier:** 1 current (edit), 2 current (review), 1 released (report)
- **Needs a human:** 2 site(s) marked review
- **Generated touched:** none
- **Sites:**

| file | line | form | tier | action | excerpt |
|---|---|---|---|---|---|
| `CHANGELOG.md` | 6 | md-link | released | report | - Linked the [catalog](docs/CATALOG.md) from the guide. |
| `docs/getting-started.md` | 3 | md-link | current | edit | Install the service, then read the [release notes](Release_Notes.md) and the [catalog](CATALOG.md). |
| `docs/index.md` | 8 | bare-stem | current | review | The catalog lists every shipment type; see CATALOG for the full list. |
| `docs/index.md` | 9 | bare-stem | current | review | Ask in the docs channel before you edit CATALOG by hand. |

### FN-6f3ce017 `docs/Rate_Limits.md` to `docs/rate-limits.md`

- **Status:** pending
- **Collision:** none
- **References:** 2 site(s) in 2 file(s)
- **By tier:** 1 current (edit), 1 released (report)
- **Needs a human:** 0 site(s) marked review
- **Generated touched:** none
- **Sites:**

| file | line | form | tier | action | excerpt |
|---|---|---|---|---|---|
| `CHANGELOG.md` | 5 | md-link | released | report | - Added `docs/Release_Notes.md` and linked the [rate limits](docs/Rate_Limits.md). |
| `docs/index.md` | 6 | backtick-path | current | edit | \| `docs/Rate_Limits.md` \| request budgets \| |

PLAN
}

case "${mode}" in
audit-tree)
  audit_tree
  ;;
collision)
  audit_tree
  printf '# Beta\n\nBeta programme.\n' >docs/BETA.md
  printf '# beta\n\nbeta notes.\n' >docs/beta.md
  ;;
plan-pending)
  audit_tree
  g add -A
  g commit -q -m "chore: seed"
  plan
  exit 0
  ;;
plan-moved)
  audit_tree
  g add -A
  g commit -q -m "chore: seed"
  plan
  mkdir -p docs/guides
  g mv docs/Release_Notes.md docs/guides/notes.md
  g commit -q -m "docs: move the release notes under guides"
  exit 0
  ;;
setup-malformed)
  printf '# File-name convention for the docs tree.\nroots: {path: docs}\nrule: "lower-kebab"\n' >docs/conventions/docs-naming.yaml
  ;;
setup-empty) ;;
setup-personal-tier)
  team_layer
  cat >docs/conventions/docs-naming.local.yaml <<'YAML'
tiers:
  - name: "mine"
    paths:
      - "docs/drafts/**"
    forms: "all"
YAML
  ;;
setup-retired-team)
  mkdir -p .claude
  printf '{\n  "schema": 1,\n  "file_names": {\n    "roots": ["docs"],\n    "rule": "lower-kebab",\n    "exempt_paths": ["docs/vendor/**"]\n  }\n}\n' >.claude/docs-hygiene.json
  ;;
setup-retired-personal)
  mkdir -p .claude
  printf 'exempt_paths:\n  - "docs/vendor/**"\n' >docs/conventions/docs-naming.local.yaml
  printf '{\n  "schema": 1,\n  "file_names": {\n    "exempt_paths": ["docs/vendor/**", "docs/legacy/**"]\n  }\n}\n' >.claude/docs-hygiene.local.json
  ;;
*)
  echo "unknown mode: ${mode}" >&2
  exit 2
  ;;
esac
g add -A
g commit -q -m "chore: seed"
