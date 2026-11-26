# shellcheck shell=bash

log() { printf '%s\n' "$*"; }
err() { printf 'ERROR: %s\n' "$*" >&2; }
section() { printf '\n== %s ==\n' "$*"; }

# shellcheck disable=SC2154  # FRONTMATTER_FILE and TMPDIR_RUN are the caller's
replace_metadata_field() {
  local field="$1" value="$2" tmp="${TMPDIR_RUN}/skill.md.tmp"
  local value_safe
  value_safe=$(printf '%s' "$value" | sed 's/[&|\\]/\\&/g')
  sed -E "s|^([[:space:]]+${field}:[[:space:]]+).*\$|\\1${value_safe}|" \
    "$FRONTMATTER_FILE" >"$tmp"
  mv "$tmp" "$FRONTMATTER_FILE"
}

# shellcheck disable=SC2154  # FRONTMATTER_FILE is the caller's
main() {
  local mode="${1:---check}"

  if [[ "$mode" == -h || "$mode" == --help ]]; then
    print_help
    exit 0
  fi

  if [[ ! -f "$FRONTMATTER_FILE" ]]; then
    err "SKILL.md not found at $FRONTMATTER_FILE — run from a plugin checkout"
    exit 2
  fi

  check_prereqs

  case "$mode" in
  --check)
    run_check
    ;;
  --apply)
    run_apply
    ;;
  *)
    err "unknown mode: $mode (expected --check, --apply, or --help)"
    exit 2
    ;;
  esac
}
