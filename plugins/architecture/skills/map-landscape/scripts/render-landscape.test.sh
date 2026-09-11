#!/usr/bin/env bash
# Self-contained tests for render-landscape.sh (skill-script shape, per
# docs/conventions/shell-test-helpers/README.md: per-plugin assertion
# primitives are duplicated on purpose, never shared across plugins).
#
# The fixture record is written here rather than collected, so the renderer is
# tested against a fixed input and every assertion is about rendering alone.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/render-landscape.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3
  actual: $2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "unexpected substring: $3
  actual: $2" ;;
  *) pass "$1" ;;
  esac
}
assert_equals() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$3], got [$2]"; fi
}

render() {
  # $1 output subdirectory, rest passed through
  local dir="$TEST_TMPDIR/$1"
  shift
  rm -rf "$dir"
  mkdir -p "$dir"
  bash "$SCRIPT" --out "$dir" "$@"
}

# --- The fixture record -----------------------------------------------------
#
# Two checked-out repositories under one owner, an edge to a third repository
# under the same owner that is NOT checked out, and two external targets whose
# reference counts differ. Hyphens and dots in names exercise alias sanitising.
cat >"$TEST_TMPDIR/record.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "current repository plus reference graph",
  "remote": "not used",
  "repositories": [
    {"name":"web-ui","path":"/srv/web-ui","remote":"https://github.com/acme/web-ui","owner":"acme","runtime":"node","tooling":"node","target_framework":">=22","dependencies":["left-pad","undici"],"dev_dependencies":["vitest"],"last_touched":"2026-01-01T00:00:00+00:00","evidence":{"owner":"origin remote URL","runtime":"node: package.json"}},
    {"name":"billing.api","path":"/srv/billing.api","remote":"https://github.com/acme/billing.api","owner":"acme","runtime":"dotnet,shell","tooling":"unknown","target_framework":"net9.0","dependencies":["a","b","c","d","e","f","g","h","i","j","k","l"],"dev_dependencies":[],"last_touched":"2026-01-02T00:00:00+00:00","evidence":{"owner":"CODEOWNERS default rule","runtime":"dotnet: Billing.csproj"}}
  ],
  "edges": [
    {"from":"web-ui","to":"acme/billing.api","type":"depends-on","relation":"internal","count":3,"files":["package.json"]},
    {"from":"web-ui","to":"acme/design-tokens","type":"cites","relation":"internal","count":2,"files":["README.md"]},
    {"from":"web-ui","to":"actions/checkout","type":"uses-workflow","relation":"external","count":9,"files":[".github/workflows/ci.yml"]},
    {"from":"web-ui","to":"vitest-dev/vitest","type":"cites","relation":"external","count":1,"files":["README.md"]}
  ]
}
JSON

# --- Case group 1: the mermaid dialect --------------------------------------
render mermaid --record "$TEST_TMPDIR/record.json"
rc=$?
assert_equals "mermaid: rendering exits 0" "$rc" "0"
md="$(cat "$TEST_TMPDIR/mermaid/landscape.md")"
assert_contains "mermaid: the diagram is a focal-system-free C4Context" "$md" 'C4Context'
assert_contains "mermaid: with the landscape title" "$md" 'title System Landscape'
assert_contains "mermaid: the owner becomes an enterprise boundary" "$md" 'Enterprise_Boundary(b0, "acme")'
assert_contains "mermaid: a dotted name is sanitised into a valid alias" "$md" 'System(acme_billing_api, "billing.api"'
assert_contains "mermaid: a hyphenated one too" "$md" 'System(acme_web_ui, "web-ui"'
assert_contains "mermaid: the node label is the primary runtime plus the framework" "$md" '"dotnet, net9.0"'
assert_contains "mermaid: a single runtime with a framework reads the same way" "$md" '"node, >=22"'
assert_contains "mermaid: a referenced repository with no checkout is still a system" "$md" 'System(acme_design_tokens, "design-tokens", "not checked out here")'
assert_contains "mermaid: an other-owner target is external" "$md" 'System_Ext(actions_checkout, "actions/checkout"'
assert_contains "mermaid: an external keeps its owner prefix, having no boundary to sit in" "$md" '"actions/checkout"'
assert_contains "mermaid: the edge label is the type and the count" "$md" 'Rel(acme_web_ui, acme_billing_api, "depends-on (3)")'
assert_contains "mermaid: the provenance line names the discovery source" "$md" 'from current repository plus reference graph'
assert_contains "mermaid: and whether remote facts were used" "$md" 'Remote facts: not used'
assert_contains "mermaid: the generated-on date comes from the record, never the clock" "$md" '2026-01-02'

# The second checked-out repository cites nothing, so it must still be a node.
assert_contains "mermaid: a repository with no outgoing edge is still drawn" "$md" 'System(acme_billing_api'

# --- Case group 2: determinism ----------------------------------------------
render mermaid2 --record "$TEST_TMPDIR/record.json"
if diff -q "$TEST_TMPDIR/mermaid/landscape.md" "$TEST_TMPDIR/mermaid2/landscape.md" >/dev/null &&
  diff -q "$TEST_TMPDIR/mermaid/portfolio.md" "$TEST_TMPDIR/mermaid2/portfolio.md" >/dev/null; then
  pass "determinism: the same record renders byte-identical artifacts"
else
  fail "determinism: the same record renders byte-identical artifacts" \
    "$(diff "$TEST_TMPDIR/mermaid/landscape.md" "$TEST_TMPDIR/mermaid2/landscape.md")"
fi

# --- Case group 3: the structurizr dialect ----------------------------------
render dsl --record "$TEST_TMPDIR/record.json" --dialect structurizr
assert_equals "structurizr: rendering exits 0" "$?" "0"
if [[ -f "$TEST_TMPDIR/dsl/landscape.dsl" && ! -f "$TEST_TMPDIR/dsl/landscape.md" ]]; then
  pass "structurizr: it writes landscape.dsl and no landscape.md"
else
  fail "structurizr: it writes landscape.dsl and no landscape.md" "$(ls "$TEST_TMPDIR/dsl")"
fi
dsl="$(cat "$TEST_TMPDIR/dsl/landscape.dsl")"
assert_contains "structurizr: the model is wrapped in a workspace" "$dsl" 'workspace {'
assert_contains "structurizr: it uses the dedicated landscape view" "$dsl" 'systemLandscape "landscape" {'
assert_contains "structurizr: with include and autoLayout" "$dsl" 'include *'
assert_contains "structurizr: owners become groups" "$dsl" 'group "acme" {'
assert_contains "structurizr: a system carries its label as the description" "$dsl" 'softwareSystem "billing.api" "dotnet, net9.0"'
assert_contains "structurizr: an other-owner system is tagged External" "$dsl" '"actions/checkout" "not checked out here" "External"'
assert_contains "structurizr: relationships carry the same type-and-count label" "$dsl" 'acme_web_ui -> acme_billing_api "depends-on (3)"'
# Structurizr dropped the internal/external `location` property, so the tag is
# the only carrier for that fact — and a tag with no style renders nothing.
assert_contains "structurizr: the External tag has a style to render through" "$dsl" 'element "External" {'

# The two dialects must agree on which systems exist.
for sys in acme_web_ui acme_billing_api acme_design_tokens actions_checkout; do
  case "$md$dsl" in
  *"$sys"*) pass "dialects: $sys appears in both" ;;
  *) fail "dialects: $sys appears in both" "missing" ;;
  esac
done

# --- Case group 4: the portfolio table --------------------------------------
pf="$(cat "$TEST_TMPDIR/mermaid/portfolio.md")"
assert_contains "portfolio: the header carries all seven columns" "$pf" \
  '| Repository | Owner | Target framework | Runtime | Dependencies | Tooling | Last touched |'
assert_contains "portfolio: a multi-runtime repository lists every runtime" "$pf" '| dotnet, shell |'
assert_contains "portfolio: dependencies past ten are truncated with a count" "$pf" 'a, b, c, d, e, f, g, h, i, j (+2)'
assert_contains "portfolio: an underived fact stays unknown" "$pf" '| unknown |'
# shellcheck disable=SC2016 # backticks are markdown code spans in the rendered output.
assert_contains "portfolio: development-scope dependencies sit below the table" "$pf" '- web-ui: `vitest`'
assert_not_contains "portfolio: a repository with none gets no empty line" "$pf" '- billing.api:'
assert_contains "portfolio: every fact names the file it came from" "$pf" '| web-ui | runtime | node: package.json |'
assert_contains "portfolio: including a non-default owner ladder rung" "$pf" 'CODEOWNERS default rule'

# Rows sort by name, so the record's order (web-ui first) must not survive.
row_order="$(printf '%s\n' "$pf" | sed -n 's/^| \([^|]*\) | acme |.*/\1/p' | tr -d ' ' | tr '\n' ' ')"
assert_equals "portfolio: rows sort by name, not by record order" "$row_order" "billing.api web-ui "

# --- Case group 5: --top-external -------------------------------------------
render capped --record "$TEST_TMPDIR/record.json" --top-external 1
capped="$(cat "$TEST_TMPDIR/capped/landscape.md")"
assert_contains "cap: the most referenced external survives the cap" "$capped" 'actions/checkout'
assert_not_contains "cap: the least referenced one is dropped from the diagram" "$capped" 'vitest-dev'
assert_contains "cap: and the remainder is counted, not silently lost" "$capped" '1 external repositories are referenced but not drawn'
assert_not_contains "cap: an edge to an undrawn system is dropped with it" "$capped" 'vitest_dev_vitest'
assert_contains "cap: every internal system is drawn whatever the cap" "$capped" 'System(acme_design_tokens'

render uncapped --record "$TEST_TMPDIR/record.json" --top-external 0
uncapped="$(cat "$TEST_TMPDIR/uncapped/landscape.md")"
assert_not_contains "cap: zero draws no external at all" "$uncapped" 'System_Ext'
assert_contains "cap: and says how many were left out" "$uncapped" '2 external repositories'
assert_not_contains "cap: a cap wide enough for every external adds no leftover line" \
  "$md" 'external repositories are referenced but not drawn'

# --- Case group 6: annotations ----------------------------------------------
printf '## Notes\n\nBilling owns the ledger.\n' >"$TEST_TMPDIR/notes.md"
render noted --record "$TEST_TMPDIR/record.json" --notes "$TEST_TMPDIR/notes.md"
noted="$(cat "$TEST_TMPDIR/noted/landscape.md")"
assert_contains "notes: the annotations are appended verbatim" "$noted" 'Billing owns the ledger.'
assert_contains "notes: under their own heading" "$noted" '## Notes'
assert_contains "notes: and the diagram is unchanged" "$noted" 'Rel(acme_web_ui, acme_billing_api, "depends-on (3)")'
assert_not_contains "notes: the portfolio does not receive them" \
  "$(cat "$TEST_TMPDIR/noted/portfolio.md")" 'Billing owns the ledger.'

# --- Case group 7: a record with nothing in it ------------------------------
cat >"$TEST_TMPDIR/empty.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "repositories": [
    {"name":"solo","path":"/srv/solo","remote":"","owner":"unknown","runtime":"unknown","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{"owner":"no CODEOWNERS and no origin remote"}}
  ],
  "edges": []
}
JSON
render solo --record "$TEST_TMPDIR/empty.json"
assert_equals "empty: an edgeless record still renders" "$?" "0"
solo="$(cat "$TEST_TMPDIR/solo/landscape.md")"
assert_contains "empty: the one system is drawn" "$solo" 'System(solo, "solo"'
# An enterprise boundary is captioned with an organisation, so the absence of
# one is drawn as no boundary rather than as a boundary named "unknown".
assert_not_contains "empty: an unknown owner does not become a boundary caption" "$solo" 'Enterprise_Boundary'
assert_contains "empty: the ownerless system is drawn at the top level instead" "$solo" 'System(solo, "solo"'
render dsl_solo --record "$TEST_TMPDIR/empty.json" --dialect structurizr
solo_dsl="$(cat "$TEST_TMPDIR/dsl_solo/landscape.dsl")"
assert_not_contains "empty: nor a group caption in the other dialect" "$solo_dsl" 'group "unknown"'
assert_contains "empty: where it sits outside every group" "$solo_dsl" 'solo = softwareSystem "solo"'
assert_contains "empty: a repository with no probed runtime says so" "$solo" 'no probed runtime'
assert_contains "empty: an empty dependency list reads as none, not blank" \
  "$(cat "$TEST_TMPDIR/solo/portfolio.md")" '| (none) |'
assert_not_contains "empty: and no relationship is invented" "$solo" 'Rel('
assert_not_contains "empty: nor is a leftover-externals line" "$solo" 'not drawn'

# --- Case group 8: several owners -------------------------------------------
cat >"$TEST_TMPDIR/two-owners.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "repositories": [
    {"name":"web-ui","path":"/srv/web-ui","remote":"","owner":"acme","runtime":"node","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}},
    {"name":"tooling","path":"/srv/tooling","remote":"","owner":"zeta","runtime":"shell","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}}
  ],
  "edges": []
}
JSON
render owners --record "$TEST_TMPDIR/two-owners.json"
owners="$(cat "$TEST_TMPDIR/owners/landscape.md")"
assert_contains "owners: the first owner gets a boundary" "$owners" 'Enterprise_Boundary(b0, "acme")'
assert_contains "owners: the second gets its own, not a shared one" "$owners" 'Enterprise_Boundary(b1, "zeta")'

# --- Case group 8a: repository content stays inside its string literal ------
#
# A target framework is read out of a manifest with only XML tags stripped, and
# a raw quote is legal there. Both dialects then carry it inside a quoted string
# literal, and neither offers a portable escape for its own delimiter, so the
# delimiter is replaced rather than escaped: what arrives here is corrupt data
# or an attempt to splice diagram syntax, never a fact worth keeping verbatim.
cat >"$TEST_TMPDIR/hostile.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "subject_owner": "acme",
  "repositories": [
    {"name":"payments","path":"/srv/payments","remote":"","owner":"acme","runtime":"dotnet","tooling":"unknown","target_framework":"net9.0\" } click n1 \"javascript:alert(1)\" \"pwn","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{"runtime":"a | b"}}
  ],
  "edges": []
}
JSON
render hostile --record "$TEST_TMPDIR/hostile.json"
hostile="$(cat "$TEST_TMPDIR/hostile/landscape.md")"
assert_not_contains "injection: the payload cannot close the mermaid literal" "$hostile" '"pwn'
assert_contains "injection: the system is still drawn, with the value neutralised" \
  "$hostile" 'System(acme_payments, "payments", "dotnet, net9.0'"'"' } click n1'
quote_count="$(printf '%s\n' "$hostile" | grep -c '^    System(acme_payments, "payments", "[^"]*")$')"
assert_equals "injection: the mermaid call has exactly its own four quotes" "$quote_count" "1"
render hostile_dsl --record "$TEST_TMPDIR/hostile.json" --dialect structurizr
hostile_dsl="$(cat "$TEST_TMPDIR/hostile_dsl/landscape.dsl")"
assert_not_contains "injection: nor the structurizr one" "$hostile_dsl" '"pwn'
dsl_count="$(printf '%s\n' "$hostile_dsl" | grep -c '^      acme_payments = softwareSystem "payments" "[^"]*"$')"
assert_equals "injection: whose string closes where it should" "$dsl_count" "1"
# A pipe read out of a manifest ends the cell it lands in and shifts every
# column after it, which corrupts the table the same way.
hostile_portfolio="$(cat "$TEST_TMPDIR/hostile/portfolio.md")"
assert_contains "injection: a pipe in a fact is escaped, not a new column" \
  "$hostile_portfolio" '| a \| b |'
ev_row="$(printf '%s\n' "$hostile_portfolio" | grep -F '| payments | runtime |')"
assert_equals "injection: so the evidence row stays three cells wide" \
  "$ev_row" '| payments | runtime | a \| b |'

# --- Case group 8b: one alias per system ------------------------------------
#
# Every character outside the alphabet folds to the same underscore, so two
# names differing only in punctuation arrive at one identifier and take each
# other's relationships with them.
cat >"$TEST_TMPDIR/collide.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "subject_owner": "acme",
  "repositories": [
    {"name":"a-b","path":"/srv/a-b","remote":"","owner":"acme","runtime":"shell","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}},
    {"name":"a_b","path":"/srv/a_b","remote":"","owner":"acme","runtime":"shell","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}}
  ],
  "edges": [
    {"from":"a-b","to":"acme/a_b","type":"depends-on","relation":"internal","count":1,"files":["go.mod"]}
  ]
}
JSON
render collide --record "$TEST_TMPDIR/collide.json"
collide="$(cat "$TEST_TMPDIR/collide/landscape.md")"
decls="$(printf '%s\n' "$collide" | grep -c '^    System(')"
assert_equals "alias: two systems, two declarations" "$decls" "2"
uniq_aliases="$(printf '%s\n' "$collide" | sed -n 's/^    System(\([^,]*\),.*$/\1/p' | sort -u | wc -l | tr -d ' ')"
assert_equals "alias: and two distinct identifiers" "$uniq_aliases" "2"
assert_contains "alias: the collision is broken with a counted suffix" "$collide" 'acme_a_b_2'
assert_contains "alias: the relationship points at one of them, not at both" \
  "$collide" 'Rel(acme_a_b, acme_a_b_2'
render collide2 --record "$TEST_TMPDIR/collide.json"
if diff -q "$TEST_TMPDIR/collide/landscape.md" "$TEST_TMPDIR/collide2/landscape.md" >/dev/null; then
  pass "alias: the same record breaks the collision the same way twice"
else
  fail "alias: the same record breaks the collision the same way twice" \
    "$(diff "$TEST_TMPDIR/collide/landscape.md" "$TEST_TMPDIR/collide2/landscape.md")"
fi

# --- Case group 8c: a checkout is not a claim of ownership ------------------
#
# Having a repository on disk says where someone works, not who owns the system.
# A third-party checkout is the same external system the edges to it call
# external, so the recorded subject owner decides and the local facts stay.
cat >"$TEST_TMPDIR/foreign.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "subject_owner": "acme",
  "repositories": [
    {"name":"web-ui","path":"/srv/web-ui","remote":"","owner":"acme","runtime":"node","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}},
    {"name":"vendor-sdk","path":"/srv/vendor-sdk","remote":"","owner":"thirdparty","runtime":"go","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}}
  ],
  "edges": []
}
JSON
render foreign --record "$TEST_TMPDIR/foreign.json"
foreign="$(cat "$TEST_TMPDIR/foreign/landscape.md")"
assert_contains "foreign: the cross-owner checkout is drawn as external" \
  "$foreign" 'System_Ext(thirdparty_vendor_sdk, "thirdparty/vendor-sdk"'
assert_not_contains "foreign: and not inside an enterprise boundary for its owner" \
  "$foreign" 'Enterprise_Boundary(b1'
assert_contains "foreign: the subject owner still gets one" "$foreign" 'Enterprise_Boundary(b0, "acme")'
assert_contains "foreign: the facts the probe read are kept" "$foreign" '"go"'
# --top-external trims the tail of repositories this run only read about, never
# the set someone asked it to chart.
render foreign_capped --record "$TEST_TMPDIR/foreign.json" --top-external 0
assert_contains "foreign: a probed external survives the external cap" \
  "$(cat "$TEST_TMPDIR/foreign_capped/landscape.md")" 'System_Ext(thirdparty_vendor_sdk'
# A record that names no subject owner cannot make the call, so nothing moves.
cat >"$TEST_TMPDIR/nosubject.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "not used",
  "repositories": [
    {"name":"vendor-sdk","path":"/srv/vendor-sdk","remote":"","owner":"thirdparty","runtime":"go","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"unknown","evidence":{}}
  ],
  "edges": []
}
JSON
render nosubject --record "$TEST_TMPDIR/nosubject.json"
assert_contains "foreign: with no subject owner recorded, the drawing is unchanged" \
  "$(cat "$TEST_TMPDIR/nosubject/landscape.md")" 'System(thirdparty_vendor_sdk, "vendor-sdk"'

# --- Case group 8d: an archived system is charted and marked ----------------
#
# Archiving is a fact about the system, and the most consequential one a reader
# can learn about it: a landscape that quietly drops archived repositories hides
# exactly the dependencies worth acting on.
cat >"$TEST_TMPDIR/archived.json" <<'JSON'
{
  "schema_version": 1,
  "generated_on": "2026-01-02",
  "discovery_source": "explicit list",
  "remote": "used, owned only",
  "subject_owner": "acme",
  "repositories": [
    {"name":"legacy-api","remote":"https://github.com/acme/legacy-api","owner":"acme","runtime":"ruby","tooling":"unknown","target_framework":"unknown","dependencies":[],"dev_dependencies":[],"last_touched":"2024-05-05T00:00:00+00:00","archived":true,"evidence":{"last_touched":"pushed_at (remote)"}}
  ],
  "edges": []
}
JSON
render archived --record "$TEST_TMPDIR/archived.json"
assert_contains "archived: the node says so before it says anything else" \
  "$(cat "$TEST_TMPDIR/archived/landscape.md")" 'System(acme_legacy_api, "legacy-api", "archived, ruby")'
assert_contains "archived: and the portfolio row is marked" \
  "$(cat "$TEST_TMPDIR/archived/portfolio.md")" '| legacy-api (archived) |'
assert_not_contains "archived: it is charted, not hidden" \
  "$(cat "$TEST_TMPDIR/archived/portfolio.md")" '| (none) | unknown | unknown |
'

# --- Case group 9: markdown that lints --------------------------------------
#
# Probed on a file known to be clean first. `npx --no-install` exits non-zero
# when the package is simply absent, which is indistinguishable at the exit code
# from a lint failure, and reading "tool missing" as "the renderer emits bad
# markdown" would fail this suite on any host without the dependency installed.
markdownlint_usable() {
  [[ -z "${SKIP_MARKDOWNLINT:-}" ]] || return 1
  command -v npx >/dev/null 2>&1 || return 1
  printf '# Probe\n\nOne clean paragraph.\n' >"$TEST_TMPDIR/probe.md"
  npx --no-install markdownlint-cli2 "$TEST_TMPDIR/probe.md" >/dev/null 2>&1
}
if markdownlint_usable; then
  npx --no-install markdownlint-cli2 "$TEST_TMPDIR/mermaid/landscape.md" \
    "$TEST_TMPDIR/mermaid/portfolio.md" >/dev/null 2>&1
  assert_equals "lint: the rendered markdown passes markdownlint" "$?" "0"
else
  pass "lint: markdownlint skipped, the package is not installed here"
fi

# --- Case group 10: usage ---------------------------------------------------
bash "$SCRIPT" >/dev/null 2>&1
assert_equals "usage: no arguments exits 2" "$?" "2"

bash "$SCRIPT" --record "$TEST_TMPDIR/record.json" >/dev/null 2>&1
assert_equals "usage: a record with no --out exits 2" "$?" "2"

bash "$SCRIPT" --record "$TEST_TMPDIR/record.json" --out "$TEST_TMPDIR" --dialect plantuml >/dev/null 2>&1
assert_equals "usage: an unsupported dialect exits 2" "$?" "2"

bash "$SCRIPT" --record "$TEST_TMPDIR/record.json" --out "$TEST_TMPDIR" --top-external many >/dev/null 2>&1
assert_equals "usage: a non-numeric cap exits 2" "$?" "2"

bash "$SCRIPT" --record "$TEST_TMPDIR/absent.json" --out "$TEST_TMPDIR" >/dev/null 2>&1
assert_equals "usage: an unreadable record exits 1" "$?" "1"

bash "$SCRIPT" --record "$TEST_TMPDIR/record.json" --out "$TEST_TMPDIR/nowhere" >/dev/null 2>&1
assert_equals "usage: an output directory that is not there exits 1" "$?" "1"

printf '{"schema_version": 2, "repositories": [], "edges": []}\n' >"$TEST_TMPDIR/v2.json"
bad="$(bash "$SCRIPT" --record "$TEST_TMPDIR/v2.json" --out "$TEST_TMPDIR" 2>&1)"
assert_equals "usage: an unknown schema version exits 1" "$?" "1"
assert_contains "usage: and says which version it wanted" "$bad" "schema_version 1"

help_out="$(bash "$SCRIPT" --help 2>&1)"
assert_equals "usage: --help exits 0" "$?" "0"
assert_contains "usage: and states the determinism contract" "$help_out" "byte-identical"

printf '\n%d cases, %d failed\n' "$CASE_NUM" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1
exit 0
