#!/usr/bin/env bash
# Non-interactive writer for the repo-fleet-hygiene config file (`setup apply`).
# Exit 0 on success, 2 on a validation error; nothing is written on error.
set -uo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: setup-config.sh apply [--config <path>] [--project-dir <dir>] [--root <dir>]...
                             [--repo <dir>]... [--skip <name>]... [--extend-skip <name>]...
                             [--max-depth <1..12>]

Adds entries to the config (default <project-dir>/.claude/repo-fleet-hygiene.conf) and leaves every
other entry and comment untouched. Re-running with the same arguments changes nothing.

  --skip <name>         writes fleet.skip, which REPLACES the audit's default skip list
  --extend-skip <name>  writes fleet.skipAppend, which ADDS to whichever skip list is in effect
EOF
}

die() {
  printf 'setup-config.sh: %s\n' "$1" >&2
  exit 2
}

[[ "${1:-}" == "apply" ]] || {
  usage
  exit 2
}
shift

config="" project_dir="${CLAUDE_PROJECT_DIR:-$PWD}" max_depth=""
roots=() repos=() skips=() extends=()
while (($#)); do
  [[ $# -ge 2 ]] || die "$1 needs a value"
  case "$1" in
  --config) config="$2" ;;
  --project-dir) project_dir="$2" ;;
  --root) roots+=("$2") ;;
  --repo) repos+=("$2") ;;
  --skip) skips+=("$2") ;;
  --extend-skip) extends+=("$2") ;;
  --max-depth) max_depth="$2" ;;
  *) die "unknown argument: $1" ;;
  esac
  shift 2
done

bare_name() {
  [[ -n "$1" && "$1" != . && "$1" != .. && "$1" != */* && "$1" != *\\* && "$1" != *[[:cntrl:]]* ]]
}
for n in ${skips[@]+"${skips[@]}"} ${extends[@]+"${extends[@]}"}; do
  bare_name "$n" || die "not a bare directory name: '$n'"
done
if [[ -n "$max_depth" ]]; then
  [[ "$max_depth" =~ ^[0-9]{1,2}$ ]] || die "--max-depth must be an integer in 1..12"
  max_depth=$((10#$max_depth))
  ((max_depth >= 1 && max_depth <= 12)) || die "--max-depth must be an integer in 1..12"
fi
for d in ${roots[@]+"${roots[@]}"}; do
  [[ -d "$d" ]] || die "root is not a directory: $d"
done
for d in ${repos[@]+"${repos[@]}"}; do
  git -C "$d" rev-parse --git-dir >/dev/null 2>&1 || die "repo is not a Git working tree: $d"
done

[[ -n "$config" ]] || config="$project_dir/.claude/repo-fleet-hygiene.conf"
[[ ! -L "$config" ]] || die "refusing to write through a symlink: $config"
((${#roots[@]} + ${#repos[@]} + ${#skips[@]} + ${#extends[@]})) || [[ -n "$max_depth" ]] ||
  die "nothing to apply: pass at least one of --root, --repo, --skip, --extend-skip, --max-depth"
if [[ -e "$config" ]]; then
  git config --file "$config" --list >/dev/null 2>&1 || die "config does not parse: $config"
fi

mkdir -p -- "$(dirname -- "$config")" || die "cannot create the config directory"
cfg_dir="$(cd -- "$(dirname -- "$config")" && pwd -P)"

# Prefer a path relative to the config directory (portable in tracked config); fall back to the
# absolute path where no relative form exists (another volume) or realpath lacks --relative-to.
target_value() {
  local abs rel
  abs="$(cd -- "$1" && pwd -P)"
  if rel="$(realpath --relative-to="$cfg_dir" "$abs" 2>/dev/null)" && [[ -n "$rel" ]]; then
    printf '%s' "$rel"
  else
    printf '%s' "$abs"
  fi
}

changed=0
add_entry() {
  if git config --file "$config" --get-all "$1" 2>/dev/null | grep -Fxq -- "$2"; then
    printf 'already present: %s = %s\n' "$1" "$2"
  else
    git config --file "$config" --add "$1" "$2" || die "git config failed writing $1"
    printf 'added: %s = %s\n' "$1" "$2"
    changed=1
  fi
}

for d in ${roots[@]+"${roots[@]}"}; do add_entry fleet.root "$(target_value "$d")"; done
for d in ${repos[@]+"${repos[@]}"}; do add_entry fleet.repo "$(target_value "$d")"; done
for n in ${skips[@]+"${skips[@]}"}; do add_entry fleet.skip "$n"; done
for n in ${extends[@]+"${extends[@]}"}; do add_entry fleet.skipAppend "$n"; done
if [[ -n "$max_depth" ]]; then
  if [[ "$(git config --file "$config" --get fleet.maxDepth 2>/dev/null)" == "$max_depth" ]]; then
    printf 'already present: fleet.maxDepth = %s\n' "$max_depth"
  else
    git config --file "$config" fleet.maxDepth "$max_depth" ||
      die "fleet.maxDepth already has several values; edit $config"
    printf 'set: fleet.maxDepth = %s\n' "$max_depth"
    changed=1
  fi
fi

((${#skips[@]})) && printf 'note: fleet.skip REPLACES the audit default skip list; use --extend-skip to add to it\n'
printf 'config: %s\n' "$config"
((changed)) || printf 'already configured\n'
exit 0
