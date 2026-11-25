#!/usr/bin/env bash
# test-scope: scripts/ci-deps/package.json
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
DEPS_DIR="$REPO_ROOT/scripts/ci-deps"
SCHEMA="$REPO_ROOT/.github/artifact-retention.schema.json"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

TABLE=.github/artifact-retention.json
WORKFLOW=.github/workflows/build.yml
ACTION=.github/actions/pack/action.yml

mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --sut "$SUT_MJS" --label artifact-retention || return 1
  dir="${!1}"
  mkdir -p "$dir/.github/workflows" "$dir/.github/actions/pack" "$dir/scripts/ci-deps"
  cp "$DEPS_DIR/package.json" "$dir/scripts/ci-deps/"
  ln -s "$DEPS_DIR/node_modules" "$dir/scripts/ci-deps/node_modules"
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
      uses: ./.github/actions/scan-upload
      with:
        path: plain.json
    - uses: actions/upload-artifact@v7
      with:
        name: pack-${{ github.run_id }}
        path: pack.tgz
        retention-days: 3
EOF
}

run_case() { test_harness::check_case mk_tree check-artifact-retention.sh "$@"; }

subst() {
  local text
  text=$(<"$1") || return 1
  printf '%s\n' "${text//"$2"/"$3"}" >"$1"
}

drop_line() {
  local text
  text=$(grep -vxF -- "$2" "$1") || return 1
  printf '%s\n' "$text" >"$1"
}

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
  "$ACTION:8: upload \`pack-\${{ github.run_id }}\` keeps 5 days"

run_case "a computed name its job is not listed for fails" 1 \
  "edit $TABLE 't.families[\"verdict-*\"].uploads=[\".github/workflows/build.yml#build\"]'" \
  "$WORKFLOW:26: upload \`\${{ steps.name.outputs.name }}\` matches no family" \
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
  "edit $TABLE 't.families[\"old-*\"]={\"retention-days\":1,\"readers\":[\".github/workflows/build.yml\"],\"reason\":\"gone\",\"scan\":\"none\"}'" \
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
  "$WORKFLOW:14: upload \`lane-patch-\${{ github.run_attempt }}\` has no scan before it; $TABLE family \`lane-patch-*\` says scan: upload"

REMOTE_SCAN=melodic-software/ci-workflows/.github/actions/scan-upload
SHA=09cf6f2ecd22f7188e62552dea9af48adbd23bb1

run_case "a ci-workflows scan-upload at main counts as the scan" 0 \
  "subst $WORKFLOW 'uses: ./.github/actions/scan-upload' 'uses: $REMOTE_SCAN@main'" \
  "check-artifact-retention: 4 upload step(s) match"

for ref in "$SHA" v1 09cf6f2 mainline; do
  run_case "a ci-workflows scan-upload at ref $ref is no scan" 1 \
    "subst $WORKFLOW 'uses: ./.github/actions/scan-upload' 'uses: $REMOTE_SCAN@$ref'" \
    "has no scan before it"
done

run_case "another owner's scan-upload at main is no scan" 1 \
  "subst $WORKFLOW 'uses: ./.github/actions/scan-upload' 'uses: other-org/ci-workflows/.github/actions/scan-upload@main'" \
  "has no scan before it"

run_case "a scan over a different path does not count" 1 \
  "subst $WORKFLOW '          path: patch.diff
      - if' '          path: other.diff
      - if'" \
  "has no scan before it"

run_case "an upload whose if: does not require the scan's clean output fails" 1 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean' 'if: steps.other.outputs.clean'" \
  "has no scan before it"

run_case "an if: with text around \${{ }} is always true, so it gates nothing" 1 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean == ' 'if: (\${{ always() }}) && steps.scan-patch.outputs.clean == '" \
  "has no scan before it"

run_case "a top-level || beside the clean output gates nothing" 1 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean == ' 'if: always() || steps.scan-patch.outputs.clean == '" \
  "has no scan before it"

run_case "an upload that runs when its scan step does not fails" 1 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean == ' 'if: (always()) && steps.scan-patch.outputs.clean == '" \
  "has no scan before it"

run_case "the upload's condition repeats its scan step's if:, parenthesized" 0 \
  "subst $WORKFLOW 'if: steps.scan-patch.outputs.clean == ' 'if: (always() && inputs.go) && steps.scan-patch.outputs.clean == ' && subst $WORKFLOW '      - id: scan-patch' '      - id: scan-patch
        if: always() && inputs.go'" \
  "check-artifact-retention: 4 upload step(s) match"

run_case "a plaintext family with no scan step before the seal fails" 1 \
  "subst $ACTION 'uses: ./.github/actions/scan-upload' 'uses: ./.github/actions/seal'" \
  "$ACTION:8: upload \`pack-\${{ github.run_id }}\` has no scan step before it; $TABLE family \`pack-*\` says scan: plaintext"

add_sealed_job() {
  local perms=$1
  shift
  {
    printf '%s\n' '  sealed:' '    runs-on: ubuntu-24.04' "    $perms" '    steps:'
    printf '%s\n' "$@"
    printf '%s\n' '      - uses: actions/upload-artifact@v7' '        with:' "          name: pack-\${{ github.run_attempt }}" '          path: pack.sealed' '          retention-days: 3'
  } >>"$WORKFLOW"
  edit "$TABLE" 't.families["pack-*"]["sealed-upstream"] = [".github/workflows/build.yml#sealed"]'
}

run_case "a plaintext upload in a listed sealed-upstream job with no checkout, secret or permissions needs no scan step" 0 \
  "add_sealed_job 'permissions: {}'" \
  "check-artifact-retention: 5 upload step(s) match"

run_case "the same upload in a job the row does not list still needs its scan step" 1 \
  "add_sealed_job 'permissions: {}' && edit $TABLE 'delete t.families[\"pack-*\"][\"sealed-upstream\"]'" \
  "upload \`pack-\${{ github.run_attempt }}\` has no scan step before it; $TABLE family \`pack-*\` says scan: plaintext"

run_case "a listed sealed-upstream job with a checkout fails" 1 \
  "add_sealed_job 'permissions: {}' '      - uses: actions/checkout@v7'" \
  "is in a sealed-upstream job of family \`pack-*\` that holds a checkout, a secret, an environment or permissions other than {}"

run_case "a listed sealed-upstream job that reads a secret fails" 1 \
  "add_sealed_job 'permissions: {}' '      - run: echo ok' '        env:' '          TOKEN: \${{ secrets.TOKEN }}'" \
  "is in a sealed-upstream job of family \`pack-*\` that holds a checkout, a secret, an environment or permissions other than {}"

ISOLATION_MESSAGE="is in a sealed-upstream job of family \`pack-*\` that holds a checkout, a secret, an environment or permissions other than {}"
for form in "TOKEN: \${{ secrets['TOKEN'] }}" "TOKEN: \${{ secrets[\"TOKEN\"] }}" "ALL: \${{ toJSON(secrets) }}" "ALL: \${{ secrets }}"; do
  export SECRET_LINE="          $form"
  run_case "a listed sealed-upstream job whose env holds ${form#*: } fails" 1 \
    "add_sealed_job 'permissions: {}' '      - run: echo ok' '        env:' \"\$SECRET_LINE\"" \
    "$ISOLATION_MESSAGE"
done

export SECRET_LINE="          token: \${{ secrets.TOKEN }}"
run_case "a listed sealed-upstream job whose with: value reads a secret fails" 1 \
  "add_sealed_job 'permissions: {}' '      - uses: acme/tool@v1' '        with:' \"\$SECRET_LINE\"" \
  "$ISOLATION_MESSAGE"

export SECRET_PERMS=$'permissions: {}\n    secrets: inherit'
run_case "a listed sealed-upstream job with secrets: inherit fails" 1 \
  "add_sealed_job \"\$SECRET_PERMS\"" \
  "$ISOLATION_MESSAGE"

run_case "the word secrets outside an expression is no secret" 0 \
  "add_sealed_job 'permissions: {}' '      - run: echo no secrets here'" \
  "check-artifact-retention: 5 upload step(s) match"

run_case "a listed sealed-upstream job with a token permission fails" 1 \
  "add_sealed_job 'permissions: { contents: read }'" \
  "is in a sealed-upstream job of family \`pack-*\` that holds a checkout, a secret, an environment or permissions other than {}"

run_case "a sealed-upstream job that holds no unscanned upload of the family fails" 1 \
  "edit $TABLE 't.families[\"pack-*\"][\"sealed-upstream\"] = [\".github/actions/pack/action.yml#runs\"]'" \
  "$TABLE: family \`pack-*\` lists sealed-upstream .github/actions/pack/action.yml#runs, which holds no upload of it without a scan step"

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
  test_harness::assert_discover_quiet "$tree/scripts/check-artifact-retention.sh"
else
  fail "discover mode: fixture build failed"
fi

# The yaml package missing is environment, not findings.
tree=""
if mk_tree tree; then
  rm "$tree/scripts/ci-deps/node_modules"
  out="$(bash "$tree/scripts/check-artifact-retention.sh" --check 2>&1 >/dev/null)"
  rc=$?
  if [[ $rc -eq 2 && $out == *"npm ci --prefix scripts/ci-deps"* ]]; then
    ok "a missing yaml package exits 2 and names the install"
  else
    fail "a missing yaml package should exit 2 naming the install (rc=$rc): $out"
  fi
else
  fail "missing package: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

out="$(bash "$SUT_SRC" --check 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "the repository's own workflows match the table"
else
  fail "the repository's own workflows should match the table (rc=$rc): $out"
fi

test_harness::report
