#!/usr/bin/env bash
# Tests for lib/setup-apply.mjs, the shared writer behind each plugin's
# skills/setup/scripts/setup-apply.mjs. A fixture schema in a temp directory
# stands in for a plugin's: mode (enum fast, slow), strict (boolean), workers
# (integer, minimum 1, maximum 8), count (integer, no bounds), label (string,
# minLength 1, pattern ^[a-z][a-z0-9-]*$), note (string), session (an object of
# a boolean and an enum), sizes (an object of objects of non-empty strings) and
# weird (an array, a shape the checker does not validate). Expected values come
# from that schema, JSON Schema's meaning of each keyword, YAML's reading of a
# plain true or 5 as a boolean or a number, and the library's stated rules and
# exit codes.
# Run directly: bash lib/setup-apply.test.sh
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
assert_eq() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi; }
assert_contains() { if [[ "$2" == *"$3"* ]]; then pass "$1"; else fail "$1" "contains: $3" "$2"; fi; }

if ! command -v node >/dev/null 2>&1; then
  printf 'SKIP: node is not on PATH\n' >&2
  exit 0
fi

# The fixture schema and two entry points, one with --ref enabled.
FIX="$TEST_TMPDIR/fixture"
mkdir -p "$FIX"
cat >"$FIX/fixture.schema.json" <<'JSON'
{
  "$id": "https://example.test/fixture.schema.json",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "$schema": { "type": "string" },
    "mode": { "type": "string", "enum": ["fast", "slow"], "default": "fast" },
    "strict": { "type": "boolean", "default": false },
    "workers": { "type": "integer", "minimum": 1, "maximum": 8, "default": 1 },
    "count": { "type": "integer", "default": 0 },
    "label": { "type": "string", "minLength": 1, "pattern": "^[a-z][a-z0-9-]*$" },
    "note": { "type": "string" },
    "session": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "uploads": { "type": "boolean", "default": false },
        "names": { "enum": ["full", "initials"], "default": "full" }
      }
    },
    "sizes": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "small": { "type": "object", "additionalProperties": { "type": "string", "minLength": 1 } },
        "large": { "type": "object", "additionalProperties": { "type": "string", "minLength": 1 } }
      }
    },
    "weird": { "type": "array" },
    "code": { "type": "string", "pattern": "^a\\-b$" }
  }
}
JSON
# shellcheck disable=SC2016 # a JavaScript program; its ${} are template literals
node -e '
  const fs = require("node:fs");
  const { pathToFileURL } = require("node:url");
  const [lib, dir] = process.argv.slice(1);
  for (const [file, ref] of [["apply.mjs", false], ["apply-ref.mjs", true]]) {
    fs.writeFileSync(`${dir}/${file}`, `import { run } from ${JSON.stringify(pathToFileURL(`${lib}/setup-apply.mjs`).href)};
run(${JSON.stringify({
      plugin: "fixture",
      schema: `${dir}/fixture.schema.json`,
      reader: `${lib}/parse-concern-value.sh`,
      parser: `${lib}/yaml-subset.awk`,
      ref,
    })});
`);
  }
' "$SCRIPT_DIR" "$FIX"
APPLY="$FIX/apply.mjs"
APPLY_REF="$FIX/apply-ref.mjs"

# A HOME outside every fixture root, so the root rule refuses only on purpose.
FAKE_HOME="$TEST_TMPDIR/home"
mkdir -p "$FAKE_HOME"
run() { HOME="$FAKE_HOME" node "$APPLY" "$@" 2>&1; }
new_root() {
  local r="$TEST_TMPDIR/$1"
  mkdir -p "$r/docs/conventions"
  printf '%s' "$r"
}
yaml_of() { printf '%s/docs/conventions/fixture.yaml' "$1"; }
exists() { [[ -e "$1" ]] && echo 1 || echo 0; }
temps() { find "$1/docs/conventions" -name '*.tmp' 2>/dev/null | wc -l | tr -d ' '; }
one_line() {
  assert_eq "$1: one line" "1" "$(printf '%s\n' "$2" | grep -c .)"
  assert_eq "$1: no stack trace" "0" "$(printf '%s\n' "$2" | grep -c '^    at ')"
}
# refused <label> <file body> <args...>: exit 1, one line, file byte for byte.
refused() {
  local label="$1" body="$2" r f before out code
  shift 2
  r="$(new_root "rf-$CASE_NUM")"
  f="$(yaml_of "$r")"
  printf '%s' "$body" >"$f"
  before="$(od -c "$f")"
  out="$(run --root "$r" --yes "$@")"
  code=$?
  assert_eq "$label: exits 1" "1" "$code"
  one_line "$label" "$out"
  assert_eq "$label: the file is untouched" "$before" "$(od -c "$f")"
  assert_eq "$label: no temp file is left" "0" "$(temps "$r")"
  OUT="$out"
}

# --- Unknown key: one warning, ignored, its line kept -------------------------
R="$(new_root unknown)"
printf '# team\nstray: keep me  # note\nmode: slow\n' >"$(yaml_of "$R")"
out="$(run --root "$R" --yes mode=fast)"
assert_eq "unknown key: apply exits 0" "0" "$?"
assert_eq "unknown key: apply names it in one warning" "1" "$(printf '%s\n' "$out" | grep -c 'WARN docs/conventions/fixture.yaml: key stray is not in the schema')"
assert_eq "unknown key: its line is kept byte for byte" $'# team\nstray: keep me  # note\nmode: fast' "$(cat "$(yaml_of "$R")")"
out="$(run --root "$R" --check)"
assert_eq "unknown key: --check exits 1" "1" "$?"
assert_eq "unknown key: --check prints one WARN for it" "1" "$(printf '%s\n' "$out" | grep -c '^WARN .*key stray is not in the schema$')"
assert_contains "unknown key: --check prints PASS for the valid key" "$out" "PASS mode: fast"
assert_contains "unknown key: --check prints PASS for an unset key" "$out" "PASS workers: (unset)"
R="$(new_root unknown-empty)"
printf 'stray:\n' >"$(yaml_of "$R")"
out="$(run --root "$R" --yes strict=true)"
assert_eq "an unknown empty key: apply exits 0 and keeps it" "0:stray:|strict: true" "$?:$(paste -sd'|' "$(yaml_of "$R")")"
out="$(run --root "$(new_root unknown-cli)" stray=1)"
assert_eq "unknown key on the command line: exits 1" "1" "$?"
one_line "unknown key on the command line" "$out"
assert_eq "unknown key on the command line: creates nothing" "0" "$(exists "$(yaml_of "$TEST_TMPDIR/unknown-cli")")"
refused "an unknown key set twice" $'stray: 1\nstray: 2\nmode: fast\n' mode=slow
refused "an unknown key holding a block map" $'stray:\n  a: 1\n' mode=slow
refused "an unknown key holding a block list" $'stray:\n  - a\n' mode=slow
refused "an unknown key holding a flow list" $'stray: [a]\n' mode=slow
refused "an unknown key holding an empty flow map" $'stray: {}\n' mode=slow

# --- Symlinked root: resolved, then every check applies to it -----------------
R="$(new_root linked-real)"
ln -s "$R" "$TEST_TMPDIR/linked"
out="$(run --root "$TEST_TMPDIR/linked" mode=slow)"
assert_eq "a symlinked root: exits 0" "0" "$?"
assert_eq "a symlinked root: writes into the directory it names" "mode: slow" "$(grep -x 'mode: slow' "$(yaml_of "$R")")"
H="$(new_root home-real)"
ln -s "$H" "$TEST_TMPDIR/home-link"
out="$(HOME="$H" node "$APPLY" --root "$TEST_TMPDIR/home-link" mode=slow 2>&1)"
assert_eq "a symlinked root resolving to \$HOME: exits 1" "1" "$?"
one_line "a symlinked root resolving to \$HOME" "$out"
assert_eq "a symlinked root resolving to \$HOME: writes nothing" "0" "$(exists "$(yaml_of "$H")")"
out="$(HOME="$H/sub" node "$APPLY" --root "$TEST_TMPDIR/home-link" --check 2>&1)"
assert_eq "a symlinked root resolving to an ancestor of \$HOME: --check exits 1" "1" "$?"
R="$TEST_TMPDIR/linked-conv"
mkdir -p "$R/docs" "$TEST_TMPDIR/elsewhere"
ln -s "$TEST_TMPDIR/elsewhere" "$R/docs/conventions"
ln -s "$R" "$TEST_TMPDIR/linked-conv-link"
out="$(run --root "$TEST_TMPDIR/linked-conv-link" mode=slow)"
assert_eq "a symlinked docs/conventions under a symlinked root: exits 1" "1" "$?"
one_line "a symlinked docs/conventions under a symlinked root" "$out"
assert_eq "a symlinked docs/conventions: nothing lands outside" "" "$(ls -A "$TEST_TMPDIR/elsewhere")"

# --- CRLF: split and written back on the file's own line ending ---------------
R="$(new_root crlf)"
printf '# team\r\nmode: slow\r\n' >"$(yaml_of "$R")"
out="$(run --root "$R" --yes mode=fast)"
assert_eq "a CRLF file with one key: apply exits 0" "0" "$?"
assert_eq "a CRLF file: the key is written in place with CRLF" "$(printf '# team\r\nmode: fast\r\n' | od -c)" "$(od -c <"$(yaml_of "$R")")"
out="$(run --root "$R" --yes strict=true)"
assert_eq "a CRLF file: an added key ends in CRLF too" "$(printf '# team\r\nmode: fast\r\nstrict: true\r\n' | od -c)" "$(od -c <"$(yaml_of "$R")")"
out="$(run --root "$R" mode=fast)"
assert_contains "a CRLF file: the same value is already configured" "$out" "already configured"
refused "a file mixing CRLF and LF" $'mode: slow\r\nstrict: true\n' mode=fast

# --- Integers: a whole number from the minimum to any maximum ------------------
for n in 1 8; do
  R="$(new_root "int-$n")"
  run --root "$R" "workers=$n" >/dev/null
  assert_eq "workers=$n: written" "workers: $n" "$(grep -x "workers: $n" "$(yaml_of "$R")")"
done
R="$(new_root int-count)"
run --root "$R" count=0 >/dev/null
assert_eq "count=0 with no minimum in the schema: written" "count: 0" "$(grep -x 'count: 0' "$(yaml_of "$R")")"
for bad in 0 9 01 -1 +1 1.5 1e1 '"2"' "'2'" '' abc; do
  out="$(run --root "$(new_root "int-bad-$CASE_NUM")" "workers=$bad")"
  assert_eq "workers=$bad on the command line: exits 1" "1" "$?"
  one_line "workers=$bad on the command line" "$out"
done
for body in 'workers: 0' 'workers: 9' 'workers: 02' 'workers: -1' 'workers: 2.5' 'workers: "2"' 'workers: null' 'workers:'; do
  R="$(new_root "int-file-$CASE_NUM")"
  printf '%s\nmode: fast\n' "$body" >"$(yaml_of "$R")"
  out="$(run --root "$R" --check)"
  assert_eq "--check on '$body': exits 1" "1" "$?"
  assert_eq "--check on '$body': no PASS workers line" "0" "$(printf '%s\n' "$out" | grep -c '^PASS workers')"
  assert_contains "--check on '$body': the other key keeps its PASS line" "$out" "PASS mode: fast"
  out="$(run --root "$R" --yes workers=3)"
  assert_eq "apply over '$body': a valid value replaces it" "0:workers: 3" "$?:$(head -n 1 "$(yaml_of "$R")")"
done
refused "an empty quoted integer" $'workers: ""\n' workers=3
refused "an integer in a flow list" $'workers: [2]\n' workers=3
refused "an out-of-range integer on a key not being written" $'workers: 9\n' mode=fast

# --- --ref: a usage error unless the plugin enables it -------------------------
R="$(new_root ref-off)"
out="$(run --root "$R" --check --ref origin/main)"
assert_eq "--ref where it is not enabled: exits 2" "2" "$?"
one_line "--ref where it is not enabled" "$out"
g() { git -C "$1" -c user.name=fixture -c user.email=fixture@example.invalid -c commit.gpgsign=false "${@:2}"; }
R="$(new_root ref-on)"
g "$R" init -q
printf 'mode: slow\n' >"$(yaml_of "$R")"
g "$R" add docs/conventions/fixture.yaml
g "$R" commit -q -m base
SHA="$(g "$R" rev-parse HEAD)"
g "$R" update-ref refs/remotes/origin/main "$SHA"
printf 'mode: fast\n' >"$(yaml_of "$R")"
g "$R" commit -q -a -m head
g "$R" update-ref refs/tags/origin/main HEAD
out="$(HOME="$FAKE_HOME" node "$APPLY_REF" --root "$R" --check --ref origin/main 2>&1)"
assert_eq "--ref origin/main where enabled: exits 0" "0" "$?"
assert_contains "--ref origin/main reads refs/remotes/origin/main, not a same-named tag" "$out" "PASS mode: slow"
assert_contains "--ref names the commit read" "$out" "$SHA"
out="$(HOME="$FAKE_HOME" node "$APPLY_REF" --root "$R" --check --ref 'origin/a..b' 2>&1)"
assert_eq "--ref with a range: exits 2" "2" "$?"

# --- Refusals that leave the file untouched -----------------------------------
refused "a duplicate key after trimming" $'mode: fast\n"mode ": slow\n' mode=slow
assert_contains "a duplicate key after trimming: named once" "$OUT" "key mode is set more than once"
refused "a block map value" $'mode:\n  a: fast\n' mode=slow
refused "a block list value" $'mode:\n  - fast\n' mode=slow
refused "a flow map value" $'mode: {a: fast}\n' mode=slow
refused "an empty flow list" $'mode: []\n' mode=slow
refused "an empty double-quoted string" $'mode: ""\n' mode=slow
refused "an empty single-quoted string" $'mode: \x27\x27\n' mode=slow
refused "a parse error on another line" $'mode: fast\nnote: "open\n' mode=slow
refused "an invalid value on a key not being written" $'strict: maybe\n' mode=slow
refused "a key given twice on the command line" $'mode: fast\n' mode=slow mode=slow
R="$(new_root hardlink)"
printf 'mode: fast\n' >"$(yaml_of "$R")"
ln "$(yaml_of "$R")" "$TEST_TMPDIR/other-name.yaml"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "a hard-linked target: exits 1" "1" "$?"
one_line "a hard-linked target" "$out"
assert_eq "a hard-linked target: the other name is untouched" "mode: fast" "$(cat "$TEST_TMPDIR/other-name.yaml")"
R="$TEST_TMPDIR/conv-link"
mkdir -p "$R/docs" "$TEST_TMPDIR/elsewhere2"
ln -s "$TEST_TMPDIR/elsewhere2" "$R/docs/conventions"
out="$(run --root "$R" mode=slow)"
assert_eq "a symlinked docs/conventions: exits 1" "1" "$?"
one_line "a symlinked docs/conventions" "$out"
assert_eq "a symlinked docs/conventions: nothing lands outside" "" "$(ls -A "$TEST_TMPDIR/elsewhere2")"

# --- Overwrites: out-of-list, empty and null values on the key being written ---
for body in 'mode: medium' 'mode: "medium"' 'mode:' 'mode: null' 'mode: ~'; do
  R="$(new_root "ow-$CASE_NUM")"
  printf '%s\n' "$body" >"$(yaml_of "$R")"
  run --root "$R" --yes mode=slow >/dev/null
  assert_eq "apply over '$body': replaced" "0:mode: slow" "$?:$(cat "$(yaml_of "$R")")"
done

# --- Temp file: a name already taken, and one close of the descriptor ----------
preload() {
  local p="$TEST_TMPDIR/$1.cjs"
  shift
  printf '%s\n' 'const fs = require("node:fs");' "$@" 'require("node:module").syncBuiltinESMExports();' >"$p"
  printf '%s' "$p"
}
P="$(preload pid 'Object.defineProperty(process, "pid", { value: 4242 });')"
R="$(new_root taken)"
printf 'someone else\n' >"$R/docs/conventions/.fixture.yaml.4242.tmp"
out="$(HOME="$FAKE_HOME" node --require "$P" "$APPLY" --root "$R" mode=slow 2>&1)"
assert_eq "a temp name already taken: exits 1" "1" "$?"
one_line "a temp name already taken" "$out"
assert_eq "a temp name already taken: that file is kept" "someone else" "$(cat "$R/docs/conventions/.fixture.yaml.4242.tmp")"
P="$(preload close-fails \
  'const open = fs.openSync, close = fs.closeSync; let tmpFd = -1, closes = 0;' \
  'fs.openSync = (p, ...r) => { const fd = open(p, ...r); if (String(p).endsWith(".tmp")) tmpFd = fd; return fd; };' \
  'fs.closeSync = (fd) => { if (fd === tmpFd) { closes++; if (closes > 1) process.stderr.write("double close\n"); close(fd); throw Object.assign(new Error("EIO"), { code: "EIO" }); } return close(fd); };')"
R="$(new_root close)"
out="$(HOME="$FAKE_HOME" node --require "$P" "$APPLY" --root "$R" mode=slow 2>&1)"
assert_eq "a failed close: exits 1" "1" "$?"
one_line "a failed close" "$out"
assert_eq "a failed close: its temp file is removed" "0" "$(temps "$R")"

# --- Strings: minLength and pattern, quoted or plain ---------------------------
# check_ok <label> <body> <expected PASS line>: --check exits 0 and prints it.
check_ok() {
  local r out code
  r="$(new_root "ok-$CASE_NUM")"
  printf '%s' "$2" >"$(yaml_of "$r")"
  out="$(run --root "$r" --check)"
  code=$?
  assert_eq "$1: --check exits 0" "0" "$code"
  assert_contains "$1: --check prints its PASS line" "$out" "$3"
  assert_eq "$1: --check prints no WARN" "0" "$(printf '%s\n' "$out" | grep -c '^WARN')"
}
# check_warn <label> <body> <WARN text>: --check exits 1, warns, and keeps the
# PASS line of the valid mode key beside it.
check_warn() {
  local r out code
  r="$(new_root "warn-$CASE_NUM")"
  printf 'mode: fast\n%s' "$2" >"$(yaml_of "$r")"
  out="$(run --root "$r" --check)"
  code=$?
  assert_eq "$1: --check exits 1" "1" "$code"
  assert_contains "$1: --check warns" "$out" "$3"
  assert_contains "$1: the other key keeps its PASS line" "$out" "PASS mode: fast"
  assert_eq "$1: no crash" "0" "$(printf '%s\n' "$out" | grep -c 'Cannot read')"
  OUT="$out"
}
check_ok "a plain string" $'label: team-a\n' "PASS label: team-a"
check_ok "a double-quoted string" $'label: "team-a"\n' "PASS label: team-a"
check_ok "a string with a colon and a hash inside quotes" $'note: "a: b # c"\n' "PASS note: a: b # c"
check_ok "an empty string with no minLength" $'note: ""\n' 'PASS note: ""'
check_warn "an empty string under minLength 1" $'label: ""\n' 'label is an empty string'
check_warn "a string outside the pattern" $'label: Team-A\n' 'label=Team-A is not'
check_warn "a plain true on a string key" $'label: true\n' 'label=true is not'
check_warn "a plain number on a string key" $'note: 5\n' 'note=5 is not'
check_warn "a map on a string key" $'label:\n  a: b\n' 'label holds a map or a list'
R="$(new_root str-cli)"
out="$(run --root "$R" label=team-b)"
assert_eq "label=team-b on the command line: written" "0:label: team-b" "$?:$(grep -x 'label: team-b' "$(yaml_of "$R")")"
out="$(run --root "$R" --yes 'note=a: b # c')"
assert_eq "a string needing quotes on the command line: exits 0" "0" "$?"
assert_contains "a string needing quotes: it reads back as given" "$(run --root "$R" --check)" "PASS note: a: b # c"
out="$(run --root "$(new_root str-newline)" $'note=a\nb')"
assert_eq "a string holding a line break on the command line: exits 1" "1" "$?"
for bad in Team '' 'a b'; do
  out="$(run --root "$(new_root "str-bad-$CASE_NUM")" "label=$bad")"
  assert_eq "label=$bad on the command line: exits 1" "1" "$?"
  one_line "label=$bad on the command line" "$out"
done

# --- Objects: nested leaves checked against properties, recursively -----------
check_ok "a one-level object" $'session:\n  uploads: true\n  names: initials  # note\n' "PASS session:"
check_warn "an object key with nothing under it" $'session:\n  # nothing yet\n' 'session is empty'
check_ok "a two-level object" $'sizes:\n  small:\n    label: S\n    note: "tiny: one"\n  large:\n    label: L\n' "PASS sizes:"
check_warn "a wrong leaf type in an object" $'session:\n  uploads: maybe\n' 'session.uploads=maybe is not one of true, false'
check_warn "a quoted boolean in an object" $'session:\n  uploads: "true"\n' 'session.uploads="true" is not one of true, false'
check_warn "an enum leaf outside its list" $'session:\n  names: someone\n' 'session.names=someone is not one of full, initials'
check_warn "an unknown key in an object" $'session:\n  extra: 1\n' 'session.extra is not in the schema'
check_warn "a nested key set twice" $'session:\n  uploads: true\n  uploads: false\n' 'session.uploads is set more than once'
check_warn "a scalar on an object key" $'session: on\n' 'session=on is not a map'
check_warn "a list on an object key" $'session:\n  - uploads\n' 'session holds a list'
check_warn "an unknown key at the outer level of a two-level object" $'sizes:\n  huge:\n    label: x\n' 'sizes.huge is not in the schema'
check_warn "an empty string two levels down" $'sizes:\n  small:\n    label: ""\n' 'sizes.small.label is an empty string'
check_warn "a scalar where an inner object belongs" $'sizes:\n  small: x\n' 'sizes.small=x is not a map'
check_warn "a map where a leaf belongs" $'session:\n  uploads:\n    a: true\n' 'session.uploads holds a map or a list'
check_warn "a schema shape the checker does not know" $'weird: [1]\n' 'weird uses a schema shape setup-apply does not check'
R="$(new_root obj-keep)"
printf 'session:\n  uploads: true\nmode: slow\n' >"$(yaml_of "$R")"
out="$(run --root "$R" --yes mode=fast)"
assert_eq "apply beside a valid object: exits 0" "0" "$?"
assert_eq "apply beside a valid object: the object is kept byte for byte" $'session:\n  uploads: true\nmode: fast' "$(cat "$(yaml_of "$R")")"
refused "apply beside an invalid object" $'session:\n  uploads: maybe\n' mode=slow
# A `#` right after a key's colon and its space starts a comment, as the
# parser reads it.
check_ok "a comment on a one-level object key's line" $'session: # guest defaults\n  uploads: true\n' "PASS session: uploads=true"
check_ok "a comment on an inner object key's line" $'sizes:\n  small: # tiny\n    label: S\n' "PASS sizes: small.label=S"
check_ok "a tab before the comment on an object key's line" $'session:\t# guest defaults\n  uploads: true\n' "PASS session: uploads=true"
check_warn "a scalar key holding only a comment" $'strict: # pick later\n' 'strict is empty'
# A key name is read the way the parser reads it: '' in single quotes is one
# quote, \" in double quotes is a quote.
check_warn "a single-quoted nested key holding a doubled quote" $'session:\n  uploads: true\n  \'guest\'\'s\': yes\n' "session.guest's is not in the schema"
check_warn "a double-quoted nested key holding an escaped quote" $'session:\n  "a\\"b": 1\n' 'session.a"b is not in the schema'
# A block sequence may sit at its key's own indent; it is a list either way.
seq_case() {
  refused "a sequence at the indent of $1" "$2" "$3"
  assert_contains "a sequence at the indent of $1: named" "$OUT" "$4"
}
seq_case strict $'strict:\n- true\n' strict=true 'strict holds a map or a list'
seq_case mode $'mode:\n- fast\n' mode=slow 'mode holds a map or a list'
seq_case workers $'workers:\n- 3\n' workers=3 'workers holds a map or a list'
seq_case session $'session:\n- uploads\n' mode=slow 'session holds a list'
# U+2028 in a trailing comment does not end the line or hide the key.
check_warn "a line separator in a trailing comment" $'strict: bogus # a\xe2\x80\xa8b\n' 'strict=bogus is not one of true, false'
check_warn "a line separator in a nested trailing comment" $'session:\n  uploads: maybe # a\xe2\x80\xa8b\n' 'session.uploads=maybe is not one of true, false'
# A pattern JavaScript cannot compile with the u flag marks the key unchecked.
check_warn "a schema pattern that does not compile" $'code: a-b\n' 'code uses a schema shape setup-apply does not check'
out="$(run --root "$(new_root pattern-cli)" code=a-b)"
assert_eq "code=a-b on the command line: exits 1" "1" "$?"
one_line "code=a-b on the command line" "$out"
check_ok "a whitespace-only string" $'note: "  "\n' 'PASS note: "  "'
# Control characters from the file are printed escaped, never raw.
check_warn "an escape character in a nested key" $'session:\n  "a\x1bb": 1\n' 'session.a\x1bb is not in the schema'
assert_eq "an escape character in a nested key: no raw ESC is printed" "0" "$(printf '%s' "$OUT" | grep -c $'\x1b')"
for bad in $'a\x01b' $'a\x7fb' $'a\xc2\x85b' $'a\xe2\x80\xa8b' $'a\xe2\x80\xa9b'; do
  R="$(new_root "ctl-cli-$CASE_NUM")"
  out="$(run --root "$R" "note=$bad")"
  assert_eq "a control or separator character on the command line: exits 1" "1" "$?"
  one_line "a control or separator character on the command line" "$out"
  assert_eq "a control or separator character on the command line: writes nothing" "0" "$(exists "$(yaml_of "$R")")"
done
for pair in session=x weird=1; do
  out="$(run --root "$(new_root "obj-cli-$CASE_NUM")" "$pair")"
  assert_eq "$pair on the command line: exits 1" "1" "$?"
  one_line "$pair on the command line" "$out"
done

# --- Convention home: a bound pointer, the offer, the decline (ADR 0075) -------
# Expected values come from the ADR's fixes 2, 7, 8 and 15 and the region
# grammar in lib/resolve-convention-home.sh: the first backticked token inside
# the region is the home, a `declined` line stops the offer, the ignore line is
# <home>/**/*.local.*, and a foreign home lists our file in an index.
git_root() {
  local r="$TEST_TMPDIR/$1"
  mkdir -p "$r"
  g "$r" init -q
  printf '%s' "$r"
}
region_text() {
  printf '<!-- BEGIN GENERATED: convention-home -->\nTeam conventions live in `%s` — read the topic doc there\nbefore changing a governed surface.\n<!-- END GENERATED: convention-home -->\n' "$1"
}
resolved_home() { bash "$SCRIPT_DIR/resolve-convention-home.sh" --root "$1" 2>/dev/null; }

# A region naming Documentation: the file lands there, listed in the index.
R="$(git_root home-bound)"
mkdir -p "$R/Documentation"
region_text Documentation >"$R/AGENTS.md"
out="$(run --root "$R" mode=slow)"
assert_eq "a region naming Documentation: apply exits 0" "0" "$?"
assert_eq "a region naming Documentation: writes Documentation/fixture.yaml" "mode: slow" "$(grep -x 'mode: slow' "$R/Documentation/fixture.yaml")"
assert_eq "a region naming Documentation: docs/conventions is not created" "0" "$(exists "$R/docs")"
assert_eq "a region naming Documentation: the index lists the file" "1" "$(grep -c '\](fixture.yaml)' "$R/Documentation/conventions-index.md")"
assert_eq "a region naming Documentation: no ignore line is added" "0" "$(exists "$R/.gitignore")"
out="$(run --root "$R" mode=slow)"
assert_contains "a bound repository: a second run is already configured" "$out" "Documentation/fixture.yaml: already configured"
assert_eq "a bound repository: the index lists the file once" "1" "$(grep -c '\](fixture.yaml)' "$R/Documentation/conventions-index.md")"
out="$(run --root "$R" --check)"
assert_eq "a region naming Documentation: --check exits 0" "0" "$?"
assert_contains "a region naming Documentation: --check reads that file" "$out" "PASS mode: slow"
out="$(run --root "$R" --home docs/conventions mode=fast)"
assert_eq "a bound repository: a different --home exits 2" "2" "$?"
assert_eq "a bound repository: a different --home writes nothing" "mode: slow" "$(cat "$R/Documentation/fixture.yaml")"
out="$(run --root "$R" --home Documentation --yes mode=fast)"
assert_eq "a bound repository: the same --home is accepted" "0:mode: fast" "$?:$(cat "$R/Documentation/fixture.yaml")"
R2="$(git_root home-bound-index)"
mkdir -p "$R2/Documentation"
region_text Documentation >"$R2/AGENTS.md"
printf '# Index\n' >"$R2/Documentation/conventions-index.md"
out="$(run --root "$R2" mode=slow)"
assert_eq "an existing index that would change: exits 3 without --yes" "3" "$?"
assert_eq "an existing index that would change: nothing is written" "0" "$(exists "$R2/Documentation/fixture.yaml")"
out="$(run --root "$R2" --yes mode=slow)"
assert_eq "an existing index that would change: --yes lists the file" "0:1" "$?:$(grep -c '\](fixture.yaml)' "$R2/Documentation/conventions-index.md")"

# An unbound repository with CLAUDE.md and no AGENTS.md.
R="$(git_root home-unbound)"
printf '# Claude\n' >"$R/CLAUDE.md"
out="$(run --root "$R" mode=slow)"
assert_eq "an unbound repository without --yes: exits 3" "3" "$?"
assert_contains "an unbound repository without --yes: the offer is printed" "$out" "No convention home is bound"
assert_eq "an unbound repository without --yes: nothing is written" "0:0:0:# Claude" "$(exists "$R/docs"):$(exists "$R/.gitignore"):$(exists "$R/AGENTS.md"):$(cat "$R/CLAUDE.md")"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "an unbound repository with --yes: exits 0" "0" "$?"
assert_eq "an unbound repository with --yes: creates docs/conventions/fixture.yaml" "mode: slow" "$(grep -x 'mode: slow' "$R/docs/conventions/fixture.yaml")"
assert_eq "an unbound repository with --yes: writes the region into the existing CLAUDE.md" "docs/conventions" "$(resolved_home "$R")"
assert_eq "an unbound repository with --yes: CLAUDE.md keeps its text" "# Claude" "$(head -n 1 "$R/CLAUDE.md")"
assert_eq "an unbound repository with --yes: AGENTS.md is not created" "0" "$(exists "$R/AGENTS.md")"
assert_eq "an unbound repository with --yes: the ignore line is added" "1" "$(grep -cxF 'docs/conventions/**/*.local.*' "$R/.gitignore")"
assert_contains "an unbound repository with --yes: the ignore line is announced" "$out" "wrote .gitignore: added docs/conventions/**/*.local.*"
assert_contains "an unbound repository with --yes: the region is announced" "$out" "wrote CLAUDE.md: added a convention-home region"
out="$(run --root "$R" --yes mode=slow)"
assert_contains "a repository bound by the writer: a second run is already configured" "$out" "already configured"
assert_eq "a repository bound by the writer: the ignore line is not repeated" "1" "$(grep -cxF 'docs/conventions/**/*.local.*' "$R/.gitignore")"
assert_eq "a repository bound by the writer: the region is not repeated" "1" "$(grep -cF 'BEGIN GENERATED: convention-home' "$R/CLAUDE.md")"

# Neither instruction file exists: AGENTS.md is created. A bare shim does not count.
R="$(git_root home-none)"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "neither instruction file exists: exits 0" "0" "$?"
assert_eq "neither instruction file exists: AGENTS.md is created with the region" "docs/conventions" "$(resolved_home "$R")"
assert_eq "neither instruction file exists: CLAUDE.md is not created" "0" "$(exists "$R/CLAUDE.md")"
R="$(git_root home-shim)"
printf '@AGENTS.md\n' >"$R/CLAUDE.md"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "a CLAUDE.md that only imports AGENTS.md: the region goes into a new AGENTS.md" "0:1:@AGENTS.md" "$?:$(exists "$R/AGENTS.md"):$(cat "$R/CLAUDE.md")"
R="$(git_root home-both)"
printf '# Agents\n' >"$R/AGENTS.md"
printf '# Claude\n' >"$R/CLAUDE.md"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "both instruction files exist: the region goes into AGENTS.md" "docs/conventions:# Claude" "$(resolved_home "$R"):$(cat "$R/CLAUDE.md")"

# --home names the home to offer; its grammar is the resolver's.
R="$(git_root home-chosen)"
out="$(run --root "$R" --yes --home Documentation mode=slow)"
assert_eq "an unbound repository with --home: exits 0" "0" "$?"
assert_eq "an unbound repository with --home: the region names it" "Documentation" "$(resolved_home "$R")"
assert_eq "an unbound repository with --home: the file lands there" "mode: slow" "$(grep -x 'mode: slow' "$R/Documentation/fixture.yaml")"
assert_eq "an unbound repository with --home: the ignore line follows the home" "1" "$(grep -cxF 'Documentation/**/*.local.*' "$R/.gitignore")"
for bad in /abs ../up 'a b' '~x' "a$(printf '\134')b"; do
  R="$(git_root "home-bad-$CASE_NUM")"
  out="$(run --root "$R" --yes --home "$bad" mode=slow)"
  assert_eq "--home $bad: exits 2" "2" "$?"
  assert_eq "--home $bad: nothing is written" "0:0" "$(exists "$R/AGENTS.md"):$(exists "$R/docs")"
done

# A decline is recorded and not offered again.
R="$(git_root home-decline)"
printf '# Agents\n' >"$R/AGENTS.md"
out="$(run --root "$R" --decline)"
assert_eq "--decline: exits 0" "0" "$?"
assert_eq "--decline: writes a declined line in the region" "1" "$(grep -cx 'declined' "$R/AGENTS.md")"
assert_eq "--decline: the resolver reports the decline" "4" "$(bash "$SCRIPT_DIR/resolve-convention-home.sh" --root "$R" >/dev/null 2>&1; echo $?)"
assert_eq "--decline: writes no ignore line and no settings file" "0:0" "$(exists "$R/.gitignore"):$(exists "$R/docs")"
before="$(cat "$R/AGENTS.md")"
out="$(run --root "$R" mode=slow)"
assert_eq "after a decline: the next run exits 0 without --yes" "0" "$?"
assert_eq "after a decline: the next run does not offer again" "0" "$(printf '%s\n' "$out" | grep -c 'No convention home')"
assert_eq "after a decline: the settings file is written in docs/conventions" "mode: slow" "$(grep -x 'mode: slow' "$R/docs/conventions/fixture.yaml")"
assert_eq "after a decline: the region is untouched and no ignore line is added" "$before:0" "$(cat "$R/AGENTS.md"):$(exists "$R/.gitignore")"
out="$(run --root "$R" --decline)"
assert_eq "--decline twice: exits 0 and writes nothing more" "$before" "$(cat "$R/AGENTS.md")"
out="$(run --root "$R" --decline mode=slow)"
assert_eq "--decline with a key: exits 2" "2" "$?"
R="$(git_root home-decline-bound)"
mkdir -p "$R/Documentation"
region_text Documentation >"$R/AGENTS.md"
out="$(run --root "$R" --decline)"
assert_eq "--decline in a bound repository: exits 1" "1" "$?"

# A region without a pointer line, a broken region, a symlinked instruction file.
R="$(git_root home-empty-region)"
printf '<!-- BEGIN GENERATED: convention-home -->\nno pointer here\n<!-- END GENERATED: convention-home -->\n' >"$R/AGENTS.md"
before="$(cat "$R/AGENTS.md")"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "a region with no pointer line: exits 1" "1" "$?"
one_line "a region with no pointer line" "$out"
assert_eq "a region with no pointer line: nothing is written" "$before:0" "$(cat "$R/AGENTS.md"):$(exists "$R/docs")"
R="$(git_root home-two-pointers)"
printf '<!-- BEGIN GENERATED: convention-home -->\n`a`\n`b`\n<!-- END GENERATED: convention-home -->\n' >"$R/AGENTS.md"
out="$(run --root "$R" mode=slow)"
assert_eq "two pointer lines in one region: exits 1" "1" "$?"
one_line "two pointer lines in one region" "$out"
R="$(git_root home-missing-dir)"
region_text Documentation >"$R/AGENTS.md"
out="$(run --root "$R" --check)"
assert_eq "a pointer to a missing directory: --check exits 1" "1" "$?"
assert_contains "a pointer to a missing directory: the refusal names it" "$out" "pointer target directory missing: Documentation"
R="$(git_root home-symlink-agents)"
printf '# Real\n' >"$R/real.md"
ln -s real.md "$R/AGENTS.md"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "a symlinked AGENTS.md: exits 1 and is not written through" "1:# Real" "$?:$(cat "$R/real.md")"
one_line "a symlinked AGENTS.md" "$out"
assert_eq "a symlinked AGENTS.md: refused before any write, so no docs/ or .gitignore" "0:0" "$(exists "$R/docs"):$(exists "$R/.gitignore")"

R="$(git_root home-symlink-claude)"
printf '# Agents\n' >"$R/AGENTS.md"
ln -s AGENTS.md "$R/CLAUDE.md"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "CLAUDE.md a link to AGENTS.md: exits 0" "0" "$?"
assert_eq "CLAUDE.md a link to AGENTS.md: the region lands in the real AGENTS.md" "docs/conventions:1" "$(resolved_home "$R"):$(grep -cF 'BEGIN GENERATED: convention-home' "$R/AGENTS.md")"
assert_eq "CLAUDE.md a link to AGENTS.md: the link is kept" "AGENTS.md" "$(readlink "$R/CLAUDE.md")"
R="$(git_root home-symlink-agents-real)"
printf '# Claude\n' >"$R/CLAUDE.md"
ln -s CLAUDE.md "$R/AGENTS.md"
out="$(run --root "$R" --yes mode=slow)"
assert_eq "AGENTS.md a link to CLAUDE.md: exits 0" "0" "$?"
assert_eq "AGENTS.md a link to CLAUDE.md: the region lands in the real file" "1:CLAUDE.md" "$(grep -cF 'BEGIN GENERATED: convention-home' "$R/CLAUDE.md"):$(readlink "$R/AGENTS.md")"

# A root that is $HOME is refused, in a repository too.
R="$(git_root home-is-home)"
out="$(HOME="$R" node "$APPLY" --root "$R" --yes mode=slow 2>&1)"
assert_eq "a git root that is \$HOME: exits 1" "1" "$?"
one_line "a git root that is \$HOME" "$out"
assert_eq "a git root that is \$HOME: nothing is written" "0:0:0" "$(exists "$R/docs"):$(exists "$R/AGENTS.md"):$(exists "$R/.gitignore")"

# --check on an unbound repository offers nothing and writes nothing.
R="$(git_root home-check-unbound)"
out="$(run --root "$R" --check)"
assert_eq "an unbound repository: --check exits 0" "0" "$?"
assert_contains "an unbound repository: --check reads docs/conventions" "$out" "INFO docs/conventions/fixture.yaml: absent"
assert_eq "an unbound repository: --check writes nothing" "0:0" "$(exists "$R/docs"):$(exists "$R/AGENTS.md")"

# --- Long whitespace runs: the line scan is linear ----------------------------
# Each line holds a 200,000-space run; all three together finish within 1 s.
# The expected keys and values follow from the key and comment rules above:
# a bare key runs to its colon, a value keeps inner spaces with no `#` after
# them, and a line with no colon is not a key line.
# shellcheck disable=SC2016 # JavaScript template literals, never expanded here
out="$(timeout 10 node --input-type=module -e '
  const { topLevelLines } = await import(process.argv[1]);
  const sp = " ".repeat(200000);
  const t = Date.now();
  const k = topLevelLines(`a${sp}b: 1`);
  const v = topLevelLines(`mode: fast${sp}x`);
  const n = topLevelLines(`a${sp}x`);
  const ms = Date.now() - t;
  console.log([k.length, k[0]?.key.length, k[0]?.raw, v[0]?.key, v[0]?.raw.length, n.length, ms < 1000].join(" "));
' "file://$SCRIPT_DIR/setup-apply.mjs" 2>&1)"
assert_eq "a 200,000-space run is scanned in under 1 s" "1 200002 1 mode 200005 0 true" "$out"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
