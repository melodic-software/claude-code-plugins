#!/usr/bin/env bash
# Black-box suite for check-upstream-drift.sh.
#
#   bash scripts/check-upstream-drift.test.sh
#
# Hermetic and cwd-independent: each case builds a throwaway tree holding a copy
# of the script, one docs/upstream page and a fixture directory read through the
# UPSTREAM_DRIFT_FIXTURE_DIR seam, so no case touches the network. Every expected
# line below is written by hand from the fixture the case builds: the SHAs, the
# paths and the page line numbers are literals of this file.
set -uo pipefail
# On a runner the script would wrap its gh calls and record into the job's
# RUNNER_TEMP; the cases here run it unwrapped.
unset RUNNER_TEMP
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SUT_SRC="$SCRIPT_DIR/check-upstream-drift.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh" || exit 2
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh" || exit 2

# The builder assigns through a nameref, which shellcheck cannot follow.
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

# PATH mirrors with one tool removed, cleaned on exit. Installed before the first
# fixture_tree::build so the builder chains this trap instead of replacing it.
MIRRORS=()
cleanup_mirrors() {
  local d
  for d in ${MIRRORS[@]+"${MIRRORS[@]}"}; do
    [[ -n "$d" && "$d" != / ]] && rm -rf "$d"
  done
}
trap cleanup_mirrors EXIT

# path_without <tool>: sets NO_PATH to a directory linking every PATH entry but
# <tool>. Later entries are linked first so earlier ones win, as PATH does.
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

# --- fixture builders --------------------------------------------------------

# page_lines: the default page. Line 3 is the marker, line 7 the alpha row (a
# drift input), line 8 a link to another repository, line 12 the beta unit in
# the Map section.
page_lines() { # [<marker>]
  printf '# Widgets\n\n'
  printf '%s\n\n' "${1:-$MARKER}"
  printf '| Unit | Outcome |\n|---|---|\n'
  printf '| [alpha](https://github.com/acme/widgets/tree/%s/skills/alpha) | adopted |\n' "$PIN"
  printf '| [other](https://github.com/elsewhere/thing/tree/%s/skills/alpha) | rejected |\n' "$PIN"
  printf '\n## Map\n\n'
  printf -- '- [beta](https://github.com/acme/widgets/tree/%s/skills/beta)\n' "$PIN"
}

# new_root: a fresh fixture tree holding the script; the root lands in $f.
new_root() {
  fixture_tree::build f --sut "$SUT_SRC" --label upstream-drift || return 2
  mkdir -p "$f/docs/upstream" "$f/fx/acme__widgets"
}

tree_file() { # <sha> <line>...
  local sha="$1"
  shift
  printf '%s\n' "$@" >"$f/fx/acme__widgets/$sha.tree"
}

set_head() { printf '%s\n' "$1" >"$f/fx/acme__widgets/HEAD"; }

# setup <head-tree-line>...: the default page, the pin tree, and HEAD at NEW
# with the given tree. With no lines, HEAD stays at the pin.
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

# --- running and asserting ---------------------------------------------------

RC=0
OUT=""
ERR=""

# run <arg>...: the script in the fixture root with the fixture seam set.
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

# run_env <env-assignment>... -- <arg>...: the script with the given environment
# only (no fixture seam unless named).
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
want_out_line() { # exact whole line on stdout
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

# --- cases -------------------------------------------------------------------

# Usage and help.
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

# Head equal to the pin: clean.
setup
run
want_rc "clean" 0
want_out_line "clean" "upstream records: 1 pages, no drift"
no_err "clean"

# A modified, added and deleted file under the row link each drift.
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

# The same paths in another repository's tree change nothing for this page.
setup
mkdir -p "$f/fx/elsewhere__thing"
run
want_rc "other repository link ignored" 0

# A Map unit that changes is not drift; one removed upstream is.
setup "$B1 README.md" "$B2 skills/alpha/SKILL.md" "$B4 skills/beta/SKILL.md"
run
want_rc "modified map unit" 0
no_err "modified map unit"

setup "$B1 README.md" "$B2 skills/alpha/SKILL.md"
run
want_rc "removed map unit" 1
want_err "removed map unit" "$PAGE:12: acme/widgets removed unit skills/beta"

# A file added under the scope that no link covers is a new unit; one added
# outside the scope is nothing.
setup "${PIN_TREE[@]}" "$B4 skills/gamma/SKILL.md"
run
want_rc "new unit" 1
want_err "new unit" "$PAGE: acme/widgets new unit skills/gamma/SKILL.md"

setup "${PIN_TREE[@]}" "$B4 docs/notes.md"
run
want_rc "added outside scope" 0
no_err "added outside scope"

# --report on drift: page, row, new-unit and removed-unit lines, path last.
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

# Path injection: a space, = and | stay inside the last field.
setup "${PIN_TREE[@]}" "$B4 skills/alpha/a b=c|d.md"
run --report
want_rc "path with space, = and |" 1
want_out_line "path with space, = and |" "row line=7 status=A path=skills/alpha/a b=c|d.md"
want_out_line "path with space, = and |" "page repo=acme/widgets pin=aaaaaaaaaaaa head=bbbbbbbbbbbb status=drift path=$PAGE"

# A control character in a tree path exits 2 with nothing on stdout. A raw
# newline splits the fixture line, so the second half is a malformed line.
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

# A blob link to a single file, on a page with no scope.
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

# A page with neither a scope nor a link is untracked, never drift.
new_root
# shellcheck disable=SC2016  # literal marker backticks
printf '# Widgets\n\n**Last audited upstream state:** `acme/widgets@%s`\n' "$PIN" >"$f/$PAGE"
tree_file "$PIN" "${PIN_TREE[@]}"
set_head "$NEW"
tree_file "$NEW" "$B4 README.md"
run --report
want_rc "untracked" 0
want_out_line "untracked" "page repo=acme/widgets pin=aaaaaaaaaaaa head=bbbbbbbbbbbb status=untracked path=$PAGE"

# Markers that are not the git form are skipped.
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

# Near-miss markers exit 2.
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

# Indented and quoted markers that name a pin are near-misses too.
for bad in "  $MARKER" "> $MARKER"; do
  new_root
  page_lines "$bad" >"$f/$PAGE"
  tree_file "$PIN" "${PIN_TREE[@]}"
  set_head "$PIN"
  run
  want_rc "near-miss marker: $bad" 2
  no_out "near-miss marker: $bad"
done

# A scope absent at the pin is a malformed record: exit 2, naming page and scope.
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

# The scope present at the pin but deleted at HEAD stays a D finding on the
# row under it and a removed Map unit, not an error.
setup "$B1 README.md"
run
want_rc "scope deleted at head" 1
want_err "scope deleted at head" "$PAGE:7: acme/widgets D skills/alpha/SKILL.md"
want_err "scope deleted at head" "$PAGE:12: acme/widgets removed unit skills/beta"

# --page on a git-form page checks that page.
setup
run --page "$PAGE"
want_rc "--page" 0
want_out_line "--page" "upstream records: 1 pages, no drift"

# --links: the default page's two links resolve at the pin.
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

# Errors: a truncated read, a missing fixture file and a missing HEAD.
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

stub_api
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "allow list, git read works" 0
want_out_line "allow list, git read works" "page repo=acme/widgets pin=${GPIN:0:12} head=${GHEAD:0:12} status=untracked path=$PAGE"
want_err "allow list, git read works" "acme: IP allow list refused the token; reading anonymously over git"
if [[ "$(wc -l <"$f/gh.log")" -eq 1 ]]; then pass "allow list: later calls skip gh"; else bad "allow list: later calls skip gh" "$(cat "$f/gh.log")"; fi
tmp_clean "allow list, git read works"

scoped_page
run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "allow list, git read finds drift" 1
no_out "allow list, git read finds drift"
want_err "allow list, git read finds drift" "$PAGE:5: acme/widgets M skills/alpha/SKILL.md"
want_err "allow list, git read finds drift" "$PAGE: acme/widgets new unit skills/gamma/SKILL.md"
tmp_clean "allow list, git read finds drift"

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --links
want_rc "allow list, git read checks links" 0
want_out "allow list, git read checks links" "1 links ok"

REAL_GIT=$(command -v git)
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
log_git
run_env PATH="$f/gitbin:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" --
want_rc "allow list, git reads fetch each commit once at depth 1" 1
fetches=$(grep -c ' fetch ' "$f/git.log")
deep=$(grep ' fetch ' "$f/git.log" | grep -cv -- '--depth=1')
if [[ "$fetches" -eq 2 && "$deep" -eq 0 ]]; then
  pass "allow list: two depth-1 fetches, pin and HEAD"
else
  bad "allow list: two depth-1 fetches, pin and HEAD" "$(cat "$f/git.log")"
fi
if ! grep -q -e cat-file -e '^GIT_NO_LAZY_FETCH= ' "$f/git.log"; then
  pass "allow list: no existence probe, lazy fetch off on every call"
else
  bad "allow list: no existence probe, lazy fetch off on every call" "$(cat "$f/git.log")"
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
want_rc "allow list, control in tree path, --report" 2
no_out "allow list, control in tree path, --report"
want_err "allow list, control in tree path, --report" "acme/widgets@${control_head:0:12}: a tree path holds a control character"
tmp_clean "allow list, control in tree path, --report"

run_env PATH="$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/control-remote" --
want_rc "allow list, control in tree path, default mode" 2
no_out "allow list, control in tree path, default mode"
want_err "allow list, control in tree path, default mode" "acme/widgets@${control_head:0:12}: a tree path holds a control character"
tmp_clean "allow list, control in tree path, default mode"

stub_api '{"message":"Not Found","status":"404"}'
log_git
run_env PATH="$f/gitbin:$f/bin:$PATH" TMPDIR="$f/tmp" UPSTREAM_DRIFT_GIT_BASE="file://$f/remote" -- --report
want_rc "other gh failure does not retry" 2
no_out "other gh failure does not retry"
want_err "other gh failure does not retry" "Not Found (HTTP 404)"
if [[ "$ERR" != *"over git"* ]]; then pass "other gh failure: no git read"; else bad "other gh failure: no git read" "$ERR"; fi
if grep -Eq ' (ls-remote|fetch)( |$)' "$f/git.log"; then
  bad "other gh failure: no ls-remote or fetch" "$(cat "$f/git.log")"
else
  pass "other gh failure: no ls-remote or fetch"
fi

# Missing prerequisites: gh outside the fixture seam, and jq always.
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
