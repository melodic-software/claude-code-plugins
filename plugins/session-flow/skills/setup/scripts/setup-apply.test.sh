#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /session-flow:setup apply.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
# Expected values come from the key contract in reference/config.md:
# worker_continuation takes resume or respawn, and the file is
# docs/conventions/session-flow.yaml at the repository root.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# settings <file>: the file without the record the writer keeps beside the
# settings, for cases about the settings; the record has its own case below.
settings() {
  awk '/^ *written_against: /{next} /^ *provenance:\r?$/{inblock=1;next} inblock&&/^ +[^ ]+: /{next} {inblock=0;print}' "$1"
}
SUT="$SCRIPT_DIR/setup-apply.mjs"
READER="$SCRIPT_DIR/../../retro/scripts/parse-concern-value.sh"
REL="docs/conventions/session-flow.yaml"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

fails=0
assert_true() { # assert_true <description> <command...>
  local desc="$1"
  shift
  if "$@"; then printf 'ok   - %s\n' "$desc"; else
    printf 'FAIL - %s\n' "$desc" >&2
    fails=$((fails + 1))
  fi
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
  OUT="$(node "$SUT" --root "$repo" "$@" 2>&1)"
  CODE=$?
}
code_is() { [[ "$CODE" -eq "$1" ]]; }
out_has() { [[ "$OUT" == *"$1"* ]]; }
no_trace() { [[ "$OUT" != *"    at "* && "$(printf '%s\n' "$OUT" | wc -l)" -le 2 ]]; }
seed() { # seed <repo> <content>
  mkdir -p "$1/docs/conventions"
  printf '%b' "$2" >"$1/$REL"
}

# Fresh write.
repo="$(new_repo)"
f="$repo/$REL"
run "$repo" worker_continuation=respawn
assert_true 'fresh write exits 0' code_is 0
assert_true 'fresh write creates the file' test -f "$f"
assert_true 'the written value reads back as respawn' [ "$(bash "$READER" "$f" worker_continuation)" = respawn ]
assert_true 'fresh write creates no other file' [ "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1 ]
assert_true 'fresh write leaves no temp file' [ -z "$(find "$repo/docs" -name '*.tmp')" ]
before="$(cat "$f")"
run "$repo" worker_continuation=respawn
assert_true 'an unchanged value reports already configured' out_has 'already configured'
assert_true 'an unchanged value leaves the file' [ "$(cat "$f")" = "$before" ]

# Existing file that would change: diff, then --yes.
repo="$(new_repo)"
f="$repo/$REL"
seed "$repo" '# team pick\nworker_continuation: resume\n'
before="$(cat "$f")"
run "$repo" worker_continuation=respawn
assert_true 'an existing file that would change exits 3 without --yes' code_is 3
assert_true 'the refusal prints the diff' out_has '+worker_continuation: respawn'
assert_true 'the diff shows the old value' out_has '-worker_continuation: resume'
assert_true 'the file is untouched without --yes' [ "$(cat "$f")" = "$before" ]
run "$repo" --yes worker_continuation=respawn
assert_true 'with --yes the change is written' code_is 0
assert_true 'the comment is kept and the value is respawn' [ "$(settings "$f")" = $'# team pick\nworker_continuation: respawn' ]

# Invalid value and unknown key.
repo="$(new_repo)"
run "$repo" worker_continuation=restart
assert_true 'an invalid value exits 1' code_is 1
assert_true 'an invalid value is named with its key' out_has 'worker_continuation=restart'
assert_true 'an invalid value writes nothing' [ ! -e "$repo/docs" ]
run "$repo" cadence=hourly
assert_true 'a key outside the schema exits 1' code_is 1
assert_true 'a key outside the schema writes nothing' [ ! -e "$repo/docs" ]

# Empty and null values: --check flags each, and apply replaces the key's
# single line with a valid value.
for doc in 'worker_continuation:\n' \
  'worker_continuation: null\n' \
  'worker_continuation: ~\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  run "$repo" --check
  assert_true "--check flags $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "--check names the bad value for $(printf '%b' "$doc" | tr '\n' ' ')" out_has 'worker_continuation'
  run "$repo" --yes worker_continuation=respawn
  assert_true "apply replaces $(printf '%b' "$doc" | tr '\n' ' ')" code_is 0
  assert_true "the replaced file holds one valid line for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(settings "$repo/$REL")" = 'worker_continuation: respawn' ]
done

# Duplicate keys (also with a space before the colon), a block or one-line
# flow map or list, an empty quoted string, and a key outside the schema set
# twice or holding a map: --check flags each, and apply refuses with the file
# unchanged. The existing file is validated before any line is replaced, so a
# value apply could overwrite does not hide a shape the operator must fix by
# hand.
for doc in 'worker_continuation: resume\nworker_continuation: respawn\n' \
  'worker_continuation: resume\nworker_continuation : respawn\n' \
  'worker_continuation:\n  mode: resume\n' \
  'worker_continuation:\n  - resume\n' \
  'worker_continuation: [resume]\n' \
  'worker_continuation: {a: b}\n' \
  'worker_continuation: []\n' \
  'worker_continuation: ""\n' \
  "worker_continuation: ''\n" \
  'stray: a\nstray: b\n' \
  'stray:\n  a: b\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  before="$(cat "$repo/$REL")"
  run "$repo" --check
  assert_true "--check flags $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  run "$repo" --yes worker_continuation=respawn
  assert_true "apply refuses $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "the file is unchanged for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = "$before" ]
done
repo="$(new_repo)"
seed "$repo" 'worker_continuation: resume\nworker_continuation: respawn\n'
run "$repo" --check
assert_true 'a duplicate key is named as a parse error' out_has 'line 2: duplicate key "worker_continuation"'

# A key outside the schema, empty or with a value, is named in one line and
# ignored: --check still prints the valid key and exits 1, and apply writes
# the asked-for key and keeps that line byte for byte.
repo="$(new_repo)"
seed "$repo" 'worker_continuation: resume\nstray:\n'
run "$repo" --check
assert_true '--check on an unknown key exits 1' code_is 1
assert_true '--check names the unknown key once' [ "$(grep -c 'key stray is not in the schema' <<<"$OUT")" -eq 1 ]
assert_true '--check keeps the valid key beside an unknown one' out_has 'worker_continuation: resume'
# SKILL.md step 7 reads these lines as a PASS/WARN table.
assert_true '--check prefixes the problem with WARN' [ "$(grep -c '^WARN docs/conventions/session-flow.yaml: key stray is not in the schema$' <<<"$OUT")" -eq 1 ]
assert_true '--check prefixes each key with PASS' [ "$(grep -c '^PASS worker_continuation: resume$' <<<"$OUT")" -eq 1 ]
run "$repo" --yes worker_continuation=respawn
assert_true 'apply beside an unknown key exits 0' code_is 0
assert_true 'apply names the unknown key in one warning' [ "$(grep -c 'WARN.*key stray is not in the schema' <<<"$OUT")" -eq 1 ]
assert_true 'apply keeps the unknown key line' [ "$(settings "$repo/$REL")" = $'worker_continuation: respawn\nstray:' ]

# An invalid existing scalar is replaced by a valid one.
repo="$(new_repo)"
seed "$repo" 'worker_continuation: restart\n'
run "$repo" --yes worker_continuation=resume
assert_true 'an invalid existing value is replaced' code_is 0
assert_true 'the replacement reads back as resume' [ "$(bash "$READER" "$repo/$REL" worker_continuation)" = resume ]

# A key given twice on the command line is refused, with or without a file.
repo="$(new_repo)"
seed "$repo" 'worker_continuation: resume\n'
before="$(cat "$repo/$REL")"
run "$repo" --yes worker_continuation=respawn worker_continuation=resume
assert_true 'a key given twice is refused against an existing file' code_is 1
assert_true 'a key given twice leaves the existing file unchanged' [ "$(cat "$repo/$REL")" = "$before" ]
repo="$(new_repo)"
run "$repo" worker_continuation=respawn worker_continuation=respawn
assert_true 'a key given twice with the same value is refused' code_is 1
assert_true 'a key given twice writes nothing' [ ! -e "$repo/docs" ]

# Write-path races, driven by a preload in the script's own process.
# swap-docs: docs/ becomes a symlink to an outside directory right after this
# run creates it. No directory may be created through it.
# pre-tmp: a file already sits at this run's temp-file name. The exclusive open
# fails, and that file, which this run did not create, must survive.
PRELOAD="$WORKROOT/preload.mjs"
cat >"$PRELOAD" <<'JS'
import fs, { mkdirSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const { HOOK_MODE: mode, HOOK_ROOT: root, HOOK_OUTSIDE: outside } = process.env;
if (mode === "pre-tmp") {
  mkdirSync(`${root}/docs/conventions`, { recursive: true });
  writeFileSync(`${root}/docs/conventions/.session-flow.yaml.${process.pid}.tmp`, "not mine\n");
}
if (mode === "swap-docs") {
  const real = fs.mkdirSync;
  fs.mkdirSync = (p, ...rest) => {
    const r = real(p, ...rest);
    if (String(p).endsWith("/docs")) {
      fs.rmdirSync(p);
      fs.symlinkSync(outside, p);
    }
    return r;
  };
  syncBuiltinESMExports();
}
JS
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
OUT="$(HOOK_MODE=swap-docs HOOK_ROOT="$repo" HOOK_OUTSIDE="$outside" node --import "$PRELOAD" "$SUT" --root "$repo" worker_continuation=respawn 2>&1)"
CODE=$?
assert_true 'docs/ swapped for a symlink mid-run exits 1' code_is 1
assert_true 'no directory is created through a swapped docs/ symlink' [ -z "$(ls -A "$outside")" ]
repo="$(new_repo)"
OUT="$(HOOK_MODE=pre-tmp HOOK_ROOT="$repo" node --import "$PRELOAD" "$SUT" --root "$repo" worker_continuation=respawn 2>&1)"
CODE=$?
assert_true 'an existing file at the temp name makes the write exit 1' code_is 1
assert_true 'the file at the temp name, not created by this run, survives' [ "$(settings "$repo/docs/conventions/.session-flow.yaml."*.tmp 2>/dev/null)" = 'not mine' ]
assert_true 'nothing is written when the temp name is taken' [ ! -e "$repo/$REL" ]

# Symlinks and hard links.
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" worker_continuation=respawn
assert_true 'a symlinked docs/conventions exits 1' code_is 1
assert_true 'nothing lands outside the repository' [ -z "$(ls -A "$outside")" ]
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf 'worker_continuation: resume\n' >"$outside/target.yaml"
ln -s "$outside/target.yaml" "$repo/$REL"
run "$repo" --yes worker_continuation=respawn
assert_true 'a symlinked target file exits 1' code_is 1
assert_true 'the symlink target is untouched' [ "$(cat "$outside/target.yaml")" = 'worker_continuation: resume' ]
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf 'worker_continuation: resume\n' >"$outside/hard.yaml"
ln "$outside/hard.yaml" "$repo/$REL"
run "$repo" --yes worker_continuation=respawn
assert_true 'a hard-linked target exits 1' code_is 1
assert_true 'the hard link is named' out_has 'hard link'
assert_true 'the other link is untouched' [ "$(cat "$outside/hard.yaml")" = 'worker_continuation: resume' ]

# A directory or a file in the way: one line, exit 1, no stack trace.
repo="$(new_repo)"
mkdir -p "$repo/$REL"
run "$repo" worker_continuation=respawn
assert_true 'a directory at the target exits 1' code_is 1
assert_true 'a directory at the target gives one line and no stack trace' no_trace
repo="$(new_repo)"
printf 'not a directory\n' >"$repo/docs"
run "$repo" worker_continuation=respawn
assert_true 'a file where docs/ should be exits 1' code_is 1
assert_true 'a file where docs/ should be gives one line and no stack trace' no_trace
run "$repo" --check
assert_true '--check with a file where docs/ should be exits 1' code_is 1
assert_true '--check with a file where docs/ should be gives no stack trace' no_trace

# An invalid value on a key the call does not write is refused.
repo="$(new_repo)"
seed "$repo" 'wip_commit: yes\n'
run "$repo" --yes worker_continuation=respawn
assert_true 'an invalid value on a key not being written is refused' code_is 1
assert_true 'that refusal leaves the file unchanged' [ "$(cat "$repo/$REL")" = 'wip_commit: yes' ]

# wip_commit takes an unquoted true or false.
repo="$(new_repo)"
run "$repo" wip_commit=true
assert_true 'wip_commit=true writes' code_is 0
assert_true 'wip_commit reads back as true' [ "$(bash "$READER" "$repo/$REL" wip_commit)" = true ]
run "$repo" --check
assert_true '--check prints wip_commit' out_has 'wip_commit: true'
for pair in wip_commit=yes wip_commit=True wip_commit=1 wip_commit=on wip_commit=; do
  repo="$(new_repo)"
  run "$repo" "$pair"
  assert_true "$pair exits 1" code_is 1
  assert_true "$pair writes nothing" [ ! -e "$repo/docs" ]
done
for doc in 'wip_commit: "true"\n' "wip_commit: 'false'\n" 'wip_commit: yes\n' 'wip_commit: TRUE\n' 'wip_commit:\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  run "$repo" --check
  assert_true "--check flags $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "--check names wip_commit for $(printf '%b' "$doc" | tr '\n' ' ')" out_has 'wip_commit'
  run "$repo" --yes wip_commit=false
  assert_true "apply replaces $(printf '%b' "$doc" | tr '\n' ' ')" code_is 0
  assert_true "the replaced file holds wip_commit: false for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(settings "$repo/$REL")" = 'wip_commit: false' ]
done
for doc in 'wip_commit: [true]\n' 'wip_commit: ""\n' 'wip_commit:\n  on: true\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  before="$(cat "$repo/$REL")"
  run "$repo" --yes wip_commit=true
  assert_true "apply refuses $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "the file is unchanged for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = "$before" ]
done

# transcript_scope takes worktree, repo or all.
for v in worktree repo all; do
  repo="$(new_repo)"
  run "$repo" "transcript_scope=$v"
  assert_true "transcript_scope=$v writes" code_is 0
  assert_true "transcript_scope reads back as $v" [ "$(bash "$READER" "$repo/$REL" transcript_scope)" = "$v" ]
done
for pair in transcript_scope=everywhere transcript_scope=Repo transcript_scope=; do
  repo="$(new_repo)"
  run "$repo" "$pair"
  assert_true "$pair exits 1" code_is 1
  assert_true "$pair writes nothing" [ ! -e "$repo/docs" ]
done
repo="$(new_repo)"
seed "$repo" 'transcript_scope: global\n'
run "$repo" --check
assert_true '--check flags transcript_scope: global' code_is 1
assert_true '--check names transcript_scope' out_has 'transcript_scope'

# retro_lenses takes 1 or 3; an unquoted 3 in the file is valid, 2 is not.
repo="$(new_repo)"
run "$repo" retro_lenses=3
assert_true 'retro_lenses=3 writes' code_is 0
assert_true 'retro_lenses reads back as 3' [ "$(bash "$READER" "$repo/$REL" retro_lenses)" = 3 ]
run "$repo" --check
assert_true '--check accepts retro_lenses: 3' code_is 0
for pair in retro_lenses=2 retro_lenses=0 retro_lenses=; do
  repo="$(new_repo)"
  run "$repo" "$pair"
  assert_true "$pair exits 1" code_is 1
  assert_true "$pair writes nothing" [ ! -e "$repo/docs" ]
done
repo="$(new_repo)"
seed "$repo" 'retro_lenses: 2\n'
run "$repo" --check
assert_true '--check flags retro_lenses: 2' code_is 1
assert_true '--check names retro_lenses' out_has 'retro_lenses'

# --check: absent and valid.
repo="$(new_repo)"
run "$repo" --check
assert_true '--check on a missing file exits 0' code_is 0
assert_true '--check on a missing file reports absent' out_has 'absent'
seed "$repo" 'worker_continuation: respawn\n'
run "$repo" --check
assert_true '--check on a valid file prints its value' out_has 'worker_continuation: respawn'

# Usage errors.
run "$repo"
assert_true 'no <key>=<value> exits 2' code_is 2
run "$repo" --check worker_continuation=resume
assert_true '--check with a pair exits 2' code_is 2
OUT="$(cd "$WORKROOT" && GIT_CEILING_DIRECTORIES="$WORKROOT" node "$SUT" worker_continuation=resume 2>&1)"
CODE=$?
assert_true 'outside a git working tree without --root exits 2' code_is 2

# --- The writer's record: written_against from plugin.json, one entry per key ---
VERSION="$(sed -n 's/^ *"version": "\(.*\)",*$/\1/p' "$SCRIPT_DIR/../../../.claude-plugin/plugin.json")"
repo="$(new_repo)"
run "$repo" worker_continuation=respawn
record="$(grep -v '^# ' "$repo/docs/conventions/session-flow.yaml")"
record_ok=0
[[ "$CODE" -eq 0 && "$record" == $'written_against: session-flow@'"$VERSION"$'\nworker_continuation: respawn\nprovenance:\n  worker_continuation: chosen'* ]] && record_ok=1
repo="$(new_repo)"
run "$repo" --default worker_continuation
default_ok=0
[[ "$CODE" -eq 0 && "$(grep -c '^  worker_continuation: default$' "$repo/docs/conventions/session-flow.yaml")" -eq 1 ]] && default_ok=1
assert_true 'the file records written_against and a chosen entry' test "$record_ok" -eq 1
assert_true '--default records a default entry' test "$default_ok" -eq 1

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
