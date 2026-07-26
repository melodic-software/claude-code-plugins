#!/usr/bin/env bash
# Black-box contract test for markdown-format.sh (the markdown-format plugin hook).
#
# Proves WIRING, not baseline parity: that the hook fires on *.md/*.mdc, skips
# otherwise, runs markdownlint-cli2 --fix from the linted file's repo root
# (config discovery is CWD-anchored), preserves --fix bytes, and surfaces
# residual findings via additionalContext with no repo-specific policy prose.
#
# Self-contained: builds a throwaway git repo with its own markdownlint config
# and runtime-generated fixtures (CRLF preserved via printf, never committed —
# a committed CRLF fixture would be LF-normalized by .gitattributes). The hook
# is invoked as a subprocess from an UNRELATED cwd so the `cd repo-root` config
# discovery is genuinely exercised (running from the repo root would false-pass
# a hook that skips the cd).

set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/markdown-format.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d)"
UNRELATED="$(mktemp -d)"
cleanup() { rm -rf "$WORK" "$UNRELATED"; }
trap cleanup EXIT

# Keep the success-path contract test independent of tools installed on the
# runner. markdownlint-cli2's documented CLI contract is an executable invoked
# as `markdownlint-cli2 --fix <file>`: it applies fixable changes, exits 0 when
# clean, and exits non-zero with remaining findings. This narrow local double
# implements exactly the behavior exercised by the fixtures below (MD004,
# MD024, and MD047); it never resolves packages or accesses the network.
TEST_BIN="$WORK/test-bin"
mkdir -p "$TEST_BIN"
cat >"$TEST_BIN/markdownlint-cli2" <<'STUB'
#!/usr/bin/env bash
set -uo pipefail

[[ "${1:-}" == "--fix" && $# -eq 2 ]] || exit 2
file="$2"

# MD004 fix: the consumer fixture requires dash list markers.
if grep -q '^\* ' "$file"; then
  sed -i 's/^\* /- /' "$file" # portability-ok: pre-existing markdownlint-cli2 stub fixture, unsuffixed sed -i predates #1527's mktemp -p scope; tracked in #1540
fi

# MD047 fix: add a final newline while preserving an existing CRLF style.
if [[ -s "$file" && "$(tail -c 1 "$file" | od -An -tx1 | tr -d ' \n')" != "0a" ]]; then
  if od -An -tx1 "$file" | grep -Eq '(^|[[:space:]])0d([[:space:]]|$)'; then
    printf '\r\n' >>"$file"
  else
    printf '\n' >>"$file"
  fi
fi

# MD024 residual: report the second occurrence of a duplicate ATX heading in
# markdownlint-cli2's default violation-line shape.
duplicate_line="$({
  awk '
    {
      sub(/\r$/, "")
      if ($0 ~ /^#{1,6}[[:space:]]+/) {
        heading = $0
        sub(/^#{1,6}[[:space:]]+/, "", heading)
        if (seen[heading]++) { print NR; exit }
      }
    }
  ' "$file"
} || true)"
if [[ -n "$duplicate_line" ]]; then
  printf '%s:%s:1 error MD024/no-duplicate-heading Multiple headings with the same content\n' \
    "$file" "$duplicate_line"
  exit 1
fi

exit 0
STUB
chmod +x "$TEST_BIN/markdownlint-cli2"
PATH="$TEST_BIN:$PATH"
export PATH

# make_sink <body> → path to an executable single-command stub sink running
# <body> (which reads the envelope on stdin). The contract requires
# HOOK_TELEMETRY_SINK to be a single executable path, not a command-with-args,
# so tests point it at a stub script. Stubs live under $WORK so the trap reaps them.
make_sink() {
  local s
  s="$(mktemp "$WORK/sink.XXXXXX")"
  {
    printf '#!/usr/bin/env bash\n'
    printf '%s\n' "$1"
  } >"$s"
  chmod +x "$s"
  printf '%s' "$s"
}

# wait_for_sink <file> [max_polls] → block until <file> is non-empty (the
# fire-and-forget sink has flushed) or the bound elapses, polling in 20ms steps.
# Replaces a fixed sleep so delivery assertions fire as soon as the write lands
# instead of racing variable process-spawn latency (notably on Windows Git Bash).
wait_for_sink() {
  local f="$1" tries="${2:-150}"
  while ((tries-- > 0)); do
    [[ -s "$f" ]] && return 0
    sleep 0.02
  done
  return 1
}

# epoch_delta_ms <start> <end> → whole milliseconds between two $EPOCHREALTIME
# reads. Splits on either '.' or ',' (locale decimal separator) and forces
# base-10 on the fractional part so a leading-zero microsecond field is not read
# as octal.
epoch_delta_ms() {
  local start="$1" end="$2" ss sf es ef
  ss="${start%[.,]*}" sf="${start#*[.,]}"
  es="${end%[.,]*}" ef="${end#*[.,]}"
  echo $(((es * 1000000 + 10#$ef - ss * 1000000 - 10#$sf) / 1000))
}

# --- Build the throwaway consumer repo --------------------------------------
REPO="$WORK/consumer"
mkdir -p "$REPO"
git -C "$REPO" init -q
git -C "$REPO" config user.email t@t.t
git -C "$REPO" config user.name t

# Consumer's own markdownlint config — the cascade the hook must discover by
# cd-ing to the repo root. MD004 dash makes `*` markers a fixable violation;
# MD024 siblings_only makes a duplicate sibling heading an unfixable residual.
cat >"$REPO/.markdownlint-cli2.jsonc" <<'JSONC'
{
  "config": {
    "MD004": { "style": "dash" },
    "MD024": { "siblings_only": true },
    "MD013": false
  }
}
JSONC

# Invoke the hook as a subprocess from an unrelated cwd. CLAUDE_PROJECT_DIR is
# left UNSET so read_file_path's project-membership guard is disabled (it is not
# part of the fire-gate contract); this isolates formatting behavior from any
# POSIX-vs-Windows path-form mismatch in the guard.
run_hook() {
  local file_path="$1"
  (cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$file_path" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")
}

# --- Fixture A: fixable only (Path A) — clean after fix, no additionalContext -
# CRLF, no final newline. Only issue is the missing final newline (MD047);
# after --fix the file is clean → empty stdout.
FA="$REPO/fixtureA.md"
printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two' >"$FA"

OUT_A="$(run_hook "$FA")"
RC_A=$?

if [[ $RC_A -eq 0 ]]; then ok "fixtureA exit 0"; else fail "fixtureA exit $RC_A"; fi
if [[ -z "$OUT_A" ]]; then ok "fixtureA empty stdout (clean after fix)"; else fail "fixtureA stdout not empty: $OUT_A"; fi
# --fix added a final newline; CRLF preserved.
EXPECT_A="$(printf '# Title A\r\n\r\nSome text\r\n\r\n- item one\r\n- item two\r\n')"
TAIL_A="$(tail -c 2 "$FA" | od -An -tx1 | tr -d ' \n')"
if [[ "$(cat "$FA")" == "$EXPECT_A" && "$TAIL_A" == "0d0a" ]]; then
  ok "fixtureA --fix added final newline, CRLF preserved"
else
  fail "fixtureA bytes wrong: $(od -c "$FA" | tail -3)"
fi

# --- Fixture B: fixable + unfixable (Path B) — fix applied + residual finding -
# `* star item` (MD004 dash, fixable) + duplicate sibling `## Section` (MD024,
# unfixable). --fix converts `*`→`-`; MD024 residual surfaces via context.
FB="$REPO/fixtureB.md"
printf '# Doc B\n\n## Section\n\ntext\n\n## Section\n\n* star item\n' >"$FB"

OUT_B="$(run_hook "$FB")"
RC_B=$?

if [[ $RC_B -eq 0 ]]; then ok "fixtureB exit 0"; else fail "fixtureB exit $RC_B"; fi
# Fixable MD004 applied: marker is now a dash.
if grep -q '^- star item$' "$FB" && ! grep -q '^\* star item$' "$FB"; then
  ok "fixtureB --fix applied MD004 dash"
else
  fail "fixtureB MD004 not fixed: $(cat "$FB")"
fi
# additionalContext carries the MD024 finding line (substring identity).
CTX_B=""
if [[ -n "$OUT_B" ]] && printf '%s' "$OUT_B" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  CTX_B="$(printf '%s' "$OUT_B" | jq -r '.hookSpecificOutput.additionalContext')"
  ok "fixtureB emitted hookSpecificOutput.additionalContext"
else
  fail "fixtureB no additionalContext JSON: $OUT_B"
fi
if printf '%s' "$CTX_B" | grep -q 'fixtureB.md:7'; then
  ok "fixtureB ctx has finding line :7"
else
  fail "fixtureB ctx missing :7: $CTX_B"
fi
if printf '%s' "$CTX_B" | grep -q 'MD024'; then
  ok "fixtureB ctx names MD024"
else
  fail "fixtureB ctx missing MD024: $CTX_B"
fi
# Genericized wrapper: the repo-specific policy tail must be gone.
if printf '%s' "$CTX_B" | grep -qi 'commit/CI will block'; then
  fail "fixtureB ctx still has repo-specific policy tail"
else
  ok "fixtureB ctx dropped repo-specific policy tail"
fi

# --- Fire gate: non-.md extension skips -------------------------------------
SKIP="$REPO/skip.other"
printf 'whatever\n' >"$SKIP"
OUT_S="$(run_hook "$SKIP")"
RC_S=$?
if [[ $RC_S -eq 0 && -z "$OUT_S" ]]; then
  ok "non-md extension skipped"
else
  fail "non-md not skipped (rc=$RC_S out=$OUT_S)"
fi

# --- Fire gate: non-existent .md skips --------------------------------------
OUT_M="$(run_hook "$REPO/does-not-exist.md")"
RC_M=$?
if [[ $RC_M -eq 0 && -z "$OUT_M" ]]; then
  ok "missing .md skipped"
else
  fail "missing .md not skipped (rc=$RC_M out=$OUT_M)"
fi

# --- Git-tree scoping: CLAUDE_PROJECT_DIR unset, file outside any git tree ----
# Regression for out-of-tree scratchpad-lint noise: with CLAUDE_PROJECT_DIR
# unset (run_hook already unsets it), a .md written outside any git working tree
# (a lane's temp comment-body) is skipped entirely — no --fix applied, no
# findings. A temp dir that happens to sit inside a git tree on this host would
# pass vacuously, so assert the fixture is genuinely out-of-tree first. The
# in-tree counterpart (unset dir, file inside a git tree still linted) is
# covered by every fixture above: they all live in $REPO, a git working tree.
OUTOFTREE="$(mktemp -d)"
if git -C "$OUTOFTREE" rev-parse --show-toplevel >/dev/null 2>&1; then
  ok "out-of-tree scratchpad case SKIPPED (temp dir sits inside a git tree on this host)"
else
  SCRATCH="$OUTOFTREE/comment-body.md"
  # A fixable issue (MD004 star marker + MD047 missing final newline) the hook
  # WOULD apply if it ran — so an unmodified file proves the skip.
  printf '# Comment\n\n* bullet' >"$SCRATCH"
  SCRATCH_BEFORE="$(cat "$SCRATCH")"
  OUT_SCRATCH="$(run_hook "$SCRATCH")"
  RC_SCRATCH=$?
  if [[ $RC_SCRATCH -eq 0 && -z "$OUT_SCRATCH" ]]; then
    ok "out-of-tree scratchpad .md skipped (exit 0, no findings)"
  else
    fail "out-of-tree scratchpad .md not skipped (rc=$RC_SCRATCH out=$OUT_SCRATCH)"
  fi
  if [[ "$(cat "$SCRATCH")" == "$SCRATCH_BEFORE" ]]; then
    ok "out-of-tree scratchpad .md left unmodified (no --fix)"
  else
    fail "out-of-tree scratchpad .md was modified: $(cat "$SCRATCH")"
  fi

  # Inherited repository overrides must not decide membership. GIT_DIR and
  # GIT_WORK_TREE override Git's discovery outright, so `git -C <out-of-tree
  # dir>` answers with the overridden repository — the same out-of-tree file
  # would be admitted and linted under that repository's rules. The fixture
  # carries an unfixable MD024 so a hook that DID run is visible in stdout.
  SCRATCH_GITDIR="$OUTOFTREE/comment-body-gitdir.md"
  printf '# Comment\n\n## Section\n\ntext\n\n## Section\n\n* bullet\n' >"$SCRATCH_GITDIR"
  OUT_GITDIR="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$SCRATCH_GITDIR" |
    env -u CLAUDE_PROJECT_DIR GIT_DIR="$REPO/.git" GIT_WORK_TREE="$REPO" \
      CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  RC_GITDIR=$?
  if [[ $RC_GITDIR -eq 0 && -z "$OUT_GITDIR" ]]; then
    ok "inherited GIT_DIR/GIT_WORK_TREE does not admit an out-of-tree .md"
  else
    fail "inherited GIT_DIR/GIT_WORK_TREE admitted an out-of-tree .md (rc=$RC_GITDIR out=$OUT_GITDIR)"
  fi
  if grep -q '^\* bullet$' "$SCRATCH_GITDIR"; then
    ok "out-of-tree .md unmodified under inherited GIT_DIR (no --fix)"
  else
    fail "out-of-tree .md was fixed under inherited GIT_DIR: $(cat "$SCRATCH_GITDIR")"
  fi

  # Symlink escape: an IN-repository path whose target is the out-of-tree file.
  # The lexical parent ($REPO) is a git tree, so a lexical membership test would
  # admit it and --fix would rewrite the external target under repo rules. The
  # guard must decide on the physical path, as hook::read_file_path does.
  # Skipped where the host cannot create real symlinks (Git Bash without
  # winsymlinks copies the file instead).
  LINK="$REPO/escaping-link.md"
  if ln -s "$SCRATCH" "$LINK" 2>/dev/null && [[ -L "$LINK" ]]; then
    LINK_BEFORE="$(cat "$SCRATCH")"
    OUT_LINK="$(run_hook "$LINK")"
    RC_LINK=$?
    if [[ $RC_LINK -eq 0 && -z "$OUT_LINK" ]]; then
      ok "in-repo symlink to out-of-tree .md skipped (exit 0, no findings)"
    else
      fail "in-repo symlink to out-of-tree .md not skipped (rc=$RC_LINK out=$OUT_LINK)"
    fi
    if [[ "$(cat "$SCRATCH")" == "$LINK_BEFORE" ]]; then
      ok "symlink target left unmodified (no --fix on the external file)"
    else
      fail "symlink target was modified: $(cat "$SCRATCH")"
    fi
    # Same escape with BOTH canonicalizers neutered, so hook::physical_path
    # degrades to the unchanged lexical path — whose parent ($REPO) IS a git
    # tree. A physical-path test alone would admit the link there and hand the
    # external target to --fix, so the guard must fail closed on an unresolved
    # symlink instead.
    #
    # The fixture carries a duplicate sibling heading (MD024, unfixable under
    # this repo's config) so a hook that DID run emits additionalContext: the
    # skip is proven by silence, not by an unchanged file. File content alone
    # would be a vacuous witness — the stub's `sed -i` replaces the link with a
    # regular file instead of writing through it, leaving the target intact
    # even when --fix ran.
    NO_CANON_ENV="$WORK/no-canonicalizer.bashenv"
    cat >"$NO_CANON_ENV" <<'EOF'
realpath() { return 1; }
readlink() { return 1; }
EOF
    run_hook_no_canon() {
      (cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$1" |
        env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_CANON_ENV" \
          CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")
    }
    SCRATCH_NC="$OUTOFTREE/comment-body-nocanon.md"
    printf '# Comment\n\n## Section\n\ntext\n\n## Section\n\n* bullet\n' >"$SCRATCH_NC"
    LINK_NC="$REPO/escaping-link-nocanon.md"
    ln -s "$SCRATCH_NC" "$LINK_NC"
    OUT_NOCANON="$(run_hook_no_canon "$LINK_NC")"
    RC_NOCANON=$?
    if [[ $RC_NOCANON -eq 0 && -z "$OUT_NOCANON" ]]; then
      ok "symlink escape fails closed when canonicalization is unavailable"
    else
      fail "symlink escape not skipped without canonicalizer (rc=$RC_NOCANON out=$OUT_NOCANON)"
    fi
    if [[ -L "$LINK_NC" ]]; then
      ok "escaping symlink untouched without canonicalizer (still a symlink)"
    else
      fail "escaping symlink was rewritten by --fix without canonicalizer"
    fi

    # Control: the neutered canonicalizers must not disable the hook wholesale,
    # or the silence above would prove nothing. The SAME fixture body in a
    # REGULAR in-repository file still lints and still reports MD024.
    NOCANON_REGULAR="$REPO/fixtureNoCanon.md"
    printf '# Comment\n\n## Section\n\ntext\n\n## Section\n\n* bullet\n' >"$NOCANON_REGULAR"
    OUT_NOCANON_REG="$(run_hook_no_canon "$NOCANON_REGULAR")"
    RC_NOCANON_REG=$?
    if [[ $RC_NOCANON_REG -eq 0 ]] &&
      printf '%s' "$OUT_NOCANON_REG" | jq -e '.hookSpecificOutput.additionalContext | test("MD024")' >/dev/null 2>&1; then
      ok "regular in-repo .md still linted without canonicalizer (control)"
    else
      fail "control failed: regular in-repo .md not linted without canonicalizer (rc=$RC_NOCANON_REG out=$OUT_NOCANON_REG)"
    fi
    rm -f "$LINK_NC"
  else
    ok "symlink-escape case SKIPPED (host cannot create real symlinks)"
  fi
  rm -f "$LINK"
fi
rm -rf "$OUTOFTREE"

# --- Repository-local markdownlint: use contained npm/Git Bash shim ---------
# Hide the PATH copy, then provide the extensionless POSIX shim npm installs
# beside its Windows .cmd launcher. The hook must execute it directly from the
# consuming repository, with no package runner or network fallback.
NO_MDLINT_ENV="$WORK/no-markdownlint.bashenv"
NPX_MARKER="$WORK/npx-was-invoked"
cat >"$NO_MDLINT_ENV" <<EOF
command() {
  if [[ "\${1:-}" == "-v" && "\${2:-}" == "markdownlint-cli2" ]]; then
    return 1
  fi
  if [[ "\${1:-}" == "-v" && "\${2:-}" == "npx" ]]; then
    printf '%s\\n' "$WORK/npx"
    return 0
  fi
  builtin command "\$@"
}
npx() {
  : >"$NPX_MARKER"
  return 99
}
EOF

LOCAL_BIN_DIR="$REPO/node_modules/.bin"
LOCAL_MDLINT="$LOCAL_BIN_DIR/markdownlint-cli2"
mkdir -p "$LOCAL_BIN_DIR"
cp "$TEST_BIN/markdownlint-cli2" "$LOCAL_MDLINT"
chmod +x "$LOCAL_MDLINT"
LOCAL_FIXTURE="$REPO/fixtureLocal.md"
printf '# Local\n\n* local item\n' >"$LOCAL_FIXTURE"
OUT_LOCAL="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$LOCAL_FIXTURE" |
  env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_MDLINT_ENV" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_LOCAL=$?
if [[ $RC_LOCAL -eq 0 && -z "$OUT_LOCAL" ]]; then
  ok "repo-local markdownlint shim exits 0 with no advisory"
else
  fail "repo-local markdownlint shim failed (rc=$RC_LOCAL out=$OUT_LOCAL)"
fi
if grep -q '^- local item$' "$LOCAL_FIXTURE"; then
  ok "repo-local markdownlint shim applied --fix"
else
  fail "repo-local markdownlint shim did not format: $(cat "$LOCAL_FIXTURE")"
fi
if [[ ! -e "$NPX_MARKER" ]]; then ok "repo-local markdownlint never invokes npx"; else fail "repo-local markdownlint invoked npx"; fi

# npm uses a relative .bin symlink on POSIX. Prove the resolver follows that
# normal contained shape without mistaking it for an escape. Git Bash may copy
# the target when native symlinks are unavailable; the regular-shim case above
# already covers that host, so this symlink-specific assertion skips there.
rm -f "$LOCAL_MDLINT"
LOCAL_PACKAGE_BIN="$REPO/node_modules/markdownlint-cli2/markdownlint-cli2"
mkdir -p "$(dirname "$LOCAL_PACKAGE_BIN")"
cp "$TEST_BIN/markdownlint-cli2" "$LOCAL_PACKAGE_BIN"
chmod +x "$LOCAL_PACKAGE_BIN"
ln -s ../markdownlint-cli2/markdownlint-cli2 "$LOCAL_MDLINT"
if [[ -L "$LOCAL_MDLINT" ]]; then
  LOCAL_SYMLINK_FIXTURE="$REPO/fixtureLocalSymlink.md"
  printf '# Local Symlink\n\n* symlink item\n' >"$LOCAL_SYMLINK_FIXTURE"
  OUT_LOCAL_SYMLINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$LOCAL_SYMLINK_FIXTURE" |
    env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_MDLINT_ENV" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  RC_LOCAL_SYMLINK=$?
  if [[ $RC_LOCAL_SYMLINK -eq 0 && -z "$OUT_LOCAL_SYMLINK" ]] &&
    grep -q '^- symlink item$' "$LOCAL_SYMLINK_FIXTURE"; then
    ok "contained relative POSIX .bin symlink applied --fix"
  else
    fail "contained relative POSIX .bin symlink failed (rc=$RC_LOCAL_SYMLINK out=$OUT_LOCAL_SYMLINK)"
  fi
else
  ok "contained relative POSIX .bin symlink skipped (host lacks native symlinks)"
fi

# --- Escaping repository-local binary: reject before execution --------------
rm -rf "$REPO/node_modules"
ESCAPE_DIR="$WORK/outside-node-modules"
ESCAPE_TARGET="$ESCAPE_DIR/.bin/markdownlint-cli2"
ESCAPE_MARKER="$WORK/outside-markdownlint-was-invoked"
mkdir -p "$ESCAPE_DIR/.bin"
cat >"$ESCAPE_TARGET" <<EOF
#!/usr/bin/env bash
: >"$ESCAPE_MARKER"
exit 0
EOF
chmod +x "$ESCAPE_TARGET"

ESCAPE_LINK_CREATED=false
ESCAPE_WINDOWS_JUNCTION=false
if command -v powershell.exe >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
  # shellcheck disable=SC2016 # $env variables expand in PowerShell, not Bash.
  LINK_PATH="$(cygpath -aw "$REPO/node_modules")" \
  TARGET_PATH="$(cygpath -aw "$ESCAPE_DIR")" \
    powershell.exe -NoLogo -NoProfile -NonInteractive -Command \
    'New-Item -ItemType Junction -Path $env:LINK_PATH -Target $env:TARGET_PATH | Out-Null' \
    >/dev/null 2>&1 &&
    ESCAPE_LINK_CREATED=true &&
    ESCAPE_WINDOWS_JUNCTION=true
else
  mkdir -p "$REPO/node_modules/.bin"
  ln -s "$ESCAPE_TARGET" "$LOCAL_MDLINT" && ESCAPE_LINK_CREATED=true
fi

if [[ "$ESCAPE_LINK_CREATED" == true ]]; then
  # Fresh CLAUDE_PLUGIN_DATA: the skip notice is once-per-session, so an
  # inherited data dir with a prior marker would suppress it and fail the assert.
  PD_ESCAPE="$(mktemp -d "$WORK/pd.XXXXXX")"
  OUT_ESCAPE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FA" |
    env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_MDLINT_ENV" CLAUDE_PLUGIN_DATA="$PD_ESCAPE" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  RC_ESCAPE=$?
  if [[ $RC_ESCAPE -eq 0 ]] &&
    printf '%s' "$OUT_ESCAPE" | jq -e '.hookSpecificOutput.additionalContext | contains("contained repository-local")' >/dev/null 2>&1; then
    ok "escaping repo-local markdownlint emits advisory"
  else
    fail "escaping repo-local markdownlint was not rejected (rc=$RC_ESCAPE out=$OUT_ESCAPE)"
  fi
  if [[ ! -e "$ESCAPE_MARKER" ]]; then ok "escaping repo-local markdownlint was not executed"; else fail "escaping repo-local markdownlint executed"; fi
else
  fail "could not create repo-local escape symlink fixture"
fi
if [[ "$ESCAPE_WINDOWS_JUNCTION" == true ]]; then
  # shellcheck disable=SC2016 # $env variables expand in PowerShell, not Bash.
  LINK_PATH="$(cygpath -aw "$REPO/node_modules")" \
    powershell.exe -NoLogo -NoProfile -NonInteractive -Command \
    'Remove-Item -LiteralPath $env:LINK_PATH -Force' >/dev/null 2>&1
else
  rm -rf "$REPO/node_modules"
fi

# --- Missing markdownlint: visible advisory, never npx ----------------------
# With neither PATH nor a contained local binary available, the hook must not
# invoke the package runner (which could fetch from the network).
PD_NO_MDLINT="$(mktemp -d "$WORK/pd.XXXXXX")"
OUT_NO_MDLINT="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FA" |
  env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_MDLINT_ENV" CLAUDE_PLUGIN_DATA="$PD_NO_MDLINT" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_NO_MDLINT=$?
if [[ $RC_NO_MDLINT -eq 0 ]]; then ok "missing markdownlint exits 0 (advisory)"; else fail "missing markdownlint exit $RC_NO_MDLINT"; fi
if printf '%s' "$OUT_NO_MDLINT" | jq -e '.hookSpecificOutput.additionalContext | contains("neither on PATH nor available as a contained repository-local")' >/dev/null 2>&1; then
  ok "missing markdownlint emits visible additionalContext"
else
  fail "missing markdownlint warning absent: $OUT_NO_MDLINT"
fi
if [[ ! -e "$NPX_MARKER" ]]; then ok "missing markdownlint never invokes npx"; else fail "missing markdownlint invoked npx"; fi

# --- Missing jq: visible advisory, no malformed parsing ---------------------
NO_JQ_ENV="$WORK/no-jq.bashenv"
cat >"$NO_JQ_ENV" <<'EOF'
command() {
  if [[ "${1:-}" == "-v" && "${2:-}" == "jq" ]]; then
    return 1
  fi
  builtin command "$@"
}
EOF
PD_NO_JQ="$(mktemp -d "$WORK/pd.XXXXXX")"
OUT_NO_JQ="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FA" |
  env -u CLAUDE_PROJECT_DIR BASH_ENV="$NO_JQ_ENV" CLAUDE_PLUGIN_DATA="$PD_NO_JQ" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_NO_JQ=$?
if [[ $RC_NO_JQ -eq 0 ]]; then ok "missing jq exits 0 (advisory)"; else fail "missing jq exit $RC_NO_JQ"; fi
if printf '%s' "$OUT_NO_JQ" | jq -e '(.hookSpecificOutput.additionalContext | contains("jq not found on PATH")) and (.systemMessage | contains("jq not found on PATH"))' >/dev/null 2>&1; then
  ok "missing jq emits visible notice on both channels"
else
  fail "missing jq warning absent: $OUT_NO_JQ"
fi

# --- Repository-config trust gate: risky config blocks lint until approved ---
# Uses the official persistent plugin-data surface so separate hook processes
# share the approval marker. A code-loading configuration must SKIP the lint
# run — with a visible notice on both channels — until the user records an
# explicit approval for that exact configuration-content state; any config
# change must revoke the approval. Blocking is observed through MD047: the
# fixture lacks a final newline, so a lint run is exactly "newline appended".
TRUST_DATA="$WORK/plugin-data"
ORIGINAL_CONFIG="$REPO/.markdownlint-cli2.jsonc"
SAVED_CONFIG="$WORK/original-markdownlint-cli2.jsonc"
mv "$ORIGINAL_CONFIG" "$SAVED_CONFIG"

has_final_newline() {
  [[ "$(tail -c 1 "$1" | od -An -tx1 | tr -d ' \n')" == "0a" ]]
}

cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
module.exports = {
  config: { "MD013": false },
  noBanner: true,
  noProgress: true
};
CJS
TRUST_FILE="$REPO/trust-cjs.md"
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"

OUT_TRUST_1="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_TRUST_1=$?
if [[ $RC_TRUST_1 -eq 0 ]]; then ok "unapproved executable config exits 0 (advisory)"; else fail "unapproved executable config exit $RC_TRUST_1"; fi
if printf '%s' "$OUT_TRUST_1" | jq -e '(.hookSpecificOutput.additionalContext | contains("trust gate") and contains(".markdownlint-cli2.cjs")) and (.systemMessage | contains("trust gate"))' >/dev/null 2>&1; then
  ok "executable .cjs config emits visible trust-gate notice on both channels"
else
  fail "executable .cjs trust-gate notice absent: $OUT_TRUST_1"
fi
if ! has_final_newline "$TRUST_FILE"; then
  ok "unapproved executable config blocks markdownlint --fix"
else
  fail "unapproved executable config still ran markdownlint --fix"
fi

# Same state, same session: the notice dedupes, but the lint run stays blocked.
OUT_TRUST_2="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -z "$OUT_TRUST_2" ]]; then
  ok "unchanged unapproved state notices only once per session"
else
  fail "unchanged unapproved state noticed again: $OUT_TRUST_2"
fi
if ! has_final_newline "$TRUST_FILE"; then
  ok "repeat edit stays blocked while unapproved"
else
  fail "repeat edit ran markdownlint --fix while unapproved"
fi

# The notice's approval instruction must name a marker under this plugin-data
# store; creating that marker is the explicit opt-in that enables the lint run.
TRUST_MARKER="$(printf '%s' "$OUT_TRUST_1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
if [[ -n "$TRUST_MARKER" && "$TRUST_MARKER" == "$TRUST_DATA"/* ]]; then
  ok "trust-gate notice carries an approval marker under CLAUDE_PLUGIN_DATA"
else
  fail "trust-gate approval marker missing or misplaced: $OUT_TRUST_1"
fi
mkdir -p "$TRUST_MARKER"
OUT_TRUST_3="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_TRUST_3=$?
if [[ $RC_TRUST_3 -eq 0 && -z "$OUT_TRUST_3" ]] && has_final_newline "$TRUST_FILE"; then
  ok "approved configuration state lints again (fix applied, no notice)"
else
  fail "approved configuration state did not lint (rc=$RC_TRUST_3 out=$OUT_TRUST_3)"
fi

# A config-content change produces a new state signature: the approval is
# revoked, and the gate blocks — and notices, despite the same session — again.
printf '\n// unreviewed configuration revision\n' >>"$REPO/.markdownlint-cli2.cjs"
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_4="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_4" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "changed executable config state revokes approval and blocks again"
else
  fail "changed executable config state was not re-gated: $OUT_TRUST_4"
fi

# Declarative CLI2 configuration still loads modules when these official keys
# are present. Empty arrays keep the fixture self-contained while proving all
# three key names are recognized without executing third-party test modules.
rm "$REPO/.markdownlint-cli2.cjs"
cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "customRules": [],
  "markdownItPlugins": [],
  "outputFormatters": [],
  "noBanner": true,
  "noProgress": true
}
JSONC
OUT_TRUST_MODULES="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_MODULES" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate") and contains(".markdownlint-cli2.jsonc")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "module-loading config keys are gated with a visible notice"
else
  fail "module-loading config keys were not gated: $OUT_TRUST_MODULES"
fi

# Fail closed: with no CLAUDE_PLUGIN_DATA an approval can be neither recorded
# nor verified, so a risky config must still skip the lint run (and notice
# every time — the once-per-session gate fails open toward visibility when it
# has no marker store).
OUT_TRUST_NOSTATE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR -u CLAUDE_PLUGIN_DATA CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_NOSTATE" | jq -e '.systemMessage | contains("trust gate")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "risky config without a plugin-data store fails closed"
else
  fail "risky config without a plugin-data store did not fail closed: $OUT_TRUST_NOSTATE"
fi

# A module-loading key spelled through a JSONC string escape must not slip past
# the textual key scan: the config is unverifiable as written, so it gates AND
# refuses approval (no marker instruction is offered).
cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "custom\u0052ules": [],
  "noBanner": true,
  "noProgress": true
}
JSONC
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_ESCAPE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_ESCAPE" | jq -e '(.systemMessage | contains("trust gate") and contains("defeat textual verification")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "escape-obfuscated module key gates and refuses approval"
else
  fail "escape-obfuscated module key was not gated unverifiable: $OUT_TRUST_ESCAPE"
fi

# A computed module expression (require whose argument is not a single string
# literal) cannot be pinned by the text scan, so the state must refuse approval
# outright rather than sign a module graph it cannot see.
rm -f "$ORIGINAL_CONFIG"
cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const path = require("path");
module.exports = {
  config: { "MD013": false },
  customRules: [require(path.join(__dirname, "rules", "local.cjs"))],
  noBanner: true,
  noProgress: true
};
CJS
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_COMPUTED="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_COMPUTED" | jq -e '(.systemMessage | contains("trust gate")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "computed require expression gates and refuses approval"
else
  fail "computed require expression was not refused: $OUT_TRUST_COMPUTED"
fi
rm "$REPO/.markdownlint-cli2.cjs"

# An escaped module specifier decodes to a different path than its raw text
# (Node reads this one as ./rules.js), so it cannot be pinned: refuse approval.
cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
module.exports = {
  config: { "MD013": false },
  customRules: [require("./r\u0075les.js")],
  noBanner: true,
  noProgress: true
};
CJS
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_ESCSPEC="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_ESCSPEC" | jq -e '(.systemMessage | contains("trust gate")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "escaped module specifier gates and refuses approval"
else
  fail "escaped module specifier was not refused: $OUT_TRUST_ESCSPEC"
fi
rm "$REPO/.markdownlint-cli2.cjs"

# An EXECUTABLE config that carries a module-loading key gets no approval route,
# whatever the entry looks like: markdownlint-cli2 resolves those entries itself,
# so the entry may be any string-producing expression and no text scan can
# enumerate that space. Both a plain literal and an array-built path are refused
# here — the literal case is the capability this deliberately gives up, and the
# array case is what no per-shape pattern could have caught.
mkdir -p "$REPO/rules"
cat >"$REPO/rules/local.cjs" <<'CJS'
module.exports = { names: ["local"], description: "noop", tags: [], function: () => {} };
CJS
for shape in literal arrayjoin; do
  case "$shape" in
  literal)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
module.exports = {
  config: { "MD013": false },
  customRules: ["./rules/local.cjs"],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  arrayjoin)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
module.exports = {
  config: { "MD013": false },
  customRules: [["./rules", "local.cjs"].join("/")],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  *) fail "unknown JS-config shape: $shape" ;;
  esac
  printf '# Executable config

Clean text.' >"$TRUST_FILE"
  OUT_JSKEY="$(cd "$UNRELATED" && printf '{"session_id":"jskey-%s","tool_input":{"file_path":"%s"}}' "$shape" "$TRUST_FILE" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  if printf '%s' "$OUT_JSKEY" | jq -e '(.systemMessage | contains("trust gate") and contains("cannot pin")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
    ! has_final_newline "$TRUST_FILE"; then
    ok "module-loading key in an executable config ($shape) refuses approval"
  else
    fail "module-loading key in an executable config ($shape) was not refused: $OUT_JSKEY"
  fi
  rm "$REPO/.markdownlint-cli2.cjs"
done

# A declarative config can carry BOTH a literal module key AND an escaped module
# VALUE. The escape verdict must still fire: chained as an else-branch, the key
# match suppressed it and the collector hashed the raw escaped spelling instead
# of the file markdownlint decodes it to and loads.
# The escape is assembled from a backslash variable (unquoted heredoc) so the
# fixture's intent survives authoring: the file must hold the six characters
# backslash-u-0-0-6-1, which JSONC decodes to the letter "a".
BS=$'\\'
cat >"$ORIGINAL_CONFIG" <<JSONC
{
  "config": { "MD013": false },
  "customRules": ["./rules/loc${BS}u0061l.cjs"],
  "noBanner": true,
  "noProgress": true
}
JSONC
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_BOTH="$(cd "$UNRELATED" && printf '{"session_id":"key-and-escape","tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_BOTH" | jq -e '(.systemMessage | contains("trust gate") and contains("defeat textual verification")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "literal key plus escaped module value still reaches the escape verdict"
else
  fail "literal key suppressed the escape verdict: $OUT_BOTH"
fi
rm -f "$ORIGINAL_CONFIG"
rm -rf "$REPO/rules"

# The evasions a loader-proximity pattern cannot see. Each must still refuse
# approval, and each defeats a `require`-adjacency window on its own:
#   comment    a JS comment between the loader name and its open paren
#   nocall     markdownlint-cli2 resolves customRules itself, so an assembled
#              specifier needs no loader token in the file at all
#   concat     string concatenation assembles the specifier
#   bare       a computed specifier reached through a variable, with a comment
#              separating it from the loader
#   envkey     the specifier comes straight from the environment: no loader call
#              and no path helper, so only the process.* token sees it
#   alias      path reached through an alias and a destructured import, with no
#              __dirname, process, template or concatenation to fall back on, so
#              only refusing the path IMPORT sees it
for evasion in comment nocall concat bare envkey alias; do
  case "$evasion" in
  comment)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const path = require("node:path");
module.exports = {
  config: { "MD013": false },
  customRules: [require/*sneak*/(path.join(__dirname, "rules", "local.cjs"))],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  nocall)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const path = require("node:path");
module.exports = {
  config: { "MD013": false },
  customRules: [
    path.join(__dirname, "rules", "local.cjs")
  ],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  concat)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const dir = "./rules";
module.exports = {
  config: { "MD013": false },
  customRules: [dir + "/local.cjs"],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  bare)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const which = process.env.MDLINT_RULE_MODULE;
module.exports = {
  config: { "MD013": false },
  customRules: [require /* pick */ (which)],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  envkey)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
module.exports = {
  config: { "MD013": false },
  customRules: [process.env.MDLINT_RULE_MODULE],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  alias)
    cat >"$REPO/.markdownlint-cli2.cjs" <<'CJS'
const { join, resolve } = require("path");
const base = resolve("rules");
module.exports = {
  config: { "MD013": false },
  customRules: [join(base, "local.cjs")],
  noBanner: true,
  noProgress: true
};
CJS
    ;;
  *) fail "unknown evasion fixture: $evasion" ;;
  esac
  printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
  OUT_EVADE="$(cd "$UNRELATED" && printf '{"session_id":"evade-%s","tool_input":{"file_path":"%s"}}' "$evasion" "$TRUST_FILE" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  if printf '%s' "$OUT_EVADE" | jq -e '(.systemMessage | contains("trust gate") and contains("cannot pin")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
    ! has_final_newline "$TRUST_FILE"; then
    ok "unpinnable specifier ($evasion) gates and refuses approval"
  else
    fail "unpinnable specifier ($evasion) was not refused: $OUT_EVADE"
  fi
  rm "$REPO/.markdownlint-cli2.cjs"
done

# The approval signature must cover the referenced module content, not only the
# config text: after approving a config whose customRules names a repository
# module, changing THAT MODULE (config untouched) must revoke the approval.
mkdir -p "$REPO/rules"
cat >"$REPO/rules/local-rule.cjs" <<'CJS'
module.exports = { names: ["local-rule"], description: "noop", tags: [], function: () => {} };
CJS
cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "customRules": ["./rules/local-rule.cjs"],
  "noBanner": true,
  "noProgress": true
}
JSONC
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_MOD1="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
MOD_MARKER="$(printf '%s' "$OUT_TRUST_MOD1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
if [[ -n "$MOD_MARKER" && "$MOD_MARKER" == "$TRUST_DATA"/* ]] && ! has_final_newline "$TRUST_FILE"; then
  ok "module-referencing config gates with an approval marker"
else
  fail "module-referencing config not gated with marker: $OUT_TRUST_MOD1"
fi
mkdir -p "$MOD_MARKER"
OUT_TRUST_MOD2="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -z "$OUT_TRUST_MOD2" ]] && has_final_newline "$TRUST_FILE"; then
  ok "approved config+module state lints"
else
  fail "approved config+module state did not lint: $OUT_TRUST_MOD2"
fi
printf '\n// unreviewed rule revision\n' >>"$REPO/rules/local-rule.cjs"
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_MOD3="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_TRUST_MOD3" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "changed referenced module revokes approval and blocks again"
else
  fail "changed referenced module did not revoke approval: $OUT_TRUST_MOD3"
fi
# An EXTENSIONLESS module reference resolves through Node's CommonJS extension
# candidates, so it must pin the same module file: approving a config that says
# "./rules/local-rule" and then changing local-rule.cjs must revoke.
cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "customRules": ["./rules/local-rule"],
  "noBanner": true,
  "noProgress": true
}
JSONC
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_EXT1="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
EXT_MARKER="$(printf '%s' "$OUT_TRUST_EXT1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$EXT_MARKER"
printf '\n// another unreviewed rule revision\n' >>"$REPO/rules/local-rule.cjs"
printf '# Executable config\n\nClean text.' >"$TRUST_FILE"
OUT_TRUST_EXT2="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -n "$EXT_MARKER" ]] && printf '%s' "$OUT_TRUST_EXT2" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "extensionless module reference is pinned; module change revokes approval"
else
  fail "extensionless module reference not pinned: m=$EXT_MARKER out=$OUT_TRUST_EXT2"
fi
rm -rf "$REPO/rules"

# A YAML plain scalar carries no quotes, so the quoted-string scan never saw
# `customRules: [./rules/local.cjs]` and the module stayed out of the signature:
# the config-only marker approved, then changing the rule file kept it valid.
# Approve, then change ONLY the rule module: the approval must be revoked.
mkdir -p "$REPO/rules"
cat >"$REPO/rules/plain.cjs" <<'CJS'
module.exports = { names: ["plain"], description: "noop", tags: [], function: () => {} };
CJS
rm -f "$ORIGINAL_CONFIG"
cat >"$REPO/.markdownlint-cli2.yaml" <<'YAML'
config:
  MD013: false
customRules: [./rules/plain.cjs]
noBanner: true
noProgress: true
YAML
printf '# Executable config

Clean text.' >"$TRUST_FILE"
OUT_YAML1="$(cd "$UNRELATED" && printf '{"session_id":"yaml-plain-a","tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
Y_MARKER="$(printf '%s' "$OUT_YAML1" | jq -r '.systemMessage' | sed -n "s/.*mkdir -p '\([^']*\)'.*/\1/p")"
mkdir -p "$Y_MARKER"
printf '
// unreviewed rule revision
' >>"$REPO/rules/plain.cjs"
printf '# Executable config

Clean text.' >"$TRUST_FILE"
OUT_YAML2="$(cd "$UNRELATED" && printf '{"session_id":"yaml-plain-b","tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -n "$Y_MARKER" ]] && printf '%s' "$OUT_YAML2" | jq -e '.hookSpecificOutput.additionalContext | contains("trust gate")' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "unquoted YAML module path is pinned; module change revokes approval"
else
  fail "unquoted YAML module path not pinned: m=$Y_MARKER out=$OUT_YAML2"
fi
rm -f "$REPO/.markdownlint-cli2.yaml"
rm -rf "$REPO/rules"

# The same escape without needing symlink support: a `../` reference reaching a
# file outside the repository. Runs on every host, so the branch stays covered
# where the symlink fixture below has to skip.
mkdir -p "$WORK/outside-repo"
printf '%s
' 'module.exports = { names: ["a"], description: "x", tags: [], function: () => {} };' >"$WORK/outside-repo/ext.cjs"
cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "customRules": ["../outside-repo/ext.cjs"],
  "noBanner": true,
  "noProgress": true
}
JSONC
printf '# Executable config

Clean text.' >"$TRUST_FILE"
OUT_ESCAPE_REL="$(cd "$UNRELATED" && printf '{"session_id":"dotdot-escape","tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if printf '%s' "$OUT_ESCAPE_REL" | jq -e '(.systemMessage | contains("trust gate") and contains("cannot pin")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
  ! has_final_newline "$TRUST_FILE"; then
  ok "module reference escaping the repository refuses approval"
else
  fail "out-of-repository module reference was not refused: $OUT_ESCAPE_REL"
fi
rm -f "$ORIGINAL_CONFIG"
rm -rf "$WORK/outside-repo"

# A repository module symlink whose target resolves OUTSIDE the repository names
# code no repository-content signature can cover: re-aiming the symlink at a
# different existing external target leaves the signature identical while Node
# follows the new one. Such a state must refuse approval rather than sign it.
if OUTSIDE_DIR="$(mktemp -d)" &&
  printf '%s
' 'module.exports = { names: ["a"], description: "x", tags: [], function: () => {} };' >"$OUTSIDE_DIR/ext.cjs" &&
  mkdir -p "$REPO/rules" &&
  ln -s "$OUTSIDE_DIR/ext.cjs" "$REPO/rules/escaping.cjs" 2>/dev/null &&
  [[ -L "$REPO/rules/escaping.cjs" ]]; then
  cat >"$ORIGINAL_CONFIG" <<'JSONC'
{
  "config": { "MD013": false },
  "customRules": ["./rules/escaping.cjs"],
  "noBanner": true,
  "noProgress": true
}
JSONC
  printf '# Executable config

Clean text.' >"$TRUST_FILE"
  OUT_ESCAPE_LINK="$(cd "$UNRELATED" && printf '{"session_id":"symlink-escape","tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
  if printf '%s' "$OUT_ESCAPE_LINK" | jq -e '(.systemMessage | contains("trust gate") and contains("cannot pin")) and (.systemMessage | contains("mkdir -p") | not)' >/dev/null 2>&1 &&
    ! has_final_newline "$TRUST_FILE"; then
    ok "module symlink resolving outside the repository refuses approval"
  else
    fail "out-of-repository module symlink was not refused: $OUT_ESCAPE_LINK"
  fi
  rm -f "$ORIGINAL_CONFIG"
  rm -rf "$REPO/rules" "$OUTSIDE_DIR"
else
  echo "SKIP: host cannot create real symlinks for the escape fixture"
  rm -rf "$REPO/rules" "${OUTSIDE_DIR:-}"
fi

# Negative control: a declarative rule-only config is not executable and loads
# no modules, so linting proceeds immediately with no gate noise.
mv "$SAVED_CONFIG" "$ORIGINAL_CONFIG"
OUT_TRUST_SAFE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$TRUST_FILE" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_DATA="$TRUST_DATA" CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
if [[ -z "$OUT_TRUST_SAFE" ]] && has_final_newline "$TRUST_FILE"; then
  ok "rule-only declarative config lints with no trust gate"
else
  fail "rule-only declarative config gated or noisy: $OUT_TRUST_SAFE"
fi

# --- Kill switch: disabled hook is a no-op ----------------------------------
OUT_K="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$FB" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=false bash "$HOOK")"
RC_K=$?
if [[ $RC_K -eq 0 && -z "$OUT_K" ]]; then
  ok "kill switch disables hook"
else
  fail "kill switch failed (rc=$RC_K out=$OUT_K)"
fi

# ============================================================================
# Phase 2: hook telemetry tests
# ============================================================================

# --- Telemetry sink unset → hook stdout + exit identical to pre-change ------
# Additive-safety proof: HOOK_TELEMETRY_SINK unset must produce byte-identical
# stdout and exit code to the pre-Phase-2 baseline.

# Re-run fixture A with sink unset — must still produce empty stdout, exit 0.
printf '# Title A2\r\n\r\nSome text\r\n\r\n- item one\r\n- item two' >"$REPO/fixtureA2.md"
OUT_A_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"}}' "$REPO/fixtureA2.md" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_A_NOSINK=$?
if [[ $RC_A_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset: exit 0 (parity)"; else fail "telemetry/sink-unset: expected 0, got $RC_A_NOSINK"; fi
if [[ -z "$OUT_A_NOSINK" ]]; then ok "telemetry/sink-unset: empty stdout (parity)"; else fail "telemetry/sink-unset: stdout not empty: $OUT_A_NOSINK"; fi

# Re-run fixture B with sink unset — must still emit additionalContext, exit 0.
printf '# Doc B2\n\n## Section\n\ntext\n\n## Section\n\n* star item\n' >"$REPO/fixtureB2.md"
OUT_B_NOSINK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Edit"}' "$REPO/fixtureB2.md" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true bash "$HOOK")"
RC_B_NOSINK=$?
if [[ $RC_B_NOSINK -eq 0 ]]; then ok "telemetry/sink-unset B: exit 0 (parity)"; else fail "telemetry/sink-unset B: expected 0, got $RC_B_NOSINK"; fi
if printf '%s' "$OUT_B_NOSINK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/sink-unset B: additionalContext present (parity)"
else
  fail "telemetry/sink-unset B: no additionalContext: $OUT_B_NOSINK"
fi
# Emit must NOT appear in hook stdout (no envelope JSON alongside additionalContext)
if printf '%s' "$OUT_B_NOSINK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/sink-unset B: envelope leaked to hook stdout"
else
  ok "telemetry/sink-unset B: no envelope in hook stdout"
fi

# --- Stub sink: real edit → schema-valid envelope with status ok and findings -
TEL_FILE="$(mktemp)"
STUB_SINK="$(make_sink "cat >\"$TEL_FILE\"")"

# Fixture with unfixable finding (MD024 duplicate heading): status ok + findings populated.
printf '# Doc T\n\n## Section\n\ntext\n\n## Section\n\nmore text\n' >"$REPO/fixtureT.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_FILE
_OUT_T="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureT.md" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_SINK" bash "$HOOK")"
RC_T=$?
wait_for_sink "$TEL_FILE"

if [[ $RC_T -eq 0 ]]; then ok "telemetry/stub-sink: hook exit 0"; else fail "telemetry/stub-sink: hook exit $RC_T"; fi

if [[ -s "$TEL_FILE" ]]; then
  ok "telemetry/stub-sink: envelope received"
  # Validate all 7 required common fields
  for field in schema_version timestamp hook hook_event status duration_ms data; do
    if jq -e "has(\"$field\")" "$TEL_FILE" >/dev/null 2>&1; then
      ok "telemetry/envelope: $field present"
    else
      fail "telemetry/envelope: $field missing. file=$(cat "$TEL_FILE")"
    fi
  done
  # status must be "ok"
  TEL_STATUS="$(jq -r '.status' "$TEL_FILE")"
  if [[ "$TEL_STATUS" == "ok" ]]; then ok "telemetry/envelope: status ok"; else fail "telemetry/envelope: status expected ok, got $TEL_STATUS"; fi
  # data.findings must contain exactly the MD024 violation line (not banner noise).
  # Schema: "Unfixable markdownlint violations remaining after --fix, one per line."
  # Banner lines (version, Finding:, Linting:, Summary:) must be excluded.
  TEL_FINDINGS_LEN="$(jq '.data.findings | length' "$TEL_FILE")"
  if [[ "$TEL_FINDINGS_LEN" -eq 1 ]]; then
    ok "telemetry/envelope: findings has exactly 1 item (violation only, no banner noise)"
  else
    fail "telemetry/envelope: findings expected 1 violation, got $TEL_FINDINGS_LEN: $(jq '.data.findings' "$TEL_FILE")"
  fi
  # The single finding must name the MD024 rule.
  if jq -e '.data.findings[0] | test("MD024")' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: findings[0] names MD024"
  else
    fail "telemetry/envelope: findings[0] does not name MD024: $(jq '.data.findings[0]' "$TEL_FILE")"
  fi
  # data.tool must be "Write" (from the input JSON)
  TEL_TOOL="$(jq -r '.data.tool' "$TEL_FILE")"
  if [[ "$TEL_TOOL" == "Write" ]]; then ok "telemetry/envelope: data.tool is Write"; else fail "telemetry/envelope: data.tool expected Write, got $TEL_TOOL"; fi
  # data.file must be repo-relative (schema: "relative to the consuming repo root").
  # A relative path does not start with / or a Windows drive letter.
  TEL_FILE_VAL="$(jq -r '.data.file' "$TEL_FILE")"
  if [[ -n "$TEL_FILE_VAL" && "$TEL_FILE_VAL" != /* && "$TEL_FILE_VAL" != ?:* ]]; then
    ok "telemetry/envelope: data.file is repo-relative ($TEL_FILE_VAL)"
  else
    fail "telemetry/envelope: data.file expected repo-relative, got: $TEL_FILE_VAL"
  fi
  # schema_version must be "1.0"
  TEL_SV="$(jq -r '.schema_version' "$TEL_FILE")"
  if [[ "$TEL_SV" == "1.0" ]]; then ok "telemetry/envelope: schema_version 1.0"; else fail "telemetry/envelope: schema_version expected 1.0, got $TEL_SV"; fi
  # duration_ms must be non-negative integer
  if jq -e '.duration_ms | type == "number" and . >= 0 and floor == .' "$TEL_FILE" >/dev/null 2>&1; then
    ok "telemetry/envelope: duration_ms is non-negative integer"
  else
    fail "telemetry/envelope: duration_ms invalid: $(jq .duration_ms "$TEL_FILE")"
  fi
else
  fail "telemetry/stub-sink: no envelope written to sink"
  for field in schema_version timestamp hook hook_event status duration_ms data status findings tool file schema_version duration_ms; do
    : # counters already accounted by the outer if branch counting
  done
  fail "telemetry/envelope: status (no envelope)"
  fail "telemetry/envelope: findings (no envelope)"
  fail "telemetry/envelope: data.tool (no envelope)"
  fail "telemetry/envelope: data.file (no envelope)"
  fail "telemetry/envelope: schema_version (no envelope)"
  fail "telemetry/envelope: duration_ms (no envelope)"
fi
rm -f "$TEL_FILE"

# --- Stub sink: clean file → status ok, findings empty array -----------------
TEL_CLEAN="$(mktemp)"
STUB_CLEAN="$(make_sink "cat >\"$TEL_CLEAN\"")"
printf '# Clean Doc\n\nSome text.\n' >"$REPO/fixtureClean.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_CLEAN
_OUT_CLEAN="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureClean.md" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$STUB_CLEAN" bash "$HOOK")"
RC_CLEAN=$?
wait_for_sink "$TEL_CLEAN"

if [[ $RC_CLEAN -eq 0 ]]; then ok "telemetry/clean: hook exit 0"; else fail "telemetry/clean: hook exit $RC_CLEAN"; fi
if [[ -s "$TEL_CLEAN" ]]; then
  STATUS_CLEAN="$(jq -r '.status' "$TEL_CLEAN")"
  if [[ "$STATUS_CLEAN" == "ok" ]]; then ok "telemetry/clean: status ok"; else fail "telemetry/clean: status expected ok, got $STATUS_CLEAN"; fi
  FINDINGS_CLEAN="$(jq '.data.findings | length' "$TEL_CLEAN")"
  if [[ "$FINDINGS_CLEAN" -eq 0 ]]; then ok "telemetry/clean: findings empty array"; else fail "telemetry/clean: findings should be empty, got $FINDINGS_CLEAN items"; fi
else
  fail "telemetry/clean: no envelope written"
  fail "telemetry/clean: status (no envelope)"
  fail "telemetry/clean: findings empty (no envelope)"
fi
rm -f "$TEL_CLEAN"

# --- Stub sink non-zero exit → format + hook exit 0 unaffected ---------------
FAIL_SINK_FILE="$(mktemp)"
# A sink that exits non-zero but still writes (to prove hook ignores sink failure)
FAIL_SINK="$(make_sink "cat >\"$FAIL_SINK_FILE\"; exit 1")"
printf '# Failing Sink Doc\n\nSome text.\n' >"$REPO/fixtureFailSink.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; exit code is the assertion
_OUT_FS="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureFailSink.md" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$FAIL_SINK" bash "$HOOK")"
RC_FS=$?
wait_for_sink "$FAIL_SINK_FILE"

if [[ $RC_FS -eq 0 ]]; then ok "telemetry/fail-sink: hook exit 0 despite sink failure"; else fail "telemetry/fail-sink: hook exit $RC_FS, expected 0"; fi
rm -f "$FAIL_SINK_FILE"

# --- Slow sink (C1 fd1-leak detector): hook does not wait on it --------------
# Invariant: the backgrounded telemetry sink must not keep fd1 open, so the
# hook's command substitution returns as soon as the hook exits, NOT after the
# sink finishes. A leak would make $() block until the sink closes fd1 — i.e.
# for the sink's whole sleep.
#
# Measured differentially rather than against a fixed wall-clock bound. Spawn
# overhead is machine- and load-dependent (on Windows Git Bash a single hook is
# already ~1.5s, and parallel test suites push it higher), so any fixed
# threshold either false-fails under load or has to be set so high the sink must
# sleep long enough to linger past the suite's EXIT cleanup and lock its stub
# file on Windows. A baseline run (fast sink, no sleep) captures the SAME ambient
# overhead as the slow run under the SAME capture; subtracting it cancels the
# overhead and isolates the leak signal. Under a leak the delta is ~SINK_SLEEP;
# with no leak it is ~0 (± scheduling jitter).
#
# THRESHOLD_MS asserts the actual invariant — "did not wait for the sink" —
# as sleep-minus-a-safety-margin, NOT half the sleep. Halving discarded margin
# for no gain and was proven too tight empirically (#448 reopen): a clean-main
# false-fail measured delta=3697ms against the old 3000ms/half-sleep threshold,
# and load-generated measurements up to ~2150ms (30 concurrent suite runs on
# Windows Git Bash) confirm noise alone can approach that old threshold.
#
# The threshold has TWO margins and both must clear that 2150ms worst observed
# noise, because the detector can fail in either direction:
#
#   noise side  threshold - max_noise      a no-leak run must stay BELOW it
#   leak  side  leak_signal - threshold    a leaking run must stay ABOVE it
#
# The leak side is the one a too-HIGH threshold breaks, and it is not covered by
# the min-of-N baseline below: that protects against ONE unlucky baseline sample,
# not against a load shift that inflates ALL of them and then subsides before the
# slow run. Baselines 2s+ slower than the slow run's own overhead subtract real
# leak signal out of the delta, so a leak whose delta lands between the threshold
# and SINK_SLEEP passes silently. SINK_SLEEP=8s with SAFETY_MARGIN_MS=3000 puts
# the threshold at 5000ms, roughly midway between the signal and the noise:
# 2850ms of noise-side margin and 3000ms of leak-side margin, both above the
# 2150ms worst case measured. Recorded measurements bracket it — a deliberately
# reintroduced leak measured delta=8065ms (detected), while 40 runs under 30x
# concurrent load peaked at ~1555ms with no leak (passed).
#
# The baseline is the MINIMUM of several fast runs, not a single sample. A lone
# baseline that happened to be descheduled longer than the slow run would shrink
# DELTA_MS below the threshold and let a real fd1 leak PASS — a false-NEGATIVE
# (fail-open). Only an *inflated* baseline can mask a leak, so the minimum
# reflects true-minimal overhead and keeps the leak signal (~SINK_SLEEP) in the
# delta regardless of one unlucky sample. The opposite error — an inflated slow
# sample with no leak — only re-fails a green run (fail-safe, re-runnable), so
# just the baseline needs min-of-N; the slow run stays single (each slow sample
# costs SINK_SLEEP).
SINK_SLEEP=8
SAFETY_MARGIN_MS=3000
BASE_SAMPLES=3
BASE_SINK="$(make_sink "cat >/dev/null")"
SLOW_SINK="$(make_sink "cat >/dev/null; sleep $SINK_SLEEP")"
printf '# Slow Sink Doc\n\nSome text.\n' >"$REPO/fixtureSlowSink.md"

# Baseline and slow runs differ ONLY by the sink's sleep — same fixture, same
# env — so the shared per-invocation overhead cancels in the delta.
run_slow_sink() {
  cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureSlowSink.md" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$1" bash "$HOOK"
}

BASE_MS=""
for ((_i = 0; _i < BASE_SAMPLES; _i++)); do
  _TS0=$EPOCHREALTIME
  # shellcheck disable=SC2034  # captured so $() blocks until fd1 closes (baseline overhead)
  _OUT_BASE="$(run_slow_sink "$BASE_SINK")"
  _TS1=$EPOCHREALTIME
  _b=$(epoch_delta_ms "$_TS0" "$_TS1")
  if [[ -z "$BASE_MS" || $_b -lt $BASE_MS ]]; then BASE_MS=$_b; fi
done

_TS0=$EPOCHREALTIME
# shellcheck disable=SC2034  # captured so $() blocks until fd1 closes — proves no fd1 leak
_OUT_SLOW="$(run_slow_sink "$SLOW_SINK")"
RC_SLOW=$?
_TS1=$EPOCHREALTIME
SLOW_MS=$(epoch_delta_ms "$_TS0" "$_TS1")

DELTA_MS=$((SLOW_MS - BASE_MS))
THRESHOLD_MS=$((SINK_SLEEP * 1000 - SAFETY_MARGIN_MS))
echo "  (C1 fd1-leak: base=${BASE_MS}ms (min of ${BASE_SAMPLES}) slow=${SLOW_MS}ms delta=${DELTA_MS}ms, threshold <${THRESHOLD_MS}ms, sink sleeps ${SINK_SLEEP}s)"
if [[ $RC_SLOW -eq 0 ]]; then ok "telemetry/slow-sink: hook exit 0"; else fail "telemetry/slow-sink: hook exit $RC_SLOW"; fi
if [[ $DELTA_MS -lt $THRESHOLD_MS ]]; then
  ok "telemetry/slow-sink: hook did not wait for the sink (delta ${DELTA_MS}ms << ${SINK_SLEEP}s sleep = no fd1 leak)"
else
  fail "telemetry/slow-sink: delta ${DELTA_MS}ms ≈ sink's ${SINK_SLEEP}s sleep — fd1 leak blocks \$() until the sink exits"
fi

# --- Emit never leaks to hook stdout -----------------------------------------
# hook stdout must contain ONLY the hookSpecificOutput JSON (for residual case)
# or be empty (clean case). Never the telemetry envelope.
TEL_LEAK="$(mktemp)"
LEAK_SINK="$(make_sink "cat >\"$TEL_LEAK\"")"
printf '# Leak Doc\n\n## Section\n\ntext\n\n## Section\n\nmore text\n' >"$REPO/fixtureLeakCheck.md"
OUT_LEAK="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureLeakCheck.md" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$LEAK_SINK" bash "$HOOK")"
wait_for_sink "$TEL_LEAK"

# The hook stdout must NOT contain the telemetry envelope's top-level keys
if printf '%s' "$OUT_LEAK" | jq -e '.schema_version' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope schema_version found in hook stdout"
elif printf '%s' "$OUT_LEAK" | jq -e '.duration_ms' >/dev/null 2>&1; then
  fail "telemetry/stdout-leak: envelope duration_ms found in hook stdout"
else
  ok "telemetry/stdout-leak: no envelope in hook stdout"
fi
# Hook stdout must still contain additionalContext (findings present for this fixture)
if printf '%s' "$OUT_LEAK" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null 2>&1; then
  ok "telemetry/stdout-leak: additionalContext still present when sink set"
else
  fail "telemetry/stdout-leak: additionalContext missing when sink set: $OUT_LEAK"
fi
rm -f "$TEL_LEAK"

# --- Unwired producer runs zero telemetry-only subprocesses -------------------
# The telemetry payload (tool_name jq parse, cygpath path normalization, data
# JSON build) must be gated on sink presence. Count the hook's subprocess
# spawns via PATH shims: a cygpath shim that logs and echoes its last argument
# unchanged (a plausible `-lm` result on any host, so the Windows branch is
# exercised even on Linux), and a jq shim that logs then delegates to the real
# jq so hook behavior is unaffected. cygpath assertions filter on the hook's
# `-lm` flag: on Windows, npm/npx launcher shims may call `cygpath -w` on
# their own, which is not the hook's doing.
SHIM_DIR="$WORK/shims"
mkdir -p "$SHIM_DIR"
CYG_LOG="$WORK/cygpath.log"
JQ_LOG="$WORK/jq.log"
REAL_JQ="$(command -v jq)"
cat >"$SHIM_DIR/cygpath" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$CYG_LOG"
printf '%s\n' "\${!#}"
EOF
cat >"$SHIM_DIR/jq" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$JQ_LOG"
exec "$REAL_JQ" "\$@"
EOF
chmod +x "$SHIM_DIR/cygpath" "$SHIM_DIR/jq"

count_lm() { grep -c -- '-lm' "$CYG_LOG" 2>/dev/null || true; }

# Unwired (sink unset), clean fixture: the legitimate jq spawns are
# hook::buffer_stdin's payload-completeness probe (`jq -e .` — a piped read
# always ends read -d '' with a non-zero status at EOF, so the probe runs on
# every invocation) and hook::read_file_path's file_path parse — TOOL, FILE_REL
# and data_json are all telemetry-only and must not be built.
: >"$CYG_LOG"
: >"$JQ_LOG"
printf '# Gate Doc\n\nClean text.\n' >"$REPO/fixtureGate.md"
OUT_GATE="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureGate.md" |
  env -u CLAUDE_PROJECT_DIR -u HOOK_TELEMETRY_SINK CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true PATH="$SHIM_DIR:$PATH" bash "$HOOK")"
RC_GATE=$?
if [[ $RC_GATE -eq 0 && -z "$OUT_GATE" ]]; then
  ok "telemetry-gate/unwired: exit 0, empty stdout"
else
  fail "telemetry-gate/unwired: rc=$RC_GATE out=$OUT_GATE"
fi
CYG_LM_UNWIRED="$(count_lm)"
if [[ "$CYG_LM_UNWIRED" -eq 0 ]]; then
  ok "telemetry-gate/unwired: zero cygpath -lm spawns"
else
  fail "telemetry-gate/unwired: $CYG_LM_UNWIRED cygpath -lm spawns: $(cat "$CYG_LOG")"
fi
JQ_UNWIRED="$(wc -l <"$JQ_LOG")"
if [[ "$JQ_UNWIRED" -eq 2 ]]; then
  ok "telemetry-gate/unwired: exactly 2 jq spawns (stdin probe + file_path parse)"
else
  fail "telemetry-gate/unwired: expected 2 jq spawns, got $JQ_UNWIRED: $(cat "$JQ_LOG")"
fi

# Wired (stub sink), same fixture shape: the payload construction must still
# run — positive control proving the shims observe the telemetry spawns (the
# unwired zeroes above would otherwise pass vacuously).
: >"$CYG_LOG"
: >"$JQ_LOG"
TEL_GATE="$(mktemp)"
GATE_SINK="$(make_sink "cat >\"$TEL_GATE\"")"
printf '# Gate Doc Wired\n\nClean text.\n' >"$REPO/fixtureGateWired.md"
# shellcheck disable=SC2034  # stdout captured for timing correctness; content checked via TEL_GATE
_OUT_GW="$(cd "$UNRELATED" && printf '{"tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$REPO/fixtureGateWired.md" |
  env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true HOOK_TELEMETRY_SINK="$GATE_SINK" PATH="$SHIM_DIR:$PATH" bash "$HOOK")"
wait_for_sink "$TEL_GATE"
CYG_LM_WIRED="$(count_lm)"
if [[ "$CYG_LM_WIRED" -eq 2 ]]; then
  ok "telemetry-gate/wired: 2 cygpath -lm spawns (FILE + REPO_ROOT normalization)"
else
  fail "telemetry-gate/wired: expected 2 cygpath -lm spawns, got $CYG_LM_WIRED: $(cat "$CYG_LOG")"
fi
JQ_WIRED="$(wc -l <"$JQ_LOG")"
if [[ "$JQ_WIRED" -gt 1 ]]; then
  ok "telemetry-gate/wired: payload jq spawns present ($JQ_WIRED total)"
else
  fail "telemetry-gate/wired: expected >1 jq spawns, got $JQ_WIRED: $(cat "$JQ_LOG")"
fi
if [[ -s "$TEL_GATE" ]] && jq -e '.data.tool == "Write"' "$TEL_GATE" >/dev/null 2>&1; then
  ok "telemetry-gate/wired: envelope delivered with data.tool intact"
else
  fail "telemetry-gate/wired: envelope missing or data.tool wrong: $(cat "$TEL_GATE" 2>/dev/null)"
fi
rm -f "$TEL_GATE"

# ============================================================================
# Bounded emission — cap, rule histogram, delta gate, mutation disclosure
# ============================================================================
# The defect: the hook appended EVERY line of markdownlint's whole-file output
# to additionalContext on every touch, with no cap, no baseline and no dedup.
# One measured session burned roughly 95K tokens across 21 byte-identical
# whole-file dumps, 97% of them one rule the repository intentionally violates.
#
# A second stub is used rather than the fixture stub above: these cases need a
# controllable finding COUNT and the "Attempted: N fixes" line markdownlint-cli2
# prints when it rewrites a file, neither of which the fixture stub produces.
NOISY_BIN="$(mktemp -d "$WORK/noisybin.XXXXXX")"
cat >"$NOISY_BIN/markdownlint-cli2" <<'NOISY'
#!/usr/bin/env bash
set -uo pipefail
file="${2:-}"
[[ -n "$file" && -f "$file" ]] || exit 2

# markdownlint-cli2 is a Node process, and on Windows its stdout is
# CRLF-terminated. STUB_CRLF reproduces that, because a stub that only ever
# emits LF makes any "no carriage returns in the report" assertion pass whether
# the hook strips them or not.
emit() {
  if [[ -n "${STUB_CRLF:-}" ]]; then
    printf '%s\r\n' "$1"
  else
    printf '%s\n' "$1"
  fi
}

# Banner lines markdownlint-cli2 always prints. None of them says anything
# about the edited file; the hook must keep them out of the report.
emit "markdownlint-cli2 v0.23.1 (markdownlint v0.41.1)"
emit "Finding: $file !**/node_modules/** !**/.venv/** !**/bin/** !**/obj/**"
emit "Linting: 1 file"
[[ -n "${STUB_FIX_COUNT:-}" ]] && emit "Attempted: $STUB_FIX_COUNT fixes in 1 file"
n="${STUB_FINDINGS:-0}"
((n > 0)) || exit 0
emit "Summary: $n issues in 1 file"

# STUB_RULE_KINDS spreads the findings across that many DISTINCT rule codes.
# The default of 2 keeps every existing case's histogram unchanged; raising it
# past the histogram's top-five cut is the only way to reach the overflow
# suffix, which no fixture could otherwise trigger.
kinds="${STUB_RULE_KINDS:-2}"
codes="MD013 MD032 MD022 MD031 MD040 MD041 MD047 MD009"
set -- $codes
# Fail loudly rather than expanding an out-of-range positional parameter, which
# under `set -u` is a fatal unbound-variable abort several frames from the cause.
if ((kinds > $#)); then
  echo "stub: STUB_RULE_KINDS=$kinds exceeds the $# rule codes this stub knows" >&2
  exit 2
fi
i=1
while ((i <= n)); do
  if ((kinds <= 2)); then
    if ((i <= n - 2)); then
      emit "$file:$i:81 error MD013/line-length Line length [Expected: 80]"
    else
      emit "$file:$i:1 error MD032/blanks-around-lists Lists should be surrounded by blank lines"
    fi
  else
    idx=$((i % kinds + 1))
    eval "code=\${$idx}"
    emit "$file:$i:1 error $code/stub-rule Stub rule violation"
  fi
  i=$((i + 1))
done
exit 1
NOISY
chmod +x "$NOISY_BIN/markdownlint-cli2"

NOISY_DATA="$(mktemp -d "$WORK/noisydata.XXXXXX")"
run_noisy() {
  local file_path="$1"
  shift
  (cd "$UNRELATED" && printf '{"session_id":"noisy-1","tool_input":{"file_path":"%s"},"tool_name":"Write"}' "$file_path" |
    env -u CLAUDE_PROJECT_DIR CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED=true \
      CLAUDE_PLUGIN_DATA="$NOISY_DATA" PATH="$NOISY_BIN:$PATH" "$@" bash "$HOOK")
}

FN="$REPO/noisy.md"
printf '# Noisy\n\nbody\n' >"$FN"

# --- 50 findings: capped detail, but the count and the rules always survive ---
OUT_N=$(run_noisy "$FN" STUB_FINDINGS=50)
CTX_N=$(printf '%s' "$OUT_N" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
DETAIL_N=$(printf '%s' "$CTX_N" | grep -c 'error MD')
if [[ "$DETAIL_N" -eq 20 ]]; then
  ok "bounded/cap: per-finding detail capped at the 20-line default (got $DETAIL_N)"
else
  fail "bounded/cap: expected 20 detail lines, got $DETAIL_N"
fi
if printf '%s' "$CTX_N" | grep -q '50 markdownlint finding'; then
  ok "bounded/cap: the full finding count is still reported"
else
  fail "bounded/cap: total count missing: $CTX_N"
fi
if printf '%s' "$CTX_N" | grep -q 'MD013 x48' && printf '%s' "$CTX_N" | grep -q 'MD032 x2'; then
  ok "bounded/cap: rule histogram names which rules dominate the truncated set"
else
  fail "bounded/cap: rule histogram missing or wrong: $CTX_N"
fi
if printf '%s' "$CTX_N" | grep -q 'more rule(s)'; then
  fail "bounded/cap: claimed omitted rules when only two rules fired: $CTX_N"
else
  ok "bounded/cap: no omitted-rule suffix when every rule fits in the histogram"
fi
if printf '%s' "$CTX_N" | grep -q 'and 30 more finding'; then
  ok "bounded/cap: the omitted remainder is reported as a count"
else
  fail "bounded/cap: remainder not reported: $CTX_N"
fi
if printf '%s' "$CTX_N" | grep -q 'markdownlint-cli2 v0.23.1' ||
  printf '%s' "$CTX_N" | grep -q 'Finding:' ||
  printf '%s' "$CTX_N" | grep -q 'Linting: 1 file'; then
  fail "bounded/cap: banner noise leaked into the report: $CTX_N"
else
  ok "bounded/cap: markdownlint banner lines kept out of the report"
fi

# --- Telemetry is NOT capped: a sink is a machine, the cap protects context ---
TELN="$(mktemp)"
SINKN="$(make_sink "cat >\"$TELN\"")"
run_noisy "$FN" STUB_FINDINGS=50 HOOK_TELEMETRY_SINK="$SINKN" >/dev/null
wait_for_sink "$TELN"
if [[ "$(jq '.data.findings | length' "$TELN" 2>/dev/null)" -eq 50 ]]; then
  ok "bounded/telemetry: all 50 findings still reach the sink uncapped"
else
  fail "bounded/telemetry: expected 50, got $(jq '.data.findings | length' "$TELN" 2>/dev/null)"
fi
rm -f "$TELN"

# --- Scale: a large payload may be LOST, but must never be FALSIFIED ---------
# The 50-finding case above cannot see this. Windows caps a process command line
# at 32767 characters; a findings array handed to jq as an --argjson value blows
# that somewhere past ~300 entries (reproduced with the hooks' own jq: 300 pass,
# 600 fail, rc=126 "argument list too long").
#
# There are two such call sites, and only one is this plugin's to fix.
# build_data_json is local and now feeds jq on stdin. hook::emit_telemetry then
# passes the FINISHED payload the same way from the shared lib/hook-utils.sh,
# which is byte-synced into every carrying plugin — fixing it there is a
# fleet-wide wave, tracked as #1595.
#
# So the assertion is the invariant that holds either way, and keeps holding
# after #1595 lands: telemetry is documented best-effort and lossy, so a dropped
# envelope is inside contract. An envelope that ARRIVES claiming zero findings
# for a 600-finding file is not — that is the local fallback firing, and it
# reports the noisiest files in the repository as clean.
FS="$REPO/scale.md"
printf '# Scale\n\nbody\n' >"$FS"
TELS="$(mktemp)"
SINKS="$(make_sink "cat >\"$TELS\"")"
run_noisy "$FS" STUB_FINDINGS=600 HOOK_TELEMETRY_SINK="$SINKS" >/dev/null
wait_for_sink "$TELS" 50
if [[ -s "$TELS" ]]; then
  SCALE_LEN=$(jq '.data.findings | length' "$TELS" 2>/dev/null)
  if [[ "$SCALE_LEN" == "600" ]]; then
    ok "bounded/scale: the envelope arrived carrying all 600 findings"
  else
    fail "bounded/scale: an envelope arrived claiming ${SCALE_LEN:-?} findings for a 600-finding file — a payload that lies is worse than none"
  fi
else
  ok "bounded/scale: oversized payload was dropped, not falsified (envelope loss is in contract; see #1595)"
fi
rm -f "$TELS"
OUT_SCALE=$(run_noisy "$FS" STUB_FINDINGS=601)
CTX_SCALE=$(printf '%s' "$OUT_SCALE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_SCALE" | grep -q '601 markdownlint finding'; then
  ok "bounded/scale: the report still states the true count at 601 findings"
else
  fail "bounded/scale: count wrong or missing at 601 findings: $CTX_SCALE"
fi

# --- Carriage returns: on EVERY channel, against a stub that emits them ------
# markdownlint-cli2 is a Node process with CRLF stdout on Windows. A stub that
# only ever emits LF makes any of this vacuous, so STUB_CRLF makes it emit the
# real thing. The strip must also cover the telemetry findings array, not just
# the rendered report: that array is built from the same output and goes to a
# different consumer.
#
# The assertion looks for the two-character JSON escape `\r` in the RAW emitted
# document, NOT for a real CR in a jq-decoded value. That is not fussiness: on
# Git Bash, reading a value back through `printf | jq -r | $(…)` normalizes CRLF
# pairs away, so a decoded-value check silently cannot see exactly the CRs this
# is about — every CR here sits at end-of-line. Verified by revert-probe: with
# the fix removed, the decoded-value form still passed while the raw-escape form
# fails. Testing the bytes the hook actually emits is the only honest check.
crlf_escaped() { case "$1" in *'\r'*) return 0 ;; *) return 1 ;; esac; }

FCR="$REPO/crlf.md"
printf '# CRLF\n\nbody\n' >"$FCR"
TELCR="$(mktemp)"
SINKCR="$(make_sink "cat >\"$TELCR\"")"
OUT_CR=$(run_noisy "$FCR" STUB_FINDINGS=4 STUB_FIX_COUNT=3 STUB_CRLF=1 HOOK_TELEMETRY_SINK="$SINKCR")
wait_for_sink "$TELCR"
CTX_RAW=$(printf '%s' "$OUT_CR" | jq -c '.hookSpecificOutput.additionalContext // ""' 2>/dev/null)
SYS_RAW=$(printf '%s' "$OUT_CR" | jq -c '.systemMessage // ""' 2>/dev/null)
if crlf_escaped "$CTX_RAW"; then
  fail "bounded/crlf: carriage returns leaked into additionalContext"
else
  ok "bounded/crlf: additionalContext carries no carriage returns (stub emitted CRLF)"
fi
if crlf_escaped "$SYS_RAW"; then
  fail "bounded/crlf: carriage returns leaked into systemMessage"
else
  ok "bounded/crlf: systemMessage carries no carriage returns"
fi
# This one is labelled because its discriminating power is PLATFORM-DEPENDENT,
# and an assertion whose strength varies by host must say so rather than be
# taken for uniform coverage. `findings_raw` reaches the envelope through a pipe
# into `jq -R`. Measured on a Windows jq build: with the hook's normalization
# removed, the two assertions above fail while this one still passes — the CRs
# are already gone by the time jq emits, so there was nothing here to catch.
# That is NOT established for the Linux jq this repo's CI runs, which has no
# text/binary mode distinction and is documented not to strip a trailing CR from
# CRLF input; there this assertion may genuinely discriminate. Kept either way:
# on Linux it guards, on Windows it documents.
TEL_FINDINGS_RAW=$(jq -c '.data.findings' "$TELCR" 2>/dev/null)
if [[ -n "$TEL_FINDINGS_RAW" ]] && ! crlf_escaped "$TEL_FINDINGS_RAW"; then
  ok "bounded/crlf: telemetry data.findings carries no carriage returns (discriminating power is platform-dependent)"
else
  fail "bounded/crlf: carriage returns leaked into data.findings: $TEL_FINDINGS_RAW"
fi
if [[ "$(jq '.data.findings | length' "$TELCR" 2>/dev/null)" -eq 4 ]]; then
  ok "bounded/crlf: CRLF output is still parsed into the right number of findings"
else
  fail "bounded/crlf: CRLF parsing lost findings: $TEL_FINDINGS_RAW"
fi
rm -f "$TELCR"

# --- The histogram overflow suffix, positively -------------------------------
# The negative case (no suffix at two rule kinds) already exists. Nothing
# exercised the suffix itself, because the stub could only ever emit two rule
# codes — so the behavior in this feature's headline was unverified.
FRULES="$REPO/manyrules.md"
printf '# Rules\n\nbody\n' >"$FRULES"
OUT_RK=$(run_noisy "$FRULES" STUB_FINDINGS=40 STUB_RULE_KINDS=8)
CTX_RK=$(printf '%s' "$OUT_RK" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if printf '%s' "$CTX_RK" | grep -q '+3 more rule(s)'; then
  ok "bounded/rules: eight rule kinds report the three the histogram omitted"
else
  fail "bounded/rules: overflow suffix missing or miscounted: $CTX_RK"
fi
if [[ "$(printf '%s' "$CTX_RK" | grep -oE 'MD[0-9]+ x[0-9]+' | wc -l)" -eq 5 ]]; then
  ok "bounded/rules: the histogram still names exactly its top five"
else
  fail "bounded/rules: histogram entry count wrong: $CTX_RK"
fi

# --- The cap is configurable, and 0 means unlimited -------------------------
# Raising the cap must bring the detail back on an OTHERWISE UNCHANGED finding
# set: the truncation hint tells the user to raise it, so a delta gate keyed on
# the finding set alone would make that advice impossible to act on. Run against
# the same file and the same 50 findings the capped run above already digested.
OUT_C=$(run_noisy "$FN" STUB_FINDINGS=50 CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS=3)
CTX_C=$(printf '%s' "$OUT_C" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ "$(printf '%s' "$CTX_C" | grep -c 'error MD')" -eq 3 ]]; then
  ok "bounded/config: markdown_format_max_findings lowers the cap, and a cap change defeats the delta gate"
else
  fail "bounded/config: cap not honored: $CTX_C"
fi
OUT_U=$(run_noisy "$FN" STUB_FINDINGS=50 CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS=0)
CTX_U=$(printf '%s' "$OUT_U" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ "$(printf '%s' "$CTX_U" | grep -c 'error MD')" -eq 50 ]]; then
  ok "bounded/config: 0 means unlimited"
else
  fail "bounded/config: 0 did not disable the cap: $(printf '%s' "$CTX_U" | grep -c 'error MD')"
fi
FG="$REPO/garbage.md"
printf '# Garbage\n\nbody\n' >"$FG"
OUT_G=$(run_noisy "$FG" STUB_FINDINGS=5 CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_MAX_FINDINGS="not-a-number; rm -rf /")
CTX_G=$(printf '%s' "$OUT_G" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ "$(printf '%s' "$CTX_G" | grep -c 'error MD')" -eq 5 ]]; then
  ok "bounded/config: a non-integer value falls back to the default, never interpolated"
else
  fail "bounded/config: garbage value not rejected: $CTX_G"
fi

# --- Delta gate: repeats drop the detail, never the message -----------------
# Suppressing the whole message on a repeat would recreate the invisible-hook
# defect on this plugin, so the summary must survive every run.
FD="$REPO/delta.md"
printf '# Delta\n\nbody\n' >"$FD"
OUT_D1=$(run_noisy "$FD" STUB_FINDINGS=30)
CTX_D1=$(printf '%s' "$OUT_D1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
OUT_D2=$(run_noisy "$FD" STUB_FINDINGS=30)
CTX_D2=$(printf '%s' "$OUT_D2" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ "$(printf '%s' "$CTX_D1" | grep -c 'error MD')" -eq 20 ]]; then
  ok "bounded/delta: first run carries the (capped) detail"
else
  fail "bounded/delta: first run detail missing: $CTX_D1"
fi
if [[ "$(printf '%s' "$CTX_D2" | grep -c 'error MD')" -eq 0 ]]; then
  ok "bounded/delta: unchanged repeat drops the per-finding detail"
else
  fail "bounded/delta: repeat still dumped detail: $CTX_D2"
fi
if printf '%s' "$CTX_D2" | grep -q '30 markdownlint finding' &&
  printf '%s' "$CTX_D2" | grep -q 'Unchanged from the previous run'; then
  ok "bounded/delta: the repeat still reports the count and says why it is short"
else
  fail "bounded/delta: repeat went silent — that is the defect, not the fix: $CTX_D2"
fi
OUT_D3=$(run_noisy "$FD" STUB_FINDINGS=31)
CTX_D3=$(printf '%s' "$OUT_D3" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
if [[ "$(printf '%s' "$CTX_D3" | grep -c 'error MD')" -eq 20 ]]; then
  ok "bounded/delta: a changed finding set brings the detail back"
else
  fail "bounded/delta: changed set stayed suppressed: $CTX_D3"
fi

# --- Applied fixes are disclosed on both channels ---------------------------
FF="$REPO/fixed.md"
printf '# Fixed\n\nbody\n' >"$FF"
OUT_F=$(run_noisy "$FF" STUB_FIX_COUNT=7)
CTX_F=$(printf '%s' "$OUT_F" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
SYS_F=$(printf '%s' "$OUT_F" | jq -r '.systemMessage // empty' 2>/dev/null)
if printf '%s' "$CTX_F" | grep -q 'Attempted: 7 fixes'; then
  ok "bounded/fixes: a clean-after-fix run no longer stays silent about the rewrite"
else
  fail "bounded/fixes: no agent-channel disclosure of the rewrite: $CTX_F"
fi
if printf '%s' "$SYS_F" | grep -q 'Attempted: 7 fixes'; then
  ok "bounded/fixes: the rewrite is disclosed on the user channel too"
else
  fail "bounded/fixes: no user-channel disclosure: $SYS_F"
fi
OUT_F0=$(run_noisy "$FF" STUB_FIX_COUNT=0)
if [[ -z "$OUT_F0" ]]; then
  ok "bounded/fixes: a run that changed nothing stays silent"
else
  fail "bounded/fixes: no-op run emitted output: $OUT_F0"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
