#!/usr/bin/env bash
# Black-box test for setup-apply.mjs, the writer behind /discovery:setup apply.
#
# Self-contained and cwd-independent; mutates only its own mktemp dir.
# Expected values come from the key contract in reference/config.md:
# explore_output takes auto, change-prep or explain, and the file is
# docs/conventions/discovery.yaml at the repository root.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/setup-apply.mjs"
READER="$SCRIPT_DIR/parse-concern-value.sh"

WORKROOT="$(mktemp -d)"
trap 'rm -rf "$WORKROOT"' EXIT

fails=0
pass() { printf 'ok   - %s\n' "$1"; }
fail() {
  printf 'FAIL - %s\n' "$1" >&2
  fails=$((fails + 1))
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

# Fresh write: no file yet, a valid value is written and reads back.
repo="$(new_repo)"
run "$repo" explore_output=explain
if ((CODE == 0)); then pass 'fresh write exits 0'; else fail 'fresh write exits 0'; fi
f="$repo/docs/conventions/discovery.yaml"
if [[ -f "$f" ]]; then pass 'fresh write creates docs/conventions/discovery.yaml'; else fail 'fresh write creates docs/conventions/discovery.yaml'; fi
if [[ "$(bash "$READER" "$f" explore_output)" == "explain" ]]; then pass 'the written value reads back as explain through parse-concern-value.sh'; else fail 'the written value reads back as explain through parse-concern-value.sh'; fi
if [[ "$(find "$repo" -path "$repo/.git" -prune -o -type f -print | wc -l)" -eq 1 ]]; then pass 'fresh write creates no other file'; else fail 'fresh write creates no other file'; fi

# Same value again: nothing changes.
before="$(cat "$f")"
run "$repo" explore_output=explain
if [[ "$CODE" -eq 0 && "$OUT" == *"already configured"* && "$(cat "$f")" == "$before" ]]; then pass 'an unchanged value reports already configured and leaves the file'; else fail 'an unchanged value reports already configured and leaves the file'; fi

# Existing file, different value, no --yes: diff printed, nothing written.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf '# team pick\nexplore_output: auto\n' >"$repo/docs/conventions/discovery.yaml"
f="$repo/docs/conventions/discovery.yaml"
before="$(cat "$f")"
run "$repo" explore_output=change-prep
if [[ "$CODE" -eq 3 ]]; then pass 'an existing file that would change exits 3 without --yes'; else fail 'an existing file that would change exits 3 without --yes'; fi
if [[ "$OUT" == *"-explore_output: auto"* && "$OUT" == *"+explore_output: change-prep"* ]]; then pass 'the refusal prints the diff of the change'; else fail 'the refusal prints the diff of the change'; fi
if [[ "$(cat "$f")" == "$before" ]]; then pass 'the existing file is untouched without --yes'; else fail 'the existing file is untouched without --yes'; fi

# Same change with --yes: written, comment kept.
run "$repo" --yes explore_output=change-prep
if ((CODE == 0)); then pass 'with --yes the change is written'; else fail 'with --yes the change is written'; fi
if [[ "$(cat "$f")" == $'# team pick\nexplore_output: change-prep' ]]; then pass 'the written file keeps the comment and holds change-prep'; else fail 'the written file keeps the comment and holds change-prep'; fi

# Invalid value: refused, nothing created.
repo="$(new_repo)"
run "$repo" explore_output=tutorial
if [[ "$CODE" -eq 1 && "$OUT" == *"explore_output=tutorial"* ]]; then pass 'an invalid value exits 1 and names the key and value'; else fail 'an invalid value exits 1 and names the key and value'; fi
if [[ ! -e "$repo/docs" ]]; then pass 'an invalid value writes nothing'; else fail 'an invalid value writes nothing'; fi

# Unknown key: refused.
run "$repo" verbosity=high
if [[ "$CODE" -eq 1 && "$OUT" == *"verbosity"* && ! -e "$repo/docs" ]]; then pass 'a key outside the schema exits 1 and writes nothing'; else fail 'a key outside the schema exits 1 and writes nothing'; fi

# Existing file holding a key outside the schema: the result would not validate.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf 'explore_output: auto\nverbosity: high\n' >"$repo/docs/conventions/discovery.yaml"
before="$(cat "$repo/docs/conventions/discovery.yaml")"
run "$repo" --yes explore_output=explain
if [[ "$CODE" -eq 1 && "$OUT" == *"verbosity"* && "$(cat "$repo/docs/conventions/discovery.yaml")" == "$before" ]]; then pass 'an existing file with an unknown key is refused and left as it was'; else fail 'an existing file with an unknown key is refused and left as it was'; fi

# An invalid existing value is replaced by a valid one.
printf 'explore_output: tutorial\n' >"$repo/docs/conventions/discovery.yaml"
run "$repo" --yes explore_output=auto
if [[ "$CODE" -eq 0 && "$(bash "$READER" "$repo/docs/conventions/discovery.yaml" explore_output)" == "auto" ]]; then pass 'an invalid existing value is replaced by a valid one'; else fail 'an invalid existing value is replaced by a valid one'; fi

# docs/conventions as a symlink to a directory outside the repository.
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
mkdir -p "$repo/docs"
ln -s "$outside" "$repo/docs/conventions"
run "$repo" explore_output=explain
if [[ "$CODE" -eq 1 && -z "$(ls -A "$outside")" ]]; then pass 'a symlinked docs/conventions is refused and nothing lands outside'; else fail 'a symlinked docs/conventions is refused and nothing lands outside'; fi

# --check: absent, valid, invalid.
repo="$(new_repo)"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *"absent"* ]]; then pass '--check on a missing file reports absent and exits 0'; else fail '--check on a missing file reports absent and exits 0'; fi
mkdir -p "$repo/docs/conventions"
printf 'explore_output: explain\n' >"$repo/docs/conventions/discovery.yaml"
run "$repo" --check
if [[ "$CODE" -eq 0 && "$OUT" == *"explore_output: explain"* ]]; then pass '--check on a valid file prints its value'; else fail '--check on a valid file prints its value'; fi
printf 'explore_output: tutorial\n' >"$repo/docs/conventions/discovery.yaml"
run "$repo" --check
if [[ "$CODE" -eq 1 && "$OUT" == *"explore_output=tutorial"* ]]; then pass '--check on an invalid value exits 1 and names it'; else fail '--check on an invalid value exits 1 and names it'; fi

# Documents a JSON Schema validator rejects although each line looks fine:
# a key set twice, an empty or null value, a map or a list where the schema
# wants one string. --check reports each as WARN. apply replaces a lone
# empty or null value line, which leaves a valid file, and refuses the rest.
shape_case() { # shape_case <label> <refuse|replace> <file content>
  local label="$1" want="$2" content="$3" repo f before
  repo="$(new_repo)"
  f="$repo/docs/conventions/discovery.yaml"
  mkdir -p "$repo/docs/conventions"
  printf '%s' "$content" >"$f"
  before="$(cat "$f")"
  run "$repo" --check
  if [[ "$CODE" -eq 1 && "$OUT" == *WARN* && "$OUT" != *"(unset)"* ]]; then pass "--check warns on $label"; else fail "--check warns on $label"; fi
  run "$repo" --yes explore_output=change-prep
  if [[ "$want" == refuse ]]; then
    if [[ "$CODE" -eq 1 && "$(cat "$f")" == "$before" ]]; then pass "apply refuses $label and leaves the file"; else fail "apply refuses $label and leaves the file"; fi
  elif [[ "$CODE" -eq 0 && "$(cat "$f")" == "explore_output: change-prep" ]]; then
    pass "apply replaces $label with the given value"
  else
    fail "apply replaces $label with the given value"
  fi
}
shape_case 'a duplicate key' refuse $'explore_output: auto\nexplore_output: explain\n'
shape_case 'a duplicate key with a space before the colon' refuse $'explore_output: auto\nexplore_output : explain\n'
shape_case 'a nested map' refuse $'explore_output:\n  mode: explain\n'
shape_case 'a list' refuse $'explore_output:\n  - explain\n'
shape_case 'a flow list' refuse $'explore_output: [explain]\n'
shape_case 'a flow map' refuse $'explore_output: {a: b}\n'
shape_case 'an empty flow list' refuse $'explore_output: []\n'
shape_case 'an empty double-quoted string' refuse $'explore_output: ""\n'
shape_case 'an empty single-quoted string' refuse $'explore_output: \'\'\n'
shape_case 'an empty value' replace $'explore_output:\n'
shape_case 'a null value' replace $'explore_output: null\n'
shape_case 'an unknown key with an empty value' refuse $'stray:\n'

repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf 'stray:\n' >"$repo/docs/conventions/discovery.yaml"
run "$repo" --yes explore_output=explain
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" == *"stray"* ]]; then pass 'an unknown empty key is a one-line refusal that names it'; else fail 'an unknown empty key is a one-line refusal that names it'; fi

# A key given twice on the command line is refused before anything is read or
# written, whether or not the file exists.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
printf 'explore_output: auto\n' >"$repo/docs/conventions/discovery.yaml"
run "$repo" --yes explore_output=change-prep explore_output=explain
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$(cat "$repo/docs/conventions/discovery.yaml")" == 'explore_output: auto' ]]; then pass 'a key given twice is a one-line refusal and the existing file is unchanged'; else fail 'a key given twice is a one-line refusal and the existing file is unchanged'; fi
repo="$(new_repo)"
run "$repo" --yes explore_output=explain explore_output=explain
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && ! -e "$repo/docs/conventions/discovery.yaml" ]]; then pass 'a key given twice with no file is a one-line refusal and nothing is created'; else fail 'a key given twice with no file is a one-line refusal and nothing is created'; fi

# A --root that is a symlink to a repository: the link is resolved once and
# the file lands in the repository it points at.
repo="$(new_repo)"
ln -s "$repo" "$WORKROOT/root-link"
run "$WORKROOT/root-link" explore_output=explain
if [[ "$CODE" -eq 0 && "$(bash "$READER" "$repo/docs/conventions/discovery.yaml" explore_output)" == "explain" ]]; then pass 'a symlinked --root writes into the repository it points at'; else fail 'a symlinked --root writes into the repository it points at'; fi

# Write-path guards: a hard-linked target, a directory where the file goes,
# and a file where docs/ should be. Each is a one-line refusal, no stack trace.
repo="$(new_repo)"
outside="$(mktemp -d "$WORKROOT/outside.XXXXXX")"
printf 'explore_output: auto\n' >"$outside/shared.yaml"
mkdir -p "$repo/docs/conventions"
ln "$outside/shared.yaml" "$repo/docs/conventions/discovery.yaml"
run "$repo" --yes explore_output=explain
if [[ "$CODE" -eq 1 && "$(cat "$outside/shared.yaml")" == "explore_output: auto" ]]; then pass 'a hard-linked target is refused and the other link is untouched'; else fail 'a hard-linked target is refused and the other link is untouched'; fi

repo="$(new_repo)"
mkdir -p "$repo/docs/conventions/discovery.yaml"
run "$repo" --yes explore_output=explain
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" != *"    at "* ]]; then pass 'a directory at the target path is a one-line refusal'; else fail 'a directory at the target path is a one-line refusal'; fi
run "$repo" --check
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" != *"    at "* ]]; then pass '--check on a directory at the target path is a one-line refusal'; else fail '--check on a directory at the target path is a one-line refusal'; fi

repo="$(new_repo)"
printf 'not a directory\n' >"$repo/docs"
run "$repo" explore_output=explain
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$(cat "$repo/docs")" == "not a directory" ]]; then pass 'docs as a file is a one-line refusal'; else fail 'docs as a file is a one-line refusal'; fi

# Failures opening or writing the temp file: one-line refusal, no temp file left.
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
chmod 555 "$repo/docs/conventions"
run "$repo" explore_output=explain
chmod 755 "$repo/docs/conventions"
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && -z "$(ls -A "$repo/docs/conventions")" ]]; then pass 'an unwritable docs/conventions is a one-line refusal'; else fail 'an unwritable docs/conventions is a one-line refusal'; fi

repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
OUT="$(ulimit -f 0 && node "$SUT" --root "$repo" explore_output=explain 2>&1)"
CODE=$?
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && -z "$(ls -A "$repo/docs/conventions")" ]]; then pass 'a failed write is a one-line refusal and removes the temp file'; else fail 'a failed write is a one-line refusal and removes the temp file'; fi

# A close that fails after releasing the descriptor (EIO, as close(2) may
# report): a preload makes the first close of the temp file throw.
preload="$WORKROOT/close-fails.cjs"
printf '%s\n' \
  'const fs = require("node:fs");' \
  'const open = fs.openSync, close = fs.closeSync;' \
  'let tmpFd = -1;' \
  'fs.openSync = (p, ...rest) => { const fd = open(p, ...rest); if (String(p).endsWith(".tmp")) tmpFd = fd; return fd; };' \
  'fs.closeSync = (fd) => { close(fd); if (fd === tmpFd) { tmpFd = -1; throw Object.assign(new Error("EIO: i/o error, close"), { code: "EIO" }); } };' \
  'require("node:module").syncBuiltinESMExports();' >"$preload"
repo="$(new_repo)"
mkdir -p "$repo/docs/conventions"
OUT="$(node --require "$preload" "$SUT" --root "$repo" explore_output=explain 2>&1)"
CODE=$?
if [[ "$CODE" -eq 1 && "$(wc -l <<<"$OUT")" -eq 1 && "$OUT" == *EIO* && "$OUT" != *"    at "* ]]; then pass 'a failed close is a one-line refusal'; else fail 'a failed close is a one-line refusal'; fi
if [[ -z "$(ls -A "$repo/docs/conventions")" ]]; then pass 'a failed close removes the temp file'; else fail 'a failed close removes the temp file'; fi

# Usage errors.
run "$repo"
if [[ "$CODE" -eq 2 ]]; then pass 'no <key>=<value> exits 2'; else fail 'no <key>=<value> exits 2'; fi
run "$repo" --check explore_output=auto
if [[ "$CODE" -eq 2 ]]; then pass '--check with a pair exits 2'; else fail '--check with a pair exits 2'; fi
OUT="$(cd "$WORKROOT" && GIT_CEILING_DIRECTORIES="$WORKROOT" node "$SUT" explore_output=auto 2>&1)"
CODE=$?
if [[ "$CODE" -eq 2 && "$OUT" == *"git working tree"* ]]; then pass 'outside a git working tree without --root exits 2'; else fail 'outside a git working tree without --root exits 2'; fi

if ((fails)); then
  printf '%d failure(s)\n' "$fails" >&2
  exit 1
fi
echo 'all setup-apply checks passed'
