#!/usr/bin/env bash
# test-scope: lib/git-hooks/resolve-tool.sh
# shellcheck disable=SC2016 # commands and expected scripts are literal text
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG GIT_INDEX_FILE CLAUDECODE AI_AGENT

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RT="$HERE/resolve-tool.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export GIT_CONFIG_GLOBAL="$WORK/no-global" GIT_CONFIG_NOSYSTEM=1
export HOME="$WORK/home"
mkdir -p "$HOME"

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

BIN="$WORK/bin"
mkdir -p "$BIN"
cat >"$BIN/stubfmt" <<EOF
#!/bin/sh
for a in "\$@"; do
  printf '%s\n' "\$a" >>"$WORK/stub.log"
  case "\$a" in -*) ;; *) printf 'formatted\n' >"\$a" ;; esac
done
EOF
chmod +x "$BIN/stubfmt"
PATH="$BIN:$PATH"

RT_PLUGIN=demo
RT_IDS=demo
# shellcheck disable=SC2329  # called by name from the resolver
rt_adapter() {
  [[ -f "$3/demo.cfg" ]] || return 1
  RT_ADAPTER=demofmt RT_TOOL=stubfmt RT_BIN=stubfmt RT_DIR="$3" RT_INSTALL="install stubfmt"
  RT_DETAIL="config demo.cfg"
  case "$1" in
  format) RT_SCRIPT='stubfmt --adapter "$@"' ;;
  *) RT_SCRIPT='stubfmt --adapter-lint "$@"' ;;
  esac
}
# shellcheck disable=SC2329  # called by name from the resolver
rt_adapter_in_repo() {
  if [[ ! -f "$2/demo.cfg" ]]; then
    RT_DETAIL="no demo.cfg"
    return 1
  fi
  RT_ADAPTER=demofmt RT_TOOL=stubfmt RT_BIN=stubfmt RT_DETAIL="config demo.cfg"
}
# shellcheck source=resolve-tool.sh
. "$RT"

n=0
new_repo() {
  n=$((n + 1))
  REPO="$WORK/r$n"
  git init -q -b main "$REPO"
  printf 'seed\n' >"$REPO/seed.dm"
}
resolve() {
  rt_resolve "$1" "$2" "$REPO"
  printf '%s|%s' "$RT_SOURCE" "$RT_SCRIPT"
}

new_repo
: >"$REPO/demo.cfg"
expect "the tool's own config opts the file into the adapter" 'adapter:demofmt|stubfmt --adapter "$@"' "$(resolve seed.dm format)"
expect "lint resolves the adapter's lint command" 'adapter:demofmt|stubfmt --adapter-lint "$@"' "$(resolve seed.dm lint)"
rm "$REPO/demo.cfg"
expect "no adapter config: nothing" "none|" "$(resolve seed.dm format)"

new_repo
mkdir -p "$REPO/.claude/ecosystems" "$HOME/.claude/ecosystems"
printf '%s\n' 'globs: ["*.dm"]' 'fix-cmd: "touch record-ran <files>"' >"$REPO/.claude/ecosystems/demo.yaml"
printf '%s\n' 'fix-cmd: "touch record-ran <files>"' >"$HOME/.claude/ecosystems/demo.yaml"
expect "a record with no adapter config resolves to nothing" "none|" "$(resolve seed.dm format)"
: >"$REPO/demo.cfg"
expect "a record and an adapter config: the adapter, never the record" 'adapter:demofmt|stubfmt --adapter "$@"' "$(resolve seed.dm format)"
rt_resolve seed.dm format "$REPO"
(cd "$REPO" && rt_run seed.dm)
expect "running the resolved command ran no record command" "no" "$([[ -e "$REPO/record-ran" ]] && echo yes || echo no)"
expect "rt_print names the adapter and says hooks do not run the record" "demo	format	adapter:demofmt	stubfmt	yes	config demo.cfg; the demo record is not run by hooks; /toolchain:lint and /toolchain:check run it" "$(rt_print format "$REPO")"
expect "rt_print executes nothing" "no" "$([[ -e "$REPO/record-ran" ]] && echo yes || echo no)"
rm -r "$HOME/.claude" "$REPO/.claude" "$REPO/demo.cfg"
expect "rt_print says none, and why, when nothing resolves" "demo	format	none		n/a	no demo.cfg" "$(rt_print format "$REPO")"
: >"$REPO/demo.cfg"
expect "rt_print with files gives one row per file" "demo	lint	adapter:demofmt	stubfmt	yes	config demo.cfg" "$(rt_print lint "$REPO" "$REPO/seed.dm")"
mkdir -p "$REPO/docs/conventions/ecosystems"
printf '%s\n' 'fix-cmd: "touch record-ran <files>"' >"$REPO/docs/conventions/ecosystems/demo.yaml"
expect "a record at the convention home gets the same note" "demo	format	adapter:demofmt	stubfmt	yes	config demo.cfg; the demo record is not run by hooks; /toolchain:lint and /toolchain:check run it" "$(rt_print format "$REPO")"
rm -r "$REPO/docs"

new_repo
: >"$REPO/demo.cfg"
name='$(touch marker);x.dm'
printf 'seed\n' >"$REPO/$name"
printf 'seed\n' >"$REPO/-lead.dm"
rt_resolve "$REPO/seed.dm" format "$REPO"
: >"$WORK/stub.log"
(cd "$REPO" && rt_run "$name" -lead.dm)
expect "a file name holding \$( and ; is never executed" "no" "$([[ -e "$REPO/marker" || -e "$WORK/marker" ]] && echo yes || echo no)"
expect "the tool receives the literal name, and a leading dash as ./" "--adapter
$name
./-lead.dm" "$(cat "$WORK/stub.log")"
expect "the tool ran on the crafted file" "formatted" "$(cat "$REPO/$name")"
RT__ARGMAX=20
: >"$WORK/stub.log"
(cd "$REPO" && rt_run seed.dm "$name" -lead.dm)
expect "file lists are split into chunks under the length limit, each run once" "3" "$(grep -c -- '--adapter' "$WORK/stub.log")"
RT__ARGMAX=24000

cat >"$BIN/stublint" <<EOF
#!/bin/sh
case "\$1" in
--abs) printf '%s/sub/a.dm:3:7: E1 bad\n' "$WORK/rl" ;;
--rel) printf 'a.dm:4: W2 meh\nsummary line\n' ;;
--crash) echo 'tool crashed' >&2; exit 2 ;;
--clean) exit 0 ;;
esac
exit 1
EOF
chmod +x "$BIN/stublint"
mkdir -p "$WORK/rl/sub"
RT_SCRIPT='stublint --abs "$@"' RT_DIR="$WORK/rl" RT_ROOT="$WORK/rl"
expect "an absolute path is made repo-relative and the column dropped" "sub/a.dm:3: E1 bad" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>/dev/null)"
RT_SCRIPT='stublint --rel "$@"' RT_DIR="$WORK/rl/sub"
expect "a path relative to the command's directory gains that directory; other lines drop" "sub/a.dm:4: W2 meh" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>/dev/null)"
RT_SCRIPT='stublint --crash "$@"' RT_DIR="$WORK/rl"
out="$(cd "$WORK/rl" && rt_lint sub/a.dm 2>&1)"
expect "a non-zero exit with no parsed finding fails closed and shows the output" "3|tool crashed" "$?|$(tail -1 <<<"$out")"
RT_SCRIPT='stublint --clean "$@"'
expect "a clean exit passes with no finding" "|0" "$(cd "$WORK/rl" && rt_lint sub/a.dm 2>&1; printf '|%s' "$?")"

std_case() {
  RT__STD_FOR=""
  if rt_standards_file "$1" "$2"; then printf '%s' "$RT_STANDARDS_FILE"; else printf 'none|%s' "$RT_STANDARDS_FILE"; fi
}
SR="$WORK/std-repo"
mkdir -p "$SR/docs/conventions" "$HOME/ghq/github.com/acme/standards" "$WORK/ghq2/github.com/acme/standards" "$WORK/stddir"
for d in "$HOME/ghq/github.com/acme/standards" "$WORK/ghq2/github.com/acme/standards" "$WORK/stddir"; do
  printf 'x\n' >"$d/_typos.toml"
done
expect "no source-control config: no standards file" "none|" "$(std_case "$SR" _typos.toml)"
printf 'pr_open_state: ready\n' >"$SR/docs/conventions/source-control.yaml"
expect "a config without standards_repository: no standards file" "none|" "$(std_case "$SR" _typos.toml)"
printf 'standards_repository: acme/standards # the org defaults\n' >"$SR/docs/conventions/source-control.yaml"
expect "standards_repository with no ghq.root reads ~/ghq" "$HOME/ghq/github.com/acme/standards/_typos.toml" "$(std_case "$SR" _typos.toml)"
expect "a path the checkout lacks: no standards file" "none|" "$(std_case "$SR" .shellcheckrc)"
git config --global ghq.root "$WORK/ghq2"
expect "ghq.root wins over ~/ghq" "$WORK/ghq2/github.com/acme/standards/_typos.toml" "$(std_case "$SR" _typos.toml)"
expect "STANDARDS_DIR wins over ghq.root" "$WORK/stddir/_typos.toml" "$(STANDARDS_DIR="$WORK/stddir" std_case "$SR" _typos.toml)"
expect "a relative STANDARDS_DIR resolves to an absolute path" "$WORK/stddir/_typos.toml" "$(cd "$WORK" && STANDARDS_DIR=stddir std_case "$SR" _typos.toml)"
printf "standards_repository: 'acme/standards'\n" >"$SR/docs/conventions/source-control.yaml"
expect "a single-quoted value resolves" "$WORK/ghq2/github.com/acme/standards/_typos.toml" "$(std_case "$SR" _typos.toml)"
printf 'standards_repository: "acme/standards"\r\n' >"$SR/docs/conventions/source-control.yaml"
expect "a double-quoted value with a CRLF line ending resolves" "$WORK/ghq2/github.com/acme/standards/_typos.toml" "$(std_case "$SR" _typos.toml)"
for bad in 'not-a-pair' '../standards' 'acme/../standards' '[acme/standards]'; do
  printf 'standards_repository: %s\n' "$bad" >"$SR/docs/conventions/source-control.yaml"
  expect "a malformed standards_repository '$bad' resolves nothing" "none|" "$(STANDARDS_DIR="$WORK/stddir" std_case "$SR" _typos.toml)"
done
printf 'nested:\n  standards_repository: acme/standards\n' >"$SR/docs/conventions/source-control.yaml"
expect "only a top-level standards_repository opts in" "none|" "$(std_case "$SR" _typos.toml)"
git config --global --unset ghq.root

echo "resolve-tool: $PASS passed, $FAIL failed"
((FAIL == 0))
