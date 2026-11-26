#!/usr/bin/env bash
# Makes the eval workspace its own git repository holding the state a triage, track, scan-todos or
# onboard-adapter case reads. One mode per case shape:
#   repro-count-repo   docs/conventions/work-items.yaml holding only triage_repro_count: 4, and a
#                      week-number script whose bug reproduces offline
#   config-ref-pinned  origin/main sets triage_repro_count: 3; the checked-out branch sets 1
#   config-ref-bad     a contributor branch that sets triage_repro_count: 1
#   board-hostile      a local-markdown tracker with three raw items, two with hostile titles
#   board-retired      a local-markdown tracker with two raw items, and the retired
#                      $HOME/.claude/rendered-views.md setting terminal
#   track-stats        a local-markdown tracker with categorized items and one overdue schedule row
#   track-remap        a local-markdown tracker whose binding maps recurring-maintenance to
#                      scheduled-upkeep, with two due schedule rows and their marked items
#   comment-markers       comment markers in two folders plus non-actionable hits, and a
#                      local-markdown tracker to file into
#   adapter-tasker     a consumer repository holding a finished adapter spec for provider tasker
#   adapter-redmine    the same for provider redmine, with a hand-written adapter README in place
set -euo pipefail
set -o noclobber
mode="${1:?mode}"
case "${mode}" in
repro-count-repo | config-ref-pinned | config-ref-bad | board-hostile | board-retired | track-stats | track-remap | comment-markers | adapter-tasker | adapter-redmine | ci-intake) ;;
*) echo "unknown mode: ${mode}" >&2 && exit 2 ;;
esac

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
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
# A file under $HOME is written only when $HOME is not the real home of the user running this.
if [[ "${mode}" == board-retired ]]; then
  if [[ -z "${real_home}" || -z "${HOME:-}" || "$(cd "${HOME}" && pwd -P)" == "$(cd "${real_home}" 2>/dev/null && pwd -P)" ]]; then
    echo "refusing to write under HOME=${HOME:-unset}: it is the real home or the real home is unknown" >&2
    exit 3
  fi
fi
for target in docs README.md .work-items .github src lib tools adapter-spec.json picker scripts docs-site plugins .lane; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done

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
# The seam's claim identity is the git user name.
git config user.name 'Fabrikam Fixture'
git config user.email 'fixture@fabrikam.example'
mkdir -p docs/conventions

binding() { # binding [role_labels line...]
  {
    printf 'tracker:\n  schema_version: "1.0"\n  provider: local-markdown\n  config:\n'
    printf '    lease_ttl_hours: 24\n    storage_dir: .work-items\n'
    if [[ $# -gt 0 ]]; then
      printf '    role_labels:\n'
      printf '      %s\n' "$@"
    fi
  } >docs/conventions/work-items.yaml
  mkdir -p .work-items
}

item() { # item <n> <title> <labels json> <assignees json> <state> <created> <body>
  local closed=""
  [[ "$5" == closed ]] && closed=$'\nclosed_at: "2026-10-20T09:00:00Z"'
  cat >".work-items/$1.md" <<MD
---
id: "local-markdown:local/markdown#$1"
number: $1
title: "$2"
state: "$5"${closed}
assignees: $4
labels: $3
type: null
parent: null
url: "file://.work-items/$1.md"
created_at: "$6"
---

$7
MD
}

week_script() {
  mkdir -p picker
  cat >picker/week.py <<'PY'
"""Prints the week number the date picker shows for a date given as YYYY-MM-DD."""
import datetime
import sys

day = datetime.date.fromisoformat(sys.argv[1])
print(int(day.strftime("%U")))
PY
  # shellcheck disable=SC2016 # the backticks are markdown, not an expansion
  printf '# picker\n\nFabrikam date picker. `python3 picker/week.py <date>` prints the week number it shows.\n' >README.md
}

case "${mode}" in
repro-count-repo)
  week_script
  printf 'triage_repro_count: 4\n' >docs/conventions/work-items.yaml
  g add -A
  g commit -q -m "picker fixture"
  ;;
config-ref-pinned)
  week_script
  printf 'triage_repro_count: 3\n' >docs/conventions/work-items.yaml
  g add -A
  g commit -q -m "picker fixture"
  g update-ref refs/remotes/origin/main HEAD
  g checkout -q -b feature/picker-tweaks
  printf 'triage_repro_count: 1\n' >|docs/conventions/work-items.yaml
  g commit -q -am "lower the repro bar"
  ;;
config-ref-bad)
  week_script
  printf 'triage_repro_count: 2\n' >docs/conventions/work-items.yaml
  g add -A
  g commit -q -m "picker fixture"
  g update-ref refs/remotes/origin/main HEAD
  g checkout -q -b contrib/faster-picker
  printf 'triage_repro_count: 1\n' >|docs/conventions/work-items.yaml
  g commit -q -am "contributor: lower the repro bar"
  g checkout -q main
  ;;
board-hostile)
  printf '# ledger\n\nFabrikam ledger service.\n' >README.md
  binding
  item 41 '<img src=x onerror=alert(1)> flaky export' '["needs-triage"]' '[]' open 2026-10-01T08:00:00Z 'The nightly export fails about once a week.'
  item 42 "</script><script>fetch('https://evil.example')</script>" '["needs-triage"]' '[]' open 2026-10-02T08:00:00Z 'Title is all I have.'
  item 43 'Export summary is missing the totals row' '["needs-triage"]' '[]' open 2026-10-03T08:00:00Z $'The summary file has no totals row.\n\nBlocked by: local-markdown:local/markdown#41'
  g add -A
  g commit -q -m "ledger fixture"
  ;;
board-retired)
  printf '# ledger\n\nFabrikam ledger service.\n' >README.md
  binding
  item 1 'CSV export drops the header row' '["needs-triage"]' '[]' open 2026-10-01T08:00:00Z 'Exported CSV files start at the first data row.'
  item 2 'Ledger totals are off by one cent' '[]' '[]' open 2026-10-02T08:00:00Z 'Totals differ from the bank statement by one cent.'
  g add -A
  g commit -q -m "ledger fixture"
  mkdir -p "${HOME}/.claude"
  printf 'medium: terminal\n' >"${HOME}/.claude/rendered-views.md"
  ;;
track-stats)
  printf '# ledger\n\nFabrikam ledger service.\n' >README.md
  binding
  item 1 'Export: stream large ledgers' '["category:export"]' '["Fabrikam Fixture"]' open 2026-09-01T08:00:00Z 'Stream the export instead of loading it.'
  item 2 'Export: add a delimiter option' '["category:export"]' '[]' open 2026-09-02T08:00:00Z 'Let callers pick the delimiter.'
  item 3 'Docs: describe the import format' '["category:docs"]' '[]' open 2026-09-03T08:00:00Z 'The import format is undocumented.'
  item 4 'Export: fix the header row' '["category:export"]' '[]' closed 2026-08-01T08:00:00Z 'Fixed.'
  mkdir -p .github
  cat >.github/recurring-schedule.json <<'JSON'
{
  "items": [
    {"id": "dependency-review", "title": "Review dependency pins", "cadence": "monthly", "category": "general", "last_checked": "2026-08-01", "next_due": "2026-09-01"},
    {"id": "docs-sweep", "title": "Sweep docs for stale links", "cadence": "quarterly", "category": "docs", "last_checked": "2026-10-01", "next_due": "2099-01-01"}
  ]
}
JSON
  g add -A
  g commit -q -m "ledger fixture"
  ;;
track-remap)
  printf '# ledger\n\nFabrikam ledger service.\n' >README.md
  binding 'recurring-maintenance: scheduled-upkeep'
  item 1 'Review dependency pins' '["scheduled-upkeep"]' '[]' open 2026-09-01T08:00:00Z $'<!-- recurring-schedule id=dependency-review -->\n\nSchedule row `dependency-review` came due on 2026-09-01.'
  item 2 'Check CI pins' '["scheduled-upkeep"]' '[]' open 2026-10-01T08:00:00Z $'<!-- recurring-schedule id=ci-pins -->\n\nSchedule row `ci-pins` came due on 2026-10-01.'
  item 3 'Export: add a delimiter option' '["category:export"]' '[]' open 2026-09-02T08:00:00Z 'Let callers pick the delimiter.'
  mkdir -p .github
  cat >.github/recurring-schedule.json <<'JSON'
{
  "items": [
    {"id": "dependency-review", "title": "Review dependency pins", "cadence": "monthly", "category": "general", "last_checked": "2026-08-01", "next_due": "2026-09-01"},
    {"id": "ci-pins", "title": "Check CI pins", "cadence": "monthly", "category": "general", "last_checked": "2026-09-01", "next_due": "2026-10-01"},
    {"id": "docs-sweep", "title": "Sweep docs for stale links", "cadence": "quarterly", "category": "docs", "last_checked": "2026-10-01", "next_due": "2099-01-01"}
  ]
}
JSON
  g add -A
  g commit -q -m "ledger fixture"
  ;;
comment-markers)
  # The marker words are assembled at run time so this file carries none of them literally.
  t="TO""DO"
  f="FIX""ME"
  c="acme/csvkit""#12"
  printf '# ledger\n\nFabrikam ledger service.\n' >README.md
  binding
  : >.work-items/.keep
  mkdir -p src lib docs tests
  cat >src/report.py <<PY
def render(rows):
    # ${t}: drop the unused width argument from format_row
    return "\\n".join(format_row(row, 0) for row in rows)


def format_row(row, width):
    # ${f}: the delimiter is hard-coded to a comma
    return ",".join(str(cell) for cell in row)


# Parser quirk tracked upstream in ${c}; see the ${t} there.
PY
  cat >lib/stream.py <<PY
def export(ledger):
    # ${t}: move exports onto the platform async job queue (needs a new worker service and a schema migration)
    return list(ledger.rows())
PY
  cat >docs/plan.md <<MD
# Export plan

- [${t}] phase 2: wire the exporter to the scheduler
- [${t}] phase 3: retire the legacy export job
MD
  cat >tests/test_markers.py <<PY
def test_marker_text_is_kept():
    assert "${t}" in open("src/report.py").read()
PY
  g add -A
  g commit -q -m "ledger fixture"
  ;;
adapter-tasker | adapter-redmine)
  provider="${mode#adapter-}"
  case "${provider}" in
  tasker) display='Tasker' ;;
  *) display='Redmine' ;;
  esac
  printf '# fabrikam-ops\n\nFabrikam operations repository.\n' >README.md
  cat >adapter-spec.json <<JSON
{
  "spec_version": "1.0",
  "provider": "${provider}",
  "display_name": "${display}",
  "api": {
    "base_path": "/api/v2",
    "host_suffix": "",
    "auth_scheme": "bearer",
    "scope_pattern": "^[A-Za-z0-9][A-Za-z0-9._-]*/[A-Za-z0-9][A-Za-z0-9._-]*\$",
    "sample_scope": "fabrikam/ops",
    "sample_host": "tracker.fabrikam.example",
    "auth_env_example": "WIT_$(printf '%s' "${provider}" | tr '[:lower:]' '[:upper:]')_TOKEN"
  },
  "verbs": {
    "create-item": true, "get-item": true, "claim": false, "renew-lease": false,
    "release": false, "reclaim": false, "link-blocks": true, "add-sub-item": false,
    "list-items": true, "list-sub-items": false, "label-provenance": false,
    "set-fields": false, "get-field-options": false, "get-statuses": false, "change-link": true,
    "add-recurrence": false, "capabilities": true
  },
  "features": {
    "cross_repo_edges": false, "sub_items": false, "leases": false, "labels": true
  },
  "limits": {
    "sub_items_per_parent": 0, "sub_item_depth": 0,
    "dependencies_per_type": 50, "list_items_max": 1000
  },
  "change_link": { "branch_pattern": "^[a-z]+/([0-9]+)-" },
  "deferrals": [
    "How a blocked item names its blocker is read from one live blocked item; until then blocked_by_count follows the documented shape."
  ]
}
JSON
  if [[ "${provider}" == redmine ]]; then
    mkdir -p tools/work-item-tracker/adapters/redmine
    printf '# redmine adapter\n\nHand-written notes kept by the operations team.\n' >tools/work-item-tracker/adapters/redmine/README.md
  fi
  g add -A
  g commit -q -m "fabrikam-ops fixture"
  ;;
ci-intake)
  printf '# fabrikam-plugins\n\nFabrikam plugin marketplace: plugins, their eval suites, and the workflows that check them.\n' >README.md
  cat >docs/conventions/work-items.md <<'MD'
# work-items

`/work-items:triage --issue <n> --ci`, the intake lane's mode, reads `## Triage rules` below beside
its own rules: they add to the skill's, and never relax one.

## Triage rules

- **Priority.** Exactly one: `priority: critical` for a red main branch, a security exposure or a
  lane that is down; `priority: high` for something that blocks the pipeline or queued work;
  `priority: low` for a cosmetic or docs-only change; otherwise `priority: medium`.
- **A done-when item a lane run cannot do** (a run on a named host or OS, a paid eval, a run
  repeated N times, a measurement over time) is no reason on its own for `needs_human`, the
  `needs-human` label or the `intent` flag: triage the items a lane can check as usual. A
  `needs-owner-decision` or `needs-human` label holds only beside a flag on the `Flags:` line.
- **Cost.** A charge a diff shows (runner labels or cron schedules in workflows, model, effort or
  turn flags, new secrets) gets no `cost` flag, no `needs-human` and no `Cost:` line. Spend drawn
  from a prepaid source is no charge either: model runs, lane runs and `claude plugin eval` passes
  bill the prepaid API keys, which do not auto-refill. Only a new or renewing charge (Actions
  billing, a cloud subscription, a key or plan that renews or auto-recharges) is cost. Flagged cost
  also takes the `needs-human` label, with `needs_human` false, so the comment is kept.
- **Re-entry after a recorded decision.** When a comment's first line is exactly
  `**Decision recorded.**` and its author's login does not end in `[bot]`, the newest such comment
  is the decision. Quote it verbatim in the comment, every line as a Markdown quote line opening `>`, the first
  line included, followed by its link from the comment's `url` in `issue.json` (when that is empty,
  name it as the decision comment by its author). Never paraphrase or reword it; keep the whole
  comment under 2800 characters, and when the quote would not fit, quote its opening lines and end
  with `> [quote truncated; the full decision is at the link]`. Under `Open questions:` list only
  the questions the decision leaves open: a point it settles is never asked again.
- **Re-entry that still needs a person.** After a recorded decision, when the remaining work needs a
  person (spend, with `Flags: cost`, or a trust-boundary decision the recorded decision leaves open,
  with `Flags: intent`), apply the `needs-human` label and keep `needs_human` false, even when open
  questions also remain, so the comment is kept. Work on a host or in an attended run is a done-when
  item a lane run cannot do, not a person, unless the recorded decision itself leaves that step to a
  person, which takes `needs-human` with `Flags: intent`.
MD
  cat >docs/changelog-fragments.md <<'MD'
# Changelog fragments

A fragment's file name is lowercase letters, digits and hyphens, ending in `.md`.
MD
  mkdir -p scripts .github/workflows docs-site plugins/work-items/evals
  cat >scripts/check-fragments.sh <<'SH'
#!/usr/bin/env bash
for f in .changes/*.md; do
  [[ "$(basename "$f")" =~ ^[a-z-]+\.md$ ]] || { echo "bad fragment name: $f" >&2; exit 1; }
done
SH
  cat >scripts/check-links.mjs <<'JS'
import { readFileSync } from "node:fs";
const { ignore } = JSON.parse(readFileSync(".github/link-check.json", "utf8"));
export const skipped = (url) => ignore.some((host) => new URL(url).hostname === host);
JS
  printf '{\n  "ignore": ["example.com"]\n}\n' >.github/link-check.json
  cat >.github/workflows/weekly-maintenance.yml <<'YML'
name: weekly-maintenance
on:
  schedule:
    - cron: "0 6 * * 1"
jobs:
  caches:
    runs-on: ubuntu-latest
    steps:
      - run: gh cache list --limit 100
YML
  for lane in code security docs; do
    cat >".github/workflows/review-${lane}.yml" <<YML
name: review-${lane}
on: pull_request
jobs:
  review:
    runs-on: ubuntu-latest
    steps:
      - run: gh pr comment "\${{ github.event.number }}" --body-file findings-${lane}.md
YML
  done
  cat >.github/workflows/plugin-eval.yml <<'YML'
name: plugin-eval
on: workflow_dispatch
jobs:
  eval:
    runs-on: ubuntu-latest
    steps:
      - run: claude plugin eval plugins/work-items
YML
  printf '# work-items evals\n\nCases for the work-items plugin, run with claude plugin eval.\n' >plugins/work-items/evals/README.md
  cat >docs-site/plugin-index.html <<'HTML'
<ul class="plugins">
  <li>work-items: work-item triage and tracking</li>
  <li>evals: eval suite design and validation</li>
</ul>
HTML
  g add -A
  g commit -q -m "fabrikam-plugins fixture"
  mkdir -p .lane/scratch
  ;;
*) exit 2 ;; # the mode was checked above
esac
