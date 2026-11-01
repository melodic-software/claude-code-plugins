#!/usr/bin/env bash
# test-scope: .github/standards/runner-policy/package.json
# test-scope: .github/artifact-retention.json .github/artifact-retention.schema.json
# test-scope: .github/workflows/* .github/actions/*
# Black-box contract test for check-artifact-retention.sh.
#
# Builds a throwaway tree with a retention table and fixture workflows, runs the
# checker against it, and asserts on exit code and output; the last case runs
# the checker on this checkout. Mutates only its own mktemp dir. The SUT
# resolves the repository root relative to its own location, so the fixture
# tree carries a copy of it under scripts/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-artifact-retention.sh"
SUT_MJS="$SCRIPT_DIR/check-artifact-retention.mjs"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
POLICY_DIR="$REPO_ROOT/.github/standards/runner-policy"
SCHEMA="$REPO_ROOT/.github/artifact-retention.schema.json"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TABLE=.github/artifact-retention.json
WORKFLOW=.github/workflows/build.yml
ACTION=.github/actions/pack/action.yml

# mk_tree <out-var>: a table whose every row one upload matches, with the
# retention the table names: an exact name, a dynamic name by its literal
# prefix, a computed name by its uploading job, a `max` row, and an upload in a
# composite action.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --sut "$SUT_MJS" --label artifact-retention || return 1
  dir="${!1}"
  mkdir -p "$dir/.github/workflows" "$dir/.github/actions/pack" "$dir/.github/standards/runner-policy"
  cp "$POLICY_DIR/package.json" "$dir/.github/standards/runner-policy/"
  ln -s "$POLICY_DIR/node_modules" "$dir/.github/standards/runner-policy/node_modules"
  cp "$SCHEMA" "$dir/.github/"
  cat >"$dir/$TABLE" <<'EOF'
{
  "$schema": "./artifact-retention.schema.json",
  "families": {
    "build-report": {
      "retention-days": 1,
      "readers": [".github/workflows/build.yml publish job, same run"],
      "reason": "Read only by its own run.",
      "scan": "none"
    },
    "lane-patch-*": {
      "retention-days": 7,
      "readers": [".github/workflows/build.yml publish job"],
      "reason": "A manual re-run of the publish job reads it.",
      "scan": "upload"
    },
    "verdict-*": {
      "retention-days": "max",
      "readers": [".github/workflows/build.yml gate job, look-back of 80 days"],
      "max-reader": ".github/workflows/build.yml",
      "reason": "The gate reads verdicts back to the pull request's creation.",
      "scan": "none",
      "uploads": [".github/workflows/build.yml#verdict"]
    },
    "pack-*": {
      "retention-days": 3,
      "readers": [".github/actions/pack/action.yml caller, same run"],
      "reason": "Read only by its own run.",
      "scan": "plaintext",
      "pending-cut": "1 day is enough."
    }
  }
}
EOF
  cat >"$dir/$WORKFLOW" <<'EOF'
on: pull_request
jobs:
  build:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/upload-artifact@v7
        with:
          name: build-report
          path: report.json
          retention-days: 1
      - id: scan-patch
        uses: ./.github/actions/scan-upload
        with:
          path: patch.diff
      - if: steps.scan-patch.outputs.clean == 'true'
        uses: actions/upload-artifact@v7
        with:
          name: lane-patch-${{ github.run_attempt }}
          path: patch.diff
          retention-days: 7
  verdict:
    runs-on: ubuntu-24.04
    steps:
      - id: name
        run: echo "name=verdict-1" >>"$GITHUB_OUTPUT"
      - uses: actions/upload-artifact@v7
        with:
          name: ${{ steps.name.outputs.name }}
          path: verdict.json
          retention-days: 90
EOF
  cat >"$dir/$ACTION" <<'EOF'
runs:
  using: composite
  steps:
    - id: scan
      shell: bash
      env:
        SCAN_PATHS: plain.json
      run: node "$GITHUB_ACTION_PATH/../scan-upload/scan-upload.mjs"
    - uses: actions/upload-artifact@v7
      with:
        name: pack-${{ github.run_id }}
        path: pack.tgz
        retention-days: 3
EOF
}

# run_case <label> <expected-rc> <setup> [<must-name>...]: build a tree, run
# <setup> in it, then the checker; assert the exit code and that every
# <must-name> string appears in the output.
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local tree out rc s
  mk_tree tree || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$tree" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  out="$(bash "$tree/scripts/check-artifact-retention.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

# subst <file> <from> <to>: replace every literal <from> in <file> with <to>.
subst() {
  local text
  text=$(<"$1") || return 1
  printf '%s\n' "${text//"$2"/"$3"}" >"$1"
}

# drop_line <file> <line>: remove every line of <file> equal to <line>.
drop_line() {
  local text
  text=$(grep -vxF -- "$2" "$1") || return 1
  printf '%s\n' "$text" >"$1"
}

# edit <file> <node expression>: rewrite a JSON file in place with a Node
# expression over `t`, the parsed file.
edit() {
  node -e 'const fs=require("fs");const f=process.argv[1];const t=JSON.parse(fs.readFileSync(f,"utf8"));'"$2"';fs.writeFileSync(f,JSON.stringify(t,null,2))' "$1"
}

run_case "a matching set passes" 0 ":" \
  "check-artifact-retention: 4 upload step(s) match"

run_case "an upload with no retention-days fails" 1 \
  "drop_line $WORKFLOW '          retention-days: 1'" \
  "$WORKFLOW:6: upload \`build-report\` sets no retention-days"

run_case "a name matching no family fails" 1 \
  "subst $WORKFLOW 'name: build-report' 'name: build-log'" \
  "$WORKFLOW:6: upload \`build-log\` matches no family in $TABLE"

run_case "a value differing from the table fails" 1 \
  "subst $WORKFLOW 'retention-days: 7' 'retention-days: 14'" \
  "$WORKFLOW:15: upload \`lane-patch-\${{ github.run_attempt }}\` keeps 14 days; $TABLE family \`lane-patch-*\` says 7"

run_case "a dynamic name maps by its literal prefix, not by a longer family" 1 \
  "subst $WORKFLOW 'name: lane-patch-' 'name: lane-patch-x-'" \
  "matches no family in $TABLE"

run_case "an upload in a composite action is checked" 1 \
  "subst $ACTION 'retention-days: 3' 'retention-days: 5'" \
  "$ACTION:9: upload \`pack-\${{ github.run_id }}\` keeps 5 days"

run_case "a computed name its job is not listed for fails" 1 \
  "edit $TABLE 't.families[\"verdict-*\"].uploads=[\".github/workflows/build.yml#build\"]'" \
  "$WORKFLOW:25: upload \`\${{ steps.name.outputs.name }}\` matches no family" \
  "$TABLE: family \`verdict-*\` lists upload .github/workflows/build.yml#build, which uploads no computed name"

run_case "a max row keeps 90 days, so 89 differs" 1 \
  "subst $WORKFLOW 'retention-days: 90' 'retention-days: 89'" \
  "keeps 89 days; $TABLE family \`verdict-*\` says max (90)"

run_case "a non-literal retention-days fails" 1 \
  "subst $WORKFLOW 'retention-days: 7' 'retention-days: \${{ inputs.days }}'" \
  "retention-days is not a whole number of days"

run_case "a step-output retention-days passes when its row names computed-by" 0 \
  "subst $WORKFLOW 'retention-days: 90' 'retention-days: \${{ steps.name.outputs.retention-days }}' && edit $TABLE 't.families[\"verdict-*\"][\"computed-by\"]=\".github/workflows/build.yml\"'" \
  "check-artifact-retention: 4 upload step(s) match"

run_case "a step-output retention-days fails when its row names no computed-by" 1 \
  "subst $WORKFLOW 'retention-days: 90' 'retention-days: \${{ steps.name.outputs.retention-days }}'" \
  "retention-days is not a whole number of days"

run_case "a computed-by naming no file of the tree fails" 1 \
  "edit $TABLE 't.families[\"verdict-*\"][\"computed-by\"]=\"scripts/gone.mjs\"'" \
  "$TABLE: family \`verdict-*\` computed-by scripts/gone.mjs names no file"

run_case "a row no upload matches fails" 1 \
  "edit $TABLE 't.families[\"old-*\"]={\"retention-days\":1,\"readers\":[\".github/workflows/build.yml\"],\"reason\":\"gone\"}'" \
  "$TABLE: family \`old-*\` matches no upload step"

run_case "a max row with no max-reader fails" 1 \
  "edit $TABLE 'delete t.families[\"verdict-*\"][\"max-reader\"]'" \
  "$TABLE: family \`verdict-*\` says max with no max-reader"

run_case "a max-reader that is not one of the readers fails" 1 \
  "edit $TABLE 't.families[\"verdict-*\"][\"max-reader\"]=\".github/actions/pack/action.yml\"'" \
  "max-reader .github/actions/pack/action.yml is none of its readers"

run_case "90 written as a number fails: the longest retention is spelled max" 1 \
  "edit $TABLE 't.families[\"verdict-*\"][\"retention-days\"]=90'" \
  "$TABLE: schema:"

run_case "a reader naming no file of the tree fails" 1 \
  "edit $TABLE 't.families[\"build-report\"].readers=[\"scripts/gone.mjs same run\"]'" \
  "$TABLE: family \`build-report\` reader scripts/gone.mjs names no file"

run_case "a row with no reason fails the schema" 1 \
  "edit $TABLE 'delete t.families[\"build-report\"].reason'" \
  "$TABLE: schema:"

run_case "a scanned family's upload with no scan step fails" 1 \
  "drop_line $WORKFLOW '        uses: ./.github/actions/scan-upload'" \
  "$WORKFLOW:15: upload \`lane-patch-\${{ github.run_attempt }}\` has no scan before it; $TABLE family \`lane-patch-*\` says scan: upload"

run_case "a scan over a different path does not count" 1 \
  "subst $WORKFLOW '          path: patch.diff
      - if' '          path: other.diff
      - if'" \
  "has no scan before it"

run_case "an upload whose if: does not require the scan's clean output fails" 1 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean' 'if: steps.other.outputs.clean'" \
  "has no scan before it"

run_case "a plaintext family with no scan step before the seal fails" 1 \
  "subst $ACTION 'scan-upload/scan-upload.mjs' 'seal.mjs'" \
  "$ACTION:9: upload \`pack-\${{ github.run_id }}\` has no scan step before it; $TABLE family \`pack-*\` says scan: plaintext"

run_case "a row with no scan field fails the schema" 1 \
  "edit $TABLE 'delete t.families[\"build-report\"].scan'" \
  "$TABLE: schema:"

run_case "a missing table fails as environment" 2 \
  "rm $TABLE" \
  "$TABLE"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  drop_line "$tree/$WORKFLOW" '          retention-days: 1'
  stdout="$(bash "$tree/scripts/check-artifact-retention.sh" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
else
  fail "discover mode: fixture build failed"
fi

# The yaml package missing is environment, not findings.
tree=""
if mk_tree tree; then
  rm "$tree/.github/standards/runner-policy/node_modules"
  out="$(bash "$tree/scripts/check-artifact-retention.sh" --check 2>&1 >/dev/null)"
  rc=$?
  if [[ $rc -eq 2 && $out == *"npm ci --prefix .github/standards/runner-policy"* ]]; then
    ok "a missing yaml package exits 2 and names the install"
  else
    fail "a missing yaml package should exit 2 naming the install (rc=$rc): $out"
  fi
else
  fail "missing package: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

# This checkout: every upload step carries the retention its row names.
out="$(bash "$SUT_SRC" --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "the repository's own workflows match the table"
else
  fail "the repository's own workflows should match the table (rc=$rc): $out"
fi

test_harness::report
