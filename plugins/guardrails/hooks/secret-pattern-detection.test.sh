#!/usr/bin/env bash
# Contract test for secret-pattern-detection.sh (guardrails plugin).
#
# Black-box subprocess invocation. The hook reads file_path as a string only —
# fixtures need not exist on disk.
#
# Token construction discipline: every real-shape token is assembled at runtime
# from concatenated parts, so the literal joined string never appears in this
# file's source bytes — no secret scanner (gitleaks etc.) sees a committed key.

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/secret-pattern-detection.sh"
TEST_TMPDIR="$(mktemp -d)"
# The temp-decline block below makes a directory link, hard-linked files and one
# empty subdirectory in a temp dir of its own, outside TEST_TMPDIR. Each is
# removed by name and without recursion, then the emptied dir, so no recursive
# delete ever runs over a directory holding a link.
D1_LINKDIR=""
D1_SEAMDIR=""
d1_cleanup() {
  if [[ -n "$D1_SEAMDIR" ]]; then
    rmdir "$D1_SEAMDIR/lowtemp" "$D1_SEAMDIR/CapTemp" 2>/dev/null
    rmdir "$D1_SEAMDIR" 2>/dev/null
  fi
  [[ -n "$D1_LINKDIR" ]] || return 0
  if [[ -L "$D1_LINKDIR/ToHooks" ]]; then
    if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
      MSYS_NO_PATHCONV=1 cmd /c rmdir "$(cygpath -w "$D1_LINKDIR/ToHooks")" >/dev/null 2>&1
    else
      rm -f "$D1_LINKDIR/ToHooks"
    fi
  fi
  rm -f "$D1_LINKDIR/hl-src.txt" "$D1_LINKDIR/hl.txt" "$D1_LINKDIR/plain.txt"
  rmdir "$D1_LINKDIR/sub" 2>/dev/null
  rmdir "$D1_LINKDIR" 2>/dev/null
  return 0
}
trap 'd1_cleanup; rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=guardrails-test-helpers.sh
source "$HOOK_DIR/guardrails-test-helpers.sh"

# Neutralize any ambient CLAUDE_PROJECT_DIR (a CC-wrapped run sets it) so the
# default cases exercise the fail-closed scan path deterministically.
unset CLAUDE_PROJECT_DIR

# Runtime-constructed obviously-fake tokens (never a literal joined string).
AWS_PREFIX='AKIA'
AWS_TOKEN="${AWS_PREFIX}IOSFODNN7EXAMPLE"
GH_PREFIX='ghp_'
GH_PAT="${GH_PREFIX}$(printf 'a%.0s' {1..36})"
SLACK_PREFIX='xoxb-'
SLACK_TOKEN="${SLACK_PREFIX}1234567890123-9876543210987"
STRIPE_PREFIX='sk_live_'
STRIPE_TOKEN="${STRIPE_PREFIX}abcdefghij1234567890"
OPENAI_PREFIX='sk-'
OPENAI_BARE_KEY="${OPENAI_PREFIX}$(printf 'A%.0s' {1..25})"
PEM_HEADER='-----BEGIN '"PRIVATE KEY-----"

# Force the Windows case-fold path even on Linux CI: OSTYPE must be set BEFORE
# the hook is sourced (bash resets it to the build value at startup).
run_hook_windows() {
  bash -c 'OSTYPE=msys; source "$1"' _ "$HOOK" <<<"$1"
}

FIXTURE="$TEST_TMPDIR/fixture.txt"

# ============================ DETECT (exit 2) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "AWS Access Key → exit 2" 2 "$RC"
assert_contains "AWS → message" "$OUT" "AWS Access Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "GitHub PAT → exit 2" 2 "$RC"
assert_contains "GH PAT → message" "$OUT" "GitHub PAT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "SLACK='$SLACK_TOKEN'")" 2>&1)
RC=$?
assert_exit "Slack Bot Token → exit 2" 2 "$RC"
assert_contains "Slack → message" "$OUT" "Slack Bot Token"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "STRIPE_KEY='$STRIPE_TOKEN'")" 2>&1)
RC=$?
assert_exit "Stripe Key → exit 2" 2 "$RC"
assert_contains "Stripe → message" "$OUT" "Stripe Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "OPENAI_KEY='$OPENAI_BARE_KEY'")" 2>&1)
RC=$?
assert_exit "OpenAI bare sk- key → exit 2" 2 "$RC"
assert_contains "OpenAI bare sk- → message" "$OUT" "OpenAI API Key"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" "$PEM_HEADER")" 2>&1)
RC=$?
assert_exit "PEM private key → exit 2" 2 "$RC"
assert_contains "PEM → message" "$OUT" "Private Key (PEM)"

OUT=$(bash "$HOOK" <<<"$(edit_json "$FIXTURE" "old to '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "Edit new_string → exit 2" 2 "$RC"

OUT=$(bash "$HOOK" <<<"$(notebook_json "$FIXTURE" "secret = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "NotebookEdit new_source → exit 2" 2 "$RC"

# A content string may legitimately encode a NUL, and the payload fields are read
# NUL-separated. hook::jq_fields strips NUL jq-side so the delimiter cannot
# collide with content; without that the field count came back wrong, this hook's
# `|| exit 0` skipped detection entirely, and a credential placed AFTER the NUL
# passed unblocked. Built with jq (`[0] | implode`) so no literal escape sequence
# for the byte appears in this file's source.
NUL_PAYLOAD=$(MSYS_NO_PATHCONV=1 jq -nc --arg fp "$FIXTURE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"Write",tool_input:{file_path:$fp,content:("harmless first line" + ([0] | implode) + "config = " + $tok)}}')
OUT=$(bash "$HOOK" <<<"$NUL_PAYLOAD" 2>&1)
RC=$?
assert_exit "secret AFTER a NUL byte in content → exit 2" 2 "$RC"
assert_contains "secret after NUL → NUL refusal message" "$OUT" "NUL byte"

# A project root is honored as a scope only when it is a git work tree, so the
# scoped cases run against a real `git init`'d root. The file paths are read as
# strings; only the root's `.git` has to exist.
SCOPE_REPO="$TEST_TMPDIR/scoperepo"
mkdir -p "$SCOPE_REPO"
git -C "$SCOPE_REPO" init -q

# In-project secret still blocks when CLAUDE_PROJECT_DIR is set (file under root).
OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "in-project secret with PROJECT_DIR set → exit 2" 2 "$RC"
assert_contains "in-project secret → message" "$OUT" "AWS Access Key"

# Trailing slash on CLAUDE_PROJECT_DIR must not skip in-project scans.
OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO/" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "trailing-slash PROJECT_DIR still scans in-project file → exit 2" 2 "$RC"

# A backslash spelling of a real repo root is the same root.
OUT=$(CLAUDE_PROJECT_DIR="${SCOPE_REPO//\//\\}" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "backslash-spelled repo root still scans in-project file → exit 2" 2 "$RC"

# --- NotebookEdit: the payload shape Claude Code sends ------------------------
# A real NotebookEdit carries tool_input.notebook_path and new_source (a required
# string, "" on a delete), never file_path; notebook_json above builds a file_path
# shape. nb_json <notebook_path> <new_source> [edit_mode] [file_path].
nb_json() {
  MSYS_NO_PATHCONV=1 jq -n --arg np "$1" --arg s "$2" --arg m "${3:-}" --arg fp "${4:-}" \
    '{tool_name:"NotebookEdit",tool_input:({notebook_path:$np,new_source:$s}
      + (if $m == "" then {} else {edit_mode:$m} end)
      + (if $fp == "" then {} else {file_path:$fp} end))}'
}
GUARD_UNDER_TEST="$HOOK"
NB_ALSO=(--also "$HOOK_DIR/hardcoded-path-check.sh" --also "$HOOK_DIR/block-windows-drive-tmp.sh")
# nb_both <label> <expected> <needle, "" for none> <payload> [env word...]:
# alone and in the dispatcher row the Write|Edit|NotebookEdit matcher runs, each
# arm's output checked for the needle so a sibling guard's exit 2 cannot pass.
# No path uses a drive-root /tmp spelling block-windows-drive-tmp matches, and
# that guard is inert off Windows.
nb_both() {
  local label="$1" expected="$2" needle="$3" payload="$4" via
  shift 4
  for via in direct dispatched; do
    expect "$label ($via)" "$expected" --via "$via" --merge-stderr --payload "$payload" "${NB_ALSO[@]}" -- "$@"
    [[ -z "$needle" ]] || assert_contains "$label ($via) names '$needle'" "$GUARD_OUT" "$needle"
  done
}
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then NB_BASE="C:/spd-nb-root"; else NB_BASE="/spd-nb-root"; fi
NB_FILE="$NB_BASE/nb/x.ipynb"

for NB_VIA in direct dispatched; do
  guard_invoke --via "$NB_VIA" --merge-stderr --payload "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'")" "${NB_ALSO[@]}"
  assert_exit "NotebookEdit real shape, no root ($NB_VIA) → exit 2" 2 "$GUARD_RC"
  assert_contains "NotebookEdit real shape ($NB_VIA) → names the pattern" "$GUARD_OUT" "AWS Access Key"
  assert_contains "NotebookEdit real shape ($NB_VIA) → names the notebook path" "$GUARD_OUT" "$NB_FILE"
done
nb_both "NotebookEdit edit_mode insert with a secret → exit 2" 2 "GitHub PAT" \
  "$(nb_json "$NB_FILE" "token = '$GH_PAT'" insert)"
nb_both "NotebookEdit clean new_source → exit 0" 0 "" "$(nb_json "$NB_FILE" "print('hello')")"
nb_both "NotebookEdit edit_mode delete, empty new_source → exit 0" 0 "" "$(nb_json "$NB_FILE" "" delete)"
nb_both "NotebookEdit to an allowlisted path → exit 0" 0 "" \
  "$(nb_json "$NB_BASE/tests/fixtures/x.ipynb" "secret = '$AWS_TOKEN'")"

# Scope comes from notebook_path, under a real git root holding the notebook.
NB_REPO="$TEST_TMPDIR/nbrepo"
mkdir -p "$NB_REPO"
git -C "$NB_REPO" init -q
[[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && NB_REPO=$(cygpath -l -m "$NB_REPO")
nb_both "NotebookEdit in a honored root → exit 2" 2 "AWS Access Key" \
  "$(nb_json "$NB_REPO/nb/x.ipynb" "secret = '$AWS_TOKEN'")" CLAUDE_PROJECT_DIR="$NB_REPO"
nb_both "NotebookEdit outside a honored root → exit 0" 0 "" \
  "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'")" CLAUDE_PROJECT_DIR="$NB_REPO"
# notebook_path decides scope even when a file_path rides along.
nb_both "NotebookEdit in-root notebook_path, out-of-root file_path → exit 2" 2 "AWS Access Key" \
  "$(nb_json "$NB_REPO/nb/x.ipynb" "secret = '$AWS_TOKEN'" "" "$NB_FILE")" CLAUDE_PROJECT_DIR="$NB_REPO"
nb_both "NotebookEdit out-of-root notebook_path, in-root file_path → exit 0" 0 "" \
  "$(nb_json "$NB_FILE" "secret = '$AWS_TOKEN'" "" "$NB_REPO/nb/x.ipynb")" CLAUDE_PROJECT_DIR="$NB_REPO"

# A NUL inside notebook_path is refused like one in file_path.
NB_NUL=$(MSYS_NO_PATHCONV=1 jq -nc --arg np "$NB_FILE" --arg tok "$AWS_TOKEN" \
  '{tool_name:"NotebookEdit",tool_input:{notebook_path:($np + ([0] | implode) + ".ipynb"),new_source:("x = " + $tok)}}')
nb_both "NotebookEdit NUL inside notebook_path → exit 2" 2 "NUL byte" "$NB_NUL"

# --- A set root that is not a trustworthy scope is treated as unset ----------
# Claude Code sets CLAUDE_PROJECT_DIR to the launch directory, which can be the
# home directory or any directory that is not a repository. Honoring such a
# root would skip every write outside it, so each of these must scan.
OUTSIDE_FILE="$TEST_TMPDIR/elsewhere/src/config.env"
NONREPO="$TEST_TMPDIR/nonrepo"
mkdir -p "$NONREPO"
OUT=$(CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "non-repo root: outside write still scanned → exit 2" 2 "$RC"
assert_contains "non-repo root: outside write names the pattern" "$OUT" "AWS Access Key"

# The root carries .git, so only the home comparison can clear it.
HOME_REPO="$TEST_TMPDIR/homerepo"
mkdir -p "$HOME_REPO/user"
git -C "$HOME_REPO" init -q
OUT=$(env HOME="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is a repo AND home: outside write scanned → exit 2" 2 "$RC"
OUT=$(env HOME="$HOME_REPO/" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is home with a trailing slash on HOME → exit 2" 2 "$RC"
OUT=$(env HOME="$HOME_REPO/user" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is a repo that is an ancestor of home → exit 2" 2 "$RC"
OUT=$(env -u HOME USERPROFILE="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "HOME unset, USERPROFILE is the repo root → exit 2" 2 "$RC"

# A real repo root that is not home keeps its scope: an outside write is skipped.
OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "real repo root: outside write → exit 0" 0 "$RC"
assert_silent "real repo root: outside write → no stderr" "$OUT"

# The same real repo root spelled with backslashes keeps its scope too.
OUT=$(CLAUDE_PROJECT_DIR="${SCOPE_REPO//\//\\}" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "backslash-spelled real repo root: outside write → exit 0" 0 "$RC"
assert_silent "backslash-spelled real repo root: outside write → no stderr" "$OUT"

# Spellings that reach home: HOME is the repo itself, and each root below names
# it. This pins that no spelling of home is honored; the spelling arms and the
# directory comparison against home both clear these roots.
H="$HOME_REPO"
mkdir -p "$H/~"
for SPELLED in "$H/." "${H%/*}//${H##*/}" "$H/../${H##*/}" "$H/user/.." "$H/~/.."; do
  OUT=$(env HOME="$H" CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "unnormalized root '$SPELLED': outside write scanned → exit 2" 2 "$RC"
done

# Each dot spelling on its own, with HOME elsewhere so only the spelling arm
# can clear the root. A root kept as spelled cannot be compared with the file
# path as a string, so even an in-project write would be skipped.
SPELL_HOME="$TEST_TMPDIR/spell-home"
mkdir -p "$SPELL_HOME" "$SCOPE_REPO/src" "${SCOPE_REPO%/*}/x"
for SPELLED in "${SCOPE_REPO%/*}/./${SCOPE_REPO##*/}" "$SCOPE_REPO/src/.." \
  "$SCOPE_REPO/." "${SCOPE_REPO%/*}/x/../${SCOPE_REPO##*/}"; do
  OUT=$(env HOME="$SPELL_HOME" USERPROFILE="" CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "dot-spelled root '$SPELLED', HOME elsewhere: in-project write scanned → exit 2" 2 "$RC"
done

# A `~` alone clears a real repo root that is not home: an 8.3 short name
# (PROGRA~1) is one more spelling a string comparison cannot see through.
TILDE_REPO="$TEST_TMPDIR/tilde~repo"
mkdir -p "$TILDE_REPO"
git -C "$TILDE_REPO" init -q
OUT=$(CLAUDE_PROJECT_DIR="$TILDE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "repo root containing '~': outside write scanned → exit 2" 2 "$RC"

# A trailing doubled slash survives a single trim. Left unrejected, the root
# keeps a trailing `/`, so even an in-project write fails the prefix test and
# is skipped.
for SPELLED in "$SCOPE_REPO//" "${SCOPE_REPO//\//\\}\\\\"; do
  OUT=$(CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root '$SPELLED': in-project write scanned → exit 2" 2 "$RC"
  OUT=$(CLAUDE_PROJECT_DIR="$SPELLED" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root '$SPELLED': outside write scanned → exit 2" 2 "$RC"
done

# A relative root resolves against the hook's working directory, which is not
# a statement about the project, so it is never honored.
OUT=$(cd "$SCOPE_REPO" && CLAUDE_PROJECT_DIR=. bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "relative root '.' inside a repo: outside write scanned → exit 2" 2 "$RC"

# A directory link to home names home under another path. Linux CI makes a
# symlink; a Windows host makes a junction (a plain `ln -s` there copies).
make_dir_link() { # <target> <link> -> 0 when <link> is a real directory link
  if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]]; then
    command -v cmd >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1 || return 1
    MSYS_NO_PATHCONV=1 cmd /c mklink /J "$(cygpath -w "$2")" "$(cygpath -w "$1")" >/dev/null 2>&1
  else
    ln -s "$1" "$2" 2>/dev/null
  fi
  [[ -L "$2" ]]
}
if make_dir_link "$HOME_REPO" "$TEST_TMPDIR/home-link"; then
  OUT=$(env HOME="$HOME_REPO" CLAUDE_PROJECT_DIR="$TEST_TMPDIR/home-link" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "root is a link to home: outside write scanned → exit 2" 2 "$RC"
else
  echo "skip: root is a link to home (no directory link could be made on this host)"
fi

# Both home candidates are checked, not only the first one set.
ELSEWHERE_HOME="$TEST_TMPDIR/elsewhere-home"
mkdir -p "$ELSEWHERE_HOME"
OUT=$(env HOME="$ELSEWHERE_HOME" USERPROFILE="$HOME_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "root is USERPROFILE while HOME is elsewhere: outside write scanned → exit 2" 2 "$RC"
# The USERPROFILE fallback names a different home: a real repo root keeps scope.
OUT=$(env -u HOME USERPROFILE="$ELSEWHERE_HOME" CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "HOME unset, USERPROFILE elsewhere: real repo root keeps scope → exit 0" 0 "$RC"

# With no home to compare against, a root cannot be shown not to contain it.
OUT=$(env HOME="" USERPROFILE="" CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty HOME and USERPROFILE: outside write scanned → exit 2" 2 "$RC"

# A .git entry is a repository only when it looks like one: a directory with a
# HEAD, or a file whose first line is a `gitdir:` pointer.
FAKE_FILE="$TEST_TMPDIR/fake-gitfile"
mkdir -p "$FAKE_FILE"
: >"$FAKE_FILE/.git"
OUT=$(CLAUDE_PROJECT_DIR="$FAKE_FILE" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty .git file: outside write scanned → exit 2" 2 "$RC"
FAKE_DIR="$TEST_TMPDIR/fake-gitdir"
mkdir -p "$FAKE_DIR/.git"
OUT=$(CLAUDE_PROJECT_DIR="$FAKE_DIR" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "empty .git directory (no HEAD): outside write scanned → exit 2" 2 "$RC"
# A real linked worktree, whose .git is a `gitdir:` file. It needs a commit.
WT_MAIN="$TEST_TMPDIR/wt-main"
WT_LINK="$TEST_TMPDIR/wt-link"
mkdir -p "$WT_MAIN"
git -C "$WT_MAIN" init -q
git -C "$WT_MAIN" -c user.email=t@t.test -c user.name=t commit -q --allow-empty -m seed
git -C "$WT_MAIN" worktree add -q "$WT_LINK" >/dev/null 2>&1
if [[ -f "$WT_LINK/.git" ]]; then
  OUT=$(CLAUDE_PROJECT_DIR="$WT_LINK" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "linked worktree root (.git gitdir: file): outside write → exit 0" 0 "$RC"
else
  bad "linked worktree root: git worktree add produced no .git file"
fi

# Windows spellings of the same directory: the root in mixed form (C:/...), HOME
# in MSYS form (/c/...) with its case folded. Only a real msys/cygwin host with
# cygpath can build both spellings of one existing directory. The mixed form
# comes from git, which answers with long names: `cygpath -m` can return an 8.3
# short name, whose `~` would clear the root for a reason other than home.
if [[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && command -v cygpath >/dev/null 2>&1; then
  HOME_REPO_M=$(git -C "$HOME_REPO" rev-parse --show-toplevel)
  HOME_REPO_U="/${HOME_REPO_M:0:1}${HOME_REPO_M:2}"
  OUT=$(env HOME="$SCOPE_REPO" CLAUDE_PROJECT_DIR="$HOME_REPO_M" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: the C:/ root alone is honored when HOME is elsewhere → exit 0" 0 "$RC"
  OUT=$(env HOME="${HOME_REPO_U,,}" CLAUDE_PROJECT_DIR="$HOME_REPO_M" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: C:/ root vs lower-cased /c/ HOME is home → exit 2" 2 "$RC"
  OUT=$(env HOME="${HOME_REPO_U^^}/" CLAUDE_PROJECT_DIR="$HOME_REPO_M/" bash "$HOOK" <<<"$(write_json "$OUTSIDE_FILE" "config = '$AWS_TOKEN'")" 2>&1)
  RC=$?
  assert_exit "msys: upper-cased /C/ HOME and trailing slashes still match → exit 2" 2 "$RC"
fi

# ============================ ALLOW (exit 0) ================================
OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'just some normal code here')" 2>&1)
RC=$?
assert_exit "clean content → exit 0" 0 "$RC"
assert_silent "clean content → no stderr" "$OUT"

OUT=$(bash "$HOOK" <<<"$(write_json "$FIXTURE" 'api_key=mySecretValue123')" 2>&1)
RC=$?
assert_exit "low-confidence generic pattern → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(other_tool_json "Read" "$FIXTURE")" 2>&1)
RC=$?
assert_exit "Read tool → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.env.example" "API_KEY='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".env.example allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/tests/fixtures/secrets.txt" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "tests/fixtures/ allowlist → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.claude/hooks/foo.sh" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".claude/hooks/ self-exemption → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(write_json "/repo/settings.local.json" "{\"k\":\"$AWS_TOKEN\"}")" 2>&1)
RC=$?
assert_exit "settings.local.json allowlist → exit 0" 0 "$RC"

# CLAUDE.local.md allowlist must match case-sensitively even under the Windows
# path fold (regression: the fold lower-cases the membership path only).
OUT=$(run_hook_windows "$(write_json "C:/repo/CLAUDE.local.md" "token='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "CLAUDE.local.md allowlist (case-sensitive) → exit 0" 0 "$RC"

# Secret in a file OUTSIDE the project root → exit 0, silent.
OUT=$(CLAUDE_PROJECT_DIR="$SCOPE_REPO" bash "$HOOK" <<<"$(write_json "/other-repo/fixtures/bad/leak.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "file outside project root → exit 0" 0 "$RC"
assert_silent "outside project root → no stderr" "$OUT"

# Kill switch — disabled path is a clean no-op even on a real-shape token.
OUT=$(CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" <<<"$(write_json "$FIXTURE" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "kill switch off → exit 0" 0 "$RC"
assert_silent "kill switch off → no stderr" "$OUT"

# --- jq fail-open visibility (finding P4) -----------------------------------
# Runtime jq-removal is not portably simulable — an isolated bin dir without jq
# cannot host bash + coreutils (their DLLs / PATH) across Git Bash and Linux.
# Assert the fail-open guard is present in the hook source via the shared
# hook::require_jq helper (docs/conventions/hook-observability/) — it composes
# the once-per-session notice_once gate with the dual-channel (systemMessage +
# additionalContext) visibility notice; require_jq's own behavior is covered
# by lib/hook-utils.test.sh, not re-asserted here.
HOOK_SRC=$(cat "$HOOK")
assert_contains "jq guard: uses hook::require_jq" "$HOOK_SRC" 'hook::require_jq'

# --- Allowlist path-segment anchoring (finding P5) --------------------------
# A real dependency-cache SEGMENT is exempt; a directory that merely CONTAINS the
# name as a substring is scanned (and blocked on a real token).
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/src/node_modules/pkg/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "node_modules real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/evil_node_modules/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "evil_node_modules substring → exit 2 (scanned)" 2 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv/lib/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".venv real segment → exit 0 (exempt)" 0 "$RC"
OUT=$(bash "$HOOK" <<<"$(write_json "/repo/.venv-backup/creds.env" "x='$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit ".venv-backup impostor → exit 2 (scanned)" 2 "$RC"

# ============================ TELEMETRY ====================================
TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINK="$(make_sink "cat >\"$TEL\"")"
env HOOK_TELEMETRY_SINK="$SINK" CLAUDE_PROJECT_DIR="$SCOPE_REPO" \
  bash "$HOOK" <<<"$(write_json "$SCOPE_REPO/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TEL"; then
  assert_contains "telemetry: hook id" "$(jq -r '.hook' "$TEL")" "secret-pattern-detection"
  assert_contains "telemetry: status blocked" "$(jq -r '.status' "$TEL")" "blocked"
  assert_contains "telemetry: violation label" "$(jq -r '.data.violations[]' "$TEL")" "AWS Access Key"
  assert_absent "telemetry: no raw token in envelope" "$(cat "$TEL")" "$AWS_TOKEN"
else
  bad "telemetry: no envelope written on block"
fi

# --- Telemetry path redaction (finding P4): absolute path (no project dir) →
# --- basename only, so no username-bearing path lands in the envelope --------
H="ho""me"
ABS_FILE="/${H}/alice/secretproj/config.env"
TELR="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKR="$(make_sink "cat >\"$TELR\"")"
env HOOK_TELEMETRY_SINK="$SINKR" bash "$HOOK" \
  <<<"$(write_json "$ABS_FILE" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELR"; then
  df=$(jq -r '.data.file' "$TELR")
  assert_contains "redaction: data.file is the basename" "$df" "config.env"
  assert_absent "redaction: data.file has no path separator" "$df" "/"
  assert_absent "redaction: envelope drops the username dir" "$(cat "$TELR")" "alice"
else
  bad "redaction: no envelope written"
fi

# --- Telemetry path: the hoisted helper, not a hand-rolled prefix strip ------
# This hook kept its own copy of the repo-relative computation after the helper
# was hoisted into hook-utils.sh, and the copy's redaction knew only two of the
# three absolute spellings. Pin the helper so a third copy cannot reappear.
assert_contains "path helper: uses hook::repo_relative_path_to" "$HOOK_SRC" 'hook::repo_relative_path_to'
assert_absent "path helper: no hand-rolled prefix strip" "$HOOK_SRC" '_fwd#'

# Telemetry path helper fixtures. A file_path is read as a string, but the
# no-project-dir cases resolve a root from the file's own checkout, so these
# need to exist on disk. Anchor on the toplevel git reports rather than on
# mktemp's answer: on macOS mktemp hands back /var/... where git reports
# /private/var/..., and the prefix strip would fail for the wrong reason.
PATHREPO="$TEST_TMPDIR/pathrepo"
mkdir -p "$PATHREPO/src"
git -C "$PATHREPO" init -q
PATHREPO_TL="$(git -C "$PATHREPO" rev-parse --show-toplevel)"

# telemetry_file <file_path> -> data.file from the envelope this hook emits.
# CLAUDE_PROJECT_DIR stays unset (the file scope guard above falls through
# rather than skipping when there is no project, so the hook still scans).
telemetry_file() {
  local tel sink
  tel="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
  sink="$(make_sink "cat >\"$tel\"")"
  env HOOK_TELEMETRY_SINK="$sink" bash "$HOOK" \
    <<<"$(write_json "$1" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
  if wait_for_sink "$tel"; then jq -r '.data.file' "$tel"; else printf '<no-envelope>'; fi
}

# --- UNC file_path with no project dir: the leak --------------------------
# A Windows UNC path is neither POSIX-absolute nor drive-lettered, so a
# redaction that tests only those two spellings passes the WHOLE share path
# through — server name and all — into the envelope. The share host is exactly
# the kind of internal name telemetry must not carry.
UNC_HOST='srv'
# shellcheck disable=SC1003  # BS is a literal single backslash, not a quote escape
BS='\'
UNC_FILE="${BS}${BS}${UNC_HOST}${BS}share${BS}secrets.env"
# Equality, not containment: the leaked path ENDS in the basename, so a
# containment check passes against the pre-fix hook for the wrong reason.
df=$(telemetry_file "$UNC_FILE")
assert_eq "UNC/no-project: data.file is exactly the basename" "secrets.env" "$df"
assert_absent "UNC/no-project: data.file keeps no backslash" "$df" "$BS"
assert_absent "UNC/no-project: data.file drops the share host" "$df" "$UNC_HOST"

# --- Ordinary in-repo file with no project dir ------------------------------
# With no project dir the hand-rolled copy resolved no root at all, so every
# in-repo path degraded to a bare basename and the envelope lost the location
# the schema asks for. The helper is paired with hook::repo_root, which answers
# from the file's own checkout.
df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "in-repo/no-project: data.file is repo-relative" "$df" "src/config.env"
assert_absent "in-repo/no-project: data.file is not absolute" "$df" "$PATHREPO_TL"

# --- Root-level file_path with no project dir --------------------------------
# The file's directory comes from parameter expansion. For `/secrets.env` the
# shortest `/*` suffix is the whole string, so a bare `${FILE%/*}` is EMPTY, and
# hook::repo_root's `${1:-.}` would then anchor on the process CWD instead of
# `/` as `dirname` did. The anchor is proven through a `git` shim ahead of the
# real one on PATH that records every `-C` argument: the hook must ask git
# about `/`, and the envelope must still redact to the basename.
GIT_SHIM_DIR="$TEST_TMPDIR/git-shim"
mkdir -p "$GIT_SHIM_DIR"
GIT_C_LOG="$TEST_TMPDIR/git-c-args"
REAL_GIT="$(command -v git)"
{
  printf '#!/usr/bin/env bash\n'
  # shellcheck disable=SC2016  # the shim's own expansions are literal source text
  printf 'if [[ "${1:-}" == "-C" ]]; then printf "%%s\\n" "${2:-}" >>"%s"; fi\n' "$GIT_C_LOG"
  printf 'exec "%s" "$@"\n' "$REAL_GIT"
} >"$GIT_SHIM_DIR/git"
chmod +x "$GIT_SHIM_DIR/git"
: >"$GIT_C_LOG"
ROOT_TEL="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
ROOT_SINK="$(make_sink "cat >\"$ROOT_TEL\"")"
env PATH="$GIT_SHIM_DIR:$PATH" HOOK_TELEMETRY_SINK="$ROOT_SINK" bash "$HOOK" \
  <<<"$(write_json "/secrets.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1
assert_exit "root-level/no-project: still blocks" 2 "$?"
if wait_for_sink "$ROOT_TEL"; then
  assert_eq "root-level/no-project: data.file is exactly the basename" \
    "secrets.env" "$(jq -r '.data.file' "$ROOT_TEL")"
else
  bad "root-level/no-project: no envelope written"
fi
# Exactly one `git -C` and its argument is `/`: neither `.` nor the empty
# string the bare expansion produced.
assert_eq "root-level/no-project: repo root is anchored on / (dirname semantics)" \
  "/" "$(cat "$GIT_C_LOG")"

# --- Symlinked checkout ------------------------------------------------------
# A real repo plus a symlink to it. Reached through the symlink, `git rev-parse
# --show-toplevel` answers with the PHYSICAL path, so a file_path arriving in
# the symlink spelling cannot be prefix-stripped by the root the helper is
# handed. Both spellings are pinned: the physical one must still come back
# repo-relative, and the symlink one must degrade to a basename rather than
# leak the resolved physical path the fallback just computed.
LINKREPO="$TEST_TMPDIR/linkrepo"
ln -s "$PATHREPO_TL" "$LINKREPO"
df=$(telemetry_file "$PATHREPO_TL/src/config.env")
assert_contains "symlinked repo, physical spelling: repo-relative" "$df" "src/config.env"
df=$(telemetry_file "$LINKREPO/src/config.env")
assert_contains "symlinked repo, symlink spelling: basename" "$df" "config.env"
assert_absent "symlinked repo, symlink spelling: no path separator" "$df" "/"

# --- Trailing-slash project dir ---------------------------------------------
# The helper strips "$root/", so a root already ending in a separator makes the
# prefix "/repo//" and matches nothing: every in-project file would collapse to
# its basename and the envelope would lose the location. A trailing slash is a
# supported spelling of CLAUDE_PROJECT_DIR (the scope test above uses one), and
# the hand-rolled copy this replaced trimmed it, so the trim has to survive the
# move to the helper.
TELTS="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKTS="$(make_sink "cat >\"$TELTS\"")"
env HOOK_TELEMETRY_SINK="$SINKTS" CLAUDE_PROJECT_DIR="$PATHREPO_TL/" bash "$HOOK" \
  <<<"$(write_json "$PATHREPO_TL/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELTS"; then
  assert_eq "trailing-slash project dir: data.file stays repo-relative" \
    "src/config.env" "$(jq -r '.data.file' "$TELTS")"
else
  bad "trailing-slash project dir: no envelope written"
fi

# --- Cleared root: data.file anchors on the file's own checkout -------------
# A set root that is not a repository is treated as unset for scanning, so the
# telemetry path must be expressed the same way the unset case expresses it:
# relative to the checkout the file lives in, not to the rejected root.
TELNR="$(mktemp "$TEST_TMPDIR/tmp.XXXXXXXXXX")"
SINKNR="$(make_sink "cat >\"$TELNR\"")"
env HOOK_TELEMETRY_SINK="$SINKNR" CLAUDE_PROJECT_DIR="$NONREPO" bash "$HOOK" \
  <<<"$(write_json "$PATHREPO_TL/src/config.env" "config = '$AWS_TOKEN'")" >/dev/null 2>&1 || true
if wait_for_sink "$TELNR"; then
  assert_eq "non-repo root: data.file is relative to the file's own checkout" \
    "src/config.env" "$(jq -r '.data.file' "$TELNR")"
else
  bad "non-repo root: no envelope written"
fi

# ===================== PAYLOAD-SIZE BOUNDARY (regression) ====================
# Guards the here-string deadlock. Bash delivers `<<<` through a pipe it fills
# ITSELF before the reader is exec'd, and it appends a newline — so a payload of
# 65536-65663 bytes puts the write 1-128 bytes past the 65536-byte pipe capacity
# and bash blocks FOREVER. At >=129 bytes over, bash spills to a temp file, so
# the window is closed on BOTH sides: 65535 and 65664 always worked and only the
# band between them hung. That shape is why no ordinary size ever caught it.
#
# Measured against the pre-fix hook on Git Bash: a 65536-byte payload carrying a
# live-shape AWS access-key id returned NO verdict at a 200s bound, where the
# same token in a small payload exits 2 immediately. The hook is registered at
# `timeout: 60`, so in production the harness cancels the guard and the secret
# verdict is lost outright. Sibling fix for the same class in hook-utils.sh's
# JSON path: #1587.
#
# The payload is PIPED here, never `bash "$HOOK" <<<"$json"` — a here-string
# would hang THIS FILE at exactly these sizes and read as the bug under test.

# Content of EXACTLY $1 bytes, ending in " $2" when $2 is given. jq reads the
# content on STDIN (`-Rs`): a 65KB `--arg` blows the Win32 32767-byte argv limit
# and jq would never run. The separating space matters for the sibling
# hardcoded-path suite, whose patterns require a left boundary; keeping one
# builder shape across both suites keeps them comparable.
size_filler() { head -c "$1" /dev/zero | tr '\0' b; }
sized_write_json() {
  local n="$1" tail="${2:-}"
  [[ -n "$tail" ]] && tail=" $tail"
  printf '%s%s' "$(size_filler $((n - ${#tail})))" "$tail" |
    MSYS_NO_PATHCONV=1 jq -Rs --arg fp "$FIXTURE" \
      '{tool_name:"Write",tool_input:{file_path:$fp,content:.}}'
}

# Bound every case so a regression FAILS LOUDLY instead of hanging CI. 150s is
# generous on purpose: the legitimate large-payload itemization measured 41-67s
# on Git Bash under Defender, while a deadlock never returns at any bound — so
# 150 separates the two without making the case flaky on a slow host.
run_bounded() {
  local rc=0
  printf '%s' "$1" | timeout 150 bash "$HOOK" >/dev/null 2>&1 || rc=$?
  printf '%s' "$rc"
}

# Asserts the EXACT code, and names 124 as its own failure. A "non-zero means
# blocked" assertion would have ACCEPTED the hang and would not have caught this
# defect — the whole point is that no verdict is not a blocking verdict.
assert_bounded_exit() {
  if [[ "$3" == "124" ]]; then
    bad "$1: HUNG (exit 124 at the 150s bound) — here-string deadlock regression"
  elif [[ "$3" == "$2" ]]; then
    ok "$1 (exit $3)"
  else
    bad "$1: expected exit $2, got $3"
  fi
}

# Clean payloads across the window and both shoulders — exercises the combined
# fast-reject gate, which is the site that scans EVERY write.
for SZ in 65535 65536 65600 65663 65664; do
  assert_bounded_exit "boundary: clean ${SZ}-byte payload → exit 0" \
    0 "$(run_bounded "$(sized_write_json "$SZ")")"
done

# The security case: a REAL detectable secret sitting inside the hang window
# must still BLOCK. Pre-fix this exact payload produced no verdict at all.
# Two sizes: the exact pipe capacity, and mid-window. These also reach the
# per-pattern itemization (the second patched call site), which a clean payload
# never touches because the fast-reject returns first.
for SZ in 65536 65600; do
  assert_bounded_exit "boundary: AWS key in ${SZ}-byte payload → exit 2" \
    2 "$(run_bounded "$(sized_write_json "$SZ" "$AWS_TOKEN")")"
done

# Process substitution must not leak writer noise onto stderr. `grep -q`
# early-exits and SIGPIPEs the `printf` feeding it; stderr is this hook's
# user-facing channel, so a stray "write error: Broken pipe" would corrupt the
# blocked message.
BOUND_ERR=$(printf '%s' "$(sized_write_json 65600 "$AWS_TOKEN")" | timeout 150 bash "$HOOK" 2>&1 >/dev/null)
assert_contains "boundary: in-window block still reports the label" "$BOUND_ERR" "AWS Access Key"
assert_absent "boundary: no SIGPIPE noise on stderr" "$BOUND_ERR" "Broken pipe"

# Empty content. `<<<""` delivered ONE EMPTY LINE; `printf '%s' ""` delivers
# zero bytes. No pattern matches an empty line either way and the hook's own
# `[[ -n "$CONTENT" ]]` guard exits first — pinned so the substitution cannot
# quietly become a behavior change.
RC=0
printf '%s' "$(sized_write_json 0)" | timeout 30 bash "$HOOK" >/dev/null 2>&1 || RC=$?
assert_exit "boundary: empty content → exit 0" 0 "$RC"

# ==================== GitHub MCP write lane (#3719) ==========================
# A Write|Edit matcher does not see a write issued through an MCP tool, so this
# guard could be cleared on a session that pushed the same secret to GitHub by
# another route. One case per PAYLOAD SHAPE, because the two tools carry content
# differently and a scanner that only understood one would silently pass the
# other.
#
#   mcp__github__create_or_update_file — .tool_input.path + .tool_input.content
#   mcp__github__push_files            — .tool_input.files[] of {path, content}
#   mcp__github__delete_file           — NO content field at all
mcp_single_json() {
  jq -n --arg p "$1" --arg c "$2" \
    '{tool_name:"mcp__github__create_or_update_file",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",path:$p,content:$c}}'
}
# mcp_push_json <path> <content> [<path> <content> ...]
mcp_push_json() {
  local args=() n=0
  while (($#)); do
    args+=(--arg "p$n" "$1" --arg "c$n" "$2")
    shift 2
    n=$((n + 1))
  done
  # One --arg pair per file, and an index-built object list, so the payload's
  # shape is the tool schema's rather than a string-interpolated approximation.
  local filter='{tool_name:"mcp__github__push_files",tool_input:{owner:"o",repo:"r",branch:"main",message:"m",files:['
  local i
  for ((i = 0; i < n; i++)); do
    ((i)) && filter+=','
    # shellcheck disable=SC2016  # $p<i>/$c<i> are jq --arg variables, not shell expansions
    filter+='{path:$p'"$i"',content:$c'"$i"'}'
  done
  filter+=']}}'
  jq -n "${args[@]}" "$filter"
}

# --- create_or_update_file: the single-file shape
RC=0
bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "import os")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP create_or_update_file: clean content → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" 2>&1)
RC=$?
assert_exit "MCP create_or_update_file: secret → exit 2" 2 "$RC"
assert_contains "MCP create_or_update_file: names the pattern" "$OUT" "GitHub PAT"
assert_contains "MCP create_or_update_file: names the repo path" "$OUT" "src/app.py"
assert_contains "MCP create_or_update_file: says there is no local file to fix" "$OUT" "goes straight to a repository"

# --- push_files: the multi-file shape, and the LAST file must be reached
RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "y = 2")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: all clean → exit 0" 0 "$RC"

OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "k = '$AWS_TOKEN'" "b.py" "y = 2")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the FIRST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: first-file block names its path" "$OUT" "a.py"

# The loop must not stop at the first clean file: a guard that checked only
# files[0] would pass this and read as covered.
OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "k = '$AWS_TOKEN'")" 2>&1)
RC=$?
assert_exit "MCP push_files: secret in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP push_files: last-file block names its path" "$OUT" "b.py"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","files":[]}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: empty files array → exit 0" 0 "$RC"

RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__push_files","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP push_files: absent files array → exit 0" 0 "$RC"

# --- delete_file carries no content, so there is nothing to scan
RC=0
bash "$HOOK" <<<'{"tool_name":"mcp__github__delete_file","tool_input":{"owner":"o","repo":"r","branch":"main","message":"m","path":"src/app.py"}}' >/dev/null 2>&1 || RC=$?
assert_exit "MCP delete_file: no content to scan → exit 0" 0 "$RC"

# --- a plugin-bundled GitHub server names its tools with a scoped segment
# (mcp__plugin_<plugin>_github__<tool>); the lane must treat them the same.
scoped() { jq --arg t "mcp__plugin_github_github__$1" '.tool_name = $t'; }
OUT=$(bash "$HOOK" <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'" | scoped create_or_update_file)" 2>&1)
RC=$?
assert_exit "MCP scoped create_or_update_file: secret → exit 2" 2 "$RC"
assert_contains "MCP scoped create_or_update_file: names the repo path" "$OUT" "src/app.py"
OUT=$(bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" "b.py" "k = '$AWS_TOKEN'" | scoped push_files)" 2>&1)
RC=$?
assert_exit "MCP scoped push_files: secret in the LAST file → exit 2" 2 "$RC"
assert_contains "MCP scoped push_files: names the last file" "$OUT" "b.py"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "a.py" "x = 1" | scoped push_files)" >/dev/null 2>&1 || RC=$?
assert_exit "MCP scoped push_files: clean → exit 0" 0 "$RC"

# The hooks.json row must route both name shapes here, and not delete_file.
MATCHER=$(jq -r '.hooks.PreToolUse[] | select(.hooks[0].command | contains("secret-pattern-detection.sh")) | .matcher | select(test("github"))' "$HOOK_DIR/hooks.json")
for name in mcp__github__push_files mcp__github__create_or_update_file \
  mcp__plugin_github_github__push_files mcp__plugin_my-plugin_github__create_or_update_file; do
  RC=0
  jq -en --arg m "$MATCHER" --arg n "$name" '$n | test($m)' >/dev/null || RC=$?
  assert_exit "hooks.json GitHub row matches $name" 0 "$RC"
done
for name in mcp__github__delete_file mcp__plugin_github_github__delete_file mcp__gitlab__push_files; do
  RC=0
  jq -en --arg m "$MATCHER" --arg n "$name" '$n | test($m)' >/dev/null || RC=$?
  assert_exit "hooks.json GitHub row does not match $name" 1 "$RC"
done

# --- the allowlist is the SAME list, asked of a repo-relative path
RC=0
bash "$HOOK" <<<"$(mcp_single_json "docs/.env.example" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted .env.example is exempt" 0 "$RC"
RC=0
bash "$HOOK" <<<"$(mcp_push_json "tests/fixtures/keys.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: allowlisted test fixture is exempt" 0 "$RC"
# A directory that merely CONTAINS an allowlisted name is not allowlisted.
RC=0
bash "$HOOK" <<<"$(mcp_push_json "evil_node_modules/x.py" "k = '$AWS_TOKEN'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a name-prefix sibling of an allowlisted dir still blocks" 2 "$RC"

# --- the local-project scope guard must NOT be applied to a remote write
# A repo-relative path is never under CLAUDE_PROJECT_DIR, so reusing the local
# scope test here would skip every MCP write. Pinned with the variable SET,
# which is the state that would trigger it.
RC=0
CLAUDE_PROJECT_DIR="$TEST_TMPDIR" bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: a set CLAUDE_PROJECT_DIR does not skip the remote write" 2 "$RC"

# --- the kill switch still governs the whole guard, MCP lane included
RC=0
CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED=false bash "$HOOK" \
  <<<"$(mcp_single_json "src/app.py" "token = '$GH_PAT'")" >/dev/null 2>&1 || RC=$?
assert_exit "MCP: disabled guard allows the write" 0 "$RC"

# ============ Temp-tree decline at the Bash exemption's width ================
# block-hook-bypass exempts a Bash redirect into a host temp tree when the
# project root is known and outside that tree. A Write of the same content to
# the same path declines here under the same gate, so the two routes agree.
#
# Every spelling case below is the rc 0 payload (D1_ROOT + D1_TARGET) with ONE input
# changed, so the refusal it pins is the only reason it scans.
#
# On a Windows host the Write tool is Node, which resolves `/tmp/x` and `/c/x`
# differently from Git Bash, so only a long-name drive spelling may decline:
# the temp base comes from `cygpath -l -m`, never from mktemp or raw TEMP (8.3).
D1_WIN=0
[[ "$OSTYPE" == msys* || "$OSTYPE" == cygwin* ]] && D1_WIN=1
if ((D1_WIN)); then
  D1_TEMP=$(cygpath -l -m "${TEMP:-${TMP:-/tmp}}")
  D1_ROOT="C:/spd-d1-nonrepo-root"
  D1_HOME="C:/spd-d1-home"
else
  D1_TEMP=/tmp
  D1_ROOT="/spd-d1-nonrepo-root"
  D1_HOME="/spd-d1-home"
fi
D1_TARGET="$D1_TEMP/spd-d1-$$/sub/f.txt"

# d1_rc <root, empty for unset> <target> [NAME=value...] -> the hook's exit code
d1_rc() {
  local root="$1" target="$2" rc=0
  shift 2
  if [[ -n "$root" ]]; then
    env "$@" CLAUDE_PROJECT_DIR="$root" bash "$HOOK" <<<"$(write_json "$target" "token = '$GH_PAT'")" >/dev/null 2>&1 || rc=$?
  else
    env "$@" bash "$HOOK" <<<"$(write_json "$target" "token = '$GH_PAT'")" >/dev/null 2>&1 || rc=$?
  fi
  printf '%s' "$rc"
}

assert_exit "D1 non-temp non-git root, temp target → exit 0" 0 "$(d1_rc "$D1_ROOT" "$D1_TARGET")"
assert_exit "D1 root is HOME, temp target → exit 0" 0 \
  "$(d1_rc "$D1_HOME" "$D1_TARGET" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
assert_exit "D1 root unset, temp target → exit 2" 2 "$(d1_rc "" "$D1_TARGET")"
assert_exit "D1 root under temp → exit 2" 2 "$(d1_rc "$D1_TEMP/spd-d1-$$" "$D1_TARGET")"
assert_exit "D1 root is the temp root → exit 2" 2 "$(d1_rc "$D1_TEMP" "$D1_TARGET")"

# Target spellings refused before any resolution.
for D1_T in "$D1_TEMP/spd-d1-$$/../../spd-d1-out/f.txt" "${D1_TEMP}Evil/spd-d1/f.txt" \
  "$D1_TEMP/spd~1/f.txt" "/$D1_TARGET" "$D1_TEMP//spd-d1/f.txt" "tmp/spd-d1/f.txt" \
  "$D1_TEMP/spd-a\$b/f.txt" "$D1_TEMP/spd-a[1]/f.txt" "$D1_TEMP/spd-a\`b/f.txt" \
  "$D1_TEMP/spd a/f.txt" "$D1_TEMP/spd;a/f.txt" "$D1_TEMP/spd\"a/f.txt" "$D1_TEMP/spd'a/f.txt" \
  "$D1_TEMP/spd(a)/f.txt" "$D1_TEMP/spd#a/f.txt" "$D1_TEMP/spd&a/f.txt"; do
  assert_exit "D1 target '$D1_T' → exit 2" 2 "$(d1_rc "$D1_ROOT" "$D1_T")"
done
# Root spellings block-hook-bypass would not accept, and a filesystem root.
for D1_R in "$D1_ROOT\$x" "${D1_ROOT}*" "${D1_ROOT}~1" "spd-d1-rel-root" "/"; do
  assert_exit "D1 root '$D1_R' → exit 2" 2 "$(d1_rc "$D1_R" "$D1_TARGET")"
done

# A test-owned temp dir for the cases that need real files under temp.
D1_LINKDIR=$(mktemp -d) || D1_LINKDIR=""
if [[ -n "$D1_LINKDIR" ]]; then
  D1_LINKBASE="$D1_LINKDIR"
  ((D1_WIN)) && D1_LINKBASE=$(cygpath -l -m "$D1_LINKDIR")
  # A link under temp pointing at an existing non-temp directory. The target
  # through it lands outside temp and scans; a genuine sibling declines. The
  # link name carries capitals so a walk over a lowercased copy would miss it.
  if make_dir_link "$HOOK_DIR" "$D1_LINKDIR/ToHooks"; then
    assert_exit "D1 target through a temp link to a non-temp dir → exit 2" 2 \
      "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/ToHooks/spd-d1-absent/f.txt")"
    assert_exit "D1 genuine sibling in the same temp dir → exit 0" 0 \
      "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/genuine/f.txt")"
  else
    echo "SKIP: D1 temp link cases (no directory link could be made on this host)"
  fi
  # A hard link resolves to itself, so a temp-tree name for a file stored
  # elsewhere passes every path test: a link count above 1 scans. A plain file
  # beside it declines.
  : >"$D1_LINKDIR/hl-src.txt"
  : >"$D1_LINKDIR/plain.txt"
  if ln "$D1_LINKDIR/hl-src.txt" "$D1_LINKDIR/hl.txt" 2>/dev/null; then
    assert_exit "D1 hard-linked temp file → exit 2" 2 "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/hl.txt")"
    assert_exit "D1 plain temp file beside it → exit 0" 0 "$(d1_rc "$D1_ROOT" "$D1_LINKBASE/plain.txt")"
  else
    echo "SKIP: D1 hard link cases (ln could not make a hard link on this host)"
  fi
  # After a decline, the directory the target walk resolved is not in the
  # resolver cache: the guard is sourced in a child shell whose `exit` is a
  # function printing the cache keys before the real exit (abort-boundary owns
  # the EXIT trap, so a trap of our own would be replaced).
  mkdir "$D1_LINKDIR/sub"
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  D1_PROBE=$(CLAUDE_PROJECT_DIR="$D1_ROOT" bash -c 'exit() { printf "MARK|%s\n" "${_HOOK_PHYS_KEYS[*]-}"; builtin exit "$@"; }; source "$1"' _ "$HOOK" <<<"$(write_json "$D1_LINKBASE/sub/f.txt" "token = '$GH_PAT'")" 2>/dev/null)
  D1_PROBE_RC=$?
  assert_exit "D1 probe: sourced guard declines" 0 "$D1_PROBE_RC"
  D1_KEYS="${D1_PROBE#*MARK|}"
  if [[ "$D1_PROBE" == *"MARK|"* && -n "$D1_KEYS" ]]; then ok "D1 probe: resolve stage ran"; else bad "D1 probe: no cache keys ($D1_PROBE)"; fi
  assert_absent "D1 probe: the resolved target directory is not cached" "$D1_KEYS" "$D1_LINKBASE/sub"
else
  echo "SKIP: D1 temp-file cases (mktemp -d failed)"
fi

# Width on POSIX: block-hook-bypass lowercases the target before comparing it
# with temp candidates that keep their case, so a capitalized temp root never
# exempts there, and the decline must not either. Lifted seam: the spd functions
# run with OSTYPE forced to POSIX and the candidate set replaced by one
# test-owned directory, capitalized or not.
# shellcheck disable=SC2016  # the sed addresses are literal hook source text
D1_SEAM=$(sed -n '/^spd_win=0$/,/^spd_temp_declines "\$FILE" && exit 0$/p' "$HOOK" | sed '$d')
d1_seam_rc() { # <candidate dir> -> spd_temp_declines' status for a file under it
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  CLAUDE_PROJECT_DIR=/spd-d1-nonrepo-root bash -c 'OSTYPE=linux-gnu; source "$1/hook-utils.sh"; eval "$2"
    d1_cand="$3"
    hook::_temp_root_candidates() { _HOOK_TEMP_CANDS=("$d1_cand"); }
    spd_temp_declines "$3/spd-d1-absent/f.txt"; printf %s "$?"' _ "$HOOK_DIR" "$D1_SEAM" "$1"
}
# mktemp names carry capitals, so the seam dirs sit under a lowercase name of
# their own, removed by name in the EXIT trap. The precondition asks the seam's
# own resolver: under a forced Linux OSTYPE the library resolves with `cd -P`,
# which on Git Bash follows the /tmp mount to a capitalized Windows path, so the
# cases only run where that resolver spells each seam dir as given.
d1_seam_self() { # <dir> -> 0 when the Linux resolver spells <dir> as given; answer left in D1_SEAM_GOT
  # shellcheck disable=SC2016  # the child shell's expansions are literal source text
  D1_SEAM_GOT=$(bash -c 'OSTYPE=linux-gnu; source "$1/hook-utils.sh"; hook::physical_path_to p "$2" && printf %s "$p"' _ "$HOOK_DIR" "$1" 2>/dev/null)
  [[ "$D1_SEAM_GOT" == "$1" ]]
}
D1_SEAM_TRY="/tmp/spd-d1-seam-$$"
D1_SEAM_STEP="mkdir $D1_SEAM_TRY"
if mkdir "$D1_SEAM_TRY" 2>/dev/null && D1_SEAMDIR="$D1_SEAM_TRY" &&
  D1_SEAM_STEP="mkdir lowtemp and CapTemp under it" &&
  mkdir "$D1_SEAMDIR/lowtemp" "$D1_SEAMDIR/CapTemp" 2>/dev/null &&
  D1_SEAM_STEP="resolve $D1_SEAMDIR/lowtemp" && d1_seam_self "$D1_SEAMDIR/lowtemp" &&
  D1_SEAM_STEP="resolve $D1_SEAMDIR/CapTemp" && d1_seam_self "$D1_SEAMDIR/CapTemp"; then
  assert_eq "D1 seam: posix, lowercase temp root declines" 0 "$(d1_seam_rc "$D1_SEAMDIR/lowtemp")"
  assert_eq "D1 seam: posix, capitalized temp root scans" 1 "$(d1_seam_rc "$D1_SEAMDIR/CapTemp")"
elif [[ "${OSTYPE:-}" == linux* ]]; then
  [[ "$D1_SEAM_STEP" == resolve* ]] && D1_SEAM_STEP+=" under the library's Linux resolver gave '$D1_SEAM_GOT'"
  bad "D1 seam: precondition failed: $D1_SEAM_STEP"
else
  echo "SKIP: D1 seam width cases (under a forced Linux OSTYPE the library resolver does not spell the /tmp seam dirs as given on this host, or the seam dirs could not be made)"
fi

if ((D1_WIN)); then
  assert_exit "D1 windows: drive root '${D1_ROOT%%/*}/' → exit 2" 2 "$(d1_rc "${D1_ROOT%%/*}/" "$D1_TARGET")"
  # A drive spelling that names no volume must terminate. timeout 124 is a hang,
  # not a verdict; a loaded Windows host spends tens of seconds on one fire.
  assert_exit "D1 windows: Z:/ root, temp target, terminates → exit 0" 0 \
    "$(
      D1_RC=0
      timeout 150 env CLAUDE_PROJECT_DIR="Z:/spd-d1-root" bash "$HOOK" <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_RC=$?
      printf '%s' "$D1_RC"
    )"
  assert_exit "D1 windows: backslash long spelling, HOME root → exit 0" 0 \
    "$(d1_rc "$D1_HOME" "${D1_TARGET//\//\\}" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  assert_exit "D1 windows: /c/ spelling → exit 2" 2 \
    "$(d1_rc "$D1_HOME" "/${D1_TARGET:0:1}${D1_TARGET:2}" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  assert_exit "D1 windows: /tmp/ spelling → exit 2" 2 \
    "$(d1_rc "$D1_HOME" "/tmp/spd-d1-$$/f.txt" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  D1_SHORT="$(cygpath -s -m "$D1_TEMP")/spd-d1-$$/sub/f.txt"
  if [[ "$D1_SHORT" != "$D1_TARGET" ]]; then
    assert_exit "D1 windows: 8.3 short spelling → exit 2" 2 \
      "$(d1_rc "$D1_HOME" "$D1_SHORT" HOME="$D1_HOME" USERPROFILE="$D1_HOME")"
  else
    echo "SKIP: D1 windows 8.3 case (the temp path has no short spelling on this volume)"
  fi
else
  echo "SKIP: D1 Windows spelling cases (not a Windows Git Bash host)"
  assert_exit "D1 posix: target carrying a backslash → exit 2" 2 \
    "$(d1_rc "$D1_ROOT" "/tmp/spd-d1-$$\\x/f.txt")"
fi

# Fork-free common path: a shim logs every resolver the hook spawns. A non-temp
# target spawns none; a temp target spawns at least one, which shows the shim is
# on the path the hook takes. Telemetry is off: its path helper runs cygpath on
# a block, which is not the decline's cost.
D1_SHIM="$TEST_TMPDIR/d1-shim"
D1_LOG="$TEST_TMPDIR/d1-shim.log"
mkdir -p "$D1_SHIM"
for D1_BIN in realpath readlink cygpath; do
  D1_REAL=$(command -v "$D1_BIN") || continue
  {
    printf '#!/usr/bin/env bash\n'
    printf 'printf "%%s\\n" %s >>"%s"\n' "$D1_BIN" "$D1_LOG"
    printf 'exec "%s" "$@"\n' "$D1_REAL"
  } >"$D1_SHIM/$D1_BIN"
  chmod +x "$D1_SHIM/$D1_BIN"
done
: >"$D1_LOG"
d1_rc "$D1_ROOT" "$D1_ROOT/src/f.txt" PATH="$D1_SHIM:$PATH" HOOK_TELEMETRY_SINK= >/dev/null
assert_eq "D1 non-temp target spawns no resolver" "" "$(cat "$D1_LOG")"
: >"$D1_LOG"
d1_rc "$D1_ROOT" "$D1_TARGET" PATH="$D1_SHIM:$PATH" HOOK_TELEMETRY_SINK= >/dev/null
if [[ "${OSTYPE:-}" == linux* ]]; then
  # On Linux hook::physical_path_to resolves an existing absolute path with
  # builtin `cd -P`, so the temp target starts no resolver either. Show the
  # shim logs a spawn by calling it directly instead.
  "$D1_SHIM/realpath" / >/dev/null
  if [[ -s "$D1_LOG" ]]; then ok "D1 shim logs a resolver spawn"; else bad "D1 shim logged no resolver spawn"; fi
elif [[ -s "$D1_LOG" ]]; then ok "D1 temp target spawns a resolver"; else bad "D1 temp target spawned no resolver"; fi

# The dispatcher runs this guard beside the other Write|Edit guards.
D1_DISPATCH_RC=0
CLAUDE_PROJECT_DIR="$D1_ROOT" bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: non-temp root, temp target → exit 0" 0 "$D1_DISPATCH_RC"
D1_DISPATCH_RC=0
bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: root unset → exit 2" 2 "$D1_DISPATCH_RC"

# A NotebookEdit declines or scans exactly as a Write to the same path does.
nb_both "D1 NotebookEdit: non-temp non-git root, temp target → exit 0" 0 "" \
  "$(nb_json "$D1_TARGET" "token = '$GH_PAT'")" CLAUDE_PROJECT_DIR="$D1_ROOT"
nb_both "D1 NotebookEdit: root unset, temp target → exit 2" 2 "GitHub PAT" \
  "$(nb_json "$D1_TARGET" "token = '$GH_PAT'")"

report
linux_mounts)
    if mount_error:
        return "mount-state-unverified"
    if mounted:
        return "nested-mount-point"
    for root in system_roots():
        if path.absolute() == root.absolute() or is_within(
            path.absolute(), root.absolute()
        ):
            return "os-owned"
    return None


def enumerate_root_children(
    target: Path,
    policy: dict[str, Any],
    known_linux_mounts: set[Path] | None = None,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """List immediate volume-root entries into admitted vs skipped buckets.

    Enumerates the root once and never recurses. Admitted entries are
    directories that cleared every root-children exclusion; skipped entries
    carry the reason they were withheld.
    """
    exact_names = set(policy["protected_exact_names"])
    os_owned = volume_root_os_owned_names()
    admitted: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    try:
        with os.scandir(target) as iterator:
            children = sorted(iterator, key=lambda entry: entry.name.casefold())
    except OSError as exc:
        raise HygieneError(f"cannot enumerate volume root: {exc}") from exc
    for child in children:
        path = Path(child.path)
        reason = root_child_skip_reason(
            path,
            exact_names=exact_names,
            known_linux_mounts=known_linux_mounts,
            os_owned_names=os_owned,
        )
        if reason is None:
            admitted.append({"name": child.name, "path": str(path)})
        else:
            skipped.append({"name": child.name, "path": str(path), "reason": reason})
    return admitted, skipped


def root_child_names_case_sensitive(platform_key: str | None = None) -> bool:
    """Whether root-child selection must preserve exact basenames.

    Linux volume roots are case-sensitive; collapsing `/Cache` and `/cache` into
    one casefolded key would let `--root-child Cache` inventory the wrong sibling
    (or both). Windows and macOS volume roots are case-insensitive, so casefold
    matching remains the operator-friendly path there.
    """
    current = platform_key or os_key()
    return current == "linux"


def normalize_root_child_selection(
    selected: list[str],
    admitted: list[dict[str, str]],
    *,
    case_sensitive: bool | None = None,
) -> list[str]:
    """Map a human selection onto admitted basenames; reject anything else."""
    if not selected:
        raise HygieneError(
            "--root-children requires an explicit --root-child selection; "
            "a general clean-everything request is not selection"
        )
    sensitive = (
        root_child_names_case_sensitive() if case_sensitive is None else case_sensitive
    )
    if sensitive:
        by_name = {item["name"]: item["name"] for item in admitted}
    else:
        by_name = {item["name"].casefold(): item["name"] for item in admitted}
    resolved: list[str] = []
    seen: set[str] = set()
    for raw in selected:
        if not raw or raw in {".", ".."} or "/" in raw or "\\" in raw:
            raise HygieneError(
                f"--root-child must be an immediate basename, not a path: {raw!r}"
            )
        key = raw if sensitive else raw.casefold()
        if key not in by_name:
            raise HygieneError(
                f"--root-child {raw!r} is not an admitted immediate child directory "
                "of the OS-managed volume root"
            )
        canonical = by_name[key]
        seen_key = canonical if sensitive else canonical.casefold()
        if seen_key in seen:
            continue
        seen.add(seen_key)
        resolved.append(canonical)
    return resolved


def scan_tree(
    target: Path,
    policy: dict[str, Any],
    max_depth: int | None = None,
    *,
    root_children: list[str] | None = None,
) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    truncated: list[str] = []
    # Why each uninventoried path is uninventoried, so the per-child roll-up can
    # name the cause instead of reporting an undifferentiated gap.
    unwalked_reasons: dict[str, str] = {}
    repositories, repo_errors = discover_enclosing_git(target)
    exact_names = set(policy["protected_exact_names"])
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        errors.append({"path": ".", "error": mount_error})
    root_children_sensitive = root_child_names_case_sensitive()
    if root_children is None:
        allowed_root_children: set[str] | None = None
    elif root_children_sensitive:
        allowed_root_children = set(root_children)
    else:
        allowed_root_children = {name.casefold() for name in root_children}

    def visit(directory: Path, depth: int = 1) -> int | None:
        total = 0
        try:
            with os.scandir(directory) as iterator:
                children = sorted(iterator, key=lambda entry: entry.name.casefold())
        except OSError as exc:
            errors.append(
                {"path": directory.relative_to(target).as_posix(), "error": str(exc)}
            )
            # Unknown coverage — not an empty directory. Caller marks not-walked.
            return None
        for child in children:
            path = Path(child.path)
            # Root-children mode never walks the volume root as a whole: only
            # explicitly selected immediate directories are entered, and the
            # root's own files / excluded siblings are never inventoried.
            child_key = child.name if root_children_sensitive else child.name.casefold()
            if (
                allowed_root_children is not None
                and depth == 1
                and directory == target
                and child_key not in allowed_root_children
            ):
                continue
            relative = path.relative_to(target).as_posix()
            protections = hard_protection(path, target, exact_names, known_mounts)
            if path.name.casefold() in VCS_NAMES:
                repositories.append(path.parent.resolve())
            if any(
                glob_matches(relative, pattern)
                for pattern in policy["additional_protected_path_globs"]
            ):
                protections.append("consumer-protected-path")
            try:
                if is_linkish(path):
                    kind = "link"
                    data = metadata(path, kind)
                elif child.is_dir(follow_symlinks=False):
                    kind = "directory"
                    walked = True
                    if path.name.casefold() in VCS_NAMES:
                        subtotal: int | None = None
                        walked = False
                        truncated.append(relative)
                        unwalked_reasons[relative] = "vcs-boundary"
                    elif protections:
                        subtotal = None
                        walked = False
                        truncated.append(relative)
                        unwalked_reasons[relative] = "protected"
                    elif max_depth is not None and depth >= max_depth:
                        # A depth cut is the one truncation reason emptiness can
                        # answer. One cheap first-child probe (no recursion, no
                        # count) decides it: an empty directory has no
                        # descendants, so nothing is left uninventoried and its
                        # size is genuinely 0 rather than unknown — record it
                        # walked, and keep it out of truncated so the four
                        # downstream consumers stop treating a vacuously complete
                        # inventory as a coverage gap. Anything with a child, or
                        # any directory the probe cannot read, keeps the old
                        # not-walked marking. Scoped to THIS branch on purpose:
                        # the VCS and protection branches above refuse to walk
                        # for reasons emptiness does not answer, so an empty
                        # protected or VCS directory must still land in
                        # truncated.
                        if directory_has_child(path):
                            subtotal = None
                            walked = False
                            truncated.append(relative)
                            unwalked_reasons[relative] = "depth-cut"
                        else:
                            subtotal = 0
                    else:
                        subtotal = visit(path, depth + 1)
                        if subtotal is None:
                            # scandir failed inside this child: unknown, not empty.
                            walked = False
                            unwalked_reasons[relative] = "scan-error"
                    data = metadata(path, kind, subtotal, walked=walked)
                    # Truncated children contribute unknown, not zero: adding
                    # null as 0 was what made a truncated subtree look empty.
                    if subtotal is not None:
                        total += subtotal
                elif child.is_file(follow_symlinks=False):
                    kind = "file"
                    data = metadata(path, kind)
                    total += entry_logical_file_bytes(data)
                else:
                    kind = "other"
                    data = metadata(path, kind)
            except OSError as exc:
                errors.append({"path": relative, "error": str(exc)})
                unwalked_reasons[relative] = "scan-error"
                continue
            if len(entries) >= MAX_SNAPSHOT_ENTRIES:
                raise HygieneError(
                    f"snapshot exceeds {MAX_SNAPSHOT_ENTRIES} entries; rerun with "
                    "--max-depth or split the audit into bounded subtrees"
                )
            entries.append(
                {
                    "path": relative,
                    **data,
                    "hints": matching_hints(relative, path.name, policy),
                    "protected_reasons": sorted(set(protections)),
                }
            )
            if len(entries) % 25_000 == 0:
                print(f"scanned {len(entries)} entries...", file=sys.stderr)
        return total

    total_size = visit(target)
    if total_size is None:
        total_size = 0
        truncated.append(".")
    repositories = sorted(set(repositories))
    annotate_tracked(entries, target, repositories, truncated, repo_errors)
    stdlib_shadowing = annotate_stdlib_shadowing(entries, target)
    reclaimable = reclaimable_local_bytes(entries)
    target_identity = metadata(target, "directory", total_size)
    # The target itself was walked, but any truncated child means the target's
    # byte roll-up is incomplete. Keep the known walked sum in logical_size and
    # surface the gap on the qualifier rather than claiming the target is empty.
    if truncated:
        target_identity["size_qualifiers"] = sorted(
            set(target_identity["size_qualifiers"] + ["not-walked"])
        )
    error_paths = {
        item["path"]
        for item in errors
        if isinstance(item, dict) and isinstance(item.get("path"), str)
    }
    # Everything the walk could not fully account for, from all three places it
    # can be recorded: an explicit truncation, a scan error (which never adds a
    # truncation and can leave no entry at all), and a `not-walked` record.
    unknown_paths = (
        set(truncated)
        | error_paths
        | {
            entry["path"]
            for entry in entries
            if "not-walked" in (entry.get("size_qualifiers") or [])
        }
    )
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "engine": "disk-hygiene-python-1",
        "session_nonce": secrets.token_hex(16),
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "platform": os_key(),
        "target": str(target),
        "target_identity": target_identity,
        "target_logical_bytes": total_size,
        "target_reclaimable_local_bytes": reclaimable,
        "empty_directory_count": empty_directory_count(
            entries, error_paths=error_paths
        ),
        "policy": policy,
        "repositories": [str(repo) for repo in repositories],
        "repository_errors": repo_errors,
        "errors": errors,
        "max_depth": max_depth,
        "truncated_paths": sorted(truncated),
        "stdlib_shadowing": stdlib_shadowing,
        "children_rollup": children_rollup(
            entries,
            unknown_paths=unknown_paths,
            unwalked_reasons=unwalked_reasons,
        ),
        "entries": sorted(entries, key=lambda entry: entry["path"]),
    }
    if root_children is not None:
        payload["root_children_mode"] = True
        payload["root_children_selected"] = list(root_children)
    return payload


def bytecode_module_names(directory: Path) -> list[str] | None:
    """Module names a ``__pycache__`` holds bytecode for, from one scandir.

    ``None`` means the directory could not be listed, which is not the same as
    holding no bytecode.
    """
    try:
        with os.scandir(directory) as iterator:
            names = [entry.name for entry in iterator]
    except OSError:
        return None
    return sorted({name.split(".", 1)[0] for name in names if name.endswith(".pyc")})


def annotate_stdlib_shadowing(
    entries: list[dict[str, Any]], target: Path
) -> list[dict[str, Any]]:
    """Flag user-home-root ``*.py`` files whose stem is a stdlib module name.

    Advisory only: the annotation never adds a hint, a confidence, or any
    eligibility. Such a file shadows the stdlib module for a Python process
    whose ``sys.path[0]`` is the home directory (``-c``, ``-m``, the REPL),
    and the sibling ``__pycache__`` is rebuilt on the next import, so the
    report should point at the source rather than the cache. The home root
    sibling ``__pycache__`` entry gains ``bytecode_sources`` naming the
    modules its ``.pyc`` files were compiled from.
    """
    home = user_home()
    if home is None:
        return []
    try:
        home_relative = home.resolve().relative_to(target.resolve()).as_posix()
    except (OSError, ValueError):
        return []
    prefix = "" if home_relative == "." else f"{home_relative}/"
    # The home prefix comes from Path.home() while entry paths come from
    # scandir names, and on Windows the two may differ only in case.
    fold = str.casefold if sys.platform == "win32" else str
    folded_prefix = fold(prefix)
    children: dict[str, dict[str, Any]] = {}
    for entry in entries:
        path = entry["path"]
        if fold(path).startswith(folded_prefix) and "/" not in path[len(prefix) :]:
            children[path[len(prefix) :]] = entry
    stdlib = sys.stdlib_module_names
    shadows: dict[str, dict[str, Any]] = {}
    for name, entry in children.items():
        stem, dot, suffix = name.rpartition(".")
        if entry.get("kind") == "file" and dot and suffix == "py" and stem in stdlib:
            shadows[stem] = entry
    cache = children.get("__pycache__")
    compiled: list[str] | None = None
    if cache is not None and cache.get("kind") == "directory":
        compiled = bytecode_module_names(target / cache["path"])
        if compiled is not None:
            cache["bytecode_sources"] = [
                {
                    "module": module,
                    "source": children.get(f"{module}.py", {}).get("path"),
                    "shadows_stdlib": module in shadows,
                }
                for module in compiled
            ]
    findings = []
    for module, entry in sorted(shadows.items()):
        has_bytecode = compiled is not None and module in compiled
        entry["advisories"] = [
            {
                "id": "stdlib-module-shadow",
                "module": module,
                "reason": (
                    f"Shadows the standard-library module '{module}' for Python "
                    "started from the home directory with -c, -m, or the REPL. "
                    "Rename or move the file; deleting its bytecode cache does "
                    "not help, because the next import rebuilds it."
                ),
            }
        ]
        findings.append(
            {
                "path": entry["path"],
                "module": module,
                "bytecode_cache": cache["path"] if has_bytecode and cache else None,
            }
        )
    return findings


def annotate_tracked(
    entries: list[dict[str, Any]],
    target: Path,
    repositories: list[Path],
    truncated: list[str],
    errors: list[str],
) -> None:
    git = shutil.which("git")
    if repositories and not git:
        errors.append("git-not-found")
        return
    by_path = {entry["path"]: entry for entry in entries}
    for repo in repositories:
        # Scope the query to what --max-depth actually inventoried: a bare
        # `ls-files` walks the whole repository regardless of the requested
        # scan bound. `base` restricts to target's own subtree (or "." when
        # target IS the repo, or a nested repo was discovered beneath
        # target); each truncated directory is then subtracted so a
        # bounded profile/root audit never pulls an unbounded repo-wide
        # tracked-file list just to annotate a handful of scanned entries.
        try:
            base = target.relative_to(repo).as_posix()
        except ValueError:
            base = "."
        pathspecs = [base]
        for relative_truncated in truncated:
            try:
                exclude = (target / relative_truncated).relative_to(repo).as_posix()
            except ValueError:
                continue
            pathspecs.append(f":(exclude){exclude}")
        try:
            run = subprocess.run(
                [
                    git,
                    "-C",
                    str(repo),
                    "ls-files",
                    "-z",
                    "--cached",
                    "--recurse-submodules",
                    "--",
                    *pathspecs,
                ],
                capture_output=True,
                timeout=20,
                check=False,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{repo}: {exc}")
            continue
        if run.returncode != 0:
            errors.append(f"{repo}: git ls-files failed")
            continue
        for raw in run.stdout.split(b"\0"):
            if not raw:
                continue
            tracked = repo / os.fsdecode(raw)
            try:
                relative = tracked.relative_to(target).as_posix()
            except ValueError:
                continue
            entry = by_path.get(relative)
            if entry is not None:
                entry["protected_reasons"] = sorted(
                    set(entry["protected_reasons"] + ["vcs-tracked"])
                )


def entry_map(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    entries = snapshot.get("entries")
    if not isinstance(entries, list):
        raise HygieneError("snapshot entries must be an array")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise HygieneError("every snapshot entry must be an object with a path")
        if entry["path"] in result:
            raise HygieneError(f"duplicate snapshot entry: {entry['path']}")
        result[entry["path"]] = entry
    return result


def subtree_names(relative: str, names: Iterable[str]) -> set[str]:
    """The snapshot paths that ARE ``relative`` or sit beneath it.

    One containment rule for every lane that asks "what did the scan record for
    this candidate" — the preview's and handoff-verify's expected-path sets and
    the apply lane's removal list — so the three cannot disagree about a
    candidate's extent. Prefix matching is on the "/"-terminated name, so a
    sibling like ``cache-old`` is never read as a child of ``cache``.
    """
    return {
        name for name in names if name == relative or name.startswith(relative + "/")
    }


def overlaps_accepted_path(
    candidate: PurePosixPath, accepted: list[PurePosixPath]
) -> bool:
    """Whether ``candidate`` is, contains, or sits under an already-accepted path.

    One overlap rule for the two lanes that build an approved set (plan
    candidates and handoff paths), so neither can admit a pair the other would
    reject.
    """
    return any(
        candidate == prior or candidate in prior.parents or prior in candidate.parents
        for prior in accepted
    )


def overlaps_truncated(relative: str, truncated_paths: set[str]) -> bool:
    """Whether ``relative`` is, contains, or lives under a truncated scan path.

    Either direction disqualifies: a truncated ancestor means this path's own
    subtree was never inventoried, and a truncated descendant means part of it
    was not. Shared by preview and handoff-verify, which must agree on which
    candidates the snapshot cannot speak for.
    """
    return any(
        name == relative
        or name.startswith(relative + "/")
        or relative.startswith(name + "/")
        for name in truncated_paths
    )


def snapshot_protection_globs(snapshot: dict[str, Any]) -> list[str]:
    """Consumer protection globs a snapshot's policy recorded, strings only.

    Read from the snapshot rather than from live policy on purpose: an approved
    snapshot must stay previewable under the protections it was scanned with.
    Non-string members are dropped here so the three validation lanes cannot
    differ on how they tolerate a hand-edited policy block.
    """
    return [
        pattern
        for pattern in snapshot.get("policy", {}).get(
            "additional_protected_path_globs", []
        )
        if isinstance(pattern, str)
    ]


def validate_plan(
    plan: dict[str, Any], entries: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    if plan.get("version") != SCHEMA_VERSION:
        raise HygieneError("plan version must be 1")
    tier = plan.get("tier")
    if tier not in TIERS:
        raise HygieneError("plan tier must be high, medium, or low")
    candidates = plan.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise HygieneError("plan candidates must be a non-empty array")
    normalized: list[dict[str, Any]] = []
    seen: list[PurePosixPath] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise HygieneError("each candidate must be an object")
        required = {
            "path",
            "tier",
            "provenance",
            "reason",
            "evidence",
            "why_not_work_product",
            "risk",
            "owner",
        }
        if not required.issubset(candidate):
            raise HygieneError(
                f"candidate is missing: {', '.join(sorted(required - set(candidate)))}"
            )
        if candidate["tier"] != tier:
            raise HygieneError("one plan may contain exactly one confidence tier")
        relative = candidate["path"]
        if not isinstance(relative, str) or not relative or relative in {".", "/"}:
            raise HygieneError("candidate path must be a non-root relative path")
        pure = PurePosixPath(relative)
        if pure.is_absolute() or ".." in pure.parts or relative not in entries:
            raise HygieneError(
                f"candidate path is outside or absent from snapshot: {relative}"
            )
        if overlaps_accepted_path(pure, seen):
            raise HygieneError(f"candidate paths overlap: {relative}")
        seen.append(pure)
        if (
            not isinstance(candidate["provenance"], str)
            or not candidate["provenance"].strip()
        ):
            raise HygieneError(f"candidate needs provenance: {relative}")
        if not isinstance(candidate["reason"], str) or not candidate["reason"].strip():
            raise HygieneError(f"candidate needs a reason: {relative}")
        if (
            not isinstance(candidate["why_not_work_product"], str)
            or not candidate["why_not_work_product"].strip()
        ):
            raise HygieneError(f"candidate needs work-product analysis: {relative}")
        if not isinstance(candidate["risk"], str) or not candidate["risk"].strip():
            raise HygieneError(f"candidate needs a risk assessment: {relative}")
        if (
            not isinstance(candidate["evidence"], list)
            or not candidate["evidence"]
            or not all(
                isinstance(value, str) and value.strip()
                for value in candidate["evidence"]
            )
        ):
            raise HygieneError(
                f"candidate needs at least one evidence item: {relative}"
            )
        owner = candidate["owner"]
        if not isinstance(owner, str) or not owner:
            raise HygieneError(
                f"candidate owner must be named or unmanaged: {relative}"
            )
        if owner != "unmanaged":
            # Managed candidates are permanently report-only (preview and apply
            # block them unconditionally). This gate exists so the report can
            # name a proven-runnable native-GC command, and so managed state
            # whose native GC is not even eligible is never proposed at all.
            native = candidate.get("native_gc_evidence")
            if (
                not isinstance(native, dict)
                or native.get("result") != "eligible"
                or not isinstance(native.get("command"), str)
                or not native["command"].strip()
            ):
                raise HygieneError(
                    f"managed candidate lacks native-GC eligibility evidence: {relative}"
                )
        normalized.append(candidate)
    return normalized


def validate_handoff_paths(
    payload: dict[str, Any], entries: dict[str, dict[str, Any]]
) -> list[str]:
    """Structurally validate a manual-handoff approved-path list.

    Same containment rules as plan candidates (relative, non-root, no
    traversal, present in the snapshot, non-overlapping) without the plan's
    tier/evidence envelope: the handoff list is the human-approved exact path
    list, and the audit report — not this file — carries the evidence.
    """
    if payload.get("version") != SCHEMA_VERSION:
        raise HygieneError("paths file version must be 1")
    paths = payload.get("paths")
    if not isinstance(paths, list) or not paths:
        raise HygieneError("paths must be a non-empty array")
    normalized: list[str] = []
    seen: list[PurePosixPath] = []
    for relative in paths:
        if not isinstance(relative, str) or not relative or relative in {".", "/"}:
            raise HygieneError("approved path must be a non-root relative path")
        pure = PurePosixPath(relative)
        if pure.is_absolute() or ".." in pure.parts or relative not in entries:
            raise HygieneError(
                f"approved path is outside or absent from snapshot: {relative}"
            )
        if overlaps_accepted_path(pure, seen):
            raise HygieneError(f"approved paths overlap: {relative}")
        seen.append(pure)
        normalized.append(relative)
    return normalized


def validate_vcs_evidence(
    payload: dict[str, Any], approved: list[str]
) -> dict[str, dict[str, Any]]:
    """Validate proof-source locations; live commands establish every fact."""
    if set(payload) != {"version", "repositories"}:
        raise HygieneError("VCS evidence must contain exactly version/repositories")
    if payload.get("version") != SCHEMA_VERSION:
        raise HygieneError("VCS evidence version must be 1")
    repositories = payload.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise HygieneError("VCS evidence repositories must be a non-empty array")
    approved_paths = [PurePosixPath(value) for value in approved]
    normalized: dict[str, dict[str, Any]] = {}
    for item in repositories:
        if not isinstance(item, dict) or set(item) != {
            "path",
            "remote",
            "stash_copies",
        }:
            raise HygieneError(
                "each VCS evidence repository must contain exactly "
                "path/remote/stash_copies"
            )
        relative = item["path"]
        pure = PurePosixPath(relative) if isinstance(relative, str) else None
        if (
            pure is None
            or not relative
            or relative in {".", "/"}
            or pure.is_absolute()
            or ".." in pure.parts
            or not any(path == pure or path in pure.parents for path in approved_paths)
        ):
            raise HygieneError(
                f"VCS evidence repository is outside approved paths: {relative}"
            )
        if relative in normalized:
            raise HygieneError(f"duplicate VCS evidence repository: {relative}")
        remote = item["remote"]
        if remote is not None and (
            not isinstance(remote, str)
            or not remote
            or remote.startswith("-")
            or any(character.isspace() for character in remote)
        ):
            raise HygieneError(
                f"VCS evidence remote must be null or a literal name: {relative}"
            )
        copies = item["stash_copies"]
        if (
            not isinstance(copies, list)
            or not all(
                isinstance(value, str)
                and value
                and Path(value).expanduser().is_absolute()
                for value in copies
            )
            or len(set(copies)) != len(copies)
        ):
            raise HygieneError(
                f"stash_copies must be unique absolute paths: {relative}"
            )
        normalized[relative] = {
            "path": relative,
            "remote": remote,
            "stash_copies": copies,
        }
    return normalized


def current_descendants(
    root: Path, candidate: Path, *, opaque_git_metadata: bool = False
) -> set[str]:
    paths: set[str] = set()
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        raise HygieneError(mount_error)

    def visit(path: Path) -> None:
        paths.add(path.relative_to(root).as_posix())
        mounted, error = mount_state(path, known_mounts)
        if error:
            raise HygieneError(error)
        if (
            is_linkish(path)
            or not path.is_dir()
            or mounted
            or (opaque_git_metadata and path.name.casefold() == GIT_METADATA_NAME)
        ):
            return
        with os.scandir(path) as iterator:
            children = [Path(entry.path) for entry in iterator]
        for child in children:
            visit(child)

    visit(candidate)
    return paths


def same_identity(path: Path, entry: dict[str, Any]) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    return same_stat_identity(info, entry)


def same_stat_identity(info: os.stat_result, entry: dict[str, Any]) -> bool:
    if is_linkish_stat(info):
        kind = "link"
    elif stat.S_ISDIR(info.st_mode):
        kind = "directory"
    elif stat.S_ISREG(info.st_mode):
        kind = "file"
    else:
        kind = "other"
    checks = (
        kind == entry.get("kind"),
        info.st_size == entry.get("stat_size"),
        info.st_mtime_ns == entry.get("mtime_ns"),
        info.st_dev == entry.get("device"),
        info.st_ino == entry.get("inode"),
        stat.S_IFMT(info.st_mode) == entry.get("mode"),
    )
    # File hard-link count is part of reclaimability. A new name after scan
    # leaves size/mtime/dev/ino/mode unchanged, so identity must notice nlink
    # or preview/apply would still treat the full size as reclaimable.
    if kind == "file":
        checks = (*checks, int(info.st_nlink) == entry.get("nlink"))
    return all(checks)


def same_object_identity(info: os.stat_result, entry: dict[str, Any]) -> bool:
    """Compare stable object identity without mutable directory size/timestamps."""
    return all(
        (
            stat.S_ISDIR(info.st_mode) and entry.get("kind") == "directory",
            info.st_dev == entry.get("device"),
            info.st_ino == entry.get("inode"),
            stat.S_IFMT(info.st_mode) == entry.get("mode"),
        )
    )


def same_open_object(left: os.stat_result, right: os.stat_result) -> bool:
    """Compare stable identity fields for two observations of one object."""
    return all(
        (
            left.st_dev == right.st_dev,
            left.st_ino == right.st_ino,
            stat.S_IFMT(left.st_mode) == stat.S_IFMT(right.st_mode),
        )
    )


def same_removal_identity(path: Path, entry: dict[str, Any]) -> bool:
    """Allow expected directory metadata churn while preserving object identity."""
    try:
        info = path.lstat()
    except OSError:
        return False
    if entry.get("kind") == "directory":
        return same_object_identity(info, entry)
    return same_stat_identity(info, entry)


def marker_exists(path: Path, errors: list[str]) -> bool:
    try:
        path.lstat()
        return True
    except FileNotFoundError:
        return False
    except OSError as exc:
        errors.append(f"{path}: marker state unverified: {exc}")
        return False


def discover_current_repositories(
    target: Path, candidate: Path
) -> tuple[list[Path], list[str]]:
    """Rediscover enclosing and nested repository markers from live state."""
    marker_roots: set[Path] = set()
    errors: list[str] = []
    current = candidate if candidate.is_dir() else candidate.parent
    while True:
        git_marker = current / ".git"
        if marker_exists(git_marker, errors):
            marker_roots.add(current)
        if any(marker_exists(current / name, errors) for name in (".hg", ".svn")):
            errors.append(f"{current}: non-Git VCS state is not independently verified")
        if current.parent == current:
            break
        current = current.parent

    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        errors.append(mount_error)

    def visit(directory: Path) -> None:
        try:
            with os.scandir(directory) as iterator:
                children = list(iterator)
        except OSError as exc:
            errors.append(f"{directory}: {exc}")
            return
        names = {entry.name.casefold() for entry in children}
        if names & VCS_NAMES:
            if ".git" not in names:
                errors.append(
                    f"{directory}: non-Git VCS state is not independently verified"
                )
            marker_roots.add(directory)
            return
        for entry in children:
            path = Path(entry.path)
            mounted, current_mount_error = mount_state(path, known_mounts)
            if current_mount_error:
                errors.append(current_mount_error)
                return
            if (
                entry.is_dir(follow_symlinks=False)
                and not is_linkish(path)
                and not mounted
            ):
                visit(path)

    if candidate.is_dir() and not is_linkish(candidate):
        visit(candidate)

    git = shutil.which("git")
    if not git:
        return sorted(marker_roots), (["git-not-found"] if marker_roots else errors)

    run = subprocess.run(
        [
            git,
            "-C",
            str(candidate.parent if candidate.is_file() else candidate),
            "rev-parse",
            "--show-toplevel",
        ],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if run.returncode == 0 and run.stdout.strip():
        marker_roots.add(Path(run.stdout.strip()).resolve())
    elif marker_roots:
        errors.append("git-worktree-state-unverified")
    return sorted(marker_roots), errors


def tracked_blocker(candidate: Path, target: Path) -> str | None:
    repositories, errors = discover_current_repositories(target, candidate)
    if errors:
        return "vcs-state-unverified"
    git = shutil.which("git")
    if repositories and not git:
        return "git-not-found"
    for repo in repositories:
        if is_within(candidate, repo):
            relative = candidate.relative_to(repo).as_posix()
            pathspec = relative + "/" if candidate.is_dir() else relative
        elif is_within(repo, candidate):
            pathspec = "."
        else:
            continue
        run = subprocess.run(
            [git, "-C", str(repo), "ls-files", "-z", "--cached", "--", pathspec],
            capture_output=True,
            timeout=20,
            check=False,
        )
        if run.returncode != 0:
            return "vcs-state-unverified"
        if run.stdout:
            return "vcs-tracked-content"
    return None


def run_git(repo: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    git = shutil.which("git")
    if not git:
        raise HygieneError("git-not-found")
    environment = os.environ.copy()
    # `git status` may otherwise refresh the index and write an optional
    # lock/index update. Evidence collection is a read-only handoff operation.
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    return subprocess.run(
        [git, "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
        env=environment,
    )


def github_remote_repository(url: str) -> tuple[str, str] | None:
    match = GITHUB_REMOTE_RE.fullmatch(url.strip())
    if match is None:
        return None
    repository = match.group("repo")
    if repository.casefold().endswith(".git"):
        repository = repository[:-4]
    if not repository:
        return None
    return match.group("owner"), repository


def verify_github_remote_head(
    repo: Path, remote: str, sha: str
) -> tuple[bool, dict[str, str]]:
    """Confirm one local head through the GitHub commits API, never by ref name."""
    # Read the literal declaration rather than `git remote get-url`, which
    # expands global `insteadOf` transport rewrites and can hide github.com.
    remote_url = run_git(repo, "config", "--get", f"remote.{remote}.url")
    if remote_url.returncode != 0 or not remote_url.stdout.strip():
        return False, {"sha": sha, "error": "remote-url-unverified"}
    coordinates = github_remote_repository(remote_url.stdout.strip())
    if coordinates is None:
        return False, {"sha": sha, "error": "remote-provider-unsupported"}
    gh = shutil.which("gh")
    if not gh:
        return False, {"sha": sha, "error": "gh-not-found"}
    owner, repository = coordinates
    try:
        checked = subprocess.run(
            [
                gh,
                "api",
                "--method",
                "GET",
                f"repos/{owner}/{repository}/commits/{sha}",
                "--jq",
                ".sha",
            ],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, {"sha": sha, "error": f"provider-query-failed: {exc}"}
    confirmed = (
        checked.returncode == 0 and checked.stdout.strip().casefold() == sha.casefold()
    )
    detail = {
        "sha": sha,
        "remote": remote,
        "repository": f"{owner}/{repository}",
    }
    if not confirmed:
        detail["error"] = "remote-head-unconfirmed"
    return confirmed, detail


def local_head_shas(repo: Path) -> tuple[list[dict[str, str]], str | None]:
    """Return every local branch head, plus a detached HEAD when present."""
    branches = run_git(
        repo, "for-each-ref", "--format=%(refname:short)%09%(objectname)", "refs/heads"
    )
    if branches.returncode != 0:
        return [], "local-heads-unverified"
    heads: list[dict[str, str]] = []
    for line in branches.stdout.splitlines():
        try:
            name, sha = line.split("\t", 1)
        except ValueError:
            return [], "local-heads-unverified"
        if not re.fullmatch(r"[0-9a-fA-F]{40,64}", sha):
            return [], "local-heads-unverified"
        heads.append({"name": name, "sha": sha.casefold()})
    symbolic = run_git(repo, "symbolic-ref", "-q", "HEAD")
    if symbolic.returncode not in {0, 1}:
        return [], "local-heads-unverified"
    if symbolic.returncode == 1:
        detached = run_git(repo, "rev-parse", "--verify", "HEAD^{commit}")
        sha = detached.stdout.strip()
        if detached.returncode != 0 or not re.fullmatch(r"[0-9a-fA-F]{40,64}", sha):
            return [], "local-heads-unverified"
        heads.append({"name": "HEAD", "sha": sha.casefold()})
    unique = {(item["name"], item["sha"]): item for item in heads}
    return sorted(unique.values(), key=lambda item: (item["name"], item["sha"])), None


def stash_shas(repo: Path) -> tuple[list[str], str | None]:
    stashes = run_git(repo, "stash", "list", "--format=%H")
    if stashes.returncode != 0:
        return [], "stashes-unverified"
    result = [value.casefold() for value in stashes.stdout.splitlines() if value]
    if not all(re.fullmatch(r"[0-9a-fA-F]{40,64}", value) for value in result):
        return [], "stashes-unverified"
    return result, None


def verify_stash_copy(
    source_candidate: Path,
    copy_value: str,
    approved_paths: list[Path],
    source_common_dir: Path,
) -> tuple[Path | None, set[str], str | None]:
    copy_input = Path(copy_value).expanduser().absolute()
    if has_linkish_component(copy_input):
        return None, set(), "stash-copy-link-or-reparse"
    try:
        copy = copy_input.resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    if (
        not copy.is_dir()
        or is_within(copy, source_candidate)
        or any(is_within(copy, approved) for approved in approved_paths)
    ):
        return None, set(), "stash-copy-not-independent"
    top = run_git(copy, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or not top.stdout.strip():
        return None, set(), "stash-copy-not-a-worktree"
    try:
        top_path = Path(top.stdout.strip()).resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    if top_path != copy:
        return None, set(), "stash-copy-root-mismatch"
    common = run_git(copy, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common.returncode != 0 or not common.stdout.strip():
        return None, set(), "stash-copy-unreadable"
    try:
        copy_common = Path(common.stdout.strip()).resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    # Linked worktrees share the source common dir (and therefore stash refs).
    # Reject any copy whose Git storage is the source store or lives under the
    # candidate about to be deleted.
    if (
        copy_common == source_common_dir
        or is_within(copy_common, source_common_dir)
        or is_within(source_common_dir, copy_common)
        or is_within(copy_common, source_candidate)
    ):
        return None, set(), "stash-copy-not-independent"
    stashes, error = stash_shas(copy)
    return copy, set(stashes), error


def checkout_repository_paths(current_paths: set[str], target: Path) -> set[Path]:
    repositories: set[Path] = set()
    for relative in current_paths:
        pure = PurePosixPath(relative)
        if pure.name.casefold() != GIT_METADATA_NAME:
            continue
        repository_relative = pure.parent
        if str(repository_relative) == ".":
            continue
        repositories.add(
            target.joinpath(*repository_relative.parts).resolve(strict=False)
        )
    return repositories


def verify_vcs_checkout_evidence(
    target: Path,
    candidate: Path,
    current_paths: set[str],
    configurations: dict[str, dict[str, Any]],
    approved: list[str],
) -> dict[str, Any]:
    """Verify the complete live evidence bundle before relaxing Git blockers."""
    gates: dict[str, dict[str, Any]] = {
        name: {"status": "failed"} for name in VCS_EVIDENCE_GATE_NAMES
    }
    gates["exact-path-operator-approval"] = {
        "status": "passed",
        "source": "handoff-paths",
        "path": candidate.relative_to(target).as_posix(),
    }
    blockers: set[str] = set()
    live_repositories = checkout_repository_paths(current_paths, target)
    configured_repositories = {
        target.joinpath(*PurePosixPath(relative).parts).resolve(strict=False)
        for relative in configurations
    }
    if (
        not live_repositories
        or live_repositories != configured_repositories
        or any(not is_within(repo, candidate) for repo in live_repositories)
    ):
        blockers.add("vcs-evidence-repository-set-mismatch")

    status_details: list[dict[str, Any]] = []
    head_details: list[dict[str, Any]] = []
    stash_details: list[dict[str, Any]] = []
    status_passed = not blockers
    heads_passed = not blockers
    stashes_passed = not blockers
    approved_paths = [
        target.joinpath(*PurePosixPath(value).parts).resolve(strict=False)
        for value in approved
    ]
    for repo in sorted(live_repositories & configured_repositories):
        relative = repo.relative_to(target).as_posix()
        config = configurations[relative]
        repository_detail: dict[str, Any] = {"repository": relative}

        top = run_git(repo, "rev-parse", "--show-toplevel")
        common = run_git(
            repo, "rev-parse", "--path-format=absolute", "--git-common-dir"
        )
        try:
            top_path = Path(top.stdout.strip()).resolve(strict=True)
            common_path = Path(common.stdout.strip()).resolve(strict=True)
        except OSError:
            top_path = Path()
            common_path = Path()
        if (
            top.returncode != 0
            or common.returncode != 0
            or top_path != repo
            or not is_within(common_path, candidate)
        ):
            blockers.add("vcs-evidence-git-boundary-unverified")
            status_passed = heads_passed = stashes_passed = False
            repository_detail["status"] = "git-boundary-unverified"
            status_details.append(repository_detail)
            continue

        status = run_git(
            repo,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--ignored=matching",
            "--ignore-submodules=none",
        )
        clean = status.returncode == 0 and not status.stdout
        repository_detail["status"] = "clean" if clean else "not-clean-or-unverified"
        status_details.append(repository_detail)
        if not clean:
            status_passed = False
            blockers.add("vcs-evidence-status-not-clean")

        heads, head_error = local_head_shas(repo)
        if head_error:
            heads_passed = False
            blockers.add("vcs-evidence-local-heads-unverified")
        elif heads and config["remote"] is None:
            heads_passed = False
            blockers.add("vcs-evidence-remote-not-declared")
        else:
            for head in heads:
                confirmed, detail = verify_github_remote_head(
                    repo, config["remote"], head["sha"]
                )
                detail["repository_path"] = relative
                detail["local_head"] = head["name"]
                head_details.append(detail)
                if not confirmed:
                    heads_passed = False
                    blockers.add("vcs-evidence-remote-head-unconfirmed")

        stashes, stash_error = stash_shas(repo)
        if stash_error:
            stashes_passed = False
            blockers.add("vcs-evidence-stashes-unverified")
            continue
        copy_stashes: dict[str, set[str]] = {}
        for copy_value in config["stash_copies"]:
            try:
                copy, copy_values, copy_error = verify_stash_copy(
                    candidate, copy_value, approved_paths, common_path
                )
            except (OSError, subprocess.SubprocessError, HygieneError):
                copy, copy_values, copy_error = None, set(), "stash-copy-unverified"
            if copy_error:
                stashes_passed = False
                blockers.add("vcs-evidence-stash-copy-unverified")
                continue
            assert copy is not None
            copy_stashes[str(copy)] = copy_values
        for sha in stashes:
            duplicated_at = sorted(
                path for path, values in copy_stashes.items() if sha in values
            )
            stash_details.append(
                {
                    "repository_path": relative,
                    "sha": sha,
                    "duplicated_at": duplicated_at,
                }
            )
            if not duplicated_at:
                stashes_passed = False
                blockers.add("vcs-evidence-stash-not-duplicated")

    gates["git-status-porcelain-empty"] = {
        "status": "passed" if status_passed else "failed",
        "repositories": status_details,
    }
    gates["all-local-heads-on-remote"] = {
        "status": "passed" if heads_passed else "failed",
        "heads": head_details,
    }
    gates["all-stashes-duplicated"] = {
        "status": "passed" if stashes_passed else "failed",
        "stashes": stash_details,
    }
    verified = not blockers and all(
        gates[name]["status"] == "passed" for name in VCS_EVIDENCE_GATE_NAMES
    )
    return {
        "status": "verified" if verified else "failed",
        "gates": gates,
        "blockers": sorted(blockers),
        "repositories": sorted(
            repo.relative_to(target).as_posix() for repo in live_repositories
        ),
    }


def evidence_adjusted_protections(
    protections: Iterable[str],
    path: Path,
    target: Path,
    repository_paths: Iterable[Path],
    exact_names: set[str],
) -> list[str]:
    """Relax only Git-marker protections, never another protected-name class."""
    adjusted = set(protections)
    metadata_roots = [repo / GIT_METADATA_NAME for repo in repository_paths]
    if not any(is_within(path, metadata) for metadata in metadata_roots):
        return sorted(adjusted)
    adjusted.discard("vcs-metadata")
    current = path
    non_git_protected_name = False
    while is_within(current, target):
        if current.name.casefold() != GIT_METADATA_NAME and has_protected_name(
            current, exact_names
        ):
            non_git_protected_name = True
            break
        if current == target:
            break
        current = current.parent
    if not non_git_protected_name:
        adjusted.discard("baseline-protected-name")
    return sorted(adjusted)


def execution_blockers() -> list[str]:
    """Return reasons why the mutation lane cannot be proven safe on this host."""
    if os_key() != "linux":
        return ["execution-platform-unsupported"]
    required = (os.open, os.stat, os.unlink, os.rmdir)
    if not all(function in os.supports_dir_fd for function in required):
        return ["dirfd-anchoring-unavailable"]
    if os.scandir not in os.supports_fd:
        return ["dirfd-anchoring-unavailable"]
    if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        return ["dirfd-anchoring-unavailable"]
    _, error = linux_mount_points()
    return ["mount-state-unverified"] if error else []


def windows_handle_state(path: Path) -> tuple[str, str | None]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    create_file = kernel32.CreateFileW
    create_file.argtypes = [
        ctypes.c_wchar_p,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_void_p,
    ]
    create_file.restype = ctypes.c_void_p
    flags = FILE_FLAG_BACKUP_SEMANTICS if path.is_dir() else FILE_ATTRIBUTE_NORMAL
    # Share mode 0 requests exclusive access; an already-open file fails the probe.
    handle = create_file(str(path), 0, 0, None, OPEN_EXISTING, flags, None)
    invalid = ctypes.c_void_p(-1).value
    if handle == invalid:
        error = ctypes.get_last_error()
        if error in {32, 33}:
            return "open", f"win32-error-{error}"
        if error in {5, 1314}:
            return "needs_elevation", f"win32-error-{error}"
        return "unverified", f"win32-error-{error}"
    kernel32.CloseHandle(ctypes.c_void_p(handle))
    return "clear", None


def posix_handle_state(path: Path) -> tuple[str, str | None]:
    lsof = shutil.which("lsof")
    if not lsof:
        return "unverified", "lsof-not-found"
    command = [lsof, "-Fn"] + (
        ["+D", str(path)] if path.is_dir() else ["--", str(path)]
    )
    try:
        run = subprocess.run(
            command, capture_output=True, text=True, timeout=20, check=False
        )
    except subprocess.TimeoutExpired:
        return "unverified", "lsof-timeout"
    if run.stderr.strip():
        return "unverified", f"lsof-diagnostic: {run.stderr.strip()[:200]}"
    if run.returncode == 0 and run.stdout.strip():
        return "open", "lsof-reported-open-file"
    if run.returncode == 1 and not run.stdout.strip():
        return "clear", None
    return "unverified", f"lsof-exit-{run.returncode}"


def handle_state(path: Path) -> tuple[str, str | None]:
    return windows_handle_state(path) if os.name == "nt" else posix_handle_state(path)


def handle_state_contest_reason(state: str, detail: str | None) -> str | None:
    """The contested reason a non-clear handle probe carries, or None when clear.

    Shared by the two read-only verdict lanes (approved paths and emptied
    containers) so an open handle, a denial, and an unverifiable probe cannot
    be worded differently depending on which one observed it.
    """
    if state == "clear":
        return None
    if state == "needs_elevation":
        return "needs-elevation"
    stem = "live-handle" if state == "open" else "handle-state-unverified"
    return stem + (f": {detail}" if detail else "")


def candidate_handle_state(
    target: Path, path: Path, expected_paths: set[str]
) -> tuple[str, str | None]:
    if os.name != "nt":
        return handle_state(path)
    for relative in sorted(expected_paths):
        state, detail = handle_state(target.joinpath(*PurePosixPath(relative).parts))
        if state != "clear":
            return state, f"{relative}: {detail or state}"
    return "clear", None


def snapshot_digest(snapshot: dict[str, Any]) -> str:
    canonical = json.dumps(snapshot, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(canonical).hexdigest()


def approval_token(snapshot: dict[str, Any], plan: dict[str, Any]) -> str:
    material = {
        "snapshot": snapshot_digest(snapshot),
        "nonce": snapshot.get("session_nonce"),
        "tier": plan.get("tier"),
        "candidates": plan.get("candidates"),
    }
    return hashlib.sha256(
        json.dumps(material, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()[:24]


def resolve_snapshot_target(snapshot: dict[str, Any]) -> tuple[Path, set[Path]]:
    """Re-validate the snapshot's target root against live state and return it.

    Shared by preview and handoff-verify: both must refuse a snapshot whose
    target root drifted, became a link, a mount point, an OS-managed root, or a
    protected shell folder since the scan. The root is held to the same stable
    device/inode/type identity as directory candidates, not to stat identity:
    a directory's mtime and size flip whenever any direct child is added or
    removed, so any unrelated write into a live target during the approval
    window would otherwise abort the run.

    Root-children mode is the sole exception to the OS-managed-root veto: the
    snapshot target is the volume root, but the inventory only covers explicitly
    selected immediate children — never a recursive walk of the root itself.
    """
    if (
        snapshot.get("schema_version") != SCHEMA_VERSION
        or snapshot.get("engine") != "disk-hygiene-python-1"
    ):
        raise HygieneError("unsupported snapshot version")
    target_input = Path(snapshot.get("target", "")).absolute()
    if has_linkish_component(target_input):
        raise HygieneError("snapshot target now traverses a link or reparse point")
    target = target_input.resolve(strict=True)
    known_mounts, mount_error = linux_mount_points()
    target_mounted, target_mount_error = mount_state(target, known_mounts)
    if mount_error or target_mount_error:
        raise HygieneError("snapshot target mount state is unverified")
    root_children_mode = bool(snapshot.get("root_children_mode"))
    if is_os_managed_target(target) and not root_children_mode:
        raise HygieneError("snapshot target is now an OS-managed root")
    if root_children_mode:
        if not is_volume_root(target) or not is_os_managed_target(target):
            raise HygieneError(
                "root-children snapshot target must remain an OS-managed volume root"
            )
        selected = snapshot.get("root_children_selected")
        if not isinstance(selected, list) or not selected:
            raise HygieneError("root-children snapshot is missing its selection")
        if any(not isinstance(name, str) or not name for name in selected):
            raise HygieneError("root-children snapshot selection is invalid")
    if target_mounted and not is_volume_root(target):
        raise HygieneError("snapshot target is a mount point")
    if has_protected_path_component(target, baseline_protected_names()):
        raise HygieneError(
            "snapshot target is now a protected shell-folder or profile-hive root"
        )
    identity = snapshot.get("target_identity", {})
    try:
        info = target.lstat()
    except OSError as exc:
        raise HygieneError(f"target root state is unverified: {exc}")
    if not same_object_identity(info, identity):
        raise HygieneError("target root was replaced since the snapshot")
    return target, known_mounts


def preview(snapshot: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    baseline_exact_names = baseline_protected_names()
    target, known_mounts = resolve_snapshot_target(snapshot)
    entries = entry_map(snapshot)
    candidates = validate_plan(plan, entries)
    truncated_paths = {
        value for value in snapshot.get("truncated_paths", []) if isinstance(value, str)
    }
    exact_names = baseline_exact_names | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    globs = snapshot_protection_globs(snapshot)
    root_children_sensitive = root_child_names_case_sensitive(snapshot.get("platform"))

    def root_child_key(name: str) -> str:
        return name if root_children_sensitive else name.casefold()

    selected_root_children = {
        root_child_key(name)
        for name in snapshot.get("root_children_selected", [])
        if isinstance(name, str)
    }

    results = []
    blocked = False
    for candidate in candidates:
        relative = candidate["path"]
        path = target.joinpath(*PurePosixPath(relative).parts)
        blockers = hard_protection(path, target, exact_names, known_mounts)
        blockers.extend(execution_blockers())
        if candidate["owner"] != "unmanaged":
            blockers.append("native-managed-report-only")
        if overlaps_truncated(relative, truncated_paths):
            blockers.append("truncated-not-inventoried")
        if snapshot.get("root_children_mode"):
            parts = PurePosixPath(relative).parts
            if not parts or root_child_key(parts[0]) not in selected_root_children:
                blockers.append("outside-root-children-selection")
        expected_paths = subtree_names(relative, entries)
        if "truncated-not-inventoried" in blockers:
            # A truncated candidate is already hard-blocked from planning above;
            # walking its live subtree here would be the same unbounded
            # traversal --max-depth exists to avoid, for a candidate that can
            # never become approvable anyway.
            current_paths = expected_paths
        else:
            try:
                current_paths = current_descendants(target, path)
            except PermissionError:
                current_paths = set()
                blockers.append("needs-elevation")
            except (OSError, HygieneError):
                current_paths = set()
                blockers.append("filesystem-state-unverified")
        if current_paths != expected_paths:
            blockers.append("changed-since-scan")
        for name in expected_paths:
            entry = entries[name]
            current = target.joinpath(*PurePosixPath(name).parts)
            if not same_identity(current, entry):
                blockers.append("changed-since-scan")
            blockers.extend(hard_protection(current, target, exact_names, known_mounts))
            relative_current = current.relative_to(target).as_posix()
            if any(glob_matches(relative_current, pattern) for pattern in globs):
                blockers.append("consumer-protected-path")
        if "truncated-not-inventoried" in blockers:
            # Same rationale as the current_descendants short-circuit above: a
            # truncated candidate can never leave "blocked" state, so skip the
            # live VCS-repository walk (discover_current_repositories, an
            # unbounded recursive scandir) and the live handle-state probe
            # (POSIX's `lsof +D`, also unbounded) instead of running them
            # against a subtree --max-depth was never asked to inventory.
            state, detail = "unverified", "truncated-not-inventoried"
        else:
            vcs = tracked_blocker(path, target)
            if vcs:
                blockers.append(vcs)
            state, detail = candidate_handle_state(target, path, expected_paths)
            if state != "clear":
                blockers.append(
                    {"open": "live-handle", "needs_elevation": "needs-elevation"}.get(
                        state, "handle-state-unverified"
                    )
                )
        blockers = sorted(set(blockers))
        candidate_entry = entries[relative]
        logical_bytes = sum(
            entry_logical_file_bytes(entries[name]) for name in expected_paths
        )
        reclaimable_bytes = sum(
            value
            for name in expected_paths
            if (value := entry_reclaimable_local_bytes(entries[name])) is not None
        )
        results.append(
            {
                "path": relative,
                "tier": plan["tier"],
                "provenance": candidate["provenance"],
                "reason": candidate["reason"],
                "why_not_work_product": candidate["why_not_work_product"],
                "risk": candidate["risk"],
                "empty_directory": entry_is_empty_directory(candidate_entry, entries),
                "logical_bytes": logical_bytes,
                "reclaimable_local_bytes": reclaimable_bytes,
                "handle_state": state,
                "handle_detail": detail,
                "blockers": blockers,
            }
        )
        blocked = blocked or bool(blockers)
    payload = {
        "status": "blocked" if blocked else "ready-for-explicit-approval",
        "tier": plan["tier"],
        "target": str(target),
        "candidates": results,
        "empty_directories": sum(1 for item in results if item["empty_directory"]),
        "logical_bytes": sum(item["logical_bytes"] for item in results),
        "reclaimable_local_bytes": sum(
            item["reclaimable_local_bytes"] for item in results
        ),
        "approval_token": None if blocked else approval_token(snapshot, plan),
        "warning": (
            "Safe tidiness is the primary objective; reclaimable bytes are "
            "secondary. Approval is valid only for this tier, exact plan, and "
            "snapshot. Re-preview after any change."
        ),
    }
    return payload


def removal_sort_key(relative: str) -> tuple[int, str]:
    """The apply lane's bottom-up ordering key: deeper paths sort later.

    Used with ``reverse=True`` so the deepest path comes first. The apply lane
    needs it because ``anchored_remove`` only ever calls ``os.rmdir`` on a
    directory it has just proven empty, so a container must be visited after
    every one of its children. ``emptied_container_order`` reuses the same key
    for the same structural reason — a parent is decided after its children —
    without inheriting the mutation the apply lane performs.
    """
    return (len(PurePosixPath(relative).parts), relative)


def emptied_container_order(
    settled: Iterable[str], entries: dict[str, dict[str, Any]]
) -> list[str]:
    """Inventoried directories the settled removals leave empty, deepest first.

    ``settled`` is the set of paths that are being removed (or are already
    gone). A snapshot directory qualifies when it is not itself part of that
    removal, the scan actually walked it, and every one of its inventoried
    immediate children is either removed or itself qualifies — the cascade.

    Decision is one pass over the inventory in decreasing depth. Every parent is
    strictly shallower than its children, so the pass reaches a container only
    after each of its children has already been decided; no fixed-point loop is
    involved and none needs a bound, which is what makes a cascade of any depth
    resolve in a single round.

    This names containers. It never removes one: the ordering is the part shared
    with the apply lane, the mutation is not.
    """
    removed: set[str] = set()
    for relative in settled:
        removed |= subtree_names(relative, entries)
    children: dict[str, set[str]] = {}
    for name in entries:
        parent = name.rsplit("/", 1)[0] if "/" in name else ""
        if parent:
            # A top-level entry's parent is the scan target itself, which is
            # never a candidate for removal — hard_protection calls it
            # target-root — so it is deliberately absent from this map.
            children.setdefault(parent, set()).add(name)
    emptied: set[str] = set()
    ordered: list[str] = []
    for name in sorted(children, key=removal_sort_key, reverse=True):
        entry = entries.get(name)
        if entry is None or entry.get("kind") != "directory" or name in removed:
            continue
        if "not-walked" in (entry.get("size_qualifiers") or []):
            # The scan never enumerated this directory, so its inventoried
            # children are not known to be all of its children. A coverage gap
            # is not emptiness (the rule entry_is_empty_directory already
            # applies to the scan's own tidiness count).
            continue
        if all(child in removed or child in emptied for child in children[name]):
            emptied.add(name)
            ordered.append(name)
    return ordered


def verify_emptied_container(
    target: Path,
    relative: str,
    entries: dict[str, dict[str, Any]],
    exact_names: set[str],
    known_mounts: set[Path],
    globs: list[str],
    truncated_paths: set[str],
) -> dict[str, Any]:
    """Verdict for one container the approved removals would empty, read-only.

    The categorical checks only. The VCS-evidence exception deliberately has no
    counterpart here: ``validate_vcs_evidence`` admits repositories at or under
    an approved path, and a container is always a strict ancestor of one, so
    evidence never covers the container itself and tracked content keeps it
    contested.
    """
    path = target.joinpath(*PurePosixPath(relative).parts)
    drifted: set[str] = set()
    contested: set[str] = set()
    try:
        info = path.lstat()
    except FileNotFoundError:
        return {"path": relative, "verdict": "gone", "reasons": ["no-longer-present"]}
    except PermissionError:
        return {
            "path": relative,
            "verdict": "contested",
            "reasons": ["needs-elevation"],
        }
    except OSError:
        return {
            "path": relative,
            "verdict": "contested",
            "reasons": ["filesystem-state-unverified"],
        }
    # Object identity, not stat identity: a directory's mtime and size change
    # every time a child is added or removed, and removing this container's
    # children is the whole premise. same_stat_identity would report the
    # container drifted for the very removals that empty it.
    if not same_object_identity(info, entries[relative]):
        drifted.add("changed-since-scan")
    contested.update(hard_protection(path, target, exact_names, known_mounts))
    if any(glob_matches(relative, pattern) for pattern in globs):
        contested.add("consumer-protected-path")
    expected_paths = subtree_names(relative, entries)
    current_paths: set[str] | None = None
    if overlaps_truncated(relative, truncated_paths):
        # Same rationale as preview's short-circuit: a truncated container can
        # never clear, so skip the unbounded live walk and probes.
        contested.add("truncated-not-inventoried")
    else:
        try:
            current_paths = current_descendants(target, path)
        except PermissionError:
            contested.add("needs-elevation")
        except (OSError, HygieneError):
            contested.add("filesystem-state-unverified")
        else:
            if current_paths - expected_paths:
                # Anything live that the snapshot did not record survives the
                # approved removals, so this container does not become empty.
                # Only the surplus matters, not exact equality: the manual lane
                # deletes one approved path at a time, so by the time a later
                # path is verified the container is legitimately missing the
                # earlier ones. An inventoried child that was replaced rather
                # than removed is caught by that child's own approved-path
                # verdict, which then keeps it out of the settled set.
                drifted.add("changed-since-scan")
        try:
            vcs = tracked_blocker(path, target)
        except (OSError, subprocess.SubprocessError):
            vcs = "vcs-state-unverified"
        if vcs:
            contested.add(vcs)
        # Probe only descendants that still exist. After verify-one-delete-one,
        # expected_paths still names settled missing children; CreateFileW
        # OPEN_EXISTING on those returns ERROR_FILE_NOT_FOUND (2) and would
        # make an emptied container handle-state-unverified.
        handle_paths = current_paths if current_paths is not None else expected_paths
        try:
            state, detail = candidate_handle_state(target, path, handle_paths)
        except (OSError, subprocess.SubprocessError):
            state, detail = "unverified", "handle-probe-failed"
        handle_reason = handle_state_contest_reason(state, detail)
        if handle_reason is not None:
            contested.add(handle_reason)
    verdict = "drifted" if drifted else "contested" if contested else "clear"
    return {
        "path": relative,
        "verdict": verdict,
        "reasons": sorted(drifted) + sorted(contested),
    }


def handoff_verify(
    snapshot: dict[str, Any],
    approved: list[str],
    vcs_evidence: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Re-run per-path revalidation for the manual handoff lane, read-only.

    Deterministically reruns the engine's identity/reparse/protection/VCS/
    handle checks against live state for each approved path and emits a
    verdict — never a deletion. Platform execution blockers deliberately do
    not apply: this subcommand exists exactly for the platforms where the
    engine's own apply lane is unsupported.
    """
    target, known_mounts = resolve_snapshot_target(snapshot)
    entries = entry_map(snapshot)
    exact_names = baseline_protected_names() | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    truncated_paths = {
        value for value in snapshot.get("truncated_paths", []) if isinstance(value, str)
    }
    globs = snapshot_protection_globs(snapshot)
    verdicts: list[dict[str, Any]] = []
    containers: list[dict[str, Any]] = []
    # Two passes when container probes run: those walks and handle checks can
    # outlast a concurrent same-name replacement of an approved path, and the
    # container surplus-name check does not see that replacement. Revalidate
    # the approved paths after the container work and recompute containers
    # from the post-revalidation settled set.
    for _ in range(2):
        verdicts = []
        for relative in approved:
            path = target.joinpath(*PurePosixPath(relative).parts)
            drifted: set[str] = set()
            contested: set[str] = set()
            evidence_result: dict[str, Any] | None = None
            candidate_pure = PurePosixPath(relative)
            candidate_evidence = {
                repository: config
                for repository, config in (vcs_evidence or {}).items()
                if (
                    (repository_pure := PurePosixPath(repository)) == candidate_pure
                    or candidate_pure in repository_pure.parents
                )
            }
            try:
                path.lstat()
            except FileNotFoundError:
                verdicts.append(
                    {
                        "path": relative,
                        "verdict": "gone",
                        "reasons": ["no-longer-present"],
                    }
                )
                continue
            except PermissionError:
                verdicts.append(
                    {
                        "path": relative,
                        "verdict": "contested",
                        "reasons": ["needs-elevation"],
                    }
                )
                continue
            except OSError:
                verdicts.append(
                    {
                        "path": relative,
                        "verdict": "contested",
                        "reasons": ["filesystem-state-unverified"],
                    }
                )
                continue
            candidate_protections = hard_protection(
                path, target, exact_names, known_mounts
            )
            truncated = overlaps_truncated(relative, truncated_paths)
            overlapping_truncations = {
                name
                for name in truncated_paths
                if name == relative
                or name.startswith(relative + "/")
                or relative.startswith(name + "/")
            }
            configured_git_truncations = {
                (PurePosixPath(repository) / GIT_METADATA_NAME).as_posix()
                for repository in candidate_evidence
            }
            evidence_inventory_eligible = bool(candidate_evidence) and not (
                overlapping_truncations - configured_git_truncations
            )
            expected_paths = subtree_names(relative, entries)
            if truncated and not evidence_inventory_eligible:
                # A truncated path has no captured descendant set, so no live walk
                # can prove anything about it — never clear (same rationale as the
                # preview short-circuit).
                contested.add("truncated-not-inventoried")
                current_paths = expected_paths
            else:
                try:
                    current_paths = current_descendants(
                        target,
                        path,
                        opaque_git_metadata=bool(candidate_evidence),
                    )
                # On failure, treat the live set as unknown rather than empty
                # (preview's choice): an unreadable subtree is contested, not
                # provably drifted — "changed" cannot be claimed without a read.
                except PermissionError:
                    current_paths = expected_paths
                    contested.add("needs-elevation")
                except (OSError, HygieneError):
                    current_paths = expected_paths
                    contested.add("filesystem-state-unverified")
            if candidate_evidence and evidence_inventory_eligible:
                try:
                    evidence_result = verify_vcs_checkout_evidence(
                        target,
                        path,
                        current_paths,
                        candidate_evidence,
                        approved,
                    )
                except (OSError, subprocess.SubprocessError, HygieneError) as exc:
                    evidence_result = {
                        "status": "failed",
                        "gates": {
                            name: {"status": "failed"}
                            for name in VCS_EVIDENCE_GATE_NAMES
                        },
                        "blockers": ["vcs-evidence-state-unverified"],
                        "error": str(exc),
                    }
                contested.update(evidence_result["blockers"])
            elif candidate_evidence:
                evidence_result = {
                    "status": "failed",
                    "gates": {
                        name: {"status": "failed"} for name in VCS_EVIDENCE_GATE_NAMES
                    },
                    "blockers": ["vcs-evidence-non-git-truncation"],
                }
                contested.update(evidence_result["blockers"])
            evidence_verified = (
                evidence_result is not None and evidence_result["status"] == "verified"
            )
            repository_paths = [
                target.joinpath(*PurePosixPath(value).parts)
                for value in (evidence_result or {}).get("repositories", [])
            ]
            if evidence_verified:
                candidate_protections = evidence_adjusted_protections(
                    candidate_protections,
                    path,
                    target,
                    repository_paths,
                    exact_names,
                )
                git_metadata_truncations = {
                    (repo / GIT_METADATA_NAME).relative_to(target).as_posix()
                    for repo in repository_paths
                }
                truncated = bool(overlapping_truncations - git_metadata_truncations)
            if truncated:
                contested.add("truncated-not-inventoried")
            contested.update(candidate_protections)
            if current_paths != expected_paths:
                drifted.add("changed-since-scan")
            for name in expected_paths:
                entry = entries[name]
                current = target.joinpath(*PurePosixPath(name).parts)
                # Distinguish unverifiable descendant state from real drift:
                # same_identity's blanket OSError->False would report a denied
                # lstat as changed-since-scan, telling the lane to rescan when
                # the actual remedy is resolving access (review finding).
                try:
                    info = current.lstat()
                except FileNotFoundError:
                    drifted.add("changed-since-scan")
                except PermissionError:
                    contested.add("needs-elevation")
                except OSError:
                    contested.add("filesystem-state-unverified")
                else:
                    metadata_entry = any(
                        current == repo / GIT_METADATA_NAME for repo in repository_paths
                    )
                    identity_matches = (
                        same_object_identity(info, entry)
                        if candidate_evidence
                        and metadata_entry
                        and entry.get("kind") == "directory"
                        else same_stat_identity(info, entry)
                    )
                    if not identity_matches:
                        drifted.add("changed-since-scan")
                current_protections = hard_protection(
                    current, target, exact_names, known_mounts
                )
                if evidence_verified:
                    current_protections = evidence_adjusted_protections(
                        current_protections,
                        current,
                        target,
                        repository_paths,
                        exact_names,
                    )
                contested.update(current_protections)
                relative_current = current.relative_to(target).as_posix()
                if any(glob_matches(relative_current, pattern) for pattern in globs):
                    contested.add("consumer-protected-path")
            if not truncated or evidence_inventory_eligible:
                # A hung git (TimeoutExpired) must degrade to this one path's
                # contested verdict, not abort the whole run with no verdicts —
                # the subcommand promises a verdict per approved path.
                try:
                    vcs = tracked_blocker(path, target)
                except (OSError, subprocess.SubprocessError):
                    vcs = "vcs-state-unverified"
                if vcs and not (evidence_verified and vcs == "vcs-tracked-content"):
                    contested.add(vcs)
                # Same degradation rule as the VCS probe: a probe that fails to
                # LAUNCH (lsof vanishing after which(), a ctypes load error) is
                # this path's contested verdict, not a whole-run abort.
                try:
                    state, detail = candidate_handle_state(target, path, expected_paths)
                except (OSError, subprocess.SubprocessError):
                    state, detail = "unverified", "handle-probe-failed"
                handle_reason = handle_state_contest_reason(state, detail)
                if handle_reason is not None:
                    contested.add(handle_reason)
            verdict = "drifted" if drifted else "contested" if contested else "clear"
            item = {
                "path": relative,
                "verdict": verdict,
                "reasons": sorted(drifted) + sorted(contested),
            }
            if evidence_result is not None:
                item["vcs_evidence"] = evidence_result
            verdicts.append(item)
        # Only paths that are actually going away can empty a container. A contested
        # or drifted approved path stays on disk, so a container that depends on it
        # must not be named removable.
        settled = [
            item["path"] for item in verdicts if item["verdict"] in {"clear", "gone"}
        ]
        containers = [
            verify_emptied_container(
                target,
                relative,
                entries,
                exact_names,
                known_mounts,
                globs,
                truncated_paths,
            )
            for relative in emptied_container_order(settled, entries)
        ]
        if not containers:
            break
    clear = sum(1 for item in verdicts if item["verdict"] == "clear")
    return {
        "status": "handoff-verify-complete",
        "target": str(target),
        "verdicts": verdicts,
        "clear": clear,
        "not_clear": len(verdicts) - clear,
        "emptied_containers": containers,
        "removable_emptied_containers": sum(
            1 for item in containers if item["verdict"] == "clear"
        ),
        "note": (
            "Read-only revalidation for the manual handoff lane; this "
            "subcommand has no deletion capability. A clear verdict is valid "
            "only at emission time — in a multi-path run the earliest checks "
            "age while later paths are still probed, so verify ONE path per "
            "deletion (verify one, delete that one, then the next) and "
            "re-verify after any delay. The multi-path form is for reporting. "
            "emptied_containers names the inventoried directories the approved "
            "removals leave empty, deepest first, with the same categorical "
            "checks applied; they are NOT in the approved list, so removing one "
            "needs its own approval, and each is removable only AFTER every "
            "path beneath it is gone. clear/not_clear count the approved paths "
            "only; not_clear includes gone paths, which do not by themselves "
            "make the command exit non-zero."
        ),
    }


def handoff_verify_blocks(result: dict[str, Any]) -> bool:
    """True when any approved path's verdict means "do not proceed".

    `gone` is the terminal state verify-one-delete-one drives each approved path
    to, so from the second round on at least one path reads `gone` while every
    verdict is correct. Only `drifted` and `contested` block.
    """
    return any(item["verdict"] not in {"clear", "gone"} for item in result["verdicts"])


def removal_entries(relative: str, entries: dict[str, dict[str, Any]]) -> list[str]:
    return sorted(subtree_names(relative, entries), key=removal_sort_key, reverse=True)


def open_anchored_parent(
    target_fd: int, relative: str, entries: dict[str, dict[str, Any]]
) -> tuple[int, str]:
    parts = PurePosixPath(relative).parts
    parent_fd = os.dup(target_fd)
    walked: list[str] = []
    try:
        for part in parts[:-1]:
            walked.append(part)
            next_fd = os.open(
                part,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=parent_fd,
            )
            os.close(parent_fd)
            parent_fd = next_fd
            expected = entries.get(PurePosixPath(*walked).as_posix())
            if expected is None or not same_object_identity(
                os.fstat(parent_fd), expected
            ):
                raise HygieneError("anchored parent changed since the snapshot")
        return parent_fd, parts[-1]
    except BaseException:
        os.close(parent_fd)
        raise


def anchored_remove(
    target_fd: int,
    relative: str,
    entry: dict[str, Any],
    entries: dict[str, dict[str, Any]],
    target: Path,
) -> None:
    parent_fd, name = open_anchored_parent(target_fd, relative, entries)
    try:
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        expected_parent = target.joinpath(*PurePosixPath(relative).parts[:-1]).resolve(
            strict=True
        )
        actual_parent = Path(f"/proc/self/fd/{parent_fd}").resolve(strict=True)
        if actual_parent != expected_parent:
            raise HygieneError("anchored parent is no longer at its expected path")
        if entry["kind"] == "directory":
            if not same_object_identity(current, entry):
                raise HygieneError("anchored directory changed since the snapshot")
            directory_fd = os.open(
                name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=parent_fd,
            )
            try:
                opened = os.fstat(directory_fd)
                if not same_object_identity(opened, entry) or not same_open_object(
                    current, opened
                ):
                    raise HygieneError("anchored directory changed since the snapshot")
                with os.scandir(directory_fd) as iterator:
                    if next(iterator, None) is not None:
                        raise HygieneError("anchored directory is not empty")
                named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if not same_object_identity(named, entry) or not same_open_object(
                    opened, named
                ):
                    raise HygieneError("anchored directory changed since the snapshot")
                os.rmdir(name, dir_fd=parent_fd)
            finally:
                os.close(directory_fd)
        elif entry["kind"] == "file":
            if not same_stat_identity(current, entry):
                raise HygieneError("anchored entry changed since the snapshot")
            os.unlink(name, dir_fd=parent_fd)
        else:
            raise HygieneError("only regular files and directories are removable")
    finally:
        os.close(parent_fd)


def apply_nothing_removed_report(
    plan: dict[str, Any], target: Path, skipped: list[dict[str, str]]
) -> dict[str, Any]:
    """An apply report for a run that removed nothing and skipped every candidate."""
    return {
        "status": "completed-with-skips",
        "tier": plan["tier"],
        "target": str(target),
        "removed": [],
        "skipped": skipped,
        "paths_removed": 0,
        "empty_directories_removed": 0,
        "logical_bytes_removed": 0,
        "reclaimable_local_bytes_removed": 0,
        "observed_free_space_delta_bytes": 0,
    }


def apply_plan(snapshot: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    target = Path(snapshot["target"]).absolute()
    entries = entry_map(snapshot)
    candidates = validate_plan(plan, entries)
    platform_blockers = execution_blockers()
    if platform_blockers:
        return apply_nothing_removed_report(
            plan,
            target,
            [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(platform_blockers),
                }
                for item in candidates
            ],
        )
    checked = preview(snapshot, plan)
    if checked["status"] != "ready-for-explicit-approval":
        by_path = {item["path"]: item for item in checked["candidates"]}
        return apply_nothing_removed_report(
            plan,
            target,
            [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(by_path[item["path"]]["blockers"]),
                }
                for item in candidates
            ],
        )
    before = shutil.disk_usage(target).free
    removed: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    logical_removed = 0
    reclaimable_removed = 0
    target_fd = os.open(target, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    if not same_object_identity(os.fstat(target_fd), snapshot["target_identity"]):
        os.close(target_fd)
        raise HygieneError("anchored target was replaced since the snapshot")
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        os.close(target_fd)
        raise HygieneError(mount_error)
    globs = snapshot_protection_globs(snapshot)
    for candidate in candidates:
        candidate_path = target.joinpath(*PurePosixPath(candidate["path"]).parts)
        candidate_blockers = hard_protection(
            candidate_path,
            target,
            baseline_protected_names()
            | set(snapshot.get("policy", {}).get("protected_exact_names", [])),
            known_mounts,
        )
        selected = removal_entries(candidate["path"], entries)
        if candidate["owner"] != "unmanaged":
            candidate_blockers.append("native-managed-report-only")
        vcs = tracked_blocker(candidate_path, target)
        if vcs:
            candidate_blockers.append(vcs)
        if candidate_blockers:
            skipped.append(
                {
                    "path": candidate["path"],
                    "outcome": "protected",
                    "detail": ", ".join(sorted(set(candidate_blockers))),
                }
            )
            continue
        for relative in selected:
            entry = entries[relative]
            path = target.joinpath(*PurePosixPath(relative).parts)
            if not same_removal_identity(path, entry) or is_linkish(path):
                skipped.append({"path": relative, "outcome": "changed-or-link"})
                continue
            fresh_mounts, fresh_mount_error = linux_mount_points()
            if fresh_mount_error:
                skipped.append(
                    {
                        "path": relative,
                        "outcome": "protected",
                        "detail": "mount-state-unverified",
                    }
                )
                continue
            fresh_protections = hard_protection(
                path,
                target,
                baseline_protected_names(),
                fresh_mounts,
            )
            if any(glob_matches(relative, pattern) for pattern in globs):
                fresh_protections.append("consumer-protected-path")
            fresh_vcs = tracked_blocker(path, target)
            if fresh_vcs:
                fresh_protections.append(fresh_vcs)
            if fresh_protections:
                skipped.append(
                    {
                        "path": relative,
                        "outcome": "protected",
                        "detail": ", ".join(sorted(set(fresh_protections))),
                    }
                )
                continue
            state, detail = handle_state(path)
            if state != "clear":
                outcome = {"open": "locked", "needs_elevation": "needs-elevation"}.get(
                    state, "handle-state-unverified"
                )
                skipped.append(
                    {"path": relative, "outcome": outcome, "detail": detail or ""}
                )
                continue
            try:
                anchored_remove(target_fd, relative, entry, entries, target)
            except HygieneError as exc:
                skipped.append(
                    {"path": relative, "outcome": "changed-or-link", "detail": str(exc)}
                )
                continue
            except PermissionError as exc:
                skipped.append(
                    {"path": relative, "outcome": "needs-elevation", "detail": str(exc)}
                )
                continue
            except OSError as exc:
                skipped.append(
                    {"path": relative, "outcome": "delete-failed", "detail": str(exc)}
                )
                continue
            logical = entry_logical_file_bytes(entry)
            reclaimable = entry_reclaimable_local_bytes(entry) or 0
            logical_removed += logical
            reclaimable_removed += reclaimable
            removed.append(
                {
                    "path": relative,
                    "empty_directory": entry_is_empty_directory(entry, entries),
                    "logical_bytes": logical,
                    "reclaimable_local_bytes": reclaimable,
                }
            )
    os.close(target_fd)
    after = shutil.disk_usage(target).free
    return {
        "status": "completed-with-skips" if skipped else "completed",
        "tier": plan["tier"],
        "target": str(target),
        "removed": removed,
        "skipped": skipped,
        "paths_removed": len(removed),
        "empty_directories_removed": sum(
            1 for item in removed if item["empty_directory"]
        ),
        "logical_bytes_removed": logical_removed,
        "reclaimable_local_bytes_removed": reclaimable_removed,
        "observed_free_space_delta_bytes": after - before,
    }


_PARSER_VALUE_TYPES = {"int": int}


def _add_flag(command: argparse.ArgumentParser, flag: engine_grammar.Flag) -> None:
    """Declare one grammar flag on a subparser.

    A valueless flag is always ``store_true`` here even when the grammar marks
    it required: that requirement is the guard's (it admits only the executing
    ``apply`` form), while the engine keeps its own diagnostic for the flag's
    absence rather than an argparse usage error.
    """
    options: dict[str, Any] = {}
    if flag.help is not None:
        options["help"] = flag.help
    if not flag.takes_value:
        command.add_argument(flag.name, action="store_true", **options)
        return
    if flag.metavar is not None:
        options["metavar"] = flag.metavar
    if flag.repeatable:
        command.add_argument(flag.name, action="append", default=[], **options)
        return
    if flag.choices is not None:
        options["choices"] = sorted(flag.choices)
    if flag.value_type is not None:
        options["type"] = _PARSER_VALUE_TYPES[flag.value_type]
    command.add_argument(flag.name, required=flag.required, **options)


def build_parser() -> argparse.ArgumentParser:
    """The engine's CLI, derived from the one grammar the guard also enforces."""
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for spec in engine_grammar.SUBCOMMANDS:
        options: dict[str, Any] = {}
        if spec.help is not None:
            options["help"] = spec.help
        command = subparsers.add_parser(spec.name, **options)
        for flag in spec.flags:
            _add_flag(command, flag)
    return parser


def main(argv: list[str] | None = None) -> int:
    global DATA_ROOT_OVERRIDE
    args = build_parser().parse_args(argv)
    DATA_ROOT_OVERRIDE = args.data_root
    try:
        if sys.version_info < MIN_PYTHON:
            floor = ".".join(str(part) for part in MIN_PYTHON)
            raise HygieneError(f"disk-hygiene requires Python {floor} or newer")
        if args.command == "scan":
            target_input = Path(args.target).expanduser().absolute()
            if (
                not target_input.exists()
                or not target_input.is_dir()
                or has_linkish_component(target_input)
            ):
                raise HygieneError(
                    "target must be an existing directory with no link or reparse-point component"
                )
            target = target_input.resolve(strict=True)
            known_mounts, mount_error = linux_mount_points()
            mounted, target_mount_error = mount_state(target, known_mounts)
            if mount_error or target_mount_error:
                raise HygieneError("target mount state is unverified")
            root_children_mode = bool(args.root_children)
            selected_root_children = list(args.root_child or [])
            if selected_root_children and not root_children_mode:
                raise HygieneError("--root-child requires --root-children")
            if root_children_mode:
                if not is_volume_root(target):
                    raise HygieneError("--root-children requires a volume-root target")
                if not is_os_managed_target(target):
                    raise HygieneError(
                        "--root-children is only valid for an OS-managed volume root; "
                        "scan a non-OS volume root without this flag"
                    )
            elif is_os_managed_target(target):
                raise HygieneError("OS-managed roots are not valid audit targets")
            if mounted and not is_volume_root(target):
                raise HygieneError("mount points are not valid audit targets")
            policy = load_policy(
                Path(args.policy).expanduser().absolute() if args.policy else None,
                Path(args.project_dir).expanduser().absolute()
                if args.project_dir
                else None,
            )
            if has_protected_path_component(
                target, set(policy["protected_exact_names"])
            ):
                raise HygieneError(
                    "protected shell-folder and profile-hive roots are not valid audit targets"
                )
            if args.max_depth is not None and args.max_depth < 1:
                raise HygieneError("--max-depth must be a positive integer")
            output_path = state_output_path(Path(args.output))
            advisory = os_autoclean_advisory(target)
            if root_children_mode:
                admitted, skipped = enumerate_root_children(
                    target, policy, known_mounts
                )
                # This status and large-target-confirmation-required name the
                # documented next step, so they exit 0 and `status` carries the
                # distinction; non-zero exits stay reserved for failures.
                if not selected_root_children:
                    return emit(
                        {
                            "status": "root-children-selection-required",
                            "target": str(target),
                            "admitted_children": admitted,
                            "skipped_children": skipped,
                            "os_autoclean": advisory,
                            "note": (
                                "OS-managed volume roots are never walked as a "
                                "whole. Re-run with --root-children and one or "
                                "more explicit --root-child NAME flags naming "
                                "admitted immediate directories; a general "
                                "'clean everything' is not selection."
                            ),
                        },
                        0,
                    )
                resolved_children = normalize_root_child_selection(
                    selected_root_children, admitted
                )
                # Each selected child is its own audit target for large-scan
                # gating: a home directory selected under the volume root still
                # requires a bound or confirmation.
                child_large_reasons: list[str] = []
                for child_name in resolved_children:
                    child_path = target / child_name
                    child_large_reasons.extend(
                        f"{child_name}:{reason}"
                        for reason in large_scan_reasons(child_path)
                    )
                if (
                    child_large_reasons
                    and args.max_depth is None
                    and not args.confirmed_large_scan
                ):
                    return emit(
                        {
                            "status": "large-target-confirmation-required",
                            "target": str(target),
                            "root_children_selected": resolved_children,
                            "large_target_reasons": sorted(set(child_large_reasons)),
                            "os_autoclean": advisory,
                            "note": (
                                "A selected root child is a known-large scan "
                                "root; re-run with --max-depth N (preferred) or, "
                                "only after the human confirms a full walk, "
                                "--confirmed-large-scan."
                            ),
                        },
                        0,
                    )
                try:
                    snapshot = scan_tree(
                        target,
                        policy,
                        args.max_depth,
                        root_children=resolved_children,
                    )
                except HygieneError as exc:
                    return emit(
                        {
                            "status": "invalid-or-blocked",
                            "error": str(exc),
                            "os_autoclean": advisory,
                        },
                        2,
                    )
                snapshot["root_children_skipped"] = skipped
                write_json(output_path, snapshot)
                return emit(
                    scan_stdout_payload(
                        scan_complete_payload(
                            target,
                            output_path,
                            snapshot,
                            policy,
                            advisory,
                            (
                                "Root-children mode inventoried only the "
                                "selected immediate directories; the volume "
                                "root itself and every skipped "
                                "OS-owned/hidden/system/reparse entry were "
                                "never walked — so children_rollup covers the "
                                "selected children only. unhinted_entries is "
                                "entries minus hinted_entries: every "
                                "inventoried entry no hint judged, left to "
                                "positional review. Hints are discovery "
                                "signals, never cleanup verdicts."
                            ),
                            {
                                "root_children_mode": True,
                                "root_children_selected": resolved_children,
                            },
                        ),
                        args.quiet,
                    )
                )
            large_reasons = large_scan_reasons(target)
            if (
                large_reasons
                and args.max_depth is None
                and not args.confirmed_large_scan
            ):
                immediate_entries, probe_error = top_level_entry_count(target)
                return emit(
                    {
                        "status": "large-target-confirmation-required",
                        "target": str(target),
                        "large_target_reasons": large_reasons,
                        "immediate_entries": immediate_entries,
                        "probe_error": probe_error,
                        "os_autoclean": advisory,
                        "note": (
                            "This is a known-large scan root; an unbounded "
                            "recursive walk is gated at the engine. Re-run with "
                            "--max-depth N for a bounded pass (start with "
                            "--max-depth 1), or, only after the human confirms a "
                            "full walk, add --confirmed-large-scan."
                        ),
                    },
                    0,
                )
            try:
                snapshot = scan_tree(target, policy, args.max_depth)
            except HygieneError as exc:
                return emit(
                    {
                        "status": "invalid-or-blocked",
                        "error": str(exc),
                        "os_autoclean": advisory,
                    },
                    2,
                )
            write_json(output_path, snapshot)
            return emit(
                scan_stdout_payload(
                    scan_complete_payload(
                        target,
                        output_path,
                        snapshot,
                        policy,
                        advisory,
                        (
                            "Safe tidiness is the primary objective; "
                            "reclaimable bytes are a secondary signal. "
                            "empty_directory_count names walked empty "
                            "directories (logical_size 0, not truncated) so "
                            "zero-byte residue stays visible. "
                            "unhinted_entries is entries minus "
                            "hinted_entries — every inventoried entry no hint "
                            "judged, left to positional review — so hint "
                            "coverage reads as a rate, not a bare count. "
                            "Hints are discovery signals, never cleanup "
                            "verdicts. children_rollup carries one row per "
                            "immediate child; its logical_bytes, entry_count "
                            "and newest_mtime_ns are exact where walked is "
                            "true and null where it is false, never 0. "
                            "target_reclaimable_local_bytes excludes every "
                            "entry whose size_qualifiers is non-empty "
                            "(cloud-placeholder, hardlinked, sparse, "
                            "not-walked); target_logical_bytes is the walked "
                            "roll-up and may understate truncated subtrees."
                        ),
                    ),
                    args.quiet,
                )
            )
        snapshot = load_json(Path(args.snapshot))
        if args.command == "handoff-verify":
            approved = validate_handoff_paths(
                load_json(Path(args.paths)), entry_map(snapshot)
            )
            vcs_evidence = (
                validate_vcs_evidence(load_json(Path(args.vcs_evidence)), approved)
                if args.vcs_evidence
                else None
            )
            result = handoff_verify(snapshot, approved, vcs_evidence)
            return emit(result, 3 if handoff_verify_blocks(result) else 0)
        plan = load_json(Path(args.plan))
        checked = preview(snapshot, plan)
        if args.command == "preview":
            return emit(checked, 3 if checked["status"] == "blocked" else 0)
        if not args.execute:
            raise HygieneError("apply requires the explicit --execute flag")
        if checked["status"] != "ready-for-explicit-approval":
            return emit(checked, 3)
        if args.confirm_tier != plan.get("tier"):
            raise HygieneError("--confirm-tier must match the plan's single tier")
        if args.approval_token != checked["approval_token"]:
            raise HygieneError("approval token does not match the fresh preview")
        report_path = state_output_path(Path(args.report))
        report = apply_plan(snapshot, plan)
        write_json(report_path, report)
        return emit(report, 4 if report["skipped"] else 0)
    except HygieneError as exc:
        return emit({"status": "invalid-or-blocked", "error": str(exc)}, 2)
    except PermissionError as exc:
        return emit({"status": "needs-elevation", "error": str(exc)}, 3)
    except (OSError, subprocess.SubprocessError) as exc:
        return emit({"status": "filesystem-state-unverified", "error": str(exc)}, 3)
    finally:
        # Close the test-isolation window: a call to `main()` must never leave
        # this override live for a later `state_output_path()` call (direct,
        # or via a subsequent `main()` invocation in the same process) to
        # observe a stale --data-root after this invocation has returned.
        DATA_ROOT_OVERRIDE = None


if __name__ == "__main__":
    raise SystemExit(main())
