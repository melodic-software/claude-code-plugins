#!/usr/bin/env bash
# Tests for lib/setup-apply.mjs, the shared writer behind each plugin's
# skills/setup/scripts/setup-apply.mjs. A fixture schema in a temp directory
# stands in for a plugin's: mode (enum fast, slow), strict (boolean), workers
# (integer, minimum 1, maximum 8) and count (integer, no bounds). Expected
# values come from that schema and the library's stated rules and exit codes.
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
    "count": { "type": "integer", "default": 0 }
  }
}
JSON
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

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1
