# shellcheck shell=bash

sha256_stdin() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  else
    echo "NO-DIGEST-TOOL"
  fi
}

sha256_jq_stdin() {
  tr -d '\r' | sha256_stdin
}

section_digest() {
  awk -v h_open="$2" -v h_close="$3" '
    $0 == h_open { inside = 1; next }
    $0 == h_close { inside = 0 }
    inside { print }
  ' "$1" | sha256_stdin
}

frontmatter_digest() {
  awk 'NR == 1 && $0 == "---" { inside = 1; next } inside && $0 == "---" { exit } inside { print }' "$1" | sha256_stdin
}

case_digest() {
  jq -S -c --arg n "$2" '.evals[] | select(.name == $n)' "$1" | sha256_jq_stdin
}

case_set_digest() {
  jq -r '.evals[] | "\(.id):\(.name)"' "$1" | sort | sha256_jq_stdin
}

file_digest() {
  sha256_stdin <"$1"
}
