# shellcheck shell=bash
# Shared high-confidence secret/credential patterns for secret-pattern-detection
# and the write-path-independent pre-commit content-invariants hook.
#
# This is a library — NOT executable. Pure-function: no env reads, no stdin
# parsing, no exit calls beyond the scan helper's documented return codes.
# Callers handle I/O, exemptions, and exit-code mapping.
#
# Pattern selection: only HIGH-confidence patterns with distinctive prefixes
# and fixed lengths. Generic patterns (password=, api_key=, secret=) are
# excluded — too many false positives for a real-time blocking hook. Sourced
# from gitleaks, TruffleHog, and secrets-patterns-db. grep -E (POSIX ERE) only.

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

# secrets::scan_text <content>
#
# Scans <content> for high-confidence secret patterns.
#
# Output (stdout): one line per hit — `<label> (line <n[,n…]>)` — empty when
# clean. Labels that matched are also appended to the SECRETS_LABELS array
# (caller may clear it first) for telemetry.
#
# Exit: 0 = clean, 1 = violations found.
#
# Feeds content through PROCESS SUBSTITUTION, never `<<<"$content"` (deadlocks
# at 65536-65663 bytes) and never `printf | grep -q` under pipefail (SIGPIPE
# inverts a hit into a clean miss). See hardcoded-path-patterns.sh for the
# two-shapes rule.
secrets::scan_text() {
  local content="$1" lines label pattern i
  local grep_e_args=()
  SECRETS_LABELS=()
  for pattern in "${SECRET_PATTERNS[@]}"; do
    grep_e_args+=(-e "$pattern")
  done
  if ! grep -qE "${grep_e_args[@]}" < <(printf '%s' "$content") 2>/dev/null; then
    return 0
  fi
  for i in "${!SECRET_PATTERNS[@]}"; do
    label="${SECRET_LABELS[$i]}"
    pattern="${SECRET_PATTERNS[$i]}"
    lines=$(grep -nE -- "$pattern" < <(printf '%s' "$content") 2>/dev/null |
      head -3 | cut -d: -f1 | tr '\n' ',' | sed 's/,$//')
    if [[ -n "$lines" ]]; then
      printf '%s (line %s)\n' "$label" "$lines"
      SECRETS_LABELS+=("$label")
    fi
  done
  return 1
}
