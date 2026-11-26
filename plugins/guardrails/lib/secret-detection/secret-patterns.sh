# shellcheck shell=bash

SECRET_LABELS=(
  "AWS Access Key"
  "GitHub PAT"
  "GitHub OAuth Token"
  "GitHub App Token"
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
  '(AKIA|ASIA|ABIA|ACCA)[A-Z0-9]{16}'
  'ghp_[0-9a-zA-Z]{36}'
  'gho_[0-9a-zA-Z]{36}'
  'gh[us]_[0-9a-zA-Z]{36}'
  '(^|[^A-Za-z0-9_])ghs_[A-Za-z0-9._-]{36,}|ghs_([0-9]+_)?eyJ[A-Za-z0-9._-]{20,}'
  'github_pat_[0-9a-zA-Z_]{82}'
  'glpat-[0-9a-zA-Z_-]{20}'
  'xoxb-[0-9]{10,13}-[0-9]{10,13}'
  'xox[pe]-[0-9]{10,13}-'
  '[sr]k_(test|live|prod)_[0-9a-zA-Z]{10,99}'
  'sk-(proj|svcacct|admin)-[A-Za-z0-9_-]{20,}'
  'sk-[A-Za-z0-9]{20,}'
  '-----BEGIN [A-Z ]*PRIVATE KEY-----'
)

secrets::any_match() {
  local pattern grep_e_args=()
  for pattern in "${SECRET_PATTERNS[@]}"; do
    grep_e_args+=(-e "$pattern")
  done
  LC_ALL=C grep -qE "${grep_e_args[@]}" < <(printf '%s' "$1") 2>/dev/null
}

secrets::scan_text() {
  local content="$1" lines i
  secrets::any_match "$content" || return 0
  for i in "${!SECRET_PATTERNS[@]}"; do
    lines=$(LC_ALL=C grep -m 3 -nE -- "${SECRET_PATTERNS[$i]}" < <(printf '%s' "$content") 2>/dev/null |
      cut -d: -f1 | tr '\n' ',')
    [[ -z "$lines" ]] || printf '%s (line %s)\n' "${SECRET_LABELS[$i]}" "${lines%,}"
  done
  return 1
}
