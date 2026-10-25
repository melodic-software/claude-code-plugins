#!/usr/bin/env bash
# No git-hook file the plugins install reaches bash by name. Every entry script a
# plugin's git-hooks/entries.json names, the check lib (canonical and copies),
# the plain dispatcher install.mjs writes, the convention resolver (canonical
# and copy) and the lefthook remote's .lefthook/ wrappers start with #!/bin/sh
# and name bash nowhere as a command, and the lefthook remote runs its scripts
# with sh: on Windows a bash looked up by name can be System32's WSL launcher,
# and a git may ship sh with no bash beside it. Under dash, each entry
# runs outside a repository and exits 0, and a probe that sources the check lib
# reruns under the first bash on PATH outside System32, or with none follows the
# check-placement contract's missing-tool rule.
# test-scope: plugins/*/git-hooks/* plugins/*/lib/git-hooks/check-lib.sh lib/git-hooks/install.mjs lib/git-hooks/check-lib.sh lib/resolve-convention-pattern.sh plugins/guardrails/hooks/resolve-convention-pattern.sh .lefthook/*
# shellcheck disable=SC2016 # single-quoted $ text is shell source written to files or matched literally
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_CONFIG CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOP="$(cd "$HERE/../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1

PASS=0
FAIL=0
expect() { # <label> <want> <got>
  if [[ "$2" == "$3" ]]; then
    echo "ok: $1"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $1: want [$2] got [$3]" >&2
    FAIL=$((FAIL + 1))
  fi
}

# bash where a command goes: at the start of a line or after ; & | ( ) { ! `
# or $(, behind any run of words that run the next one (then, do, else, if,
# elif, while, until, exec, env, time, xargs, nohup, command, or feed, the
# dispatcher's helper) and of NAME=value assignments. Comment lines are
# skipped. A path ending in /bash or a message naming bash is not a command.
CMD_BASH='(^|[;&|(){!`]|\$\()[[:space:]]*((then|do|else|if|elif|while|until|exec|env|time|xargs|nohup|command|feed|[[:alnum:]_]+=[^[:space:]]*)[[:space:]]+)*bash([[:space:]]|;|\)|$)'
COMMENT='^[[:space:]]*#'

# bash_commands <file>: "<line number>: <line>" for each line after the first
# that names bash as a command.
bash_commands() {
  local n=0 line
  while IFS= read -r line || [[ -n "$line" ]]; do
    n=$((n + 1))
    ((n > 1)) || continue
    [[ "$line" =~ $COMMENT ]] && continue
    [[ "$line" =~ $CMD_BASH ]] && printf '%s: %s\n' "$n" "$line"
  done <"$1"
  return 0
}

printf '%s\n' '#!/bin/sh' 'x=$(bash y)' '  feed bash "$f"' 'exec bash z' '  ROOT="$r" bash "$g" |' \
  '*) bash w ;;' 'if bash v; then :; fi' '# bash in a comment' 'echo "run: bash y"' \
  'echo "skip only while bash is missing"' '[ -x "$d/bash" ]' '"$BASH" y' >"$WORK/sample"
expect "the command pattern catches bash run by name, and only that" \
  $'2: x=$(bash y)\n3:   feed bash "$f"\n4: exec bash z\n5:   ROOT="$r" bash "$g" |\n6: *) bash w ;;\n7: if bash v; then :; fi' \
  "$(bash_commands "$WORK/sample")"

# sh_only <label> <file>: line 1 is #!/bin/sh and no line runs bash by name.
sh_only() {
  expect "$1: line 1 is #!/bin/sh" "#!/bin/sh" "$(head -n 1 "$2")"
  expect "$1: names bash as no command" "" "$(bash_commands "$2")"
}

# entry_scripts <entries.json>: the script each entry names, one per line.
entry_scripts() {
  sed -n 's/.*"script"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$1"
}

entries=0
for manifest in "$TOP"/plugins/*/git-hooks/entries.json; do
  dir="${manifest%/entries.json}"
  while IFS= read -r script; do
    entries=$((entries + 1))
    sh_only "entry ${dir#"$TOP"/}/$script" "$dir/$script"
  done < <(entry_scripts "$manifest")
done
expect "every plugin's entries were read" yes "$( ((entries >= 12)) && echo yes)"

sh_only "check lib" "$HERE/check-lib.sh"
for lib in "$TOP"/plugins/*/lib/git-hooks/check-lib.sh; do
  sh_only "check lib copy ${lib#"$TOP"/}" "$lib"
done
sh_only "convention resolver" "$TOP/lib/resolve-convention-pattern.sh"
sh_only "convention resolver copy" "$TOP/plugins/guardrails/hooks/resolve-convention-pattern.sh"
for wrapper in "$TOP"/.lefthook/*/*.sh; do
  sh_only "lefthook remote wrapper ${wrapper#"$TOP"/}" "$wrapper"
done

remote="$TOP/plugins/guardrails/git-hooks/lefthook-remote.yml"
expect "the lefthook remote runs every script with sh" "3|0" \
  "$(grep -cE '^[[:space:]]*runner:[[:space:]]*sh[[:space:]]*$' "$remote")|$(grep -E '^[[:space:]]*runner:' "$remote" | grep -cvE 'runner:[[:space:]]*sh[[:space:]]*$')"

# The path goes in the environment, not argv: install.mjs runs its CLI when
# argv[1] names it.
INSTALL_MJS="$HERE/install.mjs" node --input-type=module -e '
  import { pathToFileURL } from "node:url";
  const { DISPATCHER } = await import(pathToFileURL(process.env.INSTALL_MJS).href);
  process.stdout.write(DISPATCHER);
' >"$WORK/dispatcher"
expect "the dispatcher was read from install.mjs" yes "$(grep -q 'checks-dispatcher' "$WORK/dispatcher" && echo yes)"
sh_only "plain dispatcher" "$WORK/dispatcher"
expect "the dispatcher runs each entry with sh" yes "$(grep -qF 'feed sh "$base/$rel"' "$WORK/dispatcher" && echo yes)"

# A probe entry beside a copy of the check lib, a child script, stand-ins for
# System32's bash (the WSL launcher), a real bash outside System32, and bash
# under the name sh, which starts it in POSIX mode: a sh that is bash.
mkdir -p "$WORK/outside" "$WORK/probe" "$WORK/Windows/System32" "$WORK/c/WINDOWS/system32" \
  "$WORK/good" "$WORK/tools" "$WORK/as-sh"
export GIT_CEILING_DIRECTORIES="$WORK"
cp "$HERE/check-lib.sh" "$WORK/probe/check-lib.sh"
cat >"$WORK/probe/probe.sh" <<'EOF'
#!/bin/sh
case "$0" in */*) here="${0%/*}" ;; *) here=. ;; esac
. "$here/check-lib.sh" || exit 1
case ":$SHELLOPTS:" in *:posix:*) mode=posix ;; *) mode=bash ;; esac
printf '%s|%s|%s|%s\n' "$BASH" "$*" "$mode" "$CHECKS_CHILD_BASH"
EOF
cat >"$WORK/child.sh" <<'EOF'
case ":$SHELLOPTS:" in *:posix:*) mode=posix ;; *) mode=bash ;; esac
printf '%s|%s|%s\n' "$mode" "$BASH" "$*"
EOF
for fake in "$WORK/Windows/System32/bash" "$WORK/c/WINDOWS/system32/bash"; do
  printf '#!/bin/sh\necho wsl\n' >"$fake"
  chmod +x "$fake"
done
ln -s "$BASH" "$WORK/good/bash"
ln -s "$BASH" "$WORK/as-sh/sh"
ln -s "$(command -v git)" "$WORK/tools/git"
SYS32="$WORK/c/WINDOWS/system32:$WORK/Windows/System32"
AS_SH="$WORK/as-sh/sh"

expect "bash named sh starts in POSIX mode, so it stands in for a sh that is bash" "posix|$AS_SH|" \
  "$(cd "$WORK/outside" && PATH="$SYS32:$WORK/good" "$AS_SH" "$WORK/child.sh")"
out="$(cd "$WORK/outside" && PATH="$SYS32:$WORK/good" "$AS_SH" "$WORK/probe/probe.sh" a b 2>&1)"
expect "bash started as sh: POSIX mode goes off, and children get the bash on PATH outside System32" \
  "0:$AS_SH|a b|bash|$WORK/good/bash" "$?:$out"
out="$(cd "$WORK/outside" && PATH="$SYS32:$WORK/tools" "$AS_SH" "$WORK/probe/probe.sh" a b 2>&1)"
expect "bash started as sh, no bash outside System32: it goes on with POSIX mode off" \
  "0:$AS_SH|a b|bash|" "$?:$out"

# run_child <PATH>: checks_bash_run from a bash started as sh; the child's
# "<mode>|<BASH>|<args>".
run_child() {
  (cd "$WORK/outside" && PATH="$1" "$AS_SH" -c '. "$1" && checks_bash_run "$2" c d' x \
    "$WORK/probe/check-lib.sh" "$WORK/child.sh" 2>&1)
}
expect "checks_bash_run starts the child under the bash on PATH outside System32" \
  "bash|$WORK/good/bash|c d" "$(run_child "$SYS32:$WORK/good")"
expect "checks_bash_run with no bash outside System32: the child turns POSIX mode off" \
  "bash|$AS_SH|c d" "$(run_child "$SYS32:$WORK/tools")"

if ! DASH="$(command -v dash)"; then
  echo "SKIP: dash not on PATH -- the cases that run entries under a sh other than bash are skipped"
  echo "sh-entries: $PASS passed, $FAIL failed"
  ((FAIL == 0))
  exit
fi

# Each entry under dash, outside any repository: its sh header sources the
# check lib, which reruns it under bash, and checks_init finds no repository.
for manifest in "$TOP"/plugins/*/git-hooks/entries.json; do
  dir="${manifest%/entries.json}"
  while IFS= read -r script; do
    out="$(cd "$WORK/outside" && "$DASH" "$dir/$script" --worktree 2>&1)"
    expect "dash runs ${dir#"$TOP"/}/$script outside a repository" "0:" "$?:$out"
  done < <(entry_scripts "$manifest")
done

out="$(cd "$WORK/outside" && PATH="$SYS32:$WORK/good" "$DASH" "$WORK/probe/probe.sh" a b 2>&1)"
expect "under dash, the probe reruns under the first bash on PATH outside System32" \
  "0:$WORK/good/bash|a b|bash|$WORK/good/bash" "$?:$out"

# probe_run <PATH> [VAR=value...]: the probe under dash; sets RUN_EXIT, RUN_OUT
# and RUN_ERR.
probe_run() {
  local path="$1"
  shift
  RUN_OUT="$(cd "$WORK/outside" && env "PATH=$path" "$@" "$DASH" "$WORK/probe/probe.sh" 2>"$WORK/err")"
  RUN_EXIT=$?
  RUN_ERR="$(cat "$WORK/err")"
}
has_err() { grep -q -- "$1" <<<"$RUN_ERR" && echo yes || echo no; } # <text> -> yes|no
probe_run "$SYS32:$WORK/tools"
expect "no bash outside System32, a person: a notice, exit 0, and System32's bash never runs" "0||yes" \
  "$RUN_EXIT|$RUN_OUT|$(has_err '^NOTICE: bash missing')"
probe_run "$SYS32:$WORK/tools" CLAUDECODE=1
expect "no bash outside System32, an agent: FAIL with the skip line, exit 1" "1||yes|yes" \
  "$RUN_EXIT|$RUN_OUT|$(has_err '^FAIL: bash missing')|$(has_err 'checks.skipmissing=bash')"
probe_run "$SYS32:$WORK/tools" CLAUDECODE=1 GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=checks.skipmissing "GIT_CONFIG_VALUE_0=jq, bash"
expect "checks.skipmissing names bash: SKIPPED, exit 0" "0||yes" \
  "$RUN_EXIT|$RUN_OUT|$(has_err '^SKIPPED: bash (missing)')"

# A `bash` on PATH that is not bash (dash under that name) is rerun once, then
# counts as missing; timeout bounds the run should the guard ever fail.
if TIMEOUT="$(command -v timeout)"; then
  mkdir -p "$WORK/notbash"
  ln -s "$DASH" "$WORK/notbash/bash"
  RUN_OUT="$(cd "$WORK/outside" && env "PATH=$WORK/notbash:$WORK/tools" "$TIMEOUT" 20 "$DASH" "$WORK/probe/probe.sh" 2>"$WORK/err")"
  RUN_EXIT=$?
  RUN_ERR="$(cat "$WORK/err")"
  expect "a bash that is not bash is rerun once, then bash counts as missing" "0||yes" \
    "$RUN_EXIT|$RUN_OUT|$(has_err '^NOTICE: bash missing')"
else
  echo "SKIP: timeout not on PATH -- the rerun-once case is skipped"
fi

echo "sh-entries: $PASS passed, $FAIL failed"
((FAIL == 0))
