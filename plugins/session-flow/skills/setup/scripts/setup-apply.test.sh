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
assert_true 'the comment is kept and the value is respawn' [ "$(cat "$f")" = $'# team pick\nworker_continuation: respawn' ]

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
  assert_true "the replaced file holds one valid line for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = 'worker_continuation: respawn' ]
done

# Duplicate keys (also with a space before the colon), a block or one-line
# flow map or list, an empty quoted string and a stray empty key: --check
# flags each, and apply refuses with the file unchanged. The existing file is
# validated before any line is replaced, so a value apply could overwrite does
# not hide a shape the operator must fix by hand.
for doc in 'worker_continuation: resume\nworker_continuation: respawn\n' \
  'worker_continuation: resume\nworker_continuation : respawn\n' \
  'worker_continuation:\n  mode: resume\n' \
  'worker_continuation:\n  - resume\n' \
  'worker_continuation: [resume]\n' \
  'worker_continuation: {a: b}\n' \
  'worker_continuation: []\n' \
  'worker_continuation: ""\n' \
  "worker_continuation: ''\n" \
  'stray:\n'; do
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
assert_true 'a duplicate key is named as appearing twice' out_has 'appears 2 times'

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
# swap-docs: docs/ becomes a symlink to an outside directory after the first
# path check. No directory may be created through it.
# pre-tmp: a file already sits at this run's temp-file name. The exclusive open
# fails, and that file, which this run did not create, must survive.
PRELOAD="$WORKROOT/preload.mjs"
cat >"$PRELOAD" <<'JS'
import childProcess from "node:child_process";
import { mkdirSync, symlinkSync, writeFileSync } from "node:fs";
import { syncBuiltinESMExports } from "node:module";
const { HOOK_MODE: mode, HOOK_ROOT: root, HOOK_OUTSIDE: outside } = process.env;
if (mode === "pre-tmp") {
  mkdirSync(`${root}/docs/conventions`, { recursive: true });
  writeFileSync(`${root}/docs/conventions/.session-flow.yaml.${process.pid}.tmp`, "not mine\n");
}
if (mode === "swap-docs") {
  const real = childProcess.spawnSync;
  childProcess.spawnSync = (cmd, ...rest) => {
    const r = real(cmd, ...rest);
    if (cmd === "awk") {
      try {
        symlinkSync(outside, `${root}/docs`);
      } catch {}
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
assert_true 'the file at the temp name, not created by this run, survives' [ "$(cat "$repo/docs/conventions/.session-flow.yaml."*.tmp 2>/dev/null)" = 'not mine' ]
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

# encode_policy takes promote-when-must-hold or strongest-first;
# review_mining_prs takes an unquoted integer from 2 to 200.
repo="$(new_repo)"
run "$repo" encode_policy=strongest-first review_mining_prs=40
assert_true 'both retro keys write in one call' code_is 0
assert_true 'encode_policy reads back as strongest-first' [ "$(bash "$READER" "$repo/$REL" encode_policy)" = strongest-first ]
assert_true 'review_mining_prs reads back as 40' [ "$(bash "$READER" "$repo/$REL" review_mining_prs)" = 40 ]
run "$repo" --check
assert_true '--check prints review_mining_prs' out_has 'review_mining_prs: 40'
for pair in encode_policy=strongest review_mining_prs=1 review_mining_prs=201 review_mining_prs=abc \
  review_mining_prs=020 review_mining_prs=2.5 review_mining_prs=; do
  repo="$(new_repo)"
  run "$repo" "$pair"
  assert_true "$pair exits 1" code_is 1
  assert_true "$pair writes nothing" [ ! -e "$repo/docs" ]
done
for doc in 'review_mining_prs: "20"\n' 'review_mining_prs: 500\n' 'review_mining_prs: 1\n' 'review_mining_prs: ~\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  run "$repo" --check
  assert_true "--check flags $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "--check names review_mining_prs for $(printf '%b' "$doc" | tr '\n' ' ')" out_has 'review_mining_prs'
  run "$repo" --yes review_mining_prs=30
  assert_true "apply replaces $(printf '%b' "$doc" | tr '\n' ' ')" code_is 0
  assert_true "the replaced file holds review_mining_prs: 30 for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = 'review_mining_prs: 30' ]
done
for doc in 'review_mining_prs: [20]\n' 'review_mining_prs: ""\n' 'encode_policy:\n  - strongest-first\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  before="$(cat "$repo/$REL")"
  run "$repo" --yes review_mining_prs=30
  assert_true "apply refuses $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "the file is unchanged for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = "$before" ]
done
repo="$(new_repo)"
seed "$repo" 'review_mining_prs: 1\n'
run "$repo" --yes worker_continuation=respawn
assert_true 'an invalid value on a key not being written is refused' code_is 1
assert_true 'that refusal leaves the file unchanged' [ "$(cat "$repo/$REL")" = 'review_mining_prs: 1' ]

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
  assert_true "the replaced file holds wip_commit: false for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = 'wip_commit: false' ]
done
for doc in 'wip_commit: [true]\n' 'wip_commit: ""\n' 'wip_commit:\n  on: true\n'; do
  repo="$(new_repo)"
  seed "$repo" "$doc"
  before="$(cat "$repo/$REL")"
  run "$repo" --yes wip_commit=true
  assert_true "apply refuses $(printf '%b' "$doc" | tr '\n' ' ')" code_is 1
  assert_true "the file is unchanged for $(printf '%b' "$doc" | tr '\n' ' ')" [ "$(cat "$repo/$REL")" = "$before" ]
done

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

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
