# shellcheck shell=bash
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT CLAUDE_PLUGIN_ROOT CLAUDE_PLUGIN_DATA LEFTHOOK
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT "${!GIT_CONFIG_KEY_@}" "${!GIT_CONFIG_VALUE_@}"

# shellcheck disable=SC2154 # HERE is set by the suite that sources this file
PLUGIN="$(cd "$HERE/.." && pwd)"
NAME="${PLUGIN##*/}"
TOP="$(cd "$PLUGIN/../.." && pwd)"
CONFIG="$HERE/lefthook-remote.yml"
INSTALL="$PLUGIN/lib/git-hooks/install.mjs"
URL="https://github.com/melodic-software/claude-code-plugins"
SH="$(command -v dash)" || SH="sh"

PASS=0
FAIL=0
expect() {
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

lr_done() {
  echo "lefthook-remote: $PASS passed, $FAIL failed"
  ((FAIL == 0))
  exit
}

LR_JOBS="$(awk '
  /^[a-z-]+:$/ { event = substr($0, 1, length($0) - 1) }
  /^ *- name: / { name = $3 }
  /^ *script: / { print event, name, $2 }
' "$CONFIG")"

lr_static() {
  local event name script wrapper line target guard root out win entry
  expect "$NAME: one remote job per entries.json entry, at its event" \
    "$(jq -r '.entries[] | "\(.event) \(.name)"' "$HERE/entries.json" | sort | xargs)" \
    "$(while read -r event name script; do echo "$event ${name#"$NAME"-remote-}"; done <<<"$LR_JOBS" | sort | xargs)"
  expect "entries.json's remote names this config and the root aggregate" \
    "plugins/$NAME/git-hooks/lefthook-remote.yml lefthook-remote.yml main" \
    "$(jq -r '.remote | "\(.config) \(.aggregate) \(.ref)"' "$HERE/entries.json")"
  # shellcheck disable=SC2053 # the aggregate's extends line is a glob, matched as one
  expect "the root lefthook-remote.yml extends this config" yes \
    "$(sed -n 's/^  - //p' "$TOP/lefthook-remote.yml" | while read -r glob; do [[ "plugins/$NAME/git-hooks/lefthook-remote.yml" == $glob ]] && echo yes; done | head -n 1)"
  guard="$(mktemp -d)"
  while read -r event name script; do
    wrapper="$TOP/.lefthook/$event/$script"
    expect "$name: its script is $NAME-<entry>.sh under .lefthook/$event/" yes \
      "$([[ -f "$wrapper" && "$script" == "$NAME-${name#"$NAME"-remote-}.sh" ]] && echo yes)"
    # shellcheck disable=SC2016 # matches the wrapper's literal text
    line="$(sed -n 's#^exec sh "${src%/\*}/../remote-entry.sh" \([a-z-]*\) \([a-z0-9-]*\) "${src%/\*}/\(.*\)" "\$@"$#\1 \2 \3#p' "$wrapper" 2>/dev/null)"
    target="${line##* }"
    expect "$name: its script passes its own event and job name to remote-entry.sh" "$event $name" "${line% *}"
    expect "$name: its script runs an entry script that exists" yes \
      "$([[ -n "$target" && -f "$TOP/.lefthook/$event/$target" ]] && echo yes)"
    expect "$name: the job's runner is sh" yes \
      "$(awk -v s="$script" '$1 == "script:" { hit = ($2 == s) } hit && $1 == "runner:" { print ($2 == "sh" ? "yes" : "no"); exit }' "$CONFIG")"
    expect "$name: a pre-push job reads the pushed refs on stdin" "$([[ "$event" == pre-push ]] && echo true)" \
      "$(awk -v s="$script" '$1 == "script:" { hit = ($2 == s) } hit && $1 == "use_stdin:" { print $2; exit } hit && $1 == "-" { exit }' "$CONFIG")"
    for root in "$guard/wt" "$guard/git/info/lefthook-remotes/r"; do
      mkdir -p "$root/.lefthook/$event" "$(dirname "$root/.lefthook/$event/$target")"
      cp "$wrapper" "$root/.lefthook/$event/$script"
      cp "$TOP/.lefthook/remote-entry.sh" "$root/.lefthook/remote-entry.sh"
      # shellcheck disable=SC2016 # the stub's own text
      printf '#!/bin/sh\necho "ran $*"\n[ "$1" = ok ]\n' >"$root/.lefthook/$event/$target"
    done
    out="$("$SH" "$guard/wt/.lefthook/$event/$script" x </dev/null 2>&1)"
    expect "$name: the work-tree copy exits 0 without running the entry script" "0:" "$?:$out"
    out="$("$SH" "$guard/git/info/lefthook-remotes/r/.lefthook/$event/$script" ok </dev/null 2>&1)"
    expect "$name: the fetched copy runs the entry script with the hook's arguments" "0:ran ok" "$?:$out"
    out="$("$SH" "$guard/git/info/lefthook-remotes/r/.lefthook/$event/$script" bad </dev/null 2>&1)"
    expect "$name: a failing entry fails the job and names the per-clone skip" "1|ran bad|yes" \
      "$?|$(head -n 1 <<<"$out")|$(grep -q "^$name failed (exit 1)" <<<"$out" && grep -qx "$event:" <<<"$out" && grep -qx "    - name: $name" <<<"$out" && grep -qx '      skip: true' <<<"$out" && echo yes)"
    win="$guard/git\\info\\lefthook-remotes\\r\\.lefthook\\$event\\$script"
    cp "$wrapper" "$win"
    out="$("$SH" "$win" ok </dev/null 2>&1)"
    expect "$name: the fetched copy runs from a backslash path" "ran ok" "$out"
    entry="${script#"$NAME"-}"
    expect "$name: not a shared-copy job name" yes "$([[ "$name" != "$NAME-${entry%.sh}" ]] && echo yes)"
  done <<<"$LR_JOBS"
  rm -rf "${guard:?}"
}

lr_e2e_start() {
  local event name script out start
  if ! command -v lefthook >/dev/null 2>&1; then
    if [[ "${LEFTHOOK_REMOTE_REQUIRE:-${GUARDRAILS_REQUIRE_LEFTHOOK:-}}" == 1 ]]; then
      expect "lefthook is on PATH for the end-to-end cases" yes no
      lr_done
    fi
    echo "SKIP: lefthook not on PATH -- remote end-to-end cases skipped"
    return 1
  fi
  WORK="$(mktemp -d)"
  trap 'rm -rf "$WORK"' EXIT
  export GIT_CONFIG_GLOBAL="$WORK/gitconfig" GIT_CONFIG_NOSYSTEM=1
  SRC="$WORK/src"
  mkdir -p "$SRC/plugins"
  cp -R "$PLUGIN" "$SRC/plugins/$NAME"
  cp -R "$TOP/.lefthook" "$SRC/.lefthook"
  cp "$TOP/lefthook-remote.yml" "$SRC/lefthook-remote.yml"
  git init -q -b main "$SRC"
  git -C "$SRC" add -A
  git -C "$SRC" -c user.name=t -c user.email=t@example.invalid commit -q -m src --no-verify
  git config --global "url.file://$SRC.insteadOf" "$URL"

  REPO="$WORK/consumer"
  git init -q --bare -b main "$WORK/consumer.git"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.name t
  git -C "$REPO" config user.email t@example.invalid
  git -C "$REPO" remote add origin "$WORK/consumer.git"
  node -e 'const p = JSON.parse(process.argv[1]); console.log(p.decisions.find((d) => d.kind === "lefthook-config").snippet)' \
    "$(node "$INSTALL" plan --scope remote --repo "$REPO")" >"$REPO/lefthook.yml"
  expect "the plan's snippet names the root aggregate" "      - lefthook-remote.yml" "$(tail -n 1 "$REPO/lefthook.yml")"
  (cd "$REPO" && lefthook install >/dev/null 2>&1)
  out="$(node "$INSTALL" verify --repo "$REPO")"
  expect "lefthook install fetches the remote and verify reports every entry ok" \
    "$(jq -r '.entries[] | "ok"' "$HERE/entries.json" | xargs)" "$(grep -v $'^tool\t' <<<"$out" | cut -f1 | xargs)"
  expect "verify reports a tool missing exactly when it is not on PATH" \
    "$(jq -r '.entries[].tools[]' "$HERE/entries.json" | sort -u | while read -r tool; do command -v "$tool" >/dev/null 2>&1 || echo "$tool"; done | xargs)" \
    "$(awk -F '\t' '$1 == "tool" && $3 == "missing" { print $2 }' <<<"$out" | sort -u | xargs)"
  FETCHED="$REPO/.git/info/lefthook-remotes/claude-code-plugins-main"
  out="$(cd "$REPO" && lefthook dump 2>/dev/null)"
  while read -r event name script; do
    expect "$name: the consumer's merged config holds the job through the aggregate's extends" yes \
      "$(grep -q "name: $name\$" <<<"$out" && echo yes)"
  done <<<"$LR_JOBS"
  git -C "$REPO" add lefthook.yml
  git -C "$REPO" commit -q -m seed --no-verify
  git -C "$REPO" push -q origin main >/dev/null 2>&1
  while read -r event name script; do
    start="$EPOCHREALTIME"
    out="$(cd "$REPO" && "$SH" "$FETCHED/.lefthook/$event/$script" </dev/null 2>&1)"
    expect "$name: with nothing to check it exits 0 with no output" "0:" "$?:$out"
    expect "$name: with nothing to check it is done within 2 s ($(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { printf "%.2f", b - a }') s)" yes \
      "$(awk -v a="$start" -v b="$EPOCHREALTIME" 'BEGIN { print (b - a < 2) ? "yes" : "no" }')"
  done <<<"$LR_JOBS"
}

lr_allowed_missing() {
  case "$1" in
    goimports) echo "the repository pins no goimports for CI" ;;
    *) return 1 ;;
  esac
}

lr_missing() {
  local why
  if [[ "${LEFTHOOK_REMOTE_REQUIRE_TOOLS:-}" == 1 ]] && ! why="$(lr_allowed_missing "$1")"; then
    expect "$1 is on PATH for the seeded $NAME cases (LEFTHOOK_REMOTE_REQUIRE_TOOLS=1)" yes no
  else
    echo "SKIP: ${2:-$1 not on PATH} -- the seeded $NAME cases skipped${why:+ ($why)}"
  fi
  lr_done
}

lr_require_tools() {
  local tool
  for tool in "$@"; do
    command -v "$tool" >/dev/null 2>&1 || lr_missing "$tool"
  done
}

lr_commit() {
  LR_ERR="$(git -C "$REPO" commit -q -m "${1:-change}" 2>&1 >/dev/null)"
  LR_RC=$?
}

lr_push() {
  git -C "$REPO" switch -q -C lr-side
  LR_ERR="$(git -C "$REPO" push -q origin main 2>&1)"
  LR_RC=$?
  git -C "$REPO" switch -q main
}

lr_expect_block() {
  local got
  got="$((LR_RC != 0))|$(grep -qE -- "$3" <<<"$LR_ERR" && echo yes)|$(grep -q "^$2 failed" <<<"$LR_ERR" && grep -qx "    - name: $2" <<<"$LR_ERR" && echo yes)"
  expect "$1" "1|yes|yes" "$got"
  [[ "$got" == "1|yes|yes" ]] || printf '%s\n' "$LR_ERR" >&2
}

lr_expect_pass() {
  expect "$1" 0 "$LR_RC"
  [[ "$LR_RC" == 0 ]] || printf '%s\n' "$LR_ERR" >&2
}

lr_skip() {
  printf '%s:\n  jobs:\n    - name: %s\n      skip: true\n' "$1" "$2" >"$REPO/lefthook-local.yml"
  grep -qx lefthook-local.yml "$REPO/.git/info/exclude" 2>/dev/null || echo lefthook-local.yml >>"$REPO/.git/info/exclude"
  if [[ "$3" == push ]]; then lr_push; else lr_commit "${LR_SKIP_MSG:-skipped}"; fi
  expect "$2: a lefthook-local.yml skip of the job lets the same $3 through" 0 "$LR_RC"
  expect "$2: the skip file stays out of git" "" "$(git -C "$REPO" status --porcelain -- lefthook-local.yml)"
  rm "$REPO/lefthook-local.yml"
}

lr_skip_keeps() {
  local job
  printf '%s' "$3" >"$REPO/$2"
  git -C "$REPO" add -- "$2"
  {
    printf 'pre-commit:\n  jobs:\n'
    for job in "$1" ${4:+"$4"}; do printf '    - name: %s\n      skip: true\n' "$job"; done
  } >"$REPO/lefthook-local.yml"
  grep -qx lefthook-local.yml "$REPO/.git/info/exclude" 2>/dev/null || echo lefthook-local.yml >>"$REPO/.git/info/exclude"
  lr_commit "${LR_SKIP_MSG:-skipped}"
  expect "$1: with the job skipped in lefthook-local.yml, $2 commits as staged" "0|$3" "$LR_RC|$(git -C "$REPO" show "HEAD:$2")
"
  rm "$REPO/lefthook-local.yml"
}
