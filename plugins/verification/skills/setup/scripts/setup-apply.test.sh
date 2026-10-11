#!/usr/bin/env bash
# Tests for setup-apply.mjs: the narrow write of docs/conventions/verification.yaml.
# Each case builds its own repository root in a temp directory; expected values
# come from the schema's allowed values (path, live, strict) and the script's stated
# exit codes, not from the script's output.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPLY="$SCRIPT_DIR/setup-apply.mjs"
TEST_TMPDIR="$(mktemp -d)"
trap 'chmod -R u+w "$TEST_TMPDIR" 2>/dev/null; rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: node is not on PATH\n' >&2
  exit 0
fi

# new_root <name>: a fresh repository root with docs/conventions/ present.
new_root() {
  local r="$TEST_TMPDIR/$1"
  mkdir -p "$r/docs/conventions"
  printf '%s' "$r"
}
yaml_of() { printf '%s/docs/conventions/verification.yaml' "$1"; }
run() { node "$APPLY" "$@" 2>&1; }
leftover_temps() {
  local n=0 f
  for f in "$1"/docs/conventions/.verification.yaml.*.tmp; do
    [[ -e "$f" ]] && n=$((n + 1))
  done
  printf '%d' "$n"
}

# --- Case 1: an absent file is created with the value -----------------------
R1="$(new_root c1)"
out="$(run --root "$R1" proof_level=live)"
assert_eq "case 1: writing to an absent file exits 0" "0" "$?"
assert_eq "case 1: the file holds the value on its own line" "1" "$(grep -cx 'proof_level: live' "$(yaml_of "$R1")")"
assert_contains "case 1: the file names its schema" "$(cat "$(yaml_of "$R1")")" "verification.schema.json"
assert_contains "case 1: the output names the written path" "$out" "wrote docs/conventions/verification.yaml"

R1B="$TEST_TMPDIR/c1b"
mkdir -p "$R1B"
run --root "$R1B" proof_level=strict >/dev/null
assert_eq "case 1: missing docs/conventions directories are created" "0" "$?"
assert_contains "case 1: the created file holds the value" "$(cat "$(yaml_of "$R1B")")" "proof_level: strict"

# --- Case 2: the same value again writes nothing ---------------------------
out="$(run --root "$R1" proof_level=live)"
assert_eq "case 2: a value already in place exits 0" "0" "$?"
assert_contains "case 2: it says already configured" "$out" "already configured"

# --- Case 3: a change to an existing file needs --yes ------------------------
before="$(cat "$(yaml_of "$R1")")"
out="$(run --root "$R1" proof_level=strict)"
assert_eq "case 3: a change without --yes exits 3" "3" "$?"
assert_contains "case 3: the diff shows the new line" "$out" "+proof_level: strict"
assert_eq "case 3: the file is unchanged without --yes" "$before" "$(cat "$(yaml_of "$R1")")"
run --root "$R1" --yes proof_level=strict >/dev/null
assert_eq "case 3: the change with --yes exits 0" "0" "$?"
assert_eq "case 3: the file holds the new value on its own line" "1" "$(grep -cx 'proof_level: strict' "$(yaml_of "$R1")")"
assert_eq "case 3: no temp file is left behind" "0" "$(leftover_temps "$R1")"

# --- Case 4: values and keys outside the schema are refused ------------------
R4="$(new_root c4)"
for bad in maybe Live STRICT true '' '""'; do
  run --root "$R4" "proof_level=$bad" >/dev/null
  assert_eq "case 4: proof_level=$bad exits 1" "1" "$?"
done
run --root "$R4" digest_policy=off >/dev/null
assert_eq "case 4: a key outside the schema exits 1" "1" "$?"
assert_eq "case 4: no refused value created the file" "0" "$([[ -e "$(yaml_of "$R4")" ]] && echo 1 || echo 0)"

# --- Case 5: --check on absent, valid and invalid files ----------------------
R5="$(new_root c5)"
out="$(run --root "$R5" --check)"
assert_eq "case 5: --check on an absent file exits 0" "0" "$?"
assert_contains "case 5: an absent file is INFO" "$out" "INFO"
printf 'proof_level: live\n' >"$(yaml_of "$R5")"
out="$(run --root "$R5" --check)"
assert_eq "case 5: --check on a valid file exits 0" "0" "$?"
assert_contains "case 5: a valid file reports the value" "$out" "PASS proof_level: live"

# check_warns <label> <file body>: --check exits 1 with a WARN, and apply over
# the same file refuses unless its result validates.
check_warns() {
  local r
  r="$(new_root "w-$1")"
  printf '%s' "$2" >"$(yaml_of "$r")"
  local out
  out="$(run --root "$r" --check)"
  assert_eq "case 6: --check exits 1 on $1" "1" "$?"
  assert_contains "case 6: --check prints WARN on $1" "$out" "WARN"
}
check_warns "an invalid value" $'proof_level: sometimes\n'
check_warns "a quoted out-of-list value" $'proof_level: "loose"\n'
check_warns "an empty double-quoted string" $'proof_level: ""\n'
check_warns "an empty single-quoted string" $'proof_level: \'\'\n'
check_warns "an empty value" $'proof_level:\n'
check_warns "a block list" $'proof_level:\n  - true\n'
check_warns "a block map" $'proof_level:\n  on: true\n'
check_warns "a flow list" $'proof_level: [true]\n'
check_warns "a flow map" $'proof_level: {on: true}\n'
check_warns "an empty flow list" $'proof_level: []\n'
R6L="$(new_root w-named)"
printf 'proof_level: []\n' >"$(yaml_of "$R6L")"
assert_contains "case 6: the WARN for an empty flow list names the key and the value" \
  "$(run --root "$R6L" --check)" "proof_level=[]"
check_warns "a duplicate key" $'proof_level: strict\nproof_level: live\n'
check_warns "a duplicate key after trimming" $'proof_level: strict\n"proof_level ": live\n'
check_warns "an unknown key" $'proof_level: strict\nproof_levels: live\n'

# --- Case 7: apply refuses a result that would not validate ------------------
R7="$(new_root c7)"
printf 'proof_level: strict\nproof_level: strict\n' >"$(yaml_of "$R7")"
before="$(cat "$(yaml_of "$R7")")"
run --root "$R7" --yes proof_level=live >/dev/null
assert_eq "case 7: apply over a duplicate key exits 1" "1" "$?"
assert_eq "case 7: the duplicate-key file is unchanged" "$before" "$(cat "$(yaml_of "$R7")")"
R7B="$(new_root c7b)"
printf 'proof_level:\n  - true\n' >"$(yaml_of "$R7B")"
before="$(cat "$(yaml_of "$R7B")")"
run --root "$R7B" --yes proof_level=live >/dev/null
assert_eq "case 7: apply over a block list exits 1" "1" "$?"
assert_eq "case 7: the block-list file is unchanged" "$before" "$(cat "$(yaml_of "$R7B")")"

# --- Case 8: unsafe paths are refused ----------------------------------------
R8="$(new_root c8)"
OUTSIDE="$TEST_TMPDIR/outside.yaml"
printf 'kept\n' >"$OUTSIDE"
ln -s "$OUTSIDE" "$(yaml_of "$R8")"
run --root "$R8" --yes proof_level=live >/dev/null
assert_eq "case 8: a symlinked target exits 1" "1" "$?"
assert_eq "case 8: the symlink's target is untouched" "kept" "$(cat "$OUTSIDE")"

R8B="$(new_root c8b)"
printf 'proof_level: strict\n' >"$(yaml_of "$R8B")"
ln "$(yaml_of "$R8B")" "$TEST_TMPDIR/hardlink.yaml"
run --root "$R8B" --yes proof_level=live >/dev/null
assert_eq "case 8: a hard-linked target exits 1" "1" "$?"
assert_eq "case 8: the hard link's other name is untouched" "proof_level: strict" "$(cat "$TEST_TMPDIR/hardlink.yaml")"

R8C="$TEST_TMPDIR/c8c"
mkdir -p "$R8C/docs" "$TEST_TMPDIR/elsewhere"
ln -s "$TEST_TMPDIR/elsewhere" "$R8C/docs/conventions"
run --root "$R8C" proof_level=live >/dev/null
assert_eq "case 8: a symlinked docs/conventions exits 1" "1" "$?"
assert_eq "case 8: nothing was written through the symlinked directory" "0" \
  "$([[ -e "$TEST_TMPDIR/elsewhere/verification.yaml" ]] && echo 1 || echo 0)"

R8D="$(new_root c8d)"
HOME="$R8D" node "$APPLY" --root "$R8D" proof_level=live >/dev/null 2>&1
assert_eq "case 8: a root equal to \$HOME exits 1" "1" "$?"
HOME="$R8D/sub" node "$APPLY" --root "$R8D" proof_level=live >/dev/null 2>&1
assert_eq "case 8: a root that is an ancestor of \$HOME exits 1" "1" "$?"
assert_eq "case 8: neither \$HOME refusal wrote the file" "0" "$([[ -e "$(yaml_of "$R8D")" ]] && echo 1 || echo 0)"

# --- Case 9: a failed write is one refusal line and leaves no temp -----------
R9="$(new_root c9)"
chmod 555 "$R9/docs/conventions"
if [[ -w "$R9/docs/conventions" ]]; then
  printf 'SKIP: case 9: this user can write a read-only directory\n' >&2
else
  err="$(node "$APPLY" --root "$R9" proof_level=live 2>&1 >/dev/null)"
  assert_eq "case 9: an unwritable directory exits 1" "1" "$?"
  assert_eq "case 9: the refusal is one line" "1" "$(printf '%s\n' "$err" | grep -c .)"
  assert_contains "case 9: the refusal says nothing was written" "$err" "nothing written"
  assert_eq "case 9: no temp file is left behind" "0" "$(leftover_temps "$R9")"
fi
chmod 755 "$R9/docs/conventions"

# --- Case 10: a root path holding a command substitution is never run --------
PWNED="$TEST_TMPDIR/pwned10"
R10="$TEST_TMPDIR/\$(touch $PWNED)"
mkdir -p "$R10/docs/conventions"
run --root "$R10" proof_level=live >/dev/null
assert_eq "case 10: a substitution-shaped root still writes" "0" "$?"
assert_eq "case 10: the substitution never ran" "0" "$([[ -e "$PWNED" ]] && echo 1 || echo 0)"

# --- Case 11: usage errors ----------------------------------------------------
run --root "$R5" >/dev/null
assert_eq "case 11: no key=value exits 2" "2" "$?"
run --root "$R5" --check proof_level=strict >/dev/null
assert_eq "case 11: --check with a key=value exits 2" "2" "$?"
run --root "$TEST_TMPDIR/no-such-root" proof_level=strict >/dev/null
assert_eq "case 11: a missing root exits 2" "2" "$?"

# one_line <label> <output>: a refusal is exactly one line with no stack frame.
one_line() {
  assert_eq "$1: the refusal is one line" "1" "$(printf '%s\n' "$2" | grep -c .)"
  assert_eq "$1: the refusal carries no stack trace" "0" "$(printf '%s\n' "$2" | grep -c '^    at ')"
}
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }

# --- Case 12: apply validates the existing file and refuses what it cannot overwrite
# apply_refuses <label> <file body>: apply --yes exits 1 with one line and
# leaves the file byte for byte as it was.
apply_refuses() {
  local r f before out
  r="$(new_root "ar-$1")"
  f="$(yaml_of "$r")"
  printf '%s' "$2" >"$f"
  before="$(od -c "$f")"
  out="$(run --root "$r" --yes proof_level=live)"
  assert_eq "case 12: apply over $1 exits 1" "1" "$?"
  one_line "case 12: apply over $1" "$out"
  assert_eq "case 12: apply over $1 leaves the file untouched" "$before" "$(od -c "$f")"
  assert_eq "case 12: apply over $1 leaves no temp file" "0" "$(leftover_temps "$r")"
  APPLY_OUT="$out"
}
apply_refuses "a duplicate key after trimming" $'proof_level: strict\n"proof_level ": live\n'
assert_eq "case 12: a trimmed duplicate is not called an unknown key" "0" \
  "$(printf '%s\n' "$APPLY_OUT" | grep -c 'not in the schema')"
assert_contains "case 12: a trimmed duplicate names the key once" "$APPLY_OUT" "key proof_level is set more than once"
apply_refuses "a duplicate key" $'proof_level: maybe\nproof_level: maybe\n'
apply_refuses "an empty flow list" $'proof_level: []\n'
apply_refuses "a one-item flow list" $'proof_level: [true]\n'
apply_refuses "an empty flow map" $'proof_level: {}\n'
apply_refuses "a flow map" $'proof_level: {a: 1}\n'
apply_refuses "a block list" $'proof_level:\n  - true\n'
apply_refuses "a block map" $'proof_level:\n  on: true\n'
apply_refuses "an empty double-quoted string" $'proof_level: ""\n'
apply_refuses "an empty single-quoted string" $'proof_level: \'\'\n'
apply_refuses "an unknown key set twice" $'stray: 1\nstray: 2\n'
apply_refuses "an unknown key holding a block map" $'stray:\n  a: 1\n'
apply_refuses "an unknown key holding a flow list" $'stray: [1]\n'
# An unknown key in the file is named in one warning, ignored, and its line is
# kept byte for byte; the asked-for key is written.
apply_keeps_unknown() { # apply_keeps_unknown <label> <file body> <expected file>
  local r f out
  r="$(new_root "ak-$1")"
  f="$(yaml_of "$r")"
  printf '%s' "$2" >"$f"
  out="$(run --root "$r" --yes proof_level=live)"
  assert_eq "case 12: apply beside $1 exits 0" "0" "$?"
  assert_eq "case 12: apply beside $1 warns once" "1" "$(printf '%s\n' "$out" | grep -c 'WARN.*key stray is not in the schema')"
  assert_eq "case 12: apply beside $1 keeps its line" "$3" "$(cat "$f")"
}
apply_keeps_unknown "an unknown key alone" $'stray: 1\n' $'stray: 1\nproof_level: live'
apply_keeps_unknown "an unknown empty key" $'stray:\n' $'stray:\nproof_level: live'
apply_keeps_unknown "an unknown empty key beside the real one" $'proof_level: strict\nstray:\n' $'proof_level: live\nstray:'
apply_refuses "a parse error on another line" $'proof_level: strict\nother: "open\n'
apply_refuses "a parse error on the key's own line" $'proof_level: "open\n'
apply_refuses "an unclosed flow list on the key's own line" $'proof_level: [true\n'

# --- Case 13: apply overwrites an out-of-list, empty or null value -----------
# apply_replaces <label> <file body>: apply --yes exits 0 and the file is the
# single line the operator asked for.
apply_replaces() {
  local r f
  r="$(new_root "rp-$1")"
  f="$(yaml_of "$r")"
  printf '%s' "$2" >"$f"
  run --root "$r" --yes proof_level=strict >/dev/null
  assert_eq "case 13: apply over $1 exits 0" "0" "$?"
  assert_eq "case 13: apply over $1 leaves the asked-for line" "proof_level: strict" "$(cat "$f")"
}
apply_replaces "an out-of-list word" $'proof_level: maybe\n'
apply_replaces "a quoted out-of-list value" $'proof_level: "loose"\n'
apply_replaces "an empty value" $'proof_level:\n'
apply_replaces "a null value" $'proof_level: null\n'
apply_replaces "a tilde null" $'proof_level: ~\n'

# --- Case 14: a key given twice on the command line is refused -----------------
# pair_twice <label> <pair> <pair>: exits 1 with one line, file absent or present.
pair_twice() {
  local r f out before
  r="$(new_root "pt-$1")"
  f="$(yaml_of "$r")"
  out="$(run --root "$r" "$2" "$3")"
  assert_eq "case 14: $1 with no file exits 1" "1" "$?"
  one_line "case 14: $1 with no file" "$out"
  assert_eq "case 14: $1 with no file creates nothing" "0" "$(exists "$f")"
  printf 'proof_level: strict\n' >"$f"
  before="$(od -c "$f")"
  out="$(run --root "$r" --yes "$2" "$3")"
  assert_eq "case 14: $1 over a file exits 1" "1" "$?"
  one_line "case 14: $1 over a file" "$out"
  assert_eq "case 14: $1 over a file leaves it untouched" "$before" "$(od -c "$f")"
}
pair_twice "the same pair twice" proof_level=live proof_level=live
pair_twice "two values for one key" proof_level=live proof_level=strict
pair_twice "a key repeated after trimming" proof_level=live ' proof_level =false'

# --- Case 15: every other refusal is one line ---------------------------------
R15="$(new_root c15)"
for bad in maybe '' '""'; do
  out="$(run --root "$R15" "proof_level=$bad")"
  one_line "case 15: proof_level=$bad" "$out"
done
out="$(run --root "$R15" digest_policy=off)"
one_line "case 15: an unknown command-line key" "$out"
out="$(run --root "$R8" --yes proof_level=live)"
one_line "case 15: a symlinked target" "$out"
out="$(run --root "$R8B" --yes proof_level=live)"
one_line "case 15: a hard-linked target" "$out"
out="$(run --root "$R8C" proof_level=live)"
one_line "case 15: a symlinked docs/conventions" "$out"
out="$(HOME="$R8D" node "$APPLY" --root "$R8D" proof_level=live 2>&1)"
one_line "case 15: a root equal to \$HOME" "$out"
R15D="$(new_root c15d)"
mkdir "$(yaml_of "$R15D")"
out="$(run --root "$R15D" --yes proof_level=live)"
assert_eq "case 15: a directory at the target exits 1" "1" "$?"
one_line "case 15: a directory at the target" "$out"
out="$(run --root "$R15D" --check)"
one_line "case 15: --check on a directory at the target" "$out"
R15F="$TEST_TMPDIR/c15f"
mkdir -p "$R15F"
printf 'not a directory\n' >"$R15F/docs"
out="$(run --root "$R15F" proof_level=live)"
assert_eq "case 15: docs as a file exits 1" "1" "$?"
one_line "case 15: docs as a file" "$out"
R15W="$(new_root c15w)"
out="$(ulimit -f 0 && node "$APPLY" --root "$R15W" proof_level=live 2>&1)"
assert_eq "case 15: a write over the file-size limit exits 1" "1" "$?"
one_line "case 15: a failed write" "$out"
assert_eq "case 15: a failed write leaves no temp file" "0" "$(leftover_temps "$R15W")"

# --- Case 16: an unreadable target is one line, apply and --check alike --------
R16="$(new_root c16)"
printf 'proof_level: strict\n' >"$(yaml_of "$R16")"
chmod 000 "$(yaml_of "$R16")"
if [[ -r "$(yaml_of "$R16")" ]]; then
  printf 'SKIP: case 16: this user can read a mode-000 file\n' >&2
else
  out="$(run --root "$R16" --yes proof_level=live)"
  assert_eq "case 16: apply over an unreadable target exits 1" "1" "$?"
  one_line "case 16: apply over an unreadable target" "$out"
  out="$(run --root "$R16" --check)"
  assert_eq "case 16: --check on an unreadable target exits 1" "1" "$?"
  one_line "case 16: --check on an unreadable target" "$out"
fi
chmod 644 "$(yaml_of "$R16")"

# Preloads stand in for failures the file system will not produce on demand.
# Each patches node:fs before the script's ESM imports bind.
preload() { # preload <name> <body lines...>
  local p="$TEST_TMPDIR/$1.cjs"
  shift
  printf '%s\n' 'const fs = require("node:fs");' "$@" 'require("node:module").syncBuiltinESMExports();' >"$p"
  printf '%s' "$p"
}

# --- Case 17: a realpath failure is one line ----------------------------------
# Node resolves its own module paths through realpathSync too, so the preload
# fails only for paths under this case's root.
R17="$(new_root c17)"
P17="$(preload realpath-fails \
  'const rp = fs.realpathSync;' \
  "fs.realpathSync = (p, ...r) => { if (String(p).startsWith(\"$R17\")) throw Object.assign(new Error(\"EACCES: permission denied, realpath\"), { code: \"EACCES\" }); return rp(p, ...r); };")"
out="$(node --require "$P17" "$APPLY" --root "$R17" proof_level=live 2>&1)"
assert_eq "case 17: a failed realpath exits 1" "1" "$?"
one_line "case 17: a failed realpath" "$out"
assert_eq "case 17: a failed realpath writes nothing" "0" "$(exists "$(yaml_of "$R17")")"

# --- Case 18: the path is checked again before each mkdir ---------------------
# After docs/ is created, the preload swaps it for a symlink to a directory
# outside the root. The check before the docs/conventions mkdir must refuse,
# so nothing is created outside.
OUT18="$TEST_TMPDIR/outside18"
mkdir -p "$OUT18"
P18="$(preload swap-docs \
  'const path = require("node:path"); const mk = fs.mkdirSync;' \
  "fs.mkdirSync = (p, ...r) => { const res = mk(p, ...r); if (path.basename(String(p)) === \"docs\") { fs.rmdirSync(p); fs.symlinkSync(\"$OUT18\", p); } return res; };")"
R18="$TEST_TMPDIR/c18"
mkdir -p "$R18"
out="$(node --require "$P18" "$APPLY" --root "$R18" proof_level=live 2>&1)"
assert_eq "case 18: a docs/ swapped for a symlink after mkdir exits 1" "1" "$?"
one_line "case 18: a swapped docs/" "$out"
assert_eq "case 18: nothing was created outside the root" "0" "$(exists "$OUT18/conventions")"

# --- Case 19: rename and close failures, and a temp this run did not create ----
P19R="$(preload rename-fails \
  'fs.renameSync = () => { throw Object.assign(new Error("EXDEV: cross-device link, rename"), { code: "EXDEV" }); };')"
R19="$(new_root c19)"
out="$(node --require "$P19R" "$APPLY" --root "$R19" proof_level=live 2>&1)"
assert_eq "case 19: a failed rename exits 1" "1" "$?"
one_line "case 19: a failed rename" "$out"
assert_eq "case 19: a failed rename removes its temp file" "0" "$(leftover_temps "$R19")"
assert_eq "case 19: a failed rename leaves no target" "0" "$(exists "$(yaml_of "$R19")")"

P19C="$(preload close-fails \
  'const open = fs.openSync, close = fs.closeSync; let tmpFd = -1; let closes = 0;' \
  'fs.openSync = (p, ...r) => { const fd = open(p, ...r); if (String(p).endsWith(".tmp")) tmpFd = fd; return fd; };' \
  'fs.closeSync = (fd) => { if (fd === tmpFd) { closes++; if (closes > 1) { process.stderr.write("double close\n"); } close(fd); throw Object.assign(new Error("EIO: i/o error, close"), { code: "EIO" }); } return close(fd); };')"
R19C="$(new_root c19c)"
out="$(node --require "$P19C" "$APPLY" --root "$R19C" proof_level=live 2>&1)"
assert_eq "case 19: a failed close exits 1" "1" "$?"
one_line "case 19: a failed close" "$out"
assert_contains "case 19: a failed close names the error" "$out" "EIO"
assert_eq "case 19: a failed close removes its temp file" "0" "$(leftover_temps "$R19C")"

P19P="$(preload fixed-pid 'Object.defineProperty(process, "pid", { value: 4242 });')"
R19P="$(new_root c19p)"
printf 'someone else\n' >"$R19P/docs/conventions/.verification.yaml.4242.tmp"
out="$(node --require "$P19P" "$APPLY" --root "$R19P" proof_level=live 2>&1)"
assert_eq "case 19: a temp name already taken exits 1" "1" "$?"
one_line "case 19: a temp name already taken" "$out"
assert_eq "case 19: a temp file this run did not create is kept" "someone else" \
  "$(cat "$R19P/docs/conventions/.verification.yaml.4242.tmp")"

# A failed rename followed by a failed cleanup: still one line naming the
# rename error, no stack trace, no target.
P19X="$(preload rename-and-rm-fail \
  'fs.renameSync = () => { throw Object.assign(new Error("EXDEV: cross-device link, rename"), { code: "EXDEV" }); };' \
  'fs.rmSync = () => { throw Object.assign(new Error("EBUSY: resource busy, rm"), { code: "EBUSY" }); };')"
R19X="$(new_root c19x)"
out="$(node --require "$P19X" "$APPLY" --root "$R19X" proof_level=live 2>&1)"
assert_eq "case 19: a failed rename and a failed cleanup exit 1" "1" "$?"
one_line "case 19: a failed rename and a failed cleanup" "$out"
assert_contains "case 19: a failed rename and cleanup names the rename error" "$out" "EXDEV"
assert_eq "case 19: a failed rename and cleanup leaves no target" "0" "$(exists "$(yaml_of "$R19X")")"

# --- Case 18W: the path is checked again before the write ---------------------
# When docs/conventions is created, the preload swaps it for a symlink to a
# directory outside the root. No mkdir follows, so only the check before the
# write can refuse; without it the temp file lands outside.
OUT18W="$TEST_TMPDIR/outside18w"
mkdir -p "$OUT18W"
P18W="$(preload swap-conventions \
  'const path = require("node:path"); const mk = fs.mkdirSync;' \
  "fs.mkdirSync = (p, ...r) => { const res = mk(p, ...r); if (path.basename(String(p)) === \"conventions\") { fs.rmdirSync(p); fs.symlinkSync(\"$OUT18W\", p); } return res; };")"
R18W="$TEST_TMPDIR/c18w"
mkdir -p "$R18W/docs"
out="$(node --require "$P18W" "$APPLY" --root "$R18W" proof_level=live 2>&1)"
assert_eq "case 18W: a docs/conventions swapped for a symlink before the write exits 1" "1" "$?"
one_line "case 18W: a swapped docs/conventions" "$out"
assert_eq "case 18W: no verification.yaml outside the root" "0" "$(exists "$OUT18W/verification.yaml")"
assert_eq "case 18W: no temp file outside the root" "" "$(ls -A "$OUT18W")"

# --- Case 20: proof_level takes path, live or strict (the schema's enum) ------
for level in path live strict; do
  R20="$(new_root "c20-ok-$level")"
  run --root "$R20" "proof_level=$level" >/dev/null
  assert_eq "case 20: proof_level=$level exits 0" "0" "$?"
  assert_eq "case 20: the file holds proof_level: $level" "1" "$(grep -cx "proof_level: $level" "$(yaml_of "$R20")")"
  out="$(run --root "$R20" --check)"
  assert_contains "case 20: --check reports proof_level: $level" "$out" "PASS proof_level: $level"
done
R20Q="$(new_root c20q)"
printf 'proof_level: "live"\n' >"$(yaml_of "$R20Q")"
out="$(run --root "$R20Q" --check)"
assert_eq "case 20: a quoted listed string is valid for an enum key" "0" "$?"
assert_contains "case 20: a quoted listed string reads as its value" "$out" "PASS proof_level: live"
R20C="$(new_root c20c)"
printf '# team floor\nproof_level: live\n' >"$(yaml_of "$R20C")"
out="$(run --root "$R20C" --check)"
assert_contains "case 20: a file holding only a comment and the key reads the key" "$out" "PASS proof_level: live"
for bad in maybe Path loose 1 ''; do
  run --root "$(new_root "c20-$bad")" "proof_level=$bad" >/dev/null
  assert_eq "case 20: proof_level=$bad exits 1" "1" "$?"
done
R20W="$(new_root c20w)"
printf 'proof_level: maybe\n' >"$(yaml_of "$R20W")"
out="$(run --root "$R20W" --check)"
assert_eq "case 20: --check on proof_level: maybe exits 1" "1" "$?"
assert_contains "case 20: the WARN names the key and the value" "$out" "proof_level=maybe"

# --- Case 21: --check --ref reads the file as committed at a ref --------------
# The fixture's origin/main commits proof_level: strict; the working tree
# (standing in for a pull request's head) lowers it to path. The ref read must report
# the committed value and the commit it read.
g() { git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "${@:2}"; }
R21="$TEST_TMPDIR/c21"
mkdir -p "$R21/docs/conventions"
g "$R21" init -q
printf 'proof_level: strict\n' >"$(yaml_of "$R21")"
g "$R21" add docs/conventions/verification.yaml
g "$R21" commit -q -m base
SHA21="$(g "$R21" rev-parse HEAD)"
g "$R21" update-ref refs/remotes/origin/main "$SHA21"
printf 'proof_level: path\n' >"$(yaml_of "$R21")"
out="$(run --root "$R21" --check --ref origin/main)"
assert_eq "case 21: --check --ref on a valid committed file exits 0" "0" "$?"
assert_contains "case 21: the committed value is read, not the working tree's" "$out" "PASS proof_level: strict"
assert_contains "case 21: the commit read is reported" "$out" "$SHA21"
out="$(run --root "$R21" --check --ref "$SHA21")"
assert_eq "case 21: a 40-hex commit id is accepted" "0" "$?"
assert_contains "case 21: a commit id reads the committed value" "$out" "PASS proof_level: strict"

g "$R21" rm -q -f docs/conventions/verification.yaml
g "$R21" commit -q -m absent
g "$R21" update-ref refs/remotes/origin/main HEAD
out="$(run --root "$R21" --check --ref origin/main)"
assert_eq "case 21: a file absent at the ref exits 0" "0" "$?"
assert_contains "case 21: a file absent at the ref is INFO absent" "$out" "absent"

mkdir -p "$R21/docs/conventions"
printf 'proof_level: maybe\n' >"$(yaml_of "$R21")"
g "$R21" add docs/conventions/verification.yaml
g "$R21" commit -q -m invalid
g "$R21" update-ref refs/remotes/origin/main HEAD
out="$(run --root "$R21" --check --ref origin/main)"
assert_eq "case 21: an invalid committed value exits 1" "1" "$?"
assert_contains "case 21: the WARN names the committed key and value" "$out" "proof_level=maybe"

g "$R21" rm -q -f docs/conventions/verification.yaml
mkdir -p "$R21/docs/conventions"
ln -s ../../outside.yaml "$(yaml_of "$R21")"
g "$R21" add docs/conventions/verification.yaml
g "$R21" commit -q -m symlink
g "$R21" update-ref refs/remotes/origin/main HEAD
out="$(run --root "$R21" --check --ref origin/main)"
assert_eq "case 21: a committed symlink exits 1" "1" "$?"
assert_contains "case 21: a committed symlink is a WARN" "$out" "WARN"

# --- Case 22: --ref accepts only a commit id or origin/<name> -----------------
PWNED22="$TEST_TMPDIR/pwned22"
for bad in main HEAD~1 'origin/a..b' 'origin/-x' '--output=x' "origin/\$(touch $PWNED22)" 'origin/main:docs' ''; do
  out="$(run --root "$R21" --check --ref "$bad")"
  assert_eq "case 22: --ref '$bad' exits 2" "2" "$?"
  one_line "case 22: --ref '$bad'" "$out"
done
assert_eq "case 22: no ref shape ran a substitution" "0" "$(exists "$PWNED22")"
run --root "$R21" --check --ref origin/nope >/dev/null
assert_eq "case 22: a ref that does not resolve exits 2" "2" "$?"
run --root "$R21" --ref origin/main proof_level=strict >/dev/null
assert_eq "case 22: --ref without --check exits 2" "2" "$?"
run --root "$R21" --check --ref >/dev/null
assert_eq "case 22: --ref with no value exits 2" "2" "$?"

# --- Case 23: origin/<name> reads refs/remotes/origin/<name>, never a same-named ref
# A pull request's head can be checked out as a local branch, or tagged, under
# the name origin/main. Each shadow below commits proof_level: path; the
# remote-tracking ref commits strict, and only strict may come back.
R23="$TEST_TMPDIR/c23"
mkdir -p "$R23/docs/conventions"
g "$R23" init -q
printf 'proof_level: strict\n' >"$(yaml_of "$R23")"
g "$R23" add docs/conventions/verification.yaml
g "$R23" commit -q -m base
SHA23="$(g "$R23" rev-parse HEAD)"
g "$R23" update-ref refs/remotes/origin/main "$SHA23"
printf 'proof_level: path\n' >"$(yaml_of "$R23")"
g "$R23" commit -q -a -m head
# has_ref <root> <full ref>: 1 when the ref exists, else 0. Shadows are made
# with update-ref, so a host setting such as tag.gpgsign cannot skip one.
has_ref() { g "$1" show-ref --verify --quiet "$2" && echo 1 || echo 0; }
for shadow in refs/heads/origin/main refs/tags/origin/main refs/origin/main; do
  g "$R23" update-ref "$shadow" HEAD
  assert_eq "case 23: the shadow $shadow exists" "1" "$(has_ref "$R23" "$shadow")"
  out="$(run --root "$R23" --check --ref origin/main)"
  assert_eq "case 23: with $shadow named origin/main, the read exits 0" "0" "$?"
  assert_contains "case 23: with $shadow named origin/main, the value is the remote-tracking one" "$out" "PASS proof_level: strict"
  assert_contains "case 23: with $shadow named origin/main, the commit read is the remote-tracking one" "$out" "$SHA23"
done

# --- Case 25: with refs/remotes/origin/main absent, no look-alike ref stands in
# Each shadow below would satisfy git's short-name lookup of
# refs/remotes/origin/main. The documented result is exit 2: the layer cannot
# be read and is skipped.
R25="$TEST_TMPDIR/c25"
mkdir -p "$R25/docs/conventions"
g "$R25" init -q
printf 'proof_level: path\n' >"$(yaml_of "$R25")"
g "$R25" add docs/conventions/verification.yaml
g "$R25" commit -q -m head
for shadow in refs/heads/refs/remotes/origin/main refs/tags/refs/remotes/origin/main \
  refs/refs/remotes/origin/main refs/remotes/refs/remotes/origin/main \
  refs/remotes/refs/remotes/origin/main/HEAD; do
  g "$R25" update-ref "$shadow" HEAD
  assert_eq "case 25: the shadow $shadow exists" "1" "$(has_ref "$R25" "$shadow")"
  assert_eq "case 25: refs/remotes/origin/main is absent beside $shadow" "0" "$(has_ref "$R25" refs/remotes/origin/main)"
  out="$(run --root "$R25" --check --ref origin/main)"
  assert_eq "case 25: with only $shadow, the read exits 2" "2" "$?"
  assert_eq "case 25: with only $shadow, no PASS line" "0" "$(printf '%s\n' "$out" | grep -c '^PASS')"
  g "$R25" update-ref -d "$shadow"
done

# --- Case 24: an invalid proof_level leaves no PASS line to read --------------
# ADR 0060 Decision 7: the reading skill names the file, key and value and
# drops the layer. The skill reads the value only from a PASS line, so an
# invalid value must print a WARN naming it and no PASS proof_level line.
bad_value() { # bad_value <label> <file body> <text the WARN must name>
  local r out
  r="$(new_root "bv-$1")"
  printf '%s' "$2" >"$(yaml_of "$r")"
  out="$(run --root "$r" --check)"
  assert_eq "case 24: $1 exits 1" "1" "$?"
  assert_contains "case 24: $1 names the key and the value" "$out" "$3"
  assert_eq "case 24: $1 prints no PASS proof_level line" "0" "$(printf '%s\n' "$out" | grep -c '^PASS proof_level')"
}
bad_value "an out-of-list value" $'proof_level: maybe\n' "proof_level=maybe"
bad_value "a capitalized level" $'proof_level: Strict\n' "proof_level=Strict"
bad_value "an empty value" $'proof_level:\n' "proof_level is empty"
bad_value "a null value" $'proof_level: null\n' "proof_level is null"
bad_value "an empty quoted string" $'proof_level: ""\n' 'proof_level=""'
bad_value "a flow list" $'proof_level: [strict]\n' "proof_level=[strict]"
bad_value "a block list" $'proof_level:\n  - strict\n' "proof_level"
bad_value "a key set twice" $'proof_level: strict\nproof_level: live\n' "set more than once"
file_level() { # file_level <label> <file body>
  local r out
  r="$(new_root "fl-$1")"
  printf '%s' "$2" >"$(yaml_of "$r")"
  out="$(run --root "$r" --check)"
  assert_eq "case 24: $1 exits 1" "1" "$?"
  assert_eq "case 24: $1 prints no PASS line" "0" "$(printf '%s\n' "$out" | grep -c '^PASS')"
}
R24U="$(new_root fl-unknown)"
printf 'stray: 1\nproof_level: strict\n' >"$(yaml_of "$R24U")"
out="$(run --root "$R24U" --check)"
assert_eq "case 24: an unknown key exits 1" "1" "$?"
assert_eq "case 24: an unknown key is one WARN" "1" "$(printf '%s\n' "$out" | grep -c '^WARN.*key stray is not in the schema')"
assert_contains "case 24: an unknown key leaves the valid key's PASS line" "$out" "PASS proof_level: strict"
file_level "an unknown key holding a map" $'stray: {a: 1}\nproof_level: strict\n'
file_level "a parse error" $'other: "open\nproof_level: strict\n'
R24="$TEST_TMPDIR/c24"
mkdir -p "$R24/docs/conventions"
g "$R24" init -q
printf 'proof_level: maybe\n' >"$(yaml_of "$R24")"
g "$R24" add docs/conventions/verification.yaml
g "$R24" commit -q -m base
g "$R24" update-ref refs/remotes/origin/main HEAD
printf 'proof_level: strict\n' >"$(yaml_of "$R24")"
out="$(run --root "$R24" --check --ref origin/main)"
assert_eq "case 24: a committed bad value exits 1" "1" "$?"
assert_contains "case 24: a committed bad value is named" "$out" "proof_level=maybe"
assert_eq "case 24: a valid working-tree value does not stand in for the committed one" "0" \
  "$(printf '%s\n' "$out" | grep -c '^PASS proof_level')"

# --- Case 26: live_workers takes an unquoted whole number of at least 1 --------
# The schema gives live_workers type integer and minimum 1, so 1, 2 and 12 are
# valid and the file holds them as written.
for n in 1 2 12; do
  R26="$(new_root "c26-$n")"
  run --root "$R26" "live_workers=$n" >/dev/null
  assert_eq "case 26: live_workers=$n exits 0" "0" "$?"
  assert_eq "case 26: the file holds live_workers: $n" "1" "$(grep -cx "live_workers: $n" "$(yaml_of "$R26")")"
  out="$(run --root "$R26" --check)"
  assert_eq "case 26: --check after live_workers=$n exits 0" "0" "$?"
  assert_contains "case 26: --check reports live_workers: $n" "$out" "PASS live_workers: $n"
done
R26B="$(new_root c26b)"
run --root "$R26B" proof_level=live live_workers=3 >/dev/null
assert_eq "case 26: both keys in one apply exit 0" "0" "$?"
assert_eq "case 26: both keys are written" "2" \
  "$(grep -cxE 'proof_level: live|live_workers: 3' "$(yaml_of "$R26B")")"
R26U="$(new_root c26u)"
printf 'proof_level: strict\n' >"$(yaml_of "$R26U")"
out="$(run --root "$R26U" --check)"
assert_contains "case 26: a file without live_workers reports it unset" "$out" "PASS live_workers: (unset)"
run --root "$R26U" --yes live_workers=2 >/dev/null
assert_eq "case 26: adding live_workers beside proof_level exits 0" "0" "$?"
assert_eq "case 26: proof_level is kept and live_workers added" $'proof_level: strict\nlive_workers: 2' \
  "$(cat "$(yaml_of "$R26U")")"

# --- Case 27: a command-line live_workers that is not such a number is refused --
# A quoted number, a decimal, a sign, 0, a leading zero, a word and an empty or
# empty-quoted value: one line, no file created, an existing file untouched.
for bad in 0 00 02 -1 +2 2.5 2.0 1e3 abc ' 2' '"2"' "'2'" '' '""'; do
  r="$(new_root "c27-$(printf '%s' "$bad" | od -An -tx1 | tr -dc '0-9a-f')")"
  f="$(yaml_of "$r")"
  out="$(run --root "$r" "live_workers=$bad")"
  assert_eq "case 27: live_workers=$bad with no file exits 1" "1" "$?"
  one_line "case 27: live_workers=$bad with no file" "$out"
  assert_eq "case 27: live_workers=$bad creates no file" "0" "$(exists "$f")"
  printf 'live_workers: 2\n' >"$f"
  before="$(od -c "$f")"
  out="$(run --root "$r" --yes "live_workers=$bad")"
  assert_eq "case 27: live_workers=$bad over a file exits 1" "1" "$?"
  one_line "case 27: live_workers=$bad over a file" "$out"
  assert_eq "case 27: live_workers=$bad leaves the file untouched" "$before" "$(od -c "$f")"
done

# --- Case 28: --check names an invalid live_workers and drops only that key -----
# ADR 0060 Decision 7: the WARN names the key and the value, no PASS live_workers
# line is printed, and a valid proof_level beside it still gets its PASS line.
lw_warns() { # lw_warns <label> <live_workers line(s)> <text the WARN must name>
  local r out
  r="$(new_root "lw-$1")"
  printf 'proof_level: live\n%s' "$2" >"$(yaml_of "$r")"
  out="$(run --root "$r" --check)"
  assert_eq "case 28: --check on $1 exits 1" "1" "$?"
  assert_contains "case 28: the WARN for $1 names it" "$out" "$3"
  assert_eq "case 28: $1 prints no PASS live_workers line" "0" "$(printf '%s\n' "$out" | grep -c '^PASS live_workers')"
  assert_contains "case 28: $1 keeps the PASS line for proof_level" "$out" "PASS proof_level: live"
}
lw_warns "zero" $'live_workers: 0\n' "live_workers=0"
lw_warns "a decimal" $'live_workers: 2.5\n' "live_workers=2.5"
lw_warns "a negative number" $'live_workers: -1\n' "live_workers=-1"
lw_warns "a plus sign" $'live_workers: +2\n' "live_workers=+2"
lw_warns "a quoted number" $'live_workers: "2"\n' 'live_workers="2"'
lw_warns "a word" $'live_workers: many\n' "live_workers=many"
lw_warns "an empty value" $'live_workers:\n' "live_workers is empty"
lw_warns "a null value" $'live_workers: null\n' "live_workers is null"
lw_warns "an empty quoted string" $'live_workers: ""\n' 'live_workers=""'
lw_warns "a flow list" $'live_workers: [2]\n' "live_workers=[2]"
lw_warns "a block list" $'live_workers:\n  - 2\n' "live_workers"

# --- Case 29: apply overwrites an out-of-range or non-integer live_workers -------
lw_replaces() { # lw_replaces <label> <file body>
  local r f
  r="$(new_root "lr-$1")"
  f="$(yaml_of "$r")"
  printf '%s' "$2" >"$f"
  run --root "$r" --yes live_workers=4 >/dev/null
  assert_eq "case 29: apply over $1 exits 0" "0" "$?"
  assert_eq "case 29: apply over $1 leaves the asked-for line" "live_workers: 4" "$(cat "$f")"
}
lw_replaces "zero" $'live_workers: 0\n'
lw_replaces "a decimal" $'live_workers: 2.5\n'
lw_replaces "a negative number" $'live_workers: -3\n'
lw_replaces "a quoted number" $'live_workers: "2"\n'
lw_replaces "a word" $'live_workers: many\n'
lw_replaces "an empty value" $'live_workers:\n'
lw_replaces "a null value" $'live_workers: ~\n'
lw_refuses() { # lw_refuses <label> <file body>: one line, file byte for byte unchanged
  local r f before out
  r="$(new_root "lf-$1")"
  f="$(yaml_of "$r")"
  printf '%s' "$2" >"$f"
  before="$(od -c "$f")"
  out="$(run --root "$r" --yes live_workers=4)"
  assert_eq "case 29: apply over $1 exits 1" "1" "$?"
  one_line "case 29: apply over $1" "$out"
  assert_eq "case 29: apply over $1 leaves the file untouched" "$before" "$(od -c "$f")"
  assert_eq "case 29: apply over $1 leaves no temp file" "0" "$(leftover_temps "$r")"
}
lw_refuses "an empty quoted string" $'live_workers: ""\n'
lw_refuses "a flow list" $'live_workers: [2]\n'
lw_refuses "a block map" $'live_workers:\n  n: 2\n'
lw_refuses "a duplicate live_workers key" $'live_workers: 2\nlive_workers: 3\n'
R29U="$(new_root lf-unknown)"
printf 'live_workers: 2\nworkers: 3\n' >"$(yaml_of "$R29U")"
run --root "$R29U" --yes live_workers=4 >/dev/null
assert_eq "case 29: apply beside an unknown key exits 0" "0" "$?"
assert_eq "case 29: apply beside an unknown key keeps its line" $'live_workers: 4\nworkers: 3' "$(cat "$(yaml_of "$R29U")")"
lw_refuses "an invalid proof_level it is not writing" $'proof_level: maybe\nlive_workers: 2\n'
pair_twice "live_workers twice" live_workers=2 live_workers=3

# --- Case 30: --check --ref reads live_workers as committed ------------------------
R30="$TEST_TMPDIR/c30"
mkdir -p "$R30/docs/conventions"
g "$R30" init -q
printf 'live_workers: 4\n' >"$(yaml_of "$R30")"
g "$R30" add docs/conventions/verification.yaml
g "$R30" commit -q -m base
g "$R30" update-ref refs/remotes/origin/main HEAD
printf 'live_workers: 1\n' >"$(yaml_of "$R30")"
out="$(run --root "$R30" --check --ref origin/main)"
assert_eq "case 30: --check --ref with a committed live_workers exits 0" "0" "$?"
assert_contains "case 30: the committed live_workers is read, not the working tree's" "$out" "PASS live_workers: 4"
assert_contains "case 30: proof_level is unset in the committed file" "$out" "PASS proof_level: (unset)"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
