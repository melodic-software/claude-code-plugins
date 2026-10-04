#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /discipline:setup apply.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
# Expected values come from the key contract in reference/config.md:
# lever_scope takes deterministic or non-trivial, and the file is
# docs/conventions/discipline.yaml at the repository root. The schema has two
# keys, lever_scope and $schema (type string). Apply writes only lever_scope, so
# the $schema cases are "an invalid value on a key not being written".
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

# Fresh write: the key is written and reads back.
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
run "$repo" lever_scope=non-trivial
check 'fresh write exits 0' test "$CODE" -eq 0
check 'fresh write creates docs/conventions/discipline.yaml' test -f "$f"
check 'lever_scope reads back as non-trivial' test "$(bash "$READER" "$f" lever_scope)" = non-trivial
check 'fresh write creates no other file' test "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1

# Same value again: nothing changes.
before="$(cat "$f")"
run "$repo" lever_scope=non-trivial
check 'an unchanged value reports already configured and leaves the file' \
  test "$CODE" -eq 0 -a "$(cat "$f")" = "$before" -a -n "$(grep -F 'already configured' <<<"$OUT")"

# Existing file, different value, no --yes: diff printed, nothing written.
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
mkdir -p "$repo/docs/conventions"
printf '# team pick\nlever_scope: deterministic\n' >"$f"
before="$(cat "$f")"
run "$repo" lever_scope=non-trivial
check 'an existing file that would change exits 3 without --yes' test "$CODE" -eq 3
if [[ "$OUT" == *"-lever_scope: deterministic"* && "$OUT" == *"+lever_scope: non-trivial"* ]]; then pass 'the refusal prints the diff'; else fail 'the refusal prints the diff'; fi
check 'the existing file is untouched without --yes' test "$(cat "$f")" = "$before"

# Same change with --yes: written, comment kept.
run "$repo" --yes lever_scope=non-trivial
check 'with --yes the change is written' test "$CODE" -eq 0
check 'the written file keeps the comment' test "$(cat "$f")" = $'# team pick\nlever_scope: non-trivial'

# Adding the key to a file that holds only comments appends it.
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
mkdir -p "$repo/docs/conventions"
printf '# owned by the platform team\n' >"$f"
run "$repo" --yes lever_scope=deterministic
check 'the key is appended to a comment-only file' \
  test "$CODE" -eq 0 -a "$(cat "$f")" = $'# owned by the platform team\nlever_scope: deterministic'

# Invalid value and unknown key: refused, nothing created.
repo="$(new_repo)"
run "$repo" lever_scope=always
if [[ "$CODE" -eq 1 && "$OUT" == *"lever_scope=always"* ]]; then pass 'an invalid value exits 1 and names the key and value'; else fail 'an invalid value exits 1 and names the key and value'; fi
check 'an invalid value writes nothing' test ! -e "$repo/docs"
run "$repo" lever_scope=Deterministic
check 'a value differing only in case is refused' test "$CODE" -eq 1 -a ! -e "$repo/docs"
run "$repo" verbosity=high
check 'a key outside the schema exits 1 and writes nothing' test "$CODE" -eq 1 -a ! -e "$repo/docs"
run "$repo" 'lever_scope='
check 'an empty value argument exits 1 and writes nothing' test "$CODE" -eq 1 -a ! -e "$repo/docs"

# An existing file holding a key outside the schema is refused and kept.
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
mkdir -p "$repo/docs/conventions"
printf 'lever_scope: deterministic\nverbosity: high\n' >"$f"
before="$(cat "$f")"
run "$repo" --yes lever_scope=non-trivial
if one_line_refusal && [[ "$OUT" == *"verbosity"* && "$(cat "$f")" == "$before" ]]; then pass 'an existing unknown key is a one-line refusal and the file kept'; else fail 'an existing unknown key is a one-line refusal and the file kept'; fi

# Shapes a schema validator rejects although each line looks plausible.
# --check reports each as WARN. apply overwrites only an out-of-list, empty
# (`key:`) or null/~ value on the key it writes, and refuses every other
# problem with one line and the file untouched.
shape_case() { # shape_case <label> <refuse|replace> <warning text> <file content>
  local label="$1" want="$2" warning="$3" content="$4" repo f before
  repo="$(new_repo)"
  f="$repo/docs/conventions/discipline.yaml"
  mkdir -p "$repo/docs/conventions"
  printf '%s' "$content" >"$f"
  before="$(cat "$f")"
  run "$repo" --check
  if [[ "$CODE" -eq 1 && "$OUT" == *"WARN"*"$warning"* && "$OUT" != *PASS* ]]; then pass "--check warns on $label"; else fail "--check warns on $label"; fi
  run "$repo" --yes lever_scope=non-trivial
  if [[ "$want" == refuse ]]; then
    if one_line_refusal && [[ "$(cat "$f")" == "$before" ]]; then pass "apply refuses $label in one line and leaves the file"; else fail "apply refuses $label in one line and leaves the file"; fi
  elif [[ "$CODE" -eq 0 && "$(cat "$f")" == "lever_scope: non-trivial" ]]; then
    pass "apply replaces $label with the given value"
  else
    fail "apply replaces $label with the given value"
  fi
}
shape_case 'a duplicate key' refuse 'set more than once' $'lever_scope: deterministic\nlever_scope: non-trivial\n'
shape_case 'a duplicate key that differs only by spaces' refuse 'set more than once' $'lever_scope: deterministic\n"lever_scope ": non-trivial\n'
shape_case 'a key with spaces around its name' refuse 'spaces around its name' $'" lever_scope": deterministic\n'
shape_case 'a block map' refuse 'map or a list' $'lever_scope:\n  mode: deterministic\n'
shape_case 'a block list' refuse 'map or a list' $'lever_scope:\n  - deterministic\n'
shape_case 'a flow list' refuse 'map or a list' $'lever_scope: [deterministic]\n'
shape_case 'a one-item flow list' refuse 'map or a list' $'lever_scope: [x]\n'
shape_case 'a flow map' refuse 'map or a list' $'lever_scope: {a: 1}\n'
shape_case 'an empty flow list' refuse 'map or a list' $'lever_scope: []\n'
shape_case 'an empty flow map' refuse 'map or a list' $'lever_scope: {}\n'
shape_case 'an empty value' replace 'is empty' $'lever_scope:\n'
shape_case 'an empty double-quoted value' refuse 'empty string' $'lever_scope: ""\n'
shape_case 'an empty single-quoted value' refuse 'empty string' $'lever_scope: \'\'\n'
shape_case 'a null value' replace 'lever_scope=null is not one of' $'lever_scope: null\n'
shape_case 'a ~ value' replace 'lever_scope=~ is not one of' $'lever_scope: ~\n'
shape_case 'an out-of-list value' replace 'lever_scope=always is not one of' $'lever_scope: always\n'
shape_case 'an anchor on the target line' refuse 'not part of the subset' $'lever_scope: &a deterministic\n'
shape_case 'an unclosed quote on the target line' refuse 'unclosed quote' $'lever_scope: "deterministic\n'
shape_case 'an unknown key with an empty value' refuse 'stray is not in the schema' $'stray:\n'
shape_case 'a parse error on another line' refuse 'unclosed quote' $'lever_scope: deterministic\nnote: "open\n'
shape_case 'a $schema flow map' refuse '$schema holds a map or a list' $'"$schema": {a: 1}\nlever_scope: deterministic\n'
shape_case 'an empty $schema flow list' refuse '$schema holds a map or a list' $'"$schema": []\nlever_scope: deterministic\n'
shape_case 'a one-item $schema flow list' refuse '$schema holds a map or a list' $'"$schema": [x]\nlever_scope: deterministic\n'
shape_case 'an empty quoted $schema' refuse '$schema is empty or null' $'"$schema": ""\nlever_scope: deterministic\n'
shape_case 'a null $schema' refuse '$schema is empty or null' $'"$schema": null\nlever_scope: deterministic\n'
shape_case 'an empty $schema' refuse '$schema is empty or null' $'"$schema":\nlever_scope: deterministic\n'

# A key given twice on the command line is refused before anything is
# written, whether or not the file exists.
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
mkdir -p "$repo/docs/conventions"
printf 'lever_scope: deterministic\n' >"$f"
run "$repo" --yes lever_scope=non-trivial lever_scope=deterministic
if one_line_refusal && [[ "$(cat "$f")" == 'lever_scope: deterministic' ]]; then pass 'a key given twice is a one-line refusal and the file is unchanged'; else fail 'a key given twice is a one-line refusal and the file is unchanged'; fi
repo="$(new_repo)"
run "$repo" --yes lever_scope=non-trivial lever_scope=non-trivial
if one_line_refusal && [[ ! -e "$repo/docs" ]]; then pass 'a key given twice with no file is a one-line refusal and creates nothing'; else fail 'a key given twice with no file is a one-line refusal and creates nothing'; fi

# --check: absent, valid.
repo="$(new_repo)"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *absent* ]]; then pass '--check on a missing file reports absent and exits 0'; else fail '--check on a missing file reports absent and exits 0'; fi
mkdir -p "$repo/docs/conventions"
printf 'lever_scope: non-trivial # agreed in review\n' >"$repo/docs/conventions/discipline.yaml"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *"PASS lever_scope: non-trivial"* ]]; then pass '--check on a valid file prints the key'; else fail '--check on a valid file prints the key'; fi
printf '"$schema": https://example.test/discipline.schema.json\nlever_scope: deterministic\n' >"$repo/docs/conventions/discipline.yaml"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *"PASS lever_scope: deterministic"* ]]; then pass '--check accepts a $schema URL string'; else fail '--check accepts a $schema URL string'; fi
run "$repo" --yes lever_scope=non-trivial
if [[ "$CODE" -eq 0 && "$(cat "$repo/docs/conventions/discipline.yaml")" == $'"$schema": https://example.test/discipline.schema.json\nlever_scope: non-trivial' ]]; then pass 'apply keeps a $schema URL string and writes the key'; else fail 'apply keeps a $schema URL string and writes the key'; fi

# Write-path guards, each a one-line refusal with nothing written outside.
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" lever_scope=deterministic
check 'a symlinked docs/conventions is refused and nothing lands outside' test "$CODE" -eq 1 -a -z "$(ls -A "$outside")"

repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
printf 'lever_scope: deterministic\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln -s "$outside/shared.yaml" "$repo/docs/conventions/discipline.yaml"
run "$repo" --yes lever_scope=non-trivial
check 'a symlinked target is refused and its target untouched' \
  test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'lever_scope: deterministic'

repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
printf 'lever_scope: deterministic\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln "$outside/shared.yaml" "$repo/docs/conventions/discipline.yaml"
run "$repo" --yes lever_scope=non-trivial
check 'a hard-linked target is refused and the other link is untouched' \
  test "$CODE" -eq 1 -a "$(cat "$outside/shared.yaml")" = 'lever_scope: deterministic'

repo="$(new_repo)"
mkdir -p "$repo/docs/conventions/discipline.yaml"
run "$repo" --yes lever_scope=deterministic
check 'a directory at the target path is a one-line refusal' one_line_refusal
run "$repo" --check
check '--check on a directory at the target path is a one-line refusal' one_line_refusal

repo="$(new_repo)"
printf 'not a directory\n' >"$repo/docs"
run "$repo" lever_scope=deterministic
check 'docs as a file is a one-line refusal' one_line_refusal
check 'docs as a file is left as it was' test "$(cat "$repo/docs")" = 'not a directory'

# An unwritable docs/conventions: the temp-file open fails, one line, no temp left.
if [[ "$(id -u)" -ne 0 ]]; then
  repo="$(new_repo)"
  mkdir -p "$repo/docs/conventions"
  chmod a-w "$repo/docs/conventions"
  run "$repo" lever_scope=deterministic
  check 'an unwritable directory is a one-line refusal' one_line_refusal
  check 'an unwritable directory leaves no temp file' test -z "$(ls -A "$repo/docs/conventions")"
  chmod u+w "$repo/docs/conventions"
fi

# A failed write (file size limit 0): one line, no temp file left.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
OUT="$(ulimit -f 0 && HOME="$FAKE_HOME" node "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
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
run_preloaded close-fails "$repo" lever_scope=deterministic
check 'a failed close is a one-line refusal' one_line_refusal
check 'a failed close removes the temp file' test -z "$(ls -A "$repo/docs/conventions")"

# A failed close followed by a failed cleanup: still one line, no stack trace.
preload close-and-rm-fail "$TRACK_TMP_FD" "$CLOSE_FAILS" \
  'fs.rmSync = () => { throw Object.assign(new Error("EBUSY: resource busy, rm"), { code: "EBUSY" }); };'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
run_preloaded close-and-rm-fail "$repo" lever_scope=deterministic
check 'a failed close and a failed cleanup are one line' one_line_refusal

# A failed rename: one line, the temp file removed, no target created.
preload rename-fails 'fs.renameSync = () => { throw Object.assign(new Error("EXDEV: cross-device link, rename"), { code: "EXDEV" }); };'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
run_preloaded rename-fails "$repo" lever_scope=deterministic
check 'a failed rename is a one-line refusal' one_line_refusal
check 'a failed rename leaves no temp file and no target' test -z "$(ls -A "$repo/docs/conventions")"

# A failed read of the existing file, for apply and --check: one line, the file
# unchanged, no temp file. A preload, not chmod 000, so the case holds as root.
preload read-fails 'const rf = fs.readFileSync;' \
  'fs.readFileSync = (p, ...r) => { if (String(p).endsWith("docs/conventions/discipline.yaml")) throw Object.assign(new Error("EACCES: permission denied, open"), { code: "EACCES" }); return rf(p, ...r); };'
repo="$(new_repo)"
f="$repo/docs/conventions/discipline.yaml"
mkdir -p "$repo/docs/conventions"
printf 'lever_scope: deterministic\n' >"$f"
run_preloaded read-fails "$repo" --yes lever_scope=non-trivial
check 'a failed read is a one-line refusal' one_line_refusal
check 'a failed read leaves the file unchanged' test "$(cat "$f")" = 'lever_scope: deterministic'
check 'a failed read leaves no temp file' test -z "$(find "$repo/docs/conventions" -name '*.tmp')"
run_preloaded read-fails "$repo" --check
check '--check with a failed read is a one-line refusal' one_line_refusal
check '--check with a failed read leaves the file unchanged' test "$(cat "$f")" = 'lever_scope: deterministic'
check '--check with a failed read leaves no temp file' test -z "$(find "$repo/docs/conventions" -name '*.tmp')"

# A failed realpath on the root: one line, no stack trace. Only the root path
# fails, so node can still resolve the script itself.
preload realpath-fails 'const rp = fs.realpathSync;' \
  'fs.realpathSync = (p, ...r) => { if (String(p) === process.env.FAIL_REALPATH) throw Object.assign(new Error("EACCES: permission denied, realpath"), { code: "EACCES" }); return rp(p, ...r); };'
repo="$(new_repo)"
OUT="$(FAIL_REALPATH="$repo" HOME="$FAKE_HOME" node --require "$WORKROOT/realpath-fails.cjs" "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
if [[ "$CODE" -ne 0 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" != *"    at "* && ! -e "$repo/docs" ]]; then pass 'a failed realpath is a one-line refusal and writes nothing'; else fail 'a failed realpath is a one-line refusal and writes nothing'; fi

# docs/ swapped for a symlink right after it is created: the next mkdir must
# not create docs/conventions outside the repository.
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
preload swap-docs 'const mk = fs.mkdirSync;' \
  'fs.mkdirSync = (p, ...r) => { const out = mk(p, ...r); if (String(p).endsWith("/docs")) { fs.rmdirSync(p); fs.symlinkSync(process.env.SWAP_TO, p); } return out; };'
repo="$(new_repo)"
OUT="$(SWAP_TO="$outside" HOME="$FAKE_HOME" node --require "$WORKROOT/swap-docs.cjs" "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
check 'a docs symlink swap between mkdirs is a one-line refusal' one_line_refusal
check 'a docs symlink swap between mkdirs creates nothing outside' test -z "$(ls -A "$outside")"

# docs/conventions swapped for a symlink right after it is created, with
# cleanup disabled: the re-check before the temp file opens must refuse, so no
# file is ever created outside the repository.
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
preload swap-conventions-before-open 'const mk = fs.mkdirSync;' \
  'fs.mkdirSync = (p, ...r) => { const out = mk(p, ...r); if (String(p).endsWith("/docs/conventions")) { fs.rmdirSync(p); fs.symlinkSync(process.env.SWAP_TO, p); } return out; };' \
  'fs.rmSync = () => {};'
repo="$(new_repo)"
OUT="$(SWAP_TO="$outside" HOME="$FAKE_HOME" node --require "$WORKROOT/swap-conventions-before-open.cjs" "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
check 'a docs/conventions symlink swap before the temp file opens is a one-line refusal' one_line_refusal
check 'a docs/conventions symlink swap before the temp file opens creates nothing outside' test -z "$(ls -A "$outside")"

# docs/conventions swapped for a symlink to an outside directory after the temp
# file is written: the re-check before the rename must refuse.
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
preload swap-conventions-before-rename 'const wr = fs.writeSync;' \
  'fs.writeSync = (fd, ...r) => { const out = wr(fd, ...r); const c = process.env.SWAP_FROM; fs.renameSync(c, process.env.SWAP_TO + "/conventions"); fs.symlinkSync(process.env.SWAP_TO + "/conventions", c); return out; };'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
OUT="$(SWAP_FROM="$repo/docs/conventions" SWAP_TO="$outside" HOME="$FAKE_HOME" node --require "$WORKROOT/swap-conventions-before-rename.cjs" "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
check 'a docs/conventions symlink swap before the rename is a one-line refusal' one_line_refusal
check 'a docs/conventions symlink swap before the rename writes nothing outside' test -z "$(ls -A "$outside/conventions")"
check 'a docs/conventions symlink swap before the rename creates no target' test ! -e "$outside/conventions/discipline.yaml"

# A temp file name another process already holds (fixed pid 4242): the
# exclusive open refuses in one line and the foreign file survives unchanged.
preload fixed-pid 'Object.defineProperty(process, "pid", { value: 4242 });'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
foreign="$repo/docs/conventions/.discipline.yaml.4242.tmp"
printf 'someone else\n' >"$foreign"
run_preloaded fixed-pid "$repo" lever_scope=deterministic
check 'an existing temp file name is a one-line refusal' one_line_refusal
check 'an existing temp file is left unchanged' test "$(cat "$foreign" 2>/dev/null)" = 'someone else'
check 'an existing temp file name creates no target' test ! -e "$repo/docs/conventions/discipline.yaml"

# A failed close of the temp file: the descriptor is closed exactly once.
preload count-closes "$TRACK_TMP_FD" 'let closes = 0;' \
  'fs.closeSync = (fd) => { if (fd !== -1 && fd === tmpFd) { closes++; if (closes > 1) process.stderr.write("double close\n"); close(fd); throw Object.assign(new Error("EIO: i/o error, close"), { code: "EIO" }); } return close(fd); };'
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
run_preloaded count-closes "$repo" lever_scope=deterministic
check 'a failed close is one line and never closes the descriptor twice' one_line_refusal
if [[ "$OUT" != *"double close"* ]]; then pass 'the temp descriptor is closed once'; else fail 'the temp descriptor is closed once'; fi

# Root rule: a root that is $HOME, or an ancestor of it, is refused.
repo="$(new_repo)"
OUT="$(HOME="$repo" node "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
check 'a root equal to $HOME is a one-line refusal' one_line_refusal
check 'a root equal to $HOME writes nothing' test ! -e "$repo/docs"
mkdir -p "$repo/inner-home"
OUT="$(HOME="$repo/inner-home" node "$SUT" --root "$repo" lever_scope=deterministic 2>&1)"
CODE=$?
check 'a root above $HOME is a one-line refusal' one_line_refusal

# A root path holding shell syntax is data, never evaluated.
weird="$WORKROOT/"'repo-$(touch PWNED)'
mkdir -p "$weird"
git -C "$weird" init -q
(cd "$WORKROOT" && BASH_COMPAT=51 HOME="$FAKE_HOME" node "$SUT" --root "$weird" lever_scope=deterministic >/dev/null 2>&1)
check 'a root path with $(...) is written as a plain path' test -f "$weird/docs/conventions/discipline.yaml"
check 'the $(...) in the root path never runs' test ! -e "$WORKROOT/PWNED" -a ! -e "$weird/PWNED"

# Usage errors.
run "$repo"
check 'no <key>=<value> exits 2' test "$CODE" -eq 2
run "$repo" --check lever_scope=deterministic
check '--check with a pair exits 2' test "$CODE" -eq 2
OUT="$(cd "$WORKROOT" && HOME="$FAKE_HOME" GIT_CEILING_DIRECTORIES="$WORKROOT" node "$SUT" lever_scope=deterministic 2>&1)"
CODE=$?
if [[ "$CODE" -eq 2 && "$OUT" == *"git working tree"* ]]; then pass 'outside a git working tree without --root exits 2'; else fail 'outside a git working tree without --root exits 2'; fi

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
