#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP="$SCRIPT_DIR/provision-prerequisites.sh"
LISTER="$SCRIPT_DIR/provision-prerequisites.mjs"

FAILED=0
CASE_NUM=0
# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

command -v node >/dev/null 2>&1 || skip_suite "node not available"

TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

fake_bin="$TEST_TMPDIR/fake-npm-bin"
mkdir -p "$fake_bin"
cat >"$fake_bin/npm" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$PWD" "$*" >>"$FAKE_NPM_LOG"
mkdir -p node_modules/fake-pkg && : >node_modules/fake-pkg/package.json
exit "${FAKE_NPM_EXIT:-0}"
EOF
chmod +x "$fake_bin/npm"

tree() {
  local t="$TEST_TMPDIR/$1"
  mkdir -p "$t/.claude/ecosystems" "$t/docs/conventions/ecosystems" "$t/tools"
  printf '{}\n' >"$t/package-lock.json"
  printf '{}\n' >"$t/tools/package-lock.json"
  cat >"$t/.claude/ecosystems/typescript.yaml" <<'EOF'
globs: ["*.ts"]
check-cmd: "npx --no biome check ."
requires:
  check-cmd:
    - name: root toolchain
      probe: "test -d node_modules/fake-pkg"
      install:
        manager: npm
        lockfile: package-lock.json
    - name: tools packages
      probe: "test -d tools/node_modules/fake-pkg"
      hint: "npm ci in tools/"
EOF
  printf '%s' "$t"
}

t=$(tree list-basic)
out=$(node "$LISTER" list "$t" 2>"$TEST_TMPDIR/err-list.txt")
assert_exit "list: exits 0" 0 "$?"
assert_eq "list: one line for the install entry, none for the report-only one" \
  ".	root toolchain	package-lock.json" "$out"

cat >"$t/docs/conventions/ecosystems/node.yaml" <<'EOF'
globs: ["*.mjs"]
gates:
  - name: policy
    cmd: "node tools/policy.mjs"
    requires:
      - name: policy packages
        probe: "test -d tools/node_modules/fake-pkg"
        install:
          manager: npm
          lockfile: tools/package-lock.json
EOF
out=$(node "$LISTER" list "$t" 2>/dev/null)
assert_contains "list: a gate's install entry in the other record home is listed" "$out" "tools	policy packages	tools/package-lock.json"

bad=$(tree list-bad)
cat >"$bad/.claude/ecosystems/typescript.yaml" <<'EOF'
globs: ["*.ts"]
requires:
  check-cmd:
    - name: extra key
      probe: "true"
      install:
        manager: npm
        lockfile: package-lock.json
        command: "npm install"
    - name: other manager
      probe: "true"
      install:
        manager: uv
        lockfile: package-lock.json
    - name: escapes
      probe: "true"
      install:
        manager: npm
        lockfile: ../package-lock.json
    - name: absent lockfile
      probe: "true"
      install:
        manager: npm
        lockfile: missing/package-lock.json
EOF
out=$(node "$LISTER" list "$bad" 2>"$TEST_TMPDIR/err-bad.txt")
assert_exit "list: entries outside the contract still exit 0" 0 "$?"
assert_eq "list: no entry outside the contract is listed" "" "$out"
err=$(cat "$TEST_TMPDIR/err-bad.txt")
assert_contains "list: an unknown install key is named" "$err" "extra key: install holds an unknown key: command"
assert_contains "list: a manager other than npm is named" "$err" "other manager: install.manager must be npm"
assert_contains "list: a lockfile outside the repository is named" "$err" "must be a repo-relative path"
assert_contains "list: a missing lockfile is named" "$err" "missing/package-lock.json does not exist"

node "$LISTER" list >/dev/null 2>&1
assert_exit "list: no repository is a usage error" 2 "$?"

t=$(tree step-ok)
log="$TEST_TMPDIR/npm-ok.log"
PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" "$t" 2>"$TEST_TMPDIR/err-ok.txt"
assert_exit "step: a declared install succeeds" 0 "$?"
assert_eq "step: npm ci runs once, in the lockfile's directory, with scripts off" \
  "$t|ci --ignore-scripts --no-audit --no-fund" "$(cat "$log" 2>/dev/null)"
(cd "$t" && test -d node_modules/fake-pkg)
assert_exit "step: the entry's probe now finds the prerequisite" 0 "$?"
assert_file_absent "step: the report-only entry's lockfile is not installed" "$t/tools/node_modules"

t="$TEST_TMPDIR/undeclared"
mkdir -p "$t"
printf '{}\n' >"$t/package-lock.json"
log="$TEST_TMPDIR/npm-undeclared.log"
PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" "$t" 2>/dev/null
assert_exit "step: nothing declared exits 0" 0 "$?"
assert_file_absent "step: an undeclared lockfile is not installed" "$log"

t=$(tree step-fail)
log="$TEST_TMPDIR/npm-fail.log"
PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" FAKE_NPM_EXIT=7 bash "$STEP" "$t" 2>"$TEST_TMPDIR/err-fail.txt"
assert_exit "step: a failed install exits 1" 1 "$?"
err=$(cat "$TEST_TMPDIR/err-fail.txt")
assert_contains "step: the warning names the entry and npm's exit" "$err" "npm ci failed (exit 7); root toolchain (package-lock.json) not provisioned"
assert_contains "step: the warning names the command that installs it" "$err" "run npm ci --ignore-scripts --no-audit --no-fund in $t"
rm -rf "${t:?}/node_modules"
(cd "$t" && test -d node_modules/fake-pkg)
assert_exit "step: after a failed install the probe still reports absent" 1 "$?"

no_npm_path=""
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [[ -n "$d" && ! -x "$d/npm" ]] && no_npm_path="${no_npm_path:+$no_npm_path:}$d"
done
if PATH="$no_npm_path" command -v node >/dev/null 2>&1 && PATH="$no_npm_path" command -v bash >/dev/null 2>&1; then
  t=$(tree step-nonpm)
  PATH="$no_npm_path" "$(command -v bash)" "$STEP" "$t" 2>"$TEST_TMPDIR/err-nonpm.txt"
  assert_exit "step: no npm exits 1" 1 "$?"
  assert_contains "step: no npm names the entry" "$(cat "$TEST_TMPDIR/err-nonpm.txt")" "npm is not on PATH; root toolchain (package-lock.json) not provisioned"
else
  skip_case "npm shares a PATH directory with node or bash; cannot hide it"
fi

if command -v flock >/dev/null 2>&1 && cp -al --help >/dev/null 2>&1; then
  seeds="$TEST_TMPDIR/seeds"
  log="$TEST_TMPDIR/npm-seed.log"
  one=$(tree seed-one)
  two=$(tree seed-two)
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" --seed-root "$seeds" "$one" 2>/dev/null
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" --seed-root "$seeds" "$two" 2>"$TEST_TMPDIR/err-seed.txt"
  assert_exit "seed: the second tree succeeds" 0 "$?"
  assert_eq "seed: npm ci ran once for two trees" "1" "$(wc -l <"$log" | tr -d ' ')"
  assert_contains "seed: the install ran with scripts off" "$(cat "$log")" "ci --ignore-scripts --no-audit --no-fund"
  if [[ "$one/node_modules/fake-pkg/package.json" -ef "$two/node_modules/fake-pkg/package.json" ]]; then
    pass "seed: both trees hard-link the same file"
  else
    fail "seed: both trees hard-link the same file" "same inode" "different files"
  fi

  seeds="$TEST_TMPDIR/seeds-shrinkwrap"
  log="$TEST_TMPDIR/npm-shrinkwrap.log"
  one=$(tree shrinkwrap-one)
  two=$(tree shrinkwrap-two)
  printf '{"a":1}\n' >"$one/npm-shrinkwrap.json"
  printf '{"a":2}\n' >"$two/npm-shrinkwrap.json"
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" --seed-root "$seeds" "$one" 2>/dev/null
  PATH="$fake_bin:$PATH" FAKE_NPM_LOG="$log" bash "$STEP" --seed-root "$seeds" "$two" 2>/dev/null
  assert_eq "seed: a different npm-shrinkwrap.json builds its own seed" "2" "$(wc -l <"$log" | tr -d ' ')"
else
  skip_case "flock or a hard-linking cp -al is unavailable; the shared seed is not used here"
fi

bash "$STEP" >/dev/null 2>&1
assert_exit "step: no tree is a usage error" 2 "$?"

t=$(tree flag-last)
for flag in --cap --seed-root; do
  timeout 10 bash "$STEP" "$t" "$flag" >/dev/null 2>"$TEST_TMPDIR/err-flag-last.txt"
  assert_exit "step: $flag with no value is a usage error" 2 "$?"
  assert_contains "step: $flag with no value is named" "$(cat "$TEST_TMPDIR/err-flag-last.txt")" "$flag needs a value"
done

[[ $FAILED -eq 0 ]] || exit 1
