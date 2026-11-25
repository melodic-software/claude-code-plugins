# shellcheck shell=bash

# shellcheck source=cleanup-paths.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/cleanup-paths.sh"

_CLEAN_OS="$(uname -s 2>/dev/null || true)"

clean_repo_root() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null | tr -d '\r')"
  printf '%s' "$root"
}

clean_git_common_dir() {
  local repo_root="$1" dir
  dir="$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null | tr -d '\r')"
  [[ -n "$dir" ]] || return 1
  case "$dir" in
  /* | [A-Za-z]:*) ;;
  *) dir="$repo_root/$dir" ;;
  esac
  (cd "$dir" 2>/dev/null && pwd -P) || return 1
}

clean_default_branch() {
  local repo_root="$1" remote="${2:-origin}" branch
  branch="$(git -C "$repo_root" symbolic-ref "refs/remotes/${remote}/HEAD" 2>/dev/null |
    sed "s|^refs/remotes/${remote}/||" | tr -d '\r')"
  if [[ -z "$branch" ]] && command -v gh >/dev/null 2>&1; then
    branch="$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null | tr -d '\r')"
  fi
  printf '%s' "${branch:-main}"
}

clean_worktree_branches() {
  git -C "$1" worktree list --porcelain 2>/dev/null | grep '^branch' | sed 's|^branch refs/heads/||' | tr -d '\r' || true
}

clean_worktree_path() {
  git -C "$1" worktree list --porcelain 2>/dev/null | tr -d '\r' |
    awk -v ref="branch refs/heads/$2" '/^worktree /{p=substr($0,10)} $0==ref{print p; exit}'
}

clean_worktree_branch_paths() {
  git -C "$1" worktree list --porcelain 2>/dev/null | tr -d '\r' |
    awk '/^worktree /{p=substr($0,10)} /^branch refs\/heads\//{b=substr($0,19); if (!(b in seen)) {seen[b]=1; print b "\t" p}}'
}

clean_loss_count() {
  local n
  n="$(git -C "$1" rev-list --count "refs/heads/$2" --not --remotes --tags 2>/dev/null)" || return 1
  n="${n%$'\r'}"
  [[ "$n" =~ ^[0-9]+$ ]] || return 1
  printf '%s' "$n"
}

clean_unreached_counts() {
  local repo_root="$1" ids graph
  shift
  IFS= read -r -d '' ids || true
  ids="${ids%$'\n'}"
  [[ -n "$ids" ]] || return 0
  graph="$(printf '%s\n' "$ids" | git -C "$repo_root" rev-list --parents --stdin --not "$@" 2>/dev/null)" || return 1
  printf '%s\n--\n%s\n' "$ids" "$graph" | awk '
    !mark && $0 == "--" { mark = 1; next }
    !mark { id[$1] = 1; next }
    NF { parents[$1] = substr($0, length($1) + 2) }
    END {
      for (t in id) {
        n = 0
        if (t in parents) {
          sp = 0; stack[sp++] = t; seen[t] = t
          while (sp > 0) {
            c = stack[--sp]; n++
            k = split(parents[c], ps, " ")
            for (i = 1; i <= k; i++) {
              p = ps[i]
              if ((p in parents) && seen[p] != t) { seen[p] = t; stack[sp++] = p }
            }
          }
        }
        print t, n
      }
    }'
}

clean_landed_proof() {
  local repo_root="$1" base="origin/$2" ref="refs/heads/$3" out mb merges synth rc=0
  local -a trees
  mb="$(git -C "$repo_root" merge-base "$base" "$ref" 2>/dev/null | tr -d '\r')"
  [[ -n "$mb" ]] || return 1
  git -C "$repo_root" diff --quiet "$mb" "$ref" 2>/dev/null || rc=$?
  [[ $rc -eq 1 ]] || return 1
  merges="$(git -C "$repo_root" rev-list --merges --max-count=1 "$base..$ref" 2>/dev/null)" || return 1
  if [[ -z "$merges" ]]; then
    out="$(git -C "$repo_root" cherry "$base" "$ref" 2>/dev/null | tr -d '\r')"
    if [[ -n "$out" ]] && ! grep -qv '^-' <<<"$out"; then
      printf 'landed by patch-id (git cherry)'
      return 0
    fi
  fi
  mapfile -t trees < <(git -C "$repo_root" rev-parse "$ref^{tree}" "$base^{tree}" 2>/dev/null | tr -d '\r')
  if [[ ${#trees[@]} -eq 2 && "${trees[0]}" == "${trees[1]}" ]]; then
    printf 'landed as identical content (tree equals %s)' "$base"
    return 0
  fi
  synth="$(GIT_AUTHOR_NAME=landed-proof GIT_AUTHOR_EMAIL=landed-proof@localhost \
    GIT_COMMITTER_NAME=landed-proof GIT_COMMITTER_EMAIL=landed-proof@localhost \
    git -C "$repo_root" commit-tree "$ref^{tree}" -p "$mb" -m landed-proof 2>/dev/null | tr -d '\r')"
  [[ -n "$synth" ]] || return 1
  out="$(git -C "$repo_root" cherry "$base" "$synth" 2>/dev/null | tr -d '\r')"
  if [[ "$out" == -* && "$out" != *$'\n'* ]]; then
    printf 'landed as a squash (tree patch-id)'
    return 0
  fi
  return 1
}

clean_pr_map() {
  local outfile="$1" fields="$2"
  local limit="${CLEAN_PR_LIST_LIMIT:-100000}"

  if ! (: >"$outfile") 2>/dev/null; then
    printf 'PRDataUnavailable: cannot create the pull-request map file; squash-merged branches cannot be detected\n'
    return 0
  fi

  if ! command -v gh >/dev/null 2>&1; then
    printf 'PRDataUnavailable: gh not on PATH; squash-merged branches cannot be detected\n'
    return 0
  fi
  if ! command -v jq >/dev/null 2>&1; then
    printf 'PRDataUnavailable: jq not on PATH; the pull-request map cannot be parsed\n'
    return 0
  fi

  local raw
  # gh pr list rejects --limit below 1 and has no unlimited value, so a count equal to the limit may be truncated:
  # https://github.com/cli/cli/blob/trunk/pkg/cmd/pr/list/list.go
  if ! raw="$(gh pr list --state all --json "$fields" --limit "$limit" 2>/dev/null)"; then
    printf 'PRDataUnavailable: gh pr list failed (unauthenticated, no GitHub remote, or API error)\n'
    return 0
  fi

  local count
  if ! count="$(printf '%s' "$raw" |
    jq -r 'if type == "array" then length else error("not an array") end' 2>/dev/null)"; then
    printf 'PRDataUnavailable: gh pr list returned output the pull-request map could not parse\n'
    return 0
  fi

  if ! (printf '%s' "$raw" | jq -r ".[] | [.${fields//,/,.}] | @tsv" | tr -d '\r' >"$outfile") 2>/dev/null ||
    [[ ! -f "$outfile" ]]; then
    printf 'PRDataUnavailable: cannot write the pull-request map file; squash-merged branches cannot be detected\n'
    return 0
  fi
  printf 'PRCount: %s\n' "$count"
  if [[ "$count" -ge "$limit" ]]; then
    printf 'PRDataTruncated: %s pull requests returned at the --limit %s cap; the map may be short, and a squash-merged branch missing from it is reported as unmerged\n' \
      "$count" "$limit"
  fi
}

clean_path_key() {
  local value="${1//\\//}"
  while [[ "$value" == */ && "$value" != "/" ]]; do value="${value%/}"; done
  case "$_CLEAN_OS" in
  MINGW* | MSYS* | CYGWIN*) printf '%s' "$value" | tr '[:upper:]' '[:lower:]' ;;
  *) printf '%s' "$value" ;;
  esac
}

clean_skip_matches() {
  local repo_key="$1" skip_key
  skip_key="$(clean_path_key "$2")"
  [[ -n "$skip_key" ]] || return 1
  [[ "$repo_key" == "$skip_key" || "$repo_key" == *"/$skip_key" ]]
}

clean_path_is_tracked() {
  local repo_root="$1" rel="$2"
  git -C "$repo_root" ls-files --error-unmatch "$rel" >/dev/null 2>&1
}

clean_path_is_protected() {
  local repo_root="$1" abs="$2"
  local norm="${abs//\\//}"
  local sub

  if clean_path_is_tracked "$repo_root" "${norm#"$repo_root"/}"; then
    return 0
  fi

  case "$norm" in
  *"/.claude/skills/"*"/data/"*) return 0 ;;
  */.env*) return 0 ;;
  *".local.json" | *".local.jsonc" | *".local.md") return 0 ;;
  *".csproj.user" | *".sln.docstates.suo" | *".suo") return 0 ;;
  *) ;;
  esac

  for sub in "${CLEAN_PROTECTED_SUBSTRINGS[@]}"; do
    [[ "$norm" == *"$sub"* ]] && return 0
  done

  return 1
}

clean_dir_has_protected_descendant() {
  local repo_root="$1" dir="$2" entry
  while IFS= read -r entry; do
    [[ -n "$entry" ]] && clean_path_is_protected "$repo_root" "$entry" && return 0
  done < <(find "$dir" -mindepth 1 2>/dev/null)
  return 1
}

clean_path_in_submodule() {
  local repo_root="$1" abs="$2" rel sm
  rel="${abs//\\//}"
  rel="${rel#"$repo_root"/}"
  while IFS= read -r sm; do
    [[ -z "$sm" ]] && continue
    if [[ "$rel" == "$sm" || "$rel" == "$sm"/* ]]; then
      return 0
    fi
  done < <(git -C "$repo_root" config --file "$repo_root/.gitmodules" --get-regexp '\.path$' 2>/dev/null | cut -d' ' -f2- | tr -d '\r')
  return 1
}

clean_tree_preserve_args() {
  local include_deps="$1" include_secrets="$2" pat
  if [[ "$include_secrets" -ne 1 ]]; then
    for pat in "${CLEAN_TREE_PRESERVE_SECRETS[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  fi
  for pat in "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  if [[ "$include_deps" -ne 1 ]]; then
    for pat in "${CLEAN_TREE_PRESERVE_DEPS[@]}"; do printf -- '-e\n%s\n' "$pat"; done
  fi
}

clean_restore_tracked_deletions() {
  local repo_root="$1" count=0 path
  while IFS= read -r -d '' path; do
    [[ -z "$path" ]] && continue
    git -C "$repo_root" restore -- "$path" 2>/dev/null && ((count++)) || true
  done < <(git -C "$repo_root" ls-files -z --deleted 2>/dev/null)
  printf '%s' "$count"
}

clean_path_matches_secret_class() {
  local rel="$1" pat base
  rel="${rel//\\//}"
  base="${rel##*/}"
  for pat in "${CLEAN_TREE_PRESERVE_SECRETS[@]}"; do
    if [[ "$pat" == */ ]]; then
      pat="${pat%/}"
      [[ "$rel" == "$pat"/* || "$rel" == *"/$pat/"* ]] && return 0
    elif [[ "$pat" == */* ]]; then
      [[ "$rel" == "$pat" || "$rel" == *"/$pat" ]] && return 0
    else
      # shellcheck disable=SC2254
      case "$base" in
      $pat) return 0 ;;
      *) ;;
      esac
    fi
  done
  return 1
}

clean_path_matches_skilldata() {
  local rel="$1" pat
  rel="${rel//\\//}"
  rel="${rel%/}"
  for pat in "${CLEAN_TREE_PRESERVE_SKILLDATA[@]}"; do
    pat="${pat%/}"
    # shellcheck disable=SC2254
    case "$rel" in
    $pat | $pat/* | */$pat | */$pat/*) return 0 ;;
    *) ;;
    esac
  done
  return 1
}

clean_path_is_reparse_point() {
  local path="$1"
  [[ -L "$path" ]] && return 0
  if command -v fsutil >/dev/null 2>&1 && command -v cygpath >/dev/null 2>&1; then
    fsutil reparsepoint query "$(cygpath -w "$path")" </dev/null >/dev/null 2>&1 && return 0
  fi
  return 1
}

clean_branch_matches_protected_pattern() {
  local branch="$1"
  local pat exact

  for exact in "${CLEAN_PROTECTED_BRANCH_EXACT[@]}"; do
    [[ "$branch" == "$exact" ]] && return 0
  done

  for pat in "${CLEAN_PROTECTED_BRANCH_GLOBS[@]}"; do
    # shellcheck disable=SC2254
    case "$branch" in
    $pat) return 0 ;;
    *) ;;
    esac
  done

  return 1
}

clean_enumerate() {
  local root="$1"
  shift
  local -a dir_names=() file_globs=()
  local bucket=dirs tok
  for tok in "$@"; do
    if [[ "$tok" == "--" ]]; then
      bucket=globs
      continue
    fi
    if [[ "$bucket" == dirs ]]; then dir_names+=("$tok"); else file_globs+=("$tok"); fi
  done

  local -a prune=('(')
  local d
  for d in "${CLEAN_PRUNE_DIRS[@]}"; do
    ((${#prune[@]} > 1)) && prune+=(-o)
    prune+=(-name "$d")
  done
  prune+=(')')
  local -a args=("$root" "${prune[@]}" -prune -o '(')
  local -a match=()
  local i
  if ((${#dir_names[@]})); then
    match+=(-type d '(')
    for i in "${!dir_names[@]}"; do
      ((i)) && match+=(-o)
      match+=(-name "${dir_names[$i]}")
    done
    match+=(')')
  fi
  if ((${#file_globs[@]})); then
    ((${#dir_names[@]})) && match+=(-o)
    match+=(-type f '(')
    for i in "${!file_globs[@]}"; do
      ((i)) && match+=(-o)
      match+=(-name "${file_globs[$i]}")
    done
    match+=(')')
  fi
  args+=("${match[@]}" ')' -print)
  find "${args[@]}" 2>/dev/null
}

clean_caches_candidates() {
  local root="$1" rel
  for rel in "${CLEAN_CACHE_EXPLICIT[@]}"; do clean_is_plain_dir "$root/$rel" && printf '%s\n' "$root/$rel"; done
  for rel in "${CLEAN_CACHE_EXPLICIT_FILES[@]}"; do clean_is_plain_file "$root/$rel" && printf '%s\n' "$root/$rel"; done
  clean_enumerate "$root" "${CLEAN_CACHE_FIND_DIR_NAMES[@]}" -- "${CLEAN_CACHE_FIND_FILE_GLOBS[@]}"
}

clean_build_candidates() {
  local root="$1"
  clean_enumerate "$root" "${CLEAN_BUILD_DIR_NAMES[@]}" -- "${CLEAN_BUILD_FILE_GLOBS[@]}"
}

clean_target_eligible() {
  local root="$1" abs="$2" rel="${2#"$1"/}"
  if clean_path_is_protected "$root" "$abs"; then
    printf 'Skip (protected): %s\n' "$rel"
    return 1
  fi
  if clean_path_in_submodule "$root" "$abs"; then
    printf 'Skip (submodule): %s\n' "$rel"
    return 1
  fi
  if [[ -d "$abs" ]] && clean_dir_has_protected_descendant "$root" "$abs"; then
    printf 'Skip (protected descendant): %s\n' "$rel"
    return 1
  fi
  return 0
}

CLEAN_CAND_ABS=()
CLEAN_CAND_CLASS=()

CLEAN_PLANNED_COUNT=0
CLEAN_PLANNED_BYTES=0
CLEAN_REMOVED_COUNT=0
CLEAN_FAILED_COUNT=0
CLEAN_REMOVED_BYTES=0

clean_add_candidates() {
  local class="$1" p
  shift
  for p in "$@"; do
    [[ -n "$p" ]] || continue
    CLEAN_CAND_ABS+=("$p")
    CLEAN_CAND_CLASS+=("$class")
  done
}

clean_human_size() {
  local b="$1"
  if ((b >= 1073741824)); then
    awk -v b="$b" 'BEGIN { printf "%.1f GB", b / 1073741824 }'
  elif ((b >= 1048576)); then
    awk -v b="$b" 'BEGIN { printf "%.1f MB", b / 1048576 }'
  elif ((b >= 1024)); then
    awk -v b="$b" 'BEGIN { printf "%.1f KB", b / 1024 }'
  else
    printf '%s B' "$b"
  fi
}

clean_plan() {
  local root="$1" manifest="$2" announce="$3"
  local -a elig_abs=() elig_class=()
  local i abs class skip
  for i in "${!CLEAN_CAND_ABS[@]}"; do
    abs="${CLEAN_CAND_ABS[$i]}"
    class="${CLEAN_CAND_CLASS[$i]}"
    [[ -e "$abs" ]] || continue
    case "$abs" in
    *$'\t'* | *$'\n'*)
      printf 'Skip (unencodable path): %s\n' "${abs#"$root"/}" >&2
      continue
      ;;
    *) ;;
    esac
    if skip="$(clean_target_eligible "$root" "$abs")"; then
      elig_abs+=("$abs")
      elig_class+=("$class")
    else
      [[ -n "$skip" ]] && printf '%s\n' "$skip"
    fi
  done

  local -a surv_abs=() surv_class=()
  local last_key="" key
  while IFS=$'\t' read -r key abs class; do
    [[ -n "$abs" ]] || continue
    if [[ -n "$last_key" && "$key" == "$last_key"* ]]; then
      continue
    fi
    surv_abs+=("$abs")
    surv_class+=("$class")
    last_key="$key"
  done < <(
    for i in "${!elig_abs[@]}"; do
      printf '%s/\t%s\t%s\n' "${elig_abs[$i]}" "${elig_abs[$i]}" "${elig_class[$i]}"
    done | LC_ALL=C sort
  )
  ((${#surv_abs[@]})) || return 0

  local -A size_of=()
  local kb path
  while IFS=$'\t' read -r kb path; do
    [[ -n "$path" ]] || continue
    size_of["$path"]=$((kb * 1024))
  done < <(printf '%s\0' "${surv_abs[@]}" | xargs -0 du -sk 2>/dev/null)

  local bytes rel
  for i in "${!surv_abs[@]}"; do
    abs="${surv_abs[$i]}"
    rel="${abs#"$root"/}"
    bytes="${size_of[$abs]:-0}"
    printf '%s\t%s\t%s\n' "${surv_class[$i]}" "$bytes" "$rel" >>"$manifest"
    ((announce)) && printf 'Planned remove: %s (%s)\n' "$rel" "$(clean_human_size "$bytes")"
    CLEAN_PLANNED_COUNT=$((CLEAN_PLANNED_COUNT + 1))
    CLEAN_PLANNED_BYTES=$((CLEAN_PLANNED_BYTES + bytes))
  done
}

clean_manifest_rel_safe() {
  local norm="${1//\\//}"
  [[ -n "$norm" ]] || return 1
  [[ "$norm" == /* ]] && return 1
  case "/$norm/" in
  */../*) return 1 ;;
  *) return 0 ;;
  esac
}

clean_path_has_reparse_ancestor() {
  local cur="$1" seg
  local -a parts
  IFS=/ read -r -a parts <<<"${2//\\//}"
  for seg in "${parts[@]}"; do
    [[ -z "$seg" ]] && continue
    cur="$cur/$seg"
    clean_path_is_reparse_point "$cur" && return 0
  done
  return 1
}

clean_path_has_pruned_segment() {
  local rel="${1//\\//}" seg
  for seg in "${CLEAN_PRUNE_DIRS[@]}"; do
    [[ "/$rel/" == *"/$seg/"* ]] && return 0
  done
  return 1
}

clean_is_plain_dir() { [[ -d "$1" ]] && ! clean_path_is_reparse_point "$1"; }
clean_is_plain_file() { [[ -f "$1" ]] && ! clean_path_is_reparse_point "$1"; }

clean_manifest_target_valid() {
  local class="$1" rel="${2//\\//}" abs="$3" base="${2##*/}" e pat
  case "$class" in
  caches)
    for e in "${CLEAN_CACHE_EXPLICIT[@]}"; do
      [[ "$rel" == "$e" ]] && { clean_is_plain_dir "$abs"; return; }
    done
    for e in "${CLEAN_CACHE_EXPLICIT_FILES[@]}"; do
      [[ "$rel" == "$e" ]] && { clean_is_plain_file "$abs"; return; }
    done
    for e in "${CLEAN_CACHE_FIND_DIR_NAMES[@]}"; do
      [[ "$base" == "$e" ]] && { clean_is_plain_dir "$abs"; return; }
    done
    for pat in "${CLEAN_CACHE_FIND_FILE_GLOBS[@]}"; do
      # shellcheck disable=SC2053
      [[ "$base" == $pat ]] && { clean_is_plain_file "$abs"; return; }
    done
    ;;
  build)
    for e in "${CLEAN_BUILD_DIR_NAMES[@]}"; do
      [[ "$base" == "$e" ]] && { clean_is_plain_dir "$abs"; return; }
    done
    for pat in "${CLEAN_BUILD_FILE_GLOBS[@]}"; do
      # shellcheck disable=SC2053
      [[ "$base" == $pat ]] && { clean_is_plain_file "$abs"; return; }
    done
    ;;
  *) ;;
  esac
  return 1
}

_clean_reject() {
  printf 'Rejected (%s): %s\n' "$1" "$2" >&2
  CLEAN_FAILED_COUNT=$((CLEAN_FAILED_COUNT + 1))
}

clean_apply_manifest() {
  local root="$1" manifest="$2" allowed="${3:-}"
  local class bytes rel abs skip
  while IFS=$'\t' read -r class bytes rel <&3 || [[ -n "$class$bytes$rel" ]]; do
    if [[ -z "$rel" ]]; then
      [[ -z "$class$bytes" ]] && continue
      _clean_reject 'malformed record' "$class $bytes"
      continue
    fi
    if [[ -n "$allowed" && " $allowed " != *" $class "* ]]; then
      _clean_reject 'wrong tier' "$rel"
      continue
    fi
    if ! clean_manifest_rel_safe "$rel"; then
      _clean_reject 'outside repo' "$rel"
      continue
    fi
    if clean_path_has_pruned_segment "$rel"; then
      _clean_reject 'pruned tree' "$rel"
      continue
    fi
    abs="$root/$rel"
    [[ -e "$abs" ]] || continue
    if clean_path_has_reparse_ancestor "$root" "$rel"; then
      _clean_reject 'symlinked path' "$rel"
      continue
    fi
    if ! clean_manifest_target_valid "$class" "$rel" "$abs"; then
      _clean_reject "not a $class target" "$rel"
      continue
    fi
    if ! skip="$(clean_target_eligible "$root" "$abs")"; then
      [[ -n "$skip" ]] && printf '%s\n' "$skip"
      continue
    fi
    local kb
    kb="$(du -sk "$abs" 2>/dev/null | awk '{print $1}')"
    [[ "$kb" =~ ^[0-9]+$ ]] || kb=0
    if rm -rf "$abs" 2>/dev/null; then
      printf 'Removed: %s\n' "$rel"
      CLEAN_REMOVED_COUNT=$((CLEAN_REMOVED_COUNT + 1))
      CLEAN_REMOVED_BYTES=$((CLEAN_REMOVED_BYTES + kb * 1024))
    else
      printf 'Unremovable: %s\n' "$rel" >&2
      CLEAN_FAILED_COUNT=$((CLEAN_FAILED_COUNT + 1))
    fi
  done 3<"$manifest"
}

clean_apply_and_report() {
  clean_apply_manifest "$1" "$2" "$3"
  printf 'Summary: removed=%s failed=%s bytes=%s\n' \
    "$CLEAN_REMOVED_COUNT" "$CLEAN_FAILED_COUNT" "$CLEAN_REMOVED_BYTES"
  [[ "$CLEAN_FAILED_COUNT" -eq 0 ]]
}

clean_manifest_writable_target() {
  local path="$1" line
  [[ -e "$path" ]] || return 0
  [[ -f "$path" ]] || return 1
  [[ -s "$path" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    [[ "$line" =~ ^(caches|build)$'\t'[0-9]+$'\t' ]] || return 1
  done <"$path"
  return 0
}

clean_manifest_path() {
  local explicit="$1" path
  if [[ -n "$explicit" ]]; then
    path="$explicit"
    if ! clean_manifest_writable_target "$path"; then
      printf 'clean: refusing to overwrite non-manifest file: %s\n' "$path" >&2
      return 1
    fi
  else
    path="$(mktemp 2>/dev/null)" || path="${TMPDIR:-/tmp}/clean-manifest.$$"
  fi
  if ! (: >"$path") 2>/dev/null; then
    printf 'clean: cannot create manifest: %s\n' "$path" >&2
    return 1
  fi
  printf '%s' "$path"
}
