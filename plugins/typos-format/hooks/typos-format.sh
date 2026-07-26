#!/usr/bin/env bash
# PostToolUse hook: auto-fix spelling typos via typos-cli (crate-ci/typos).
# Triggered on Write|Edit of ANY file — typos is language-agnostic, unlike the
# sibling ruff-format/markdown-format hooks, which are extension-scoped.
#
# ADVISORY: always exits 0. `typos --write-changes` applies every correction it
# has confidence in; residual (unfixable, e.g. a blank-correction "disallowed"
# entry) findings surface via additionalContext but never block the edit. A
# commit hook or CI is the hard gate.
#
# DISCLOSURE: every correction this hook APPLIES is reported on both channels —
# additionalContext for the agent, systemMessage for the person whose file was
# rewritten. A dictionary autocorrect is a content mutation the user never asked
# for (a domain acronym rewritten into an unrelated English word is the failure
# mode this exists to make visible), and it has no memory: repairing a word by
# hand gets it re-corrected on the next save unless the repo allow-lists it. The
# disclosure therefore carries the allow-list remediation with it. Set the
# `typos_format_write_changes` userConfig to false for a report-only hook that
# never modifies a file.
#
# Unconditional: typos ships a built-in spelling dictionary and runs with zero
# configuration, so this hook runs on every edit regardless of whether the
# repo has adopted a typos config — matching the sibling markdown-format
# hook's unconditional pattern. When a config IS present (typos.toml,
# _typos.toml, .typos.toml, Cargo.toml with [workspace.metadata.typos] or
# [package.metadata.typos], or pyproject.toml with [tool.typos], per
# crate-ci/typos' own docs at
# https://github.com/crate-ci/typos/blob/master/docs/reference.md), typos'
# own file-anchored discovery finds and honors it (allowlist/exclude) — this
# hook never re-implements that walk itself. The typos binary is resolved
# from PATH only — never downloaded (typos is a standalone Rust binary with no
# per-repo dependency-manager convention, unlike ruff's .venv).
#
# Hook-precision: this convention is fleet-wide by intent (its owner doc says
# "every plugin hook follows" it), even though today's CI-audited enforcement
# is narrower (plugins/guardrails/hooks/** only). This hook opts in
# voluntarily. Rule 1 (diff-scope Edit checks to the changed hunk): N/A for a
# formatter/autofix hook — whole-file scanning is the accepted posture here
# (ruff-format/markdown-format do the same); rule 1's "changed hunk" framing
# targets detector/guard hooks flagging pre-existing lines the edit never
# touched. Rule 3 (bounded stdin): inherited via hook::buffer_stdin. Rules 2/4/5
# (command-structure parsing, canonical-marker gating, repo-path/home-dir
# branching): N/A — this hook has none of those shapes.
#
# KNOWN RISK (not fixed here): Claude Code runs every matching PostToolUse hook
# in parallel for one tool call. This hook has no extension filter, so on a
# repo with both a typos config and (e.g.) a Ruff config, editing a .py file
# fires this hook and ruff-format.sh concurrently — each independently
# reading-then-writing the same file with no locking, so a nondeterministic
# clobber is possible. This race class already exists between eol-normalizer
# (also extension-unscoped) and every formatter hook; no hook-level
# locking/ordering primitive exists in Claude Code today. Tracked separately,
# not addressed in this plugin.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "TYPOS_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# fixes typos on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice when there is no
# file_path at all (e.g. a tool_input shape this hook cannot act on regardless).
# shellcheck disable=SC2034  # existence-only check; no extension filter to apply (typos is language-agnostic)
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine).
hook::require_jq PostToolUse typos-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used as the CWD typos runs in and to compute
# the schema-required repo-relative path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
# Repo-relative path: schema requires "relative to the consuming repo root".
# On Windows Git Bash, git rev-parse --show-toplevel returns a drive-letter path
# while FILE may be in POSIX mount form. Normalize both through cygpath -lm
# (long name, forward-slash mixed form) when available so the prefix strip
# compares the same representation. On Linux/macOS, cygpath is absent and both
# paths are already POSIX. Falls back to raw FILE on any normalization error.
FILE_REL="$FILE"
if command -v cygpath >/dev/null 2>&1; then
  _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
  _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
  if [[ -n "$_file_lm" && -n "$_root_lm" ]]; then
    FILE_REL="${_file_lm#"$_root_lm"/}"
  fi
else
  FILE_REL="${FILE#"$REPO_ROOT"/}"
fi

# Build the telemetry data object for the current TOOL/FILE_REL. $1 is the
# residual-findings JSON array; optional $2 is the applied-corrections JSON
# array (additive schema property, defaults to empty). jq is authoritative. The
# fallback is a fixed empty-shape object — NOT an interpolation of
# TOOL/FILE_REL, which could inject quotes or backslashes from a path and
# corrupt the envelope.
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    --argjson applied "${2:-[]}" \
    '{tool:$tool,file:$file,findings:$findings,applied:$applied}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[],"applied":[]}'
}

emit_skipped() {
  local data_json
  data_json=$(build_data_json '[]')
  emit_tel "typos-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

root="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || root=""

# Resolve the typos binary from PATH — never downloaded (typos is a standalone
# Rust binary; no per-repo dependency-manager convention exists for it, unlike
# ruff's .venv or markdownlint's node_modules).
TYPOS_BIN="$(command -v typos 2>/dev/null)" || TYPOS_BIN=""

# No binary available → visible once-per-session skip notice, not a silent gap
# (dim-9 doctrine).
if [[ -z "$TYPOS_BIN" ]]; then
  if hook::notice_once "typos-format-typos" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "typos-format: no 'typos' binary was found on PATH — spell-check skipped for this session. Install: https://github.com/crate-ci/typos#install"
  fi
  emit_skipped
fi

# Pass the file as a path relative to the repo root (the CWD typos runs in) so
# concise diagnostics echo a clean repo-relative path instead of an absolute
# one. typos resolves config relative to the TARGET PATH passed on the command
# line, not the process CWD (verified empirically: running from the repo root
# with a relative subdirectory path still discovers and honors that
# subdirectory's own config) — so running from repo root here does not change
# which config governs, regardless of nesting depth. Falls back to the
# absolute path and the file's own directory when the repo root did not
# resolve or the file is outside it.
TYPOS_ARG="$FILE"
RUN_DIR="${root:-$(dirname "$FILE")}"
if [[ -n "$root" && -n "$FILE_REL" && "$FILE_REL" != "$FILE" ]]; then
  TYPOS_ARG="$FILE_REL"
fi

# Report-only switch. Writing is the default; a consumer that wants the findings
# without the rewrites sets the `typos_format_write_changes` userConfig to
# false. Read from the CLAUDE_PLUGIN_OPTION_<KEY> environment mirror rather than
# a `${user_config.*}` placeholder: shell-form hook commands REJECT
# `${user_config.*}` substitution outright — "substituting a configured value
# into a shell command would let the shell run whatever that value contains, so
# the component fails" — and every option is exported to hook processes as
# CLAUDE_PLUGIN_OPTION_<KEY> anyway (Plugins reference, "User configuration",
# https://code.claude.com/docs/en/plugins-reference, fetched 2026-07-26). Same
# idiom as hook::check_enabled's kill switch. Any value other than the literal
# "false" means write.
WRITE_CHANGES="${CLAUDE_PLUGIN_OPTION_TYPOS_FORMAT_WRITE_CHANGES:-true}"

# Disclosure cap. A file with hundreds of corrections must not turn this hook's
# own report into the context flood it exists to prevent, so each list is capped
# and the remainder is summarized as a count.
MAX_REPORT=10

# --- Pass 1: read-only scan ---------------------------------------------------
# --write-changes emits NOTHING for a correction it applies: verified against
# typos-cli 1.44.0, a file whose every finding is auto-fixable exits 0 with
# empty stdout after rewriting the file. A write-only run therefore cannot tell
# anyone what it changed — which is exactly how this hook came to rewrite file
# content invisibly. The read-only pass below is the only place the pre-write
# finding set exists; it never touches the file, so a run killed by the
# handler's `timeout` between the two passes has mutated nothing.
#
# --force-exclude honors the config's own exclude/extend-exclude even for this
# explicitly-passed path, so a file the repo excludes (generated or vendored
# code, intentional-misspelling fixtures) is left untouched with no advisory
# noise — same rationale as ruff-format.sh's identical flag. Verified against
# typos-cli 1.44.0: exit 0 = clean (or excluded); exit 2 = findings; any other
# code = typos itself failed (bad config, internal error) — not a judgment.
SCAN_OUTPUT=$(cd "$RUN_DIR" && "$TYPOS_BIN" --force-exclude --format json "$TYPOS_ARG" 2>&1)
SCAN_RC=$?

# Emit the tool-break diagnostic for $1 and exit. typos broke for non-lint
# reasons (config parse error, internal error) — no judgment was made. Surfaced
# via additionalContext (NOT stderr — an advisory hook's exit-0 stderr can trip
# a false "Hook Error" label). Recorded as "skipped" (typos never ran to
# judgment), the same status as the no-binary path.
emit_tool_break() {
  hook::ctx_reset
  hook::ctx_append "typos-format: typos failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
  local line
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
  done <<<"$1"
  hook::ctx_flush PostToolUse
  local data_json
  data_json=$(build_data_json '[]')
  emit_tel "typos-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

if [[ $SCAN_RC -eq 0 ]]; then
  # Clean, or excluded by the repo's own typos config. Nothing was changed and
  # there is nothing to disclose.
  data_json=$(build_data_json '[]')
  emit_tel "typos-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

if [[ $SCAN_RC -ne 2 || -z "$SCAN_OUTPUT" ]]; then
  emit_tool_break "$SCAN_OUTPUT"
fi

# --- Pass 2: apply ------------------------------------------------------------
# In report-only mode no write happens at all, so every scanned finding stays in
# the file and the residual set IS the scan set. Otherwise the write pass runs
# and its own output is authoritative for what SURVIVED the write: exit 0 = all
# fixed, nothing residual; exit 2 = the listed findings remain. Deriving the
# applied set as scan-minus-residual keeps this correct without guessing which
# findings typos considers safe to auto-fix (it declines ambiguous ones — a
# finding with more than one candidate correction stays put), and stays correct
# if that judgment changes in a future typos release.
RESIDUAL_OUTPUT="$SCAN_OUTPUT"
if [[ "$WRITE_CHANGES" != "false" ]]; then
  WRITE_OUTPUT=$(cd "$RUN_DIR" && "$TYPOS_BIN" --write-changes --force-exclude --format json "$TYPOS_ARG" 2>&1)
  WRITE_RC=$?
  # The write pass is guarded exactly as the scan pass is, and for a sharper
  # reason: an exit 2 with no output is a typos break mid-write, and reading it
  # as "no residual findings" would classify EVERY scanned finding as applied —
  # reporting rewrites that never happened, on the very channel this hook exists
  # to make trustworthy. Any code other than 0-with-no-findings or
  # 2-with-findings is a tool break, not a judgment.
  if [[ $WRITE_RC -ne 0 ]] && [[ $WRITE_RC -ne 2 || -z "$WRITE_OUTPUT" ]]; then
    emit_tool_break "$WRITE_OUTPUT"
  fi
  RESIDUAL_OUTPUT="$WRITE_OUTPUT"
  [[ $WRITE_RC -eq 0 ]] && RESIDUAL_OUTPUT=""
fi

# Classify both finding sets in ONE jq invocation.
#
# The per-finding shell loop this replaces spawned jq several times per finding,
# which is the difference between a hook that discloses and a hook that does
# not: a 120-correction file rewrote the file and then hit the handler's
# 15-second timeout with empty stdout — recreating, at scale, exactly the silent
# mutation this change exists to end. Process-spawn cost dominates everything
# else here (typos itself runs in ~80 ms on a 68 KB file), so the loop is gone
# and the total spawn count is constant in the number of findings.
#
# Residual identity key: line number + the flagged token. Byte offsets shift as
# earlier corrections on the same line change its length, so an offset-keyed
# comparison would classify wrongly; a line/token pair is stable across the
# write because a repeated token on one line always shares one fix decision.
# The key is built and compared inside jq as a JSON string, so a token carrying
# a shell or glob metacharacter is data throughout and can never widen a match.
#
# The display lines are rendered here too, capped, so the shell never has to
# walk the finding set at all.
#
# Both streams arrive on STDIN, separated by a marker line, rather than as --arg
# values. Windows caps a process command line at 32767 characters, and typos'
# jsonlines run about 110 bytes per finding — so passing them as arguments
# silently broke somewhere past ~300 corrections: jq never ran, and the run
# degraded to "could not be summarized" on exactly the typo-heavy files the
# disclosure matters most for. Reproduced at 500 corrections before the change,
# clean after. The marker is not valid JSON, so it can never collide with a
# finding line.
CLASSIFIED=$(printf '%s\n@@typos-format-split@@\n%s\n' "$SCAN_OUTPUT" "$RESIDUAL_OUTPUT" |
  jq -R -s -c --argjson max "$MAX_REPORT" '
    def parse($lines): [$lines[] | select(length > 0) | (fromjson? // empty) | select(.type == "typo")];
    def keyof: "\(.line_num // 0)\t\(.typo // "")";
    def corr1: (.corrections[0] // "");
    (split("\n")) as $lines
    | (($lines | index("@@typos-format-split@@")) // ($lines | length)) as $sep
    | (parse($lines[($sep + 1):]) | map(keyof)) as $res
    | parse($lines[0:$sep]) as $all
    | ($all | map(select((keyof) as $key | ($res | index($key)) != null))) as $r
    | ($all | map(select((keyof) as $key | ($res | index($key)) == null))) as $a
    | {
        appliedCount: ($a | length),
        residualCount: ($r | length),
        applied: ($a | map({typo: (.typo // ""), correction: corr1, line: (.line_num // 0)})),
        findings: ($r | map({typo: (.typo // ""), corrections: .corrections})),
        appliedText: ([limit($max; $a[])] | map("  \"\(.typo)\" -> \"\(corr1)\" (line \(.line_num // 0))") | join("\n")),
        appliedInline: ([limit($max; $a[])] | map("\"\(.typo)\" -> \"\(corr1)\" (line \(.line_num // 0))") | join("; ")),
        residualText: ([limit($max; $r[])] | map(
            if .corrections == null then
              "  \"\(.typo)\" (line \(.line_num // 0)) is disallowed with no known correction — if intentional, add it to extend-words / extend-identifiers (or an extend-ignore-re pattern) in your typos config."
            else
              "  \"\(.typo)\" (line \(.line_num // 0)) should be \"\(corr1)\" — if intentional, add it to extend-words / extend-identifiers in your typos config."
            end) | join("\n"))
      }' 2>/dev/null) || CLASSIFIED=""

if [[ -z "$CLASSIFIED" ]]; then
  # jq is already a hard prerequisite (hook::require_jq above), so this is
  # near-unreachable. It still must not degrade into silence: the file may
  # already have been rewritten, and "changed, details unavailable" is a far
  # better answer than nothing.
  hook::ctx_reset
  hook::ctx_append "typos-format ran on $(basename "$FILE") and its findings could not be summarized (internal parse failure). If the file was rewritten, review it — this run cannot say what changed."
  hook::ctx_flush PostToolUse
  data_json=$(build_data_json '[]')
  emit_tel "typos-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

read_field() { printf '%s' "$CLASSIFIED" | jq -r "$1" 2>/dev/null; }
APPLIED_COUNT=$(read_field '.appliedCount')
RESIDUAL_COUNT=$(read_field '.residualCount')
APPLIED_LINES=$(read_field '.appliedText')
APPLIED_INLINE=$(read_field '.appliedInline')
RESIDUAL_LINES=$(read_field '.residualText')
APPLIED_JSON=$(printf '%s' "$CLASSIFIED" | jq -c '.applied' 2>/dev/null) || APPLIED_JSON='[]'
FINDINGS_JSON=$(printf '%s' "$CLASSIFIED" | jq -c '.findings' 2>/dev/null) || FINDINGS_JSON='[]'
[[ "$APPLIED_COUNT" =~ ^[0-9]+$ ]] || APPLIED_COUNT=0
[[ "$RESIDUAL_COUNT" =~ ^[0-9]+$ ]] || RESIDUAL_COUNT=0
# jq writes stdout in text mode on Windows, so a multi-line value comes back
# with CRLF line endings; command substitution strips only the trailing one and
# leaves a CR embedded before every remaining newline, which then survives
# JSON-escaping into the emitted context as a literal \r. These strings are
# display text with no meaningful carriage returns of their own.
APPLIED_LINES="${APPLIED_LINES//$'\r'/}"
APPLIED_INLINE="${APPLIED_INLINE//$'\r'/}"
RESIDUAL_LINES="${RESIDUAL_LINES//$'\r'/}"
[[ -n "$APPLIED_LINES" ]] && APPLIED_LINES="$APPLIED_LINES"$'\n'
[[ -n "$RESIDUAL_LINES" ]] && RESIDUAL_LINES="$RESIDUAL_LINES"$'\n'

# Compose ONE stdout document. Claude Code parses a hook's entire stdout as a
# single JSON document, so the agent-channel context and the user-channel
# message are built here and emitted together — printing twice would make the
# second document unreadable and silently drop half the disclosure.
CTX=""
SYSMSG=""
BASE="$(basename "$FILE")"

if ((APPLIED_COUNT > 0)); then
  CTX+="typos-format REWROTE $APPLIED_COUNT word(s) in $BASE after your edit:"$'\n'
  CTX+="$APPLIED_LINES"
  if ((APPLIED_COUNT > MAX_REPORT)); then
    CTX+="  ... and $((APPLIED_COUNT - MAX_REPORT)) more."$'\n'
  fi
  CTX+="  These come from typos' built-in dictionary, not from this repository. If any is wrong here (an acronym, an identifier, a proper noun), add it to extend-words / extend-identifiers in your typos config — the autocorrect has no memory, so repairing the word by hand alone gets it rewritten again on the next edit."$'\n'
  # The person whose file was just changed is the one who has to judge whether
  # the change was correct, and they never asked for it. This is a content
  # mutation, not a lint finding, so it goes to the user channel too.
  SYSMSG="typos-format rewrote $APPLIED_COUNT word(s) in $BASE: $APPLIED_INLINE"
  if ((APPLIED_COUNT > MAX_REPORT)); then
    SYSMSG+="; ... and $((APPLIED_COUNT - MAX_REPORT)) more"
  fi
  SYSMSG+=". Add any wrong rewrite to extend-words / extend-identifiers in your typos config, or set the typos_format_write_changes option to false for report-only mode."
elif [[ "$WRITE_CHANGES" == "false" ]]; then
  CTX+="typos-format is in report-only mode (typos_format_write_changes = false) — $BASE was NOT modified. Findings:"$'\n'
fi

if ((RESIDUAL_COUNT > 0)); then
  if ((APPLIED_COUNT > 0)); then
    CTX+="typos-format: $BASE also has $RESIDUAL_COUNT finding(s) it did not rewrite (advisory):"$'\n'
  elif [[ "$WRITE_CHANGES" != "false" ]]; then
    CTX+="typos-format: $BASE has residual typos findings (advisory):"$'\n'
  fi
  CTX+="$RESIDUAL_LINES"
  if ((RESIDUAL_COUNT > MAX_REPORT)); then
    CTX+="  ... and $((RESIDUAL_COUNT - MAX_REPORT)) more."$'\n'
  fi
fi

# Trim the trailing newline the same way hook::ctx_flush does.
CTX="${CTX%"${CTX##*[![:space:]]}"}"
hook::emit_channels PostToolUse "$CTX" "$SYSMSG"

data_json=$(build_data_json "$FINDINGS_JSON" "$APPLIED_JSON")
# Status "ok" — typos RAN and produced a judgment (findings live in
# data.findings, applied rewrites in data.applied), mirroring the sibling
# formatter plugins where status reflects whether the tool ran, not whether it
# was clean.
emit_tel "typos-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
exit 0
