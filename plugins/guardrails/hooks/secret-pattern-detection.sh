#!/usr/bin/env bash
# PreToolUse hook: detect secret/credential patterns before file writes.
# Triggered on Write|Edit|NotebookEdit of any file.
#
# BLOCKING: exits 2 when high-confidence secret patterns (API keys, tokens,
# private keys) are detected in new content. Stderr feedback tells Claude what
# was found and how to fix it.
#
# Pattern selection: only HIGH-confidence patterns with distinctive prefixes
# and fixed lengths. Generic patterns (password=, api_key=, secret=) are
# excluded — too many false positives for a real-time blocking hook. Sourced
# from gitleaks, TruffleHog, and secrets-patterns-db.
#
# Cross-platform: uses grep -E (POSIX ERE) only — no grep -P (macOS lacks it).
#
# Consumer seams: scoped to $CLAUDE_PROJECT_DIR (files outside it are another
# repo's concern); a generic allowlist exempts dependency caches, .env
# examples, test fixtures, and machine-local CC state. Disable entirely with
# the secret_pattern_detection_enabled userConfig option set to false.

set -uo pipefail

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "SECRET_PATTERN_DETECTION"

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; buffer
# once, parse each field from it. rc 1 (empty stdin) skips like the empty-field
# guards below; rc 2 (read timed out before a complete payload) FAILS CLOSED —
# the guard cannot evaluate the tool call, and a silent skip would pass exactly
# the traffic this guard exists to stop. buffer_stdin already printed the
# BLOCKED reason to stderr. Buffering does not require jq (hook::buffer_stdin's
# own JSON-completeness check is jq-optional), so it runs before the jq gate
# below — hook::require_jq needs the buffered input for its once-per-session
# notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-secret-pattern-detection" "$INPUT"

# The content to scan lives under a different key per tool: Write has .content,
# Edit has .new_string, NotebookEdit has .new_source.
hook::jq_fields "$INPUT" '.tool_name // ""' '.tool_input.file_path // ""' \
  '(if .tool_name == "Write" then .tool_input.content
    elif .tool_name == "Edit" then .tool_input.new_string
    elif .tool_name == "NotebookEdit" then .tool_input.new_source
    else null end) // ""'
TOOL=${HOOK_JQ_FIELDS[0]}
FILE=${HOOK_JQ_FIELDS[1]}
CONTENT=${HOOK_JQ_FIELDS[2]}

case "$TOOL" in
Write | Edit | NotebookEdit) ;;
*) exit 0 ;;
esac

[[ -n "$FILE" ]] || exit 0

NORM_FILE="$(hook::normalize_path "$FILE")"

# Case-preserved, slash-normalized path for the allowlist globs below. On
# Windows hook::normalize_path lower-cases the remainder so the membership
# comparison is effectively case-insensitive; reusing that folded value for the
# case-sensitive allowlist would silently break the upper-case patterns
# (CLAUDE.local.md). The allowlist globs are suffix/substring matches, so a
# plain backslash→slash fixup is enough — the drive letter never participates.
ALLOW_FILE="${FILE//\\//}"

# --- Scope guard: police only files inside THIS project ---
# A PreToolUse Write|Edit hook fires on every file write regardless of which
# repo the target lives in. A file outside the project root is not ours to scan
# — that repo owns its own secret policy. Fail CLOSED: when the root cannot be
# resolved (CLAUDE_PROJECT_DIR unset), fall through and scan rather than skip.
PROJECT_DIR="$(hook::normalize_path "${CLAUDE_PROJECT_DIR:-}")"
PROJECT_DIR="${PROJECT_DIR%/}"
if [[ -n "$PROJECT_DIR" ]]; then
  case "$NORM_FILE" in
  "$PROJECT_DIR"/*) ;; # inside the project — proceed
  *) exit 0 ;;         # outside the project — not this hook's concern
  esac
fi

# --- Allowlist: files that legitimately contain secret patterns ---
# Each entry grants a narrow hole — keep it tight:
#   - hook scripts: contain regex strings for the patterns themselves
#   - settings.local.json / CLAUDE.local.md: gitignored, designed for real secrets
#   - .venv / node_modules: gitignored dependency caches
#   - .env.example/sample/template: placeholder format; the patterns require
#     10+ chars after prefix so `sk_test_xxx`-style placeholders don't match
#   - tests/fixtures, tests/testdata: scoped to test trees only
#   - CC skill context/completed: research notes; code review is the backstop
case "$ALLOW_FILE" in
*.claude/hooks/*) exit 0 ;;
*settings.local.json) exit 0 ;;
*CLAUDE.local.md) exit 0 ;;
# Dependency caches — anchored to a path-segment boundary (leading `/` or start
# of path) so a directory that merely CONTAINS the name (evil_node_modules/,
# .venv-backup/) is NOT exempted from the scan.
*/.venv/* | .venv/*) exit 0 ;;
*/node_modules/* | node_modules/*) exit 0 ;;
*.env.example | *.env.sample | *.env.template) exit 0 ;;
*tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) exit 0 ;;
*.claude/skills/*/context/*) exit 0 ;;
*.claude/skills/*/completed/*) exit 0 ;;
*) ;; # proceed to content check
esac

[[ -n "$CONTENT" ]] || exit 0

# Repo-relative file for telemetry data.file (best-effort prefix strip).
FILE_REL="$FILE"
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  _root="${CLAUDE_PROJECT_DIR//\\//}"
  _root="${_root%/}"
  _fwd="${FILE//\\//}"
  FILE_REL="${_fwd#"$_root"/}"
fi
# Redaction: if the path could not be made repo-relative, emit the basename only
# — never an absolute path (it would embed the developer's username) into telemetry.
case "$FILE_REL" in
/* | [A-Za-z]:*)
  FILE_REL="${FILE_REL##*/}"
  FILE_REL="${FILE_REL##*\\}"
  ;;
*) ;;
esac

# Emit one telemetry envelope: $1 status, $2 labels JSON array. Gated on the
# high-res start stamp and the opt-in sink — the unwired path spawns nothing.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg file "$FILE_REL" --argjson violations "$2" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "secret-pattern-detection" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- High-confidence secret patterns (grep -E compatible) ---
# Each pattern has a distinctive prefix + structured format = very low FP rate.
# Sourced from gitleaks default rules (github.com/gitleaks/gitleaks).
VIOLATIONS=""
LABELS=()

check_pattern() {
  local label="$1" pattern="$2" lines
  lines=$(grep -nE -- "$pattern" <<<"$CONTENT" 2>/dev/null | head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
  if [[ -n "$lines" ]]; then
    VIOLATIONS="${VIOLATIONS}${label} (line ${lines})\n"
    LABELS+=("$label")
  fi
}

# (label, ERE) parallel arrays — one combined grep can fast-reject the common
# (no-secret) case in a single process. Index alignment is load-bearing: the
# Nth label describes the Nth pattern.
SECRET_LABELS=(
  "AWS Access Key"
  "GitHub PAT"
  "GitHub OAuth Token"
  "GitHub App Token"
  "GitHub Fine-grained PAT"
  "GitLab PAT"
  "Slack Bot Token"
  "Slack User/App Token"
  "Stripe Key"
  "OpenAI API Key"
  "OpenAI API Key"
  "Private Key (PEM)"
)
SECRET_PATTERNS=(
  '(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}'          # AWS (AKIA/ASIA/ABIA/ACCA + 16)
  'ghp_[0-9a-zA-Z]{36}'                        # GitHub PAT
  'gho_[0-9a-zA-Z]{36}'                        # GitHub OAuth
  'gh[us]_[0-9a-zA-Z]{36}'                     # GitHub app (ghu_/ghs_)
  'github_pat_[0-9a-zA-Z_]{82}'                # GitHub fine-grained PAT
  'glpat-[0-9a-zA-Z_-]{20}'                    # GitLab PAT
  'xoxb-[0-9]{10,13}-[0-9]{10,13}'             # Slack bot token
  'xox[pe]-[0-9]{10,13}-'                      # Slack user/app token
  '[sr]k_(test|live|prod)_[0-9a-zA-Z]{10,99}'  # Stripe key
  'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}' # OpenAI prefixed API key
  'sk-[A-Za-z0-9]{20,}'                        # OpenAI legacy bare sk- key
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'         # PEM private key header
)

# Fast reject: one grep spawn matching ANY pattern. The common case (no secret)
# exits here. Without it, the per-pattern itemization (grep|head|cut|tr|sed = 5
# processes × 12 patterns) runs unconditionally; on a large file under Windows
# MSYS2 + Defender that is ~60 spawns costing 10-25s. grep -qE over all patterns
# is logically equivalent to "any pattern matched" — if it finds nothing, no
# individual pattern can match, so skipping itemization is sound.
grep_e_args=()
for pattern in "${SECRET_PATTERNS[@]}"; do
  grep_e_args+=(-e "$pattern")
done
if ! grep -qE "${grep_e_args[@]}" <<<"$CONTENT" 2>/dev/null; then
  emit_tel "ok" '[]'
  exit 0
fi

# Rare path: a secret matched — itemize per-pattern (label + line numbers) for
# the actionable message. The expensive pipeline only runs here, on a hit.
for i in "${!SECRET_PATTERNS[@]}"; do
  check_pattern "${SECRET_LABELS[$i]}" "${SECRET_PATTERNS[$i]}"
done

# --- Report violations ---
if [[ -n "$VIOLATIONS" ]]; then
  {
    printf 'Secret/credential pattern(s) detected in %s:\n\n' "$FILE"
    printf '%b' "$VIOLATIONS"
    printf 'If this is a test fixture or example, add the file to the allowlist\n'
    printf 'in secret-pattern-detection.sh. Never commit real secrets — use\n'
    printf 'environment variables, settings.local.json, or a secret manager.\n'
  } >&2
  labels_json=$(printf '%s\n' "${LABELS[@]}" | jq -R . | jq -s . 2>/dev/null) || labels_json='[]'
  emit_tel "blocked" "$labels_json"
  exit 2
fi

emit_tel "ok" '[]'
exit 0
