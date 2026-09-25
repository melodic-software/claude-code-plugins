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
  "$D1_TEMP/spd~1/f.txt" "/$D1_TARGET" "$D1_TEMP//spd-d1/f.txt" "tmp/spd-d1/f.txt"; do
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
# their own, removed by name in the EXIT trap.
D1_SEAM_TRY="/tmp/spd-d1-seam-$$"
if [[ "$(realpath /tmp 2>/dev/null)" == /tmp ]] && mkdir "$D1_SEAM_TRY" 2>/dev/null &&
  D1_SEAMDIR="$D1_SEAM_TRY" && mkdir "$D1_SEAMDIR/lowtemp" "$D1_SEAMDIR/CapTemp" 2>/dev/null; then
  assert_eq "D1 seam: posix, lowercase temp root declines" 0 "$(d1_seam_rc "$D1_SEAMDIR/lowtemp")"
  assert_eq "D1 seam: posix, capitalized temp root scans" 1 "$(d1_seam_rc "$D1_SEAMDIR/CapTemp")"
else
  echo "SKIP: D1 seam width cases (/tmp does not resolve to itself, or the seam dirs could not be made)"
fi

if ((D1_WIN)); then
  assert_exit "D1 windows: drive root '${D1_ROOT%%/*}/' → exit 2" 2 "$(d1_rc "${D1_ROOT%%/*}/" "$D1_TARGET")"
  # A drive spelling that names no volume must terminate. timeout 124 is a hang,
  # not a verdict; a loaded Windows host spends tens of seconds on one fire.
  assert_exit "D1 windows: Z:/ root, temp target, terminates → exit 0" 0 \
    "$(D1_RC=0; timeout 150 env CLAUDE_PROJECT_DIR="Z:/spd-d1-root" bash "$HOOK" <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_RC=$?; printf '%s' "$D1_RC")"
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
if [[ -s "$D1_LOG" ]]; then ok "D1 temp target spawns a resolver"; else bad "D1 temp target spawned no resolver"; fi

# The dispatcher runs this guard beside the other Write|Edit guards.
D1_DISPATCH_RC=0
CLAUDE_PROJECT_DIR="$D1_ROOT" bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: non-temp root, temp target → exit 0" 0 "$D1_DISPATCH_RC"
D1_DISPATCH_RC=0
bash "$HOOK_DIR/run-guards.sh" secret-pattern-detection.sh hardcoded-path-check.sh block-windows-drive-tmp.sh \
  <<<"$(write_json "$D1_TARGET" "token = '$GH_PAT'")" >/dev/null 2>&1 || D1_DISPATCH_RC=$?
assert_exit "D1 dispatcher: root unset → exit 2" 2 "$D1_DISPATCH_RC"

report
