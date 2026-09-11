# worktree-root-legacy.sh — retired git config alias peel.
# Sourced by worktree-root-resolve.sh. Not a skill body. Delete after 2026-12-31.
#
# A publisher-named alias still exists on some machines. Readers rewrite it to
# worktreeroot.path at the winning origin and drop the alias so consumers are
# left on the current key. Fleet audit is read-only: when _worktree_root_git is
# defined, this file dual-reads and does not write.

# Delete this file after 2026-12-31.

WORKTREE_ROOT_LEGACY_KEY="melodic.worktreeroot"
# Assigned by worktree-root-resolve.sh before this file is sourced.
: "${WORKTREE_ROOT_CURRENT_KEY:=worktreeroot.path}"

worktree_root_legacy_read_only() {
  declare -F _worktree_root_git >/dev/null 2>&1
}

# Last-wins stream of retired-key records: one "<origin-file>\t<value>" line
# per git config record. Origin-file is empty when git did not report file:.
# Returns 0 when the key had at least one record.
worktree_root_legacy_pairs() {
  local repo="$1" line origin val had=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    origin="${line%%$'\t'*}"
    if [[ "$origin" == "$line" ]]; then
      val=""
    else
      val="${line#*$'\t'}"
    fi
    if [[ "$origin" == file:* ]]; then
      origin="${origin#file:}"
    else
      origin=""
    fi
    printf '%s\t%s\n' "$origin" "$val"
    had=1
  done < <(worktree_root_git -C "$repo" config --show-origin --get-all --type=path \
    "$WORKTREE_ROOT_LEGACY_KEY" 2>/dev/null)
  ((had))
}

worktree_root_legacy_write_current() {
  local repo="$1" origin="$2" value="$3"
  if [[ -n "$origin" ]]; then
    worktree_root_git -C "$repo" config --file "$origin" \
      "$WORKTREE_ROOT_CURRENT_KEY" "$value"
  else
    worktree_root_git -C "$repo" config "$WORKTREE_ROOT_CURRENT_KEY" "$value"
  fi
}

worktree_root_legacy_unset_file() {
  local repo="$1" origin="$2"
  if [[ -n "$origin" ]]; then
    worktree_root_git -C "$repo" config --file "$origin" --unset-all \
      "$WORKTREE_ROOT_LEGACY_KEY" 2>/dev/null || true
  else
    worktree_root_git -C "$repo" config --unset-all \
      "$WORKTREE_ROOT_LEGACY_KEY" 2>/dev/null || true
  fi
}

# Copy the winning retired value onto the current key, then drop the alias
# from every origin that still carries it. No-op when read-only or when the
# last retired value is empty (same fallthrough as an empty last current key).
worktree_root_legacy_promote() {
  local repo="$1" line origin val win_origin="" win_val="" had=0
  local -a origins=()
  worktree_root_legacy_read_only && return 0
  [[ -n "$WORKTREE_ROOT_LEGACY_KEY" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    origin="${line%%$'\t'*}"
    if [[ "$origin" == "$line" ]]; then
      val=""
    else
      val="${line#*$'\t'}"
    fi
    origins+=("$origin")
    win_origin="$origin"
    win_val="$val"
    had=1
  done < <(worktree_root_legacy_pairs "$repo")
  ((had)) || return 0
  [[ -n "$win_val" ]] || return 0
  worktree_root_legacy_write_current "$repo" "$win_origin" "$win_val" || return 1
  for origin in "${origins[@]}"; do
    worktree_root_legacy_unset_file "$repo" "$origin"
  done
}

# Drop leftover retired-key records once the current key already answers.
worktree_root_legacy_retire() {
  local repo="$1" line origin
  worktree_root_legacy_read_only && return 0
  [[ "${WORKTREE_ROOT_SKIP_RETIRE:-}" == "1" ]] && return 0
  [[ -n "$WORKTREE_ROOT_LEGACY_KEY" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    origin="${line%%$'\t'*}"
    [[ "$origin" == "$line" ]] && origin=""
    worktree_root_legacy_unset_file "$repo" "$origin"
  done < <(worktree_root_legacy_pairs "$repo")
  return 0
}
