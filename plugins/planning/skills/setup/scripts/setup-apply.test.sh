#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /planning:setup apply.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
# Expected values come from the key contract in reference/config.md:
# plan_store takes local or tracker, phase_order takes composed,
# subtraction-first or riskiest-first, and the file is
# docs/conventions/planning.yaml at the repository root.
# Labels and one fixture path hold a literal $HOME or $(...) on purpose.
# shellcheck disable=SC2016
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup-apply.mjs"
READER="$SCRIPT_DIR/parse-concern-value.sh"

WORKROOT="$(mktemp -d)"
trap 'chmod -R u+w "$WORKROOT" 2>/dev/null; rm -rf "$WORKROOT"' EXIT
# A HOME outside every test repository, so the root rule does not refuse them.
FAKE_HOME="$WORKROOT/home"
mkdir -p "$FAKE_HOME"

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
}
check() { # check <label> <command...>: pass when the command succeeds
  local label="$1"
  shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}

new_repo() {
  local dir
  dir="$(mktemp -d "$WORKROOT/repo.XXXXXX")"
  git -C "$dir" init -q
  printf '%s\n' "$dir"
}

OUT=""
CODE=0
run() { # run <repo> [args...]
  local repo="$1"
  shift
  OUT="$(HOME="$FAKE_HOME" node "$SUT" --root "$repo" "$@" 2>&1)"
  CODE=$?
}
one_line_refusal() { [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" != *"    at "* ]]; }

# Fresh write: both keys written, each reads back.
repo="$(new_repo)"
f="$repo/docs/conventions/planning.yaml"
run "$repo" phase_order=riskiest-first plan_store=tracker
check 'fresh write exits 0' test "$CODE" -eq 0
check 'fresh write creates docs/conventions/planning.yaml' test -f "$f"
check 'phase_order reads back as riskiest-first' test "$(bash "$READER" "$f" phase_order)" = riskiest-first
check 'plan_store reads back as tracker' test "$(bash "$READER" "$f" plan_store)" = tracker
check 'fresh write creates no other file' test "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1

# Same value again: nothing changes.
before="$(cat "$f")"
run "$repo" phase_order=riskiest-first
check 'an unchanged value reports already configured and leaves the file' \
  test "$CODE" -eq 0 -a "$(cat "$f")" = "$before" -a -n "$(grep -F 'already configured' <<<"$OUT")"

# Existing file, different value, no --yes: diff printed, nothing written.
repo="$(new_repo)"
f="$repo/docs/conventions/planning.yaml"
mkdir -p "$repo/docs/conventions"
printf '# team pick\nplan_store: local\nphase_order: composed\n' >"$f"
before="$(cat "$f")"
run "$repo" phase_order=subtraction-first
check 'an existing file that would change exits 3 without --yes' test "$CODE" -eq 3
if [[ "$OUT" == *"-phase_order: composed"* && "$OUT" == *"+phase_order: subtraction-first"* ]]; then pass 'the refusal prints the diff'; else fail 'the refusal prints the diff'; fi
check 'the existing file is untouched without --yes' test "$(cat "$f")" = "$before"

# Same change with --yes: written, comment and the other key kept.
run "$repo" --yes phase_order=subtraction-first
check 'with --yes the change is written' test "$CODE" -eq 0
check 'the written file keeps the comment and plan_store' \
  test "$(cat "$f")" = $'# team pick\nplan_store: local\nphase_order: subtraction-first'

# Adding a key the file does not hold yet appends it.
repo="$(new_repo)"
f="$repo/docs/conventions/planning.yaml"
mkdir -p "$repo/docs/conventions"
printf 'plan_store: tracker\n' >"$f"
run "$repo" --yes phase_order=composed
check 'a new key is appended to an existing file' test "$CODE" -eq 0 -a "$(cat "$f")" = $'plan_store: tracker\nphase_order: composed'

# Invalid value and unknown key: refused, nothing created.
repo="$(new_repo)"
run "$repo" phase_order=risky-first
if [[ "$CODE" -eq 1 && "$OUT" == *"phase_order=risky-first"* ]]; then pass 'an invalid value exits 1 and names the key and value'; else fail 'an invalid value exits 1 and names the key and value'; fi
check 'an invalid value writes nothing' test ! -e "$repo/docs"
run "$repo" scaffold_stubs=true
check 'a key outside the schema exits 1 and writes nothing' test "$CODE" -eq 1 -a ! -e "$repo/docs"
run "$repo" 'phase_order='
check 'an empty value argument exits 1 and writes nothing' test "$CODE" -eq 1 -a ! -e "$repo/docs"

# An existing file holding a key outside the schema is refused and kept.
repo="$(new_repo)"
f="$repo/docs/conventions/planning.yaml"
mkdir -p "$repo/docs/conventions"
printf 'phase_order: composed\nverbosity: high\n' >"$f"
before="$(cat "$f")"
run "$repo" --yes phase_order=riskiest-first
if [[ "$CODE" -eq 1 && "$OUT" == *"verbosity"* && "$(cat "$f")" == "$before" ]]; then pass 'an existing unknown key is refused and the file kept'; else fail 'an existing unknown key is refused and the file kept'; fi

# An invalid existing value is replaced by a valid one.
printf 'phase_order: risky-first\n' >"$f"
run "$repo" --yes phase_order=composed
check 'an invalid existing value is replaced by a valid one' \
  test "$CODE" -eq 0 -a "$(bash "$READER" "$f" phase_order)" = composed

# Shapes a schema validator rejects although each line looks plausible.
# --check reports each as WARN. apply overwrites only an out-of-list, empty
# (`key:`) or null/~ value on the key it writes, and refuses every other
# problem with one line and the file untouched.
shape_case() { # shape_case <label> <refuse|replace> <warning text> <file content>
  local label="$1" want="$2" warning="$3" content="$4" repo f before
  repo="$(new_repo)"
  f="$repo/docs/conventions/planning.yaml"
  mkdir -p "$repo/docs/conventions"
  printf '%s' "$content" >"$f"
  before="$(cat "$f")"
  run "$repo" --check
  if [[ "$CODE" -eq 1 && "$OUT" == *"WARN"*"$warning"* && "$OUT" != *PASS* ]]; then pass "--check warns on $label"; else fail "--check warns on $label"; fi
  run "$repo" --yes phase_order=riskiest-first
  if [[ "$want" == refuse ]]; then
    if one_line_refusal && [[ "$(cat "$f")" == "$before" ]]; then pass "apply refuses $label in one line and leaves the file"; else fail "apply refuses $label in one line and leaves the file"; fi
  elif [[ "$CODE" -eq 0 && "$(cat "$f")" == "phase_order: riskiest-first" ]]; then
    pass "apply replaces $label with the given value"
  else
    fail "apply replaces $label with the given value"
  fi
}
shape_case 'a duplicate key' refuse 'set more than once' $'phase_order: composed\nphase_order: riskiest-first\n'
shape_case 'a duplicate key that differs only by spaces' refuse 'set more than once' $'phase_order: composed\n"phase_order ": riskiest-first\n'
shape_case 'a key with spaces around its name' refuse 'spaces around its name' $'" phase_order": composed\n'
shape_case 'a block map' refuse 'map or a list' $'phase_order:\n  mode: composed\n'
shape_case 'a block list' refuse 'map or a list' $'phase_order:\n  - composed\n'
shape_case 'a flow list' refuse 'map or a list' $'phase_order: [composed]\n'
shape_case 'a flow map' refuse 'map or a list' $'phase_order: {mode: composed}\n'
shape_case 'an empty flow list' refuse 'map or a list' $'phase_order: []\n'
shape_case 'an empty value' replace 'is empty' $'phase_order:\n'
shape_case 'an empty double-quoted value' refuse 'empty string' $'phase_order: ""\n'
shape_case 'an empty single-quoted value' refuse 'empty string' $'phase_order: \'\'\n'
shape_case 'a null value' replace 'phase_order=null is not one of' $'phase_order: null\n'
shape_case 'a ~ value' replace 'phase_order=~ is not one of' $'phase_order: ~\n'
shape_case 'an out-of-list value' replace 'phase_order=risky-first is not one of' $'phase_order: risky-first\n'
shape_case 'an anchor on the target line' refuse 'not part of the subset' $'phase_order: &a composed\n'
shape_case 'an unclosed quote on the target line' refuse 'unclosed quote' $'phase_order: "composed\n'
shape_case 'an unknown key with an empty value' refuse 'stray is not in the schema' $'stray:\n'
shape_case 'an out-of-list value on a key not being written' refuse 'plan_store=bogus is not one of' $'plan_store: bogus\n'

# A key given twice on the command line is refused before anything is
# written, whether or not the file exists.
repo="$(new_repo)"
f="$repo/docs/conventions/planning.yaml"
mkdir -p "$repo/docs/conventions"
printf 'phase_order: composed\n' >"$f"
run "$repo" --yes phase_order=riskiest-first phase_order=subtraction-first
if one_line_refusal && [[ "$(cat "$f")" == 'phase_order: composed' ]]; then pass 'a key given twice is a one-line refusal and the file is unchanged'; else fail 'a key given twice is a one-line refusal and the file is unchanged'; fi
repo="$(new_repo)"
run "$repo" --yes phase_order=composed phase_order=composed
if one_line_refusal && [[ ! -e "$repo/docs" ]]; then pass 'a key given twice with no file is a one-line refusal and creates nothing'; else fail 'a key given twice with no file is a one-line refusal and creates nothing'; fi

# --check: absent, valid.
repo="$(new_repo)"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *absent* ]]; then pass '--check on a missing file reports absent and exits 0'; else fail '--check on a missing file reports absent and exits 0'; fi
mkdir -p "$repo/docs/conventions"
printf 'phase_order: subtraction-first\n' >"$repo/docs/conventions/planning.yaml"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *"PASS phase_order: subtraction-first"* && "$OUT" == *"PASS plan_store: (unset)"* ]]; then pass '--check on a valid file prints each key'; else fail '--check on a valid file prints each key'; fi

# Write-path guards, each a one-line refusal with nothing written outside.
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" phase_order=composed
check 'a symlinked docs/conventions is refused and nothing lands outside' test "$CODE" -eq 1 -a -z "$(ls -A "$outside")"

repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
printf 'phase_order: composed\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/shared.yaml" "$repo/docs/conventions/planning.yaml"
run "$repo" --yes phase_order=riskiest-first
check 'a symlinked target is refused and its target untouched' \
  test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'phase_order: composed'

repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
printf 'phase_order: composed\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln "$outside/shared.yaml" "$repo/docs/conventions/planning.yaml"
run "$repo" --yes phase_order=riskiest-first
check 'a hard-linked target is refused and the other link is untouched' \
  test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'phase_order: composed'

repo="$(new_repo)"
mkdir -p "$repo/docs/conventions/planning.yaml"
run "$repo" --yes phase_order=composed
check 'a directory at the target path is a one-line refusal' one_line_refusal
run "$repo" --check
check '--check on a directory at the target path is a one-line refusal' one_line_refusal

repo="$(new_repo)"
printf 'not a directory\n' >"$repo/docs"
run "$repo" phase_order=composed
check 'docs as a file is a one-line refusal' one_line_refusal
check 'docs as a file is left as it was' test "$(cat "$repo/docs")" = 'not a directory'

# An unwritable docs/conventions: the temp-file open fails, one line, no temp left.
if [[ "$(id -u)" -ne 0 ]]; then
  repo="$(new_repo)"
  mkdir -p "$repo/docs/conventions"
  chmod a-w "$repo/docs/conventions"
  run "$repo" phase_order=composed
  check 'an unwritable directory is a one-line refusal' one_line_refusal
  check 'an unwritable directory leaves no temp file' test -z "$(ls -A "$repo/docs/conventions")"
  chmod u+w "$repo/docs/conventions"
fi

# A failed write (file size limit 0): one line, no temp file left.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
OUT="$(ulimit -f 0 && HOME="$FAKE_HOME" node "$SUT" --root "$repo" phase_order=composed 2>&1)"
CODE=$?
check 'a failed write is a one-line refusal' one_line_refusal
check 'a failed write removes the temp file' test -z "$(ls -A "$repo/docs/conventions")"

# Preloads that inject filesystem faults into the script's node:fs calls.
preload() { # preload <name> <js line...>: writes $WORKROOT/<name>.cjs
  local name="$1"
  shift
  printf '%s\n' 'const fs = require("node:fs");' "$@" 'require("node:module").syncBuiltinESMExports();' >"$WORKROOT/$name.cjs"
}
run_preloaded() { # run_preloaded <name> <repo> [args...]
  local name="$1" repo="$2"
  shift 2
  OUT="$(HOME="$FAKE_HOME" node --require "$WORKROOT/$name.cjs" "$SUT" --root "$repo" "$@" 2>&1)"
  CODE=$?
}
TRACK_TMP_FD='const open = fs.openSync, close = fs.closeSync; let tmpFd = -1; fs.openSync = (p, ...r) => { const fd = open(p, ...r); if (String(p).endsWith(".tmp")) tmpFd = fd; return fd; };'
CLOSE_FAILS='fs.closeSync = (fd) => { close(fd); if (fd === tmpFd) { tmpFd = -1; throw Object.assign(new Error("EIO: i/o error, close"), { code: "EIO" }); } };'

# A close that fails after releasing the descriptor (close(2) may report EIO).
preload close-fails "$TRACK_TMP_FD" "$CLOSE_FAILS"
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
run_preloaded close-fails "$repo" phase_order=composed
check 'a failed close is a one-line refusal' one_line_refusal
check 'a failed close removes the temp file' test -z "$(ls -A "$repo/docs/conventions")"

# A failed close followed by a failed cleanup: still one line, no stack trace.
preload close-and-rm-fail "$TRACK_TMP_FD" "$CLOSE_FAILS" \
  'fs.rmSync = () => { throw Object.assign(new Error("EBUSY: resource busy, rm"), { code: "EBUSY" }); };'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
run_preloaded close-and-rm-fail "$repo" phase_order=composed
check 'a failed close and a failed cleanup are one line' one_line_refusal

# docs/ swapped for a symlink right after it is created: the next mkdir must
# not create docs/conventions outside the repository.
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
preload swap-docs 'const mk = fs.mkdirSync;' \
  'fs.mkdirSync = (p, ...r) => { const out = mk(p, ...r); if (String(p).endsWith("/docs")) { fs.rmdirSync(p); fs.symlinkSync(process.env.SWAP_TO, p); } return out; };'
repo="$(new_repo)"
OUT="$(SWAP_TO="$outside" HOME="$FAKE_HOME" node --require "$WORKROOT/swap-docs.cjs" "$SUT" --root "$repo" phase_order=composed 2>&1)"
CODE=$?
check 'a docs symlink swap between mkdirs is a one-line refusal' one_line_refusal
check 'a docs symlink swap between mkdirs creates nothing outside' test -z "$(ls -A "$outside")"

# Root rule: a root that is $HOME, or an ancestor of it, is refused.
repo="$(new_repo)"
OUT="$(HOME="$repo" node "$SUT" --root "$repo" phase_order=composed 2>&1)"
CODE=$?
check 'a root equal to $HOME is a one-line refusal' one_line_refusal
check 'a root equal to $HOME writes nothing' test ! -e "$repo/docs"
mkdir -p "$repo/inner-home"
OUT="$(HOME="$repo/inner-home" node "$SUT" --root "$repo" phase_order=composed 2>&1)"
CODE=$?
check 'a root above $HOME is a one-line refusal' one_line_refusal

# A root path holding shell syntax is data, never evaluated.
weird="$WORKROOT/"'repo-$(touch PWNED)'
mkdir -p "$weird"
git -C "$weird" init -q
(cd "$WORKROOT" && BASH_COMPAT=51 HOME="$FAKE_HOME" node "$SUT" --root "$weird" phase_order=composed >/dev/null 2>&1)
check 'a root path with $(...) is written as a plain path' test -f "$weird/docs/conventions/planning.yaml"
check 'the $(...) in the root path never runs' test ! -e "$WORKROOT/PWNED" -a ! -e "$weird/PWNED"

# Usage errors.
run "$repo"
check 'no <key>=<value> exits 2' test "$CODE" -eq 2
run "$repo" --check phase_order=composed
check '--check with a pair exits 2' test "$CODE" -eq 2
OUT="$(cd "$WORKROOT" && HOME="$FAKE_HOME" GIT_CEILING_DIRECTORIES="$WORKROOT" node "$SUT" phase_order=composed 2>&1)"
CODE=$?
if [[ "$CODE" -eq 2 && "$OUT" == *"git working tree"* ]]; then pass 'outside a git working tree without --root exits 2'; else fail 'outside a git working tree without --root exits 2'; fi

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
