#!/usr/bin/env bash
# project-scope-reap-probe.sh — measure what `claude plugin uninstall <id>
# -s project` actually acts on, so the teardown reap in context/cleanup.md
# rests on a measurement rather than on an inference from the flag's name.
#
# The whole reap design turns on one question: `-s project` has no path flag,
# so WHICH directory's records does it remove, and does it still work once the
# directory it recorded is gone? A reap wired in after `git worktree remove`
# would be worthless if the answer were "only the live cwd, and only while it
# exists".
#
# Costs no `claude -p` turns. It writes real project-scope records for its own
# throwaway directories and removes them again through the CLI; it never
# touches a record belonging to any other path, and it never edits
# installed_plugins.json — that file is read here and written only by the CLI.
#
# Usage: bash project-scope-reap-probe.sh [plugin@marketplace] [second@marketplace]
# See fixtures/README.md for the recorded outcome and its as-of stamp.

set -uo pipefail

PLUGIN_A="${1:-caveman@caveman}"
PLUGIN_B="${2:-codex@openai-codex}"
WORKDIR="${TEMP:-${TMPDIR:-/tmp}}/wt-reap-probe.$$"

command -v claude >/dev/null 2>&1 || {
  printf 'claude CLI not on PATH — cannot probe\n' >&2
  exit 1
}
command -v jq >/dev/null 2>&1 || {
  printf 'jq not on PATH — the record reader needs it\n' >&2
  exit 1
}

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR"
printf 'probe workdir: %s\n' "$WORKDIR"
printf 'claude version: %s\n' "$(claude --version 2>&1)"
printf 'probe plugins: %s, %s\n\n' "$PLUGIN_A" "$PLUGIN_B"

REC="${USERPROFILE:-$HOME}/.claude/plugins/installed_plugins.json"

# READ-ONLY view of the record store. Every mutation below goes through the CLI.
snap() {
  jq -r '
    [.plugins // {} | to_entries[] | .key as $id | .value[] | select(.scope=="project") | {id:$id, path:(.projectPath // "-")}]
    | (length | tostring) as $n
    | ([.[] | select(.path | ascii_downcase | test("wt-reap-probe"))] ) as $mine
    | "  machine-wide project records: " + $n
      + " | this probe'"'"'s: " + ($mine | length | tostring)
      + (if ($mine|length) > 0 then "  [" + ($mine | map(.id + " -> " + .path) | join(" ; ")) + "]" else "" end)
  ' "$REC"
}

native() { (cd "$1" && { pwd -W 2>/dev/null || pwd -P; }); }

printf -- '--- baseline ---\n'
snap

LIVE="$WORKDIR/live"
DEAD="$WORKDIR/dead"
OTHER="$WORKDIR/other"
mkdir -p "$LIVE" "$DEAD" "$OTHER"

printf '\n=== ARM 1: install -s project from a plain (non-git) directory ===\n'
printf 'Q: does it write a record, and keyed by what?\n'
(cd "$LIVE" && claude plugin install "$PLUGIN_A" -s project >/dev/null 2>&1)
printf '  install exit: %s\n' "$?"
(cd "$LIVE" && claude plugin install "$PLUGIN_B" -s project >/dev/null 2>&1)
printf '  install exit: %s\n' "$?"
(cd "$DEAD" && claude plugin install "$PLUGIN_A" -s project >/dev/null 2>&1)
printf '  install exit (second directory): %s\n' "$?"
snap
printf '  live/.claude/settings.json: %s\n' "$(tr -d '\n\r' <"$LIVE/.claude/settings.json" 2>/dev/null)"
printf '  cwd resolved natively as: %s\n' "$(native "$LIVE")"

printf '\n=== ARM 2: is plugin list --json enumeration cwd-INDEPENDENT? ===\n'
printf 'Q: can a reap enumerate records for a path it is not standing in?\n'
for d in "$LIVE" "$OTHER"; do
  sig="$( (cd "$d" && claude plugin list --json 2>/dev/null) | jq -r '
      (if type=="object" then (.installed // .plugins // []) else . end)
      | map(select(.scope=="project"))
      | .[]
      | (.id + "|" + (.projectPath // "-"))
    ' | tr -d '\r' | sort)"
  printf '  from %s: %s project records, set checksum %s\n' "$d" \
    "$(printf '%s\n' "$sig" | grep -c '[^[:space:]]')" \
    "$(printf '%s' "$sig" | cksum)"
done

printf '\n=== ARM 3: uninstall -s project from a DIFFERENT cwd ===\n'
printf 'Q: does the flag reach a record belonging to another path?\n'
out="$( (cd "$OTHER" && claude plugin uninstall "$PLUGIN_A" -s project) 2>&1 )"
printf '  exit: %s\n' "$?"
printf '  output: %s\n' "$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ')"
snap

printf '\n=== ARM 4: uninstall -s project from the recorded directory ===\n'
out="$( (cd "$LIVE" && claude plugin uninstall "$PLUGIN_A" -s project) 2>&1 )"
printf '  exit: %s\n' "$?"
printf '  output: %s\n' "$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ')"
out="$( (cd "$LIVE" && claude plugin uninstall "$PLUGIN_B" -s project) 2>&1 )"
printf '  exit: %s\n' "$?"
snap

printf '\n=== ARM 5: delete the directory, then recreate it EMPTY at the same path ===\n'
printf 'Q: does the record outlive the directory, and can a recreated directory reach it?\n'
cd "$WORKDIR" || exit 1
rm -rf "$DEAD"
printf '  directory exists after rm -rf: %s\n' "$([[ -d "$DEAD" ]] && echo yes || echo no)"
printf '  record after rm -rf:\n'
snap
mkdir -p "$DEAD"
out="$( (cd "$DEAD" && claude plugin uninstall "$PLUGIN_A" -s project) 2>&1 )"
printf '  exit: %s\n' "$?"
printf '  output: %s\n' "$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ')"
snap
printf '  residue the recreated directory is left holding: %s\n' \
  "$(find "$DEAD" -type f 2>/dev/null | tr '\n' ' ')"

printf '\n=== ARM 6: uninstall -s project where NO record exists here ===\n'
printf 'Q: what does a no-op look like, and what does it advise?\n'
out="$( (cd "$OTHER" && claude plugin uninstall "$PLUGIN_A" -s project) 2>&1 )"
printf '  exit: %s\n' "$?"
printf '  output: %s\n' "$(printf '%s' "$out" | tr -d '\r' | tr '\n' ' ')"

printf '\n--- final ---\n'
snap
printf '\nIf the final line still names a probe directory, recreate that directory\n'
printf 'and re-run the uninstall from inside it — never hand-edit installed_plugins.json.\n'
printf 'probe complete. Record the outcome in fixtures/README.md and refresh its stamp.\n'
