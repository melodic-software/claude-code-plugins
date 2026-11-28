#!/usr/bin/env bash

set -uo pipefail

WORKDIR="${1:-$(mktemp -d "${TMPDIR:-/tmp}/wtprobe.XXXXXX")}"
mkdir -p "$WORKDIR"
printf 'probe workdir: %s\n' "$WORKDIR"
printf 'claude version: %s\n\n' "$(claude --version 2>&1)"

command -v claude >/dev/null 2>&1 || {
  printf 'claude CLI not on PATH — cannot probe\n' >&2
  exit 1
}

mkrepo() {
  local repo="$WORKDIR/$1"
  rm -rf "$repo"
  git init -q -b main "$repo"
  git -C "$repo" config user.email probe@probe.test
  git -C "$repo" config user.name probe
  git -C "$repo" config commit.gpgsign false
  printf 'seed\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -qm init
  printf '%s' "$repo"
}

mkhook() {
  local name="$1" body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" >"$WORKDIR/$name.sh"
  # Shell form: no path placeholder, so "Set `args` whenever the hook references a path
  # placeholder" (<https://code.claude.com/docs/en/hooks>) does not apply.
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

arm "ARM 1 control: no WorktreeCreate hook" "$(mkrepo repoA)" probe0

arm "ARM 2: hook exits 0, prints no path" "$(mkrepo repoB)" probe1 "$WORKDIR/noop-settings.json"

arm "ARM 3: hook exits 3 with two stderr lines" "$(mkrepo repoC)" probe3 "$WORKDIR/fail-settings.json"

rm -rf "$WORKDIR/uncreated-dir"
arm "ARM 4: hook prints a path it did not create" "$(mkrepo repoD)" probe4 "$WORKDIR/path-settings.json"

printf 'probe complete. Compare against fixtures/README.md and update the as-of stamp there.\n'
