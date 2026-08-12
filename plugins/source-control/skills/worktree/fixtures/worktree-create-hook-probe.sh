#!/usr/bin/env bash
# worktree-create-hook-probe.sh — measure what Claude Code actually does with a
# WorktreeCreate hook's exit status, stdout, and stderr.
#
# This exists because the plugin's placement gate, its opt-out option, and its
# whole failure-message design rest on four harness behaviors that no doc stated
# unambiguously when they were first written, and that a reader cannot check by
# inspection. Running this is the recheck procedure — not a re-derivation from
# memory. See fixtures/README.md for the recorded outcome and its as-of stamp.
#
# Costs four real `claude -p` turns. Network and an authenticated CLI required.
#
# Usage: bash worktree-create-hook-probe.sh [workdir]

set -uo pipefail

WORKDIR="${1:-$(mktemp -d "${TMPDIR:-/tmp}/wtprobe.XXXXXX")}"
mkdir -p "$WORKDIR"
printf 'probe workdir: %s\n' "$WORKDIR"
printf 'claude version: %s\n\n' "$(claude --version 2>&1)"

command -v claude >/dev/null 2>&1 || {
  printf 'claude CLI not on PATH — cannot probe\n' >&2
  exit 1
}

# Each arm gets its own throwaway repo: a failed arm must not leave a worktree
# behind that the next arm then reads as its own result.
mkrepo() {
  local repo="$WORKDIR/$1"
  rm -rf "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email probe@probe.test
  git -C "$repo" config user.name probe
  # Repo-local, on a repo this function just created: a machine with global
  # commit.gpgsign=true has no secret key for the fixture identity.
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  printf '%s' "$repo"
}

# Write a hook script and the settings file that registers it.
mkhook() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" >"$WORKDIR/$name.sh"
  # Shell form (no `args`): the path carries no placeholder, so the documented
  # rule at <https://code.claude.com/docs/en/hooks> ("Set `args` whenever the
  # hook references a path placeholder") does not require exec form here.
  printf '{"hooks":{"WorktreeCreate":[{"hooks":[{"type":"command","command":"bash \\"%s\\"","timeout":30}]}]}}\n' \
    "$WORKDIR/$name.sh" >"$WORKDIR/$name-settings.json"
}

arm() {
  local label="$1" repo="$2" wtname="$3" settings="${4:-}"
  printf '=== %s ===\n' "$label"
  local out rc
  if [[ -n "$settings" ]]; then
    out="$(cd "$repo" && claude -p "Reply with exactly: OK" --worktree "$wtname" --settings "$settings" 2>&1)"
  else
    out="$(cd "$repo" && claude -p "Reply with exactly: OK" --worktree "$wtname" 2>&1)"
  fi
  rc=$?
  printf 'exit: %s\n' "$rc"
  printf 'output: %s\n' "$out"
  printf 'worktrees:\n'
  git -C "$repo" worktree list --porcelain | sed 's/^/  /'
  printf '\n'
}

mkhook noop 'printf "PROBE-STDERR-MARKER\n" >&2
exit 0'
mkhook fail 'printf "FIRST-STDERR-LINE\n" >&2
printf "SECOND-STDERR-LINE\n" >&2
exit 3'
mkhook path "printf '%s/uncreated-dir\n' \"$WORKDIR\"
exit 0"

# Arm 1 — control. Establishes the default placement, the branch name, and
# whether Claude Code locks what it creates.
arm "ARM 1 control: no WorktreeCreate hook" "$(mkrepo repoA)" probe0

# Arm 2 — the decisive one. Does exit 0 with an empty stdout hand placement back
# to Claude Code, or fail the creation? Also: does an exit-0 hook's stderr reach
# the user? Grep the output for PROBE-STDERR-MARKER.
arm "ARM 2: hook exits 0, prints no path" "$(mkrepo repoB)" probe1 "$WORKDIR/noop-settings.json"

# Arm 3 — how much of a FAILING hook's stderr is surfaced: the first line only,
# or all of it? The plugin's message design depends on the answer.
arm "ARM 3: hook exits 3 with two stderr lines" "$(mkrepo repoC)" probe3 "$WORKDIR/fail-settings.json"

# Arm 4 — must the hook create the directory, or is printing a path enough?
rm -rf "$WORKDIR/uncreated-dir"
arm "ARM 4: hook prints a path it did not create" "$(mkrepo repoD)" probe4 "$WORKDIR/path-settings.json"

printf 'probe complete. Compare against fixtures/README.md and update the as-of stamp there.\n'
