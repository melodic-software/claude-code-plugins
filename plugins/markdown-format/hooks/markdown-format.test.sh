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
  sed -i 's/^\* /- /' "$file"
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
  s="$(mktemp -p "$WORK" sink.XXXXXX)"
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
  PD_ESCAPE="$(mktemp -d -p "$WORK" pd.XXXXXX)"
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
PD_NO_MDLINT="$(mktemp -d -p "$WORK" pd.XXXXXX)"
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
PD_NO_JQ="$(mktemp -d -p "$WORK" pd.XXXXXX)"
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
# with no leak it is ~0 (± scheduling jitter). Threshold is half the sleep:
# comfortably above jitter, comfortably below the leak signal.
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
SINK_SLEEP=6
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
THRESHOLD_MS=$((SINK_SLEEP * 1000 / 2))
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]]
