#!/usr/bin/env bash
set -uo pipefail
unset RUNNER_TEMP
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT_SRC="$SCRIPT_DIR/check-upstream-drift.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh" || exit 2

f=""

PIN=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
NEW=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
B1=1111111111111111111111111111111111111111
B2=2222222222222222222222222222222222222222
B3=3333333333333333333333333333333333333333
B4=4444444444444444444444444444444444444444
B5=5555555555555555555555555555555555555555
PAGE=docs/upstream/widgets.md
MARKER="**Last audited upstream state:** \`acme/widgets@$PIN\` under \`skills/\` (widgets 1.0)"
PIN_TREE=("$B1 README.md" "$B2 skills/alpha/SKILL.md" "$B3 skills/beta/SKILL.md")

MIRRORS=()
cleanup_mirrors() {
  local d
  for d in ${MIRRORS[@]+"${MIRRORS[@]}"}; do
    [[ -n "$d" && "$d" != / ]] && rm -rf "$d"
  done
}
trap cleanup_mirrors EXIT

NO_PATH=""
path_without() {
  local dir i
  local -a parts=()
  dir="$(mktemp -d)" || return 2
  MIRRORS+=("$dir")
  IFS=':' read -r -a parts <<<"$PATH"
  for ((i = ${#parts[@]} - 1; i >= 0; i--)); do
    [[ -d "${parts[i]}" ]] && ln -sf "${parts[i]}"/* "$dir"/ 2>/dev/null
  done
  rm -f "$dir/$1"
  NO_PATH="$dir"
}

page_lines() {
  printf '# Widgets\n\n'
  printf '%s\n\n' "${1:-$MARKER}"
  printf '| Unit | Outcome |\n|---|---|\n'
  printf '| [alpha](https://github.com/acme/widgets/tree/%s/skills/alpha) | adopted |\n' "$PIN"
  printf '| [other](https://github.com/elsewhere/thing/tree/%s/skills/alpha) | rejected |\n' "$PIN"
  printf '\n## Map\n\n'
  printf -- '- [beta](https://github.com/acme/widgets/tree/%s/skills/beta)\n' "$PIN"
}

new_root() {
  fixture_tree::build f --sut "$SUT_SRC" --label upstream-drift || return 2
  mkdir -p "$f/docs/upstream" "$f/fx/acme__widgets"
}

tree_file() {
  local sha="$1"
  shift
  printf '%s\n' "$@" >"$f/fx/acme__widgets/$sha.tree"
}

set_head() { printf '%s\n' "$1" >"$f/fx/acme__widgets/HEAD"; }

setup() {
  new_root || return 2
  page_lines >"$f/$PAGE"
  tree_file "$PIN" "${PIN_TREE[@]}"
  if (($# == 0)); then
    set_head "$PIN"
  else
    set_head "$NEW"
    tree_file "$NEW" "$@"
  fi
}

RC=0
OUT=""
ERR=""

run() {
  local o e
  o="$(mktemp)" || return 2
  e="$(mktemp)" || return 2
  (cd "$f" && UPSTREAM_DRIFT_FIXTURE_DIR="$f/fx" bash scripts/check-upstream-drift.sh "$@") >"$o" 2>"$e"
  RC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
  rm -f "$o" "$e"
}

run_env() {
  local o e
  local -a envs=()
  while (($# > 0)) && [[ "$1" != -- ]]; do
    envs+=("$1")
    shift
  done
  shift
  o="$(mktemp)" || return 2
  e="$(mktemp)" || return 2
  (cd "$f" && env -u UPSTREAM_DRIFT_FIXTURE_DIR "${envs[@]}" bash scripts/check-upstream-drift.sh "$@") >"$o" 2>"$e"
  RC=$?
  OUT="$(cat "$o")"
  ERR="$(cat "$e")"
  rm -f "$o" "$e"
}

state() { printf '(rc=%s stdout=%q stderr=%q)' "$RC" "$OUT" "$ERR"; }

want_rc() {
  if ((RC == $2)); then ok "$1: exit $2"; else fail "$1: wanted exit $2 $(state)"; fi
}
want_out() {
  if [[ "$OUT" == *"$2"* ]]; then ok "$1: stdout has '$2'"; else fail "$1: stdout lacks '$2' $(state)"; fi
}
want_err() {
  if [[ "$ERR" == *"$2"* ]]; then ok "$1: stderr has '$2'"; else fail "$1: stderr lacks '$2' $(state)"; fi
}
want_out_line() {
  if grep -qxF -- "$2" <<<"$OUT"; then ok "$1: stdout line '$2'"; else fail "$1: no stdout line '$2' $(state)"; fi
}
no_out() {
  if [[ -z "$OUT" ]]; then ok "$1: nothing on stdout"; else fail "$1: wanted empty stdout $(state)"; fi
}
no_err() {
  if [[ -z "$ERR" ]]; then ok "$1: nothing on stderr"; else fail "$1: wanted empty stderr $(state)"; fi
}
out_lacks() {
  if [[ "$OUT" != *"$2"* ]]; then ok "$1: stdout lacks '$2'"; else fail "$1: stdout carries '$2' $(state)"; fi
}

setup
run --help
want_rc "help" 0
want_out "help" "usage:"
run --bogus
want_rc "unknown argument" 2
no_out "unknown argument"
run --report --links
want_rc "two modes" 2
no_out "two modes"

setup
run
want_rc "clean" 0
want_out_line "clean" "upstream records: 1 pages, no drift"
no_err "clean"

setup "$B1 README.md" "$B4 skills/alpha/SKILL.md" "$B3 skills/beta/SKILL.md"
run
want_rc "modified row file" 1
want_err "modified row file" "$PAGE:7: acme/widgets M skills/alpha/SKILL.md"
out_lacks "modified row file" "skills/alpha/SKILL.md"

setup "${PIN_TREE[@]}" "$B4 skills/alpha/extra.md"
run
want_rc "added row file" 1
want_err "added row file" "$PAGE:7: acme/widgets A skills/alpha/extra.md"
if [[ "$ERR" != *"new unit"* ]]; then ok "added row file: a covered file is not a new unit"; else fail "added row file: reported a new unit $(state)"; fi

setup "$B1 README.md" "$B3 skills/beta/SKILL.md"
run
want_rc "deleted row file" 1
want_err "deleted row file" "$PAGE:7: acme/widgets D skills/alpha/SKILL.md"

setup
mkdir -p "$f/fx/elsewhere__thing"
run
want_rc "other repository link ignored" 0

setup "$B1 README.md" "$B2 skills/alpha/SKILL.md" "$B4 skills/beta/SKILL.md"
run
want_rc "modified map unit" 0
no_err "modified map unit"

setup "$B1 README.md" "$B2 skills/alpha/SKILL.md"
run
want_rc "removed map unit" 1
want_err "removed map unit" "$PAGE:12: acme/widgets removed unit skills/beta"

setup "${PIN_TREE[@]}" "$B4 skills/gamma/SKILL.md"
run
want_rc "new unit" 1
want_err "new unit" "$PAGE: acme/widgets new unit skills/gamma/SKILL.md"

setup "${PIN_TREE[@]}" "$B4 docs/notes.md"
run
want_rc "added outside scope" 0
no_err "added outside scope"

setup "$B1 README.md" "$B4 skills/alpha/SKILL.md" "$B5 skills/gamma/SKILL.md"
run --report
want_rc "report drift" 1
want_out_line "report drift" "page repo=acme/widgets pin=aaaaaaaaaaaa head=bbbbbbbbbbbb status=drift path=$PAGE"
want_out_line "report drift" "row line=7 status=M path=skills/alpha/SKILL.md"
want_out_line "report drift" "new-unit path=skills/gamma/SKILL.md"
want_out_line "report drift" "removed-unit path=skills/beta"

setup
run --report
want_rc "report clean" 0
want_out_line "report clean" "page repo=acme/widgets pin=aaaaaaaaaaaa head=aaaaaaaaaaaa status=clean path=$PAGE"
want_out_line "report clean" "row line=7 status=unchanged path=skills/alpha"

setup "${PIN_TREE[@]}" "$B4 skills/alpha/a b=c|d.md"
run --report
want_rc "path with space, = and |" 1
want_out_line "path with space, = and |" "row line=7 status=A path=skills/alpha/a b=c|d.md"
want_out_line "path with space, = and |" "page repo=acme/widgets pin=aaaaaaaaaaaa head=bbbbbbbbbbbb status=drift path=$PAGE"

for ctl in tab cr newline; do
  case "$ctl" in
  tab) setup "${PIN_TREE[@]}" "$B4 skills/alpha/a"$'\t'"b.md" ;;
  cr) setup "${PIN_TREE[@]}" "$B4 skills/alpha/a"$'\r'"b.md" ;;
  newline) setup "${PIN_TREE[@]}" "$B4 skills/alpha/evil" "name.md" ;;
  *) fail "no fixture for $ctl" ;;
  esac
  run --report
  want_rc "path with $ctl" 2
  no_out "path with $ctl"
done

new_root
{
  printf '# Widgets\n\n'
  # shellcheck disable=SC2016  # literal marker backticks
  printf '**Last audited upstream state:** `acme/widgets@%s` (no scope)\n\n' "$PIN"
  printf -- '- [readme](https://github.com/acme/widgets/blob/%s/README.md)\n' "$PIN"
} >"$f/$PAGE"
tree_file "$PIN" "${PIN_TREE[@]}"
set_head "$NEW"
tree_file "$NEW" "$B4 README.md" "$B2 skills/alpha/SKILL.md" "$B3 skills/beta/SKILL.md" "$B5 skills/gamma/SKILL.md"
run
want_rc "blob link drift, no scope" 1
want_err "blob link drift, no scope" "$PAGE:5: acme/widgets M README.md"
if [[ "$ERR" != *"new unit"* ]]; then ok "no scope: no new units"; else fail "no scope: reported a new unit $(state)"; fi

new_root
# shellcheck disable=SC2016  # literal marker backticks
printf '# Widgets\n\n**Last audited upstream state:** `acme/widgets@%s`\n' "$PIN" >"$f/$PAGE"
tree_file "$PIN" "${PIN_TREE[@]}"
set_head "$NEW"
tree_file "$NEW" "$B4 README.md"
run --report
want_rc "untracked" 0
want_out_line "untracked" "page repo=acme/widgets pin=aaaaaaaaaaaa head=bbbbbbbbbbbb status=untracked path=$PAGE"

new_root
# shellcheck disable=SC2016  # literal marker backticks
printf '**Last audited upstream state:** `main@3c26291` (upstream HEAD)\n' >"$f/docs/upstream/a.md"
# shellcheck disable=SC2016  # literal marker backticks
printf '**Last audited upstream state:** changelog through `2.1.263`\n' >"$f/docs/upstream/b.md"
run
want_rc "non-git markers skipped" 0
want_out_line "non-git markers skipped" "upstream records: 0 pages, no drift"
run --page docs/upstream/a.md
want_rc "--page without the git form" 2
no_out "--page without the git form"

for bad in \
  "**Last audited upstream state:** \`acme/widgets@aaaaaaa\` (short sha)" \
  "**Last audited upstream state:** \`acme/widgets@$PIN\` under skills/" \
  "**Last audited upstream state:** \`acme/widgets@$PIN\` under \`skills\`"; do
  new_root
  page_lines "$bad" >"$f/$PAGE"
  tree_file "$PIN" "${PIN_TREE[@]}"
  set_head "$PIN"
  run
  want_rc "near-miss marker: $bad" 2
  no_out "near-miss marker: $bad"
done

for bad in "  $MARKER" "> $MARKER"; do
  new_root
  page_lines "$bad" >"$f/$PAGE"
  tree_file "$PIN" "${PIN_TREE[@]}"
  set_head "$PIN"
  run
  want_rc "near-miss marker: $bad" 2
  no_out "near-miss marker: $bad"
done

new_root
page_lines "**Last audited upstream state:** \`acme/widgets@$PIN\` under \`skilz/\`" >"$f/$PAGE"
tree_file "$PIN" "${PIN_TREE[@]}"
set_head "$NEW"
tree_file "$NEW" "${PIN_TREE[@]}" "$B4 skilz/new/SKILL.md"
for mode in "" --report --links; do
  run ${mode:+"$mode"}
  want_rc "scope absent at pin ${mode:-default}" 2
  no_out "scope absent at pin ${mode:-default}"
  want_err "scope absent at pin ${mode:-default}" "$PAGE: scope skilz/"
done

setup "$B1 README.md"
run
want_rc "scope deleted at head" 1
want_err "scope deleted at head" "$PAGE:7: acme/widgets D skills/alpha/SKILL.md"
want_err "scope deleted at head" "$PAGE:12: acme/widgets removed unit skills/beta"

setup
run --page "$PAGE"
want_rc "--page" 0
want_out_line "--page" "upstream records: 1 pages, no drift"

setup
run --links
want_rc "links ok" 0
want_out "links ok" "2 links ok"
no_err "links ok"

new_root
{
  page_lines
  printf -- '- [main](https://github.com/acme/widgets/tree/main/skills/alpha)\n'
  printf -- '- [ghost](https://github.com/acme/widgets/tree/%s/skills/ghost)\n' "$PIN"
  printf -- '- [root](https://github.com/acme/widgets/tree/%s)\n' "$PIN"
  printf -- '- [readme](https://github.com/acme/widgets/blob/%s/README.md)\n' "$PIN"
} >"$f/$PAGE"
tree_file "$PIN" "${PIN_TREE[@]}"
set_head "$PIN"
run --links
want_rc "bad links" 1
want_err "bad links" "$PAGE:13: wrong-sha"
want_err "bad links" "$PAGE:14: missing-at-pin"
want_err "bad links" "$PAGE:15: bad-form"
if [[ "$ERR" != *"$PAGE:16:"* ]]; then ok "bad links: blob link is ok"; else fail "bad links: blob link flagged $(state)"; fi
out_lacks "bad links" "wrong-sha"

setup
tree_file "$PIN" "${PIN_TREE[@]}" truncated
run
want_rc "truncated tree" 2
no_out "truncated tree"
want_err "truncated tree" "was truncated"

setup
set_head "$NEW"
run
want_rc "missing fixture tree" 2
no_out "missing fixture tree"

setup
rm -f "$f/fx/acme__widgets/HEAD"
run
want_rc "missing fixture HEAD" 2
no_out "missing fixture HEAD"

# The backticks below are literal text.
# shellcheck disable=SC2016
ALLOW_BODY='{"message":"Although you appear to have the correct authorization credentials, the `acme` organization has an IP allow list enabled.","status":"403"}'
GPIN="" GHEAD=""
ugit() { git -c user.name=t -c user.email=t@example.invalid -C "$f/src" "$@"; }
stub_api() {
  new_root || return 2
  mkdir -p "$f/bin" "$f/tmp" "$f/src/skills/alpha" "$f/src/skills/gamma" "$f/remote/acme"
  git init -q -b main "$f/src" || return 2
  echo one >"$f/src/skills/alpha/SKILL.md"
  ugit add skills/alpha/SKILL.md && ugit commit -qm one || return 2
  GPIN="$(ugit rev-parse HEAD)"
  echo two >"$f/src/skills/alpha/SKILL.md"
  echo new >"$f/src/skills/gamma/SKILL.md"
  ugit add -A && ugit commit -qm two || return 2
  GHEAD="$(ugit rev-parse HEAD)"
  git clone -q --bare "$f/src" "$f/remote/acme/widgets.git" || return 2
  {
    printf '# Widgets\n\n'
    # shellcheck disable=SC2016
    printf '**Last audited upstream state:** `acme/widgets@%s`\n' "$GPIN"
  } >"$f/$PAGE"
  printf '%s\n' "${1:-$ALLOW_BODY}" >"$f/gh.body"
  cat >"$f/bin/gh" <<EOS
#!/usr/bin/env bash
echo "\$*" >>"$f/gh.log"
cat "$f/gh.body"
exit 1
EOS
  chmod +x "$f/bin/gh"
}

scoped_page() {
  {
    printf '# Widgets\n\n'
    # shellcheck disable=SC2016
    printf '**Last audited upstream state:** `acme/widgets@%s` under `skills/`\n\n' "$GPIN"
    printf '| [alpha](https://github.com/acme/widgets/tree/%s/skills/alpha) | adopted |\n' "$GPIN"
  } >"$f/$PAGE"
}

tmp_clean() {
  if [[ -z "$(ls -A "$f/tmp")" ]]; then ok "$1: temporary directory removed"; else fail "$1: left $(ls -A "$f/tmp")"; fi
}

no_gh() {
  if [[ ! -s "$f/gh.log" ]]; then pass "$1: gh never called"; else bad "$1: gh never called" "$(cat "$f/gh.log")"; fi
}

stub_api
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "public upstream, git read works" 0
want_out_line "public upstream, git read works" "page repo=acme/widgets pin=${GPIN:0:12} head=${GHEAD:0:12} status=untracked path=$PAGE"
no_err "public upstream, git read works"
no_gh "public upstream, git read works"
tmp_clean "public upstream, git read works"

scoped_page
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "public upstream, git read finds drift" 1
no_out "public upstream, git read finds drift"
want_err "public upstream, git read finds drift" "$PAGE:5: acme/widgets M skills/alpha/SKILL.md"
want_err "public upstream, git read finds drift" "$PAGE: acme/widgets new unit skills/gamma/SKILL.md"
no_gh "public upstream, git read finds drift"
tmp_clean "public upstream, git read finds drift"
GIT_ERR="$ERR"

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --links
want_rc "public upstream, git read checks links" 0
want_out "public upstream, git read checks links" "1 links ok"
no_gh "public upstream, git read checks links"

rest_gh() {
  mkdir -p "$f/restbin"
  cat >"$f/restbin/gh" <<EOS
#!/usr/bin/env bash
echo "\$*" >>"$f/gh.log"
g() { git -C "$f/remote/acme/widgets.git" "\$@"; }
fail() { printf '{"message":"%s","status":"%s"}\\n' "\$1" "\$2"; exit 1; }
u="\$2"
case "\$u" in
*/commits/HEAD) printf '{"sha":"%s"}\\n' "\$(g rev-parse HEAD)" ;;
*/git/commits/*) g cat-file -e "\${u##*/}^{commit}" 2>/dev/null || fail "Not Found" 404; printf '{"sha":"%s"}\\n' "\${u##*/}" ;;
*/git/trees/*)
  u="\${u##*/git/trees/}" rec=()
  [[ "\$u" == *'?recursive=1' ]] && rec=(-r -t) u="\${u%\\?recursive=1}"
  obj="\$u^{tree}"
  [[ "\$u" == *:* ]] && obj="\$u"
  case "\$(g cat-file -t "\$obj" 2>/dev/null || g ls-tree "\${u%%:*}" -- "\${u#*:}" | cut -d' ' -f2)" in
  tree) ;;
  blob | commit) fail "not a tree" 422 ;;
  *) fail "Not Found" 404 ;;
  esac
  g ls-tree "\${rec[@]}" -z "\$obj" | tr '\\0' '\\n' |
    jq -Rs '{truncated: false, tree: [split("\\n")[] | select(. != "") |
      capture("^(?<mode>[0-9]+) (?<type>[a-z]+) (?<sha>[0-9a-f]+)\\t(?<path>.*)\$")]}'
  ;;
*) fail "Not Found" 404 ;;
esac
EOS
  chmod +x "$f/restbin/gh"
}
rest_gh
: >"$f/gh.log"
run_env PATH="$f/restbin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/nowhere" --
want_rc "private upstream, REST read finds drift" 1
if [[ "$ERR" == "$GIT_ERR" ]]; then
  pass "private upstream: REST findings match the git read's"
else
  bad "private upstream: REST findings match the git read's" "git=$(printf '%q' "$GIT_ERR") rest=$(printf '%q' "$ERR")"
fi
if grep -qxF "api repos/acme/widgets/git/trees/$GHEAD:skills?recursive=1" "$f/gh.log"; then
  pass "private upstream: trees read over REST"
else
  bad "private upstream: trees read over REST" "$(cat "$f/gh.log")"
fi
tmp_clean "private upstream, REST read finds drift"

REAL_GIT=$(command -v git)
stub_api
mkdir -p "$f/fail-first-fetch"
cat >"$f/fail-first-fetch/git" <<EOS
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\$arg" == fetch && ! -e "$f/fetched-once" ]]; then
    : >"$f/fetched-once"
    echo "fatal: unable to access remote" >&2
    exit 128
  fi
done
exec "$REAL_GIT" "\$@"
EOS
chmod +x "$f/fail-first-fetch/git"
run_env PATH="$f/fail-first-fetch:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "git fails, allow list refuses REST, git retry works" 0
want_out_line "git fails, allow list refuses REST, git retry works" "page repo=acme/widgets pin=${GPIN:0:12} head=${GHEAD:0:12} status=untracked path=$PAGE"
want_err "git fails, allow list refuses REST, git retry works" "acme: IP allow list refused the token; reading anonymously over git"
if [[ "$(wc -l <"$f/gh.log")" -eq 1 ]]; then pass "allow list: later calls skip gh"; else bad "allow list: later calls skip gh" "$(cat "$f/gh.log")"; fi
tmp_clean "git fails, allow list refuses REST, git retry works"

log_git() {
  mkdir -p "$f/gitbin"
  : >"$f/git.log"
  cat >"$f/gitbin/git" <<EOS
#!/usr/bin/env bash
echo "GIT_NO_LAZY_FETCH=\${GIT_NO_LAZY_FETCH:-} \$*" >>"$f/git.log"
exec "$REAL_GIT" "\$@"
EOS
  chmod +x "$f/gitbin/git"
}
scoped_page
log_git
run_env PATH="$f/gitbin:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "git reads fetch each commit once at depth 1" 1
fetches=$(grep -c ' fetch ' "$f/git.log")
deep=$(grep ' fetch ' "$f/git.log" | grep -cv -- '--depth=1')
if [[ "$fetches" -eq 2 && "$deep" -eq 0 ]]; then
  pass "git read: two depth-1 fetches, pin and HEAD"
else
  bad "git read: two depth-1 fetches, pin and HEAD" "$(cat "$f/git.log")"
fi
if ! grep -q -e cat-file -e '^GIT_NO_LAZY_FETCH= ' "$f/git.log"; then
  pass "git read: no existence probe, lazy fetch off on every call"
else
  bad "git read: no existence probe, lazy fetch off on every call" "$(cat "$f/git.log")"
fi

stub_api
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/nowhere" -- --report
want_rc "allow list, git read fails, --report" 0
want_out_line "allow list, git read fails, --report" "page repo=acme/widgets pin=${GPIN:0:12} head=unknown status=unreachable path=$PAGE"
want_err "allow list, git read fails, --report" "$PAGE: acme/widgets refused the token (IP allow list) and an anonymous git read failed (git: "
tmp_clean "allow list, git read fails, --report"

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/nowhere" --
want_rc "allow list, git read fails, default mode" 2
no_out "allow list, git read fails, default mode"

stub_api
mkdir -p "$f/fail-ls-remote"
cat >"$f/fail-ls-remote/git" <<EOS
#!/usr/bin/env bash
for arg in "\$@"; do
  if [[ "\$arg" == "ls-remote" ]]; then
    echo "fatal: unable to access remote" >&2
    exit 128
  fi
done
exec "$REAL_GIT" "\$@"
EOS
chmod +x "$f/fail-ls-remote/git"
run_env PATH="$f/fail-ls-remote:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "allow list, ls-remote fails after pin fetch, --report" 0
want_out_line "allow list, ls-remote fails after pin fetch, --report" "page repo=acme/widgets pin=${GPIN:0:12} head=unknown status=unreachable path=$PAGE"
want_err "allow list, ls-remote fails after pin fetch, --report" "$PAGE: acme/widgets refused the token (IP allow list) and an anonymous git read failed (git: fatal: unable to access remote); not checked"
tmp_clean "allow list, ls-remote fails after pin fetch, --report"

run_env PATH="$f/fail-ls-remote:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "allow list, ls-remote fails after pin fetch, default mode" 2
no_out "allow list, ls-remote fails after pin fetch, default mode"

stub_api
scoped_page
mkdir -p "$f/fail-head-fetch"
cat >"$f/fail-head-fetch/git" <<EOS
#!/usr/bin/env bash
is_fetch=0
has_head=0
for arg in "\$@"; do
  [[ "\$arg" == "fetch" ]] && is_fetch=1
  [[ "\$arg" == "$GHEAD" ]] && has_head=1
done
if ((is_fetch && has_head)); then
  echo "fatal: remote hung up unexpectedly" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
EOS
chmod +x "$f/fail-head-fetch/git"
run_env PATH="$f/fail-head-fetch:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "allow list, HEAD fetch fails after ls-remote, --report" 0
want_out_line "allow list, HEAD fetch fails after ls-remote, --report" "page repo=acme/widgets pin=${GPIN:0:12} head=unknown status=unreachable path=$PAGE"
want_err "allow list, HEAD fetch fails after ls-remote, --report" "$PAGE: acme/widgets refused the token (IP allow list) and an anonymous git read failed (git: fatal: remote hung up unexpectedly); not checked"
tmp_clean "allow list, HEAD fetch fails after ls-remote, --report"

run_env PATH="$f/fail-head-fetch:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "allow list, HEAD fetch fails after ls-remote, default mode" 2
no_out "allow list, HEAD fetch fails after ls-remote, default mode"

{
  printf '# Widgets\n\n'
  # shellcheck disable=SC2016
  printf '**Last audited upstream state:** `acme/widgets@%s`\n' "$PIN"
} >"$f/$PAGE"
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "allow list, pin missing upstream" 2
no_out "allow list, pin missing upstream"
want_err "allow list, pin missing upstream" "is not a commit upstream"

stub_api || exit 2
scoped_page
control_path=$'skills/alpha/control\tpath'
echo malformed >"$f/src/$control_path"
ugit add -- "$control_path" && ugit commit -qm control || exit 2
control_head=$(ugit rev-parse HEAD) || exit 2
mkdir -p "$f/control-remote/acme"
git clone -q --bare "$f/src" "$f/control-remote/acme/widgets.git" || exit 2

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/control-remote" -- --report
want_rc "git read, control in tree path, --report" 2
no_out "git read, control in tree path, --report"
want_err "git read, control in tree path, --report" "acme/widgets@${control_head:0:12}: a tree path holds a control character"
tmp_clean "git read, control in tree path, --report"

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/control-remote" --
want_rc "git read, control in tree path, default mode" 2
no_out "git read, control in tree path, default mode"
want_err "git read, control in tree path, default mode" "acme/widgets@${control_head:0:12}: a tree path holds a control character"
tmp_clean "git read, control in tree path, default mode"

outside_path=$'control\tpath'
ugit rm -q -- "$control_path" || exit 2
echo malformed >"$f/src/$outside_path"
ugit add -- "$outside_path" && ugit commit -qm outside || exit 2
rm -rf "${f:?}/control-remote"
mkdir -p "$f/control-remote/acme"
git clone -q --bare "$f/src" "$f/control-remote/acme/widgets.git" || exit 2
outside_head=$(ugit rev-parse HEAD) || exit 2
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/control-remote" --
want_rc "git read, control outside the read path" 2
no_out "git read, control outside the read path"
want_err "git read, control outside the read path" "acme/widgets@${outside_head:0:12}: a tree path holds a control character"

stub_api '{"message":"Not Found","status":"404"}'
log_git
run_env PATH="$f/gitbin:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/nowhere" -- --report
want_rc "private upstream, other gh failure does not retry" 2
no_out "private upstream, other gh failure does not retry"
want_err "private upstream, other gh failure does not retry" "Not Found (HTTP 404)"
if [[ "$ERR" != *"over git"* ]]; then pass "other gh failure: no git retry"; else bad "other gh failure: no git retry" "$ERR"; fi
if [[ "$(grep -c ' fetch ' "$f/git.log")" -eq 1 ]] && ! grep -q ' ls-remote ' "$f/git.log"; then
  pass "other gh failure: one git fetch before REST, no ls-remote"
else
  bad "other gh failure: one git fetch before REST, no ls-remote" "$(cat "$f/git.log")"
fi

fail_git_on() {
  mkdir -p "$f/failgit"
  cat >"$f/failgit/git" <<EOS
#!/usr/bin/env bash
hit=0 sub=0
for arg in "\$@"; do
  [[ "\$arg" == "$1" ]] && sub=1
  [[ "\$arg" == "$2" ]] && hit=1
done
if ((sub && hit)); then
  echo "fatal: remote hung up unexpectedly" >&2
  exit 128
fi
exec "$REAL_GIT" "\$@"
EOS
  chmod +x "$f/failgit/git"
}

midpage() {
  stub_api
  scoped_page
  rest_gh
  fail_git_on "$1" "${2/@head/$GHEAD}"
  run_env PATH="$f/failgit:$f/restbin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
  want_rc "$3" 1
  if [[ "$ERR" == "$GIT_ERR" ]]; then pass "$3: findings match the git read's"; else bad "$3: findings match the git read's" "git=$(printf '%q' "$GIT_ERR") got=$(printf '%q' "$ERR")"; fi
  run_env PATH="$f/failgit:$f/restbin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
  out_lacks "$3" "status=unreachable"
  tmp_clean "$3"
}
midpage ls-remote ls-remote "git HEAD read fails, REST HEAD read succeeds"
midpage fetch @head "git HEAD tree fetch fails, REST tree read succeeds"
if grep -q "git/trees/$GHEAD:skills" "$f/gh.log"; then
  pass "git HEAD tree fetch fails: the HEAD tree is read over REST"
else
  bad "git HEAD tree fetch fails: the HEAD tree is read over REST" "$(cat "$f/gh.log")"
fi

shape() {
  local name="$1" want="$2" want_rest="$3" scope="$4" link="$5" mode="$6" p
  shift 6
  new_root || return 2
  mkdir -p "$f/bin" "$f/tmp" "$f/remote/acme"
  git init -q -b main "$f/src" || return 2
  for p in "$@"; do
    [[ "$p" != */* ]] || mkdir -p "$f/src/${p%/*}"
    echo x >"$f/src/$p" || return 2
  done
  ugit add -A && ugit commit -qm one || return 2
  GPIN="$(ugit rev-parse HEAD)"
  git clone -q --bare "$f/src" "$f/remote/acme/widgets.git" || return 2
  {
    printf '# Widgets\n\n'
    # shellcheck disable=SC2016
    printf '**Last audited upstream state:** `acme/widgets@%s`%s\n\n' "$GPIN" "${scope:+ under \`$scope/\`}"
    printf -- '- [row](https://github.com/acme/widgets/%s)\n' "${link/\//\/$GPIN/}"
  } >"$f/$PAGE"
  printf '#!/usr/bin/env bash\necho "$*" >>"%s/gh.log"\nexit 1\n' "$f" >"$f/bin/gh"
  chmod +x "$f/bin/gh"
  rest_gh
  run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- ${mode:+"$mode"}
  local grc=$RC gout=$OUT gerr=$ERR
  want_rc "$name, git read" "$want"
  no_gh "$name, git read"
  run_env PATH="$f/restbin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/nowhere" -- ${mode:+"$mode"}
  want_rc "$name, REST read" "$want_rest"
  if ((want == 2)); then
    if [[ -z "$gout" && "$gerr" == *"acme/widgets@${GPIN:0:12}: a tree path holds a control character"* ]]; then
      pass "$name: git refuses on any control character in the tree"
    else
      bad "$name: git refuses on any control character in the tree" "git=$(printf '%q' "$grc/$gout/$gerr")"
    fi
    ((want_rest != 2)) || want_err "$name, REST read" "a tree path holds a control character"
  elif [[ "$RC/$OUT/$ERR" == "$grc/$gout/$gerr" ]]; then
    pass "$name: git and REST give the same exit, stdout and stderr"
  else
    bad "$name: git and REST give the same exit, stdout and stderr" "git=$(printf '%q' "$grc/$gout/$gerr") rest=$(printf '%q' "$RC/$OUT/$ERR")"
  fi
}
TAB=$'\t'
shape "folder row" 0 0 "" tree/skills/alpha --report skills/alpha/SKILL.md README.md
shape "file row" 0 0 "" blob/skills/alpha/SKILL.md --report skills/alpha/SKILL.md skills/alpha/other.md
shape "root file row" 0 0 "" blob/README.md --report README.md skills/alpha/SKILL.md
shape "scoped page" 0 0 skills tree/skills/alpha --report skills/alpha/SKILL.md skills/beta/SKILL.md
shape "missing row path" 1 1 "" tree/skills/ghost --links skills/alpha/SKILL.md
shape "folder row, control under it" 2 2 "" tree/skills/alpha "" skills/alpha/SKILL.md "skills/alpha/a${TAB}b"
shape "folder row, control outside it" 2 0 "" tree/skills/alpha --report skills/alpha/SKILL.md "c${TAB}d"
shape "file row, control in a sibling name" 2 2 "" blob/skills/alpha/SKILL.md "" skills/alpha/SKILL.md "skills/alpha/a${TAB}b"
shape "file row, control below a sibling folder" 2 0 "" blob/skills/alpha/SKILL.md --report skills/alpha/SKILL.md "skills/alpha/sub/a${TAB}b"
shape "file row, control in a sibling folder name" 2 2 "" blob/skills/alpha/SKILL.md "" skills/alpha/SKILL.md "skills/alpha/s${TAB}b/x"
shape "root file row, control below a top folder" 2 0 "" blob/README.md --report README.md "skills/a${TAB}b"
shape "root file row, control in a top name" 2 2 "" blob/README.md "" README.md "c${TAB}d"
shape "scoped page, control elsewhere in the scope" 2 2 skills tree/skills/alpha "" skills/alpha/SKILL.md "skills/beta/a${TAB}b"
shape "scoped page, control outside the scope" 2 0 skills tree/skills/alpha --report skills/alpha/SKILL.md "c${TAB}d"

setup
path_without gh
run_env PATH="$NO_PATH" --
want_rc "no gh" 2
no_out "no gh"
want_err "no gh" "gh"

mkdir -p "$f/.github/actions/log-api-budget"
cp "$SCRIPT_DIR/../.github/actions/log-api-budget/api-budget.bash" "$f/.github/actions/log-api-budget/"
run_env PATH="$NO_PATH" RUNNER_TEMP="$f" --
want_rc "no gh on a runner, where the api-budget gh function is defined" 2
no_out "no gh on a runner, where the api-budget gh function is defined"
want_err "no gh on a runner, where the api-budget gh function is defined" "gh is required"

path_without jq
run_env PATH="$NO_PATH" UPSTREAM_DRIFT_FIXTURE_DIR="$f/fx" --
want_rc "no jq" 2
no_out "no jq"
want_err "no jq" "jq"

test_harness::report
