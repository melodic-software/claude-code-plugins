#!/usr/bin/env bash
# Exit codes:
#   0  ran to completion (per-install verdicts, including every unverifiable
#      one, are reported in the body — a verdict is not an error)
#   2  fatal: jq or git missing, no temporary file, a usage error, a named
#      marketplace that is not in known_marketplaces.json, or an internal state
#      file that is present but does not match its expected shape (fail loud on
#      schema drift)

set -uo pipefail

script_src="${BASH_SOURCE[0]}"
case "$script_src" in
*/*) script_src_dir="${script_src%/*}" ;;
*) script_src_dir="." ;;
esac
JQ_CAPTURE="$script_src_dir/jq-capture.sh"
if [[ -f "$JQ_CAPTURE" ]]; then
  # shellcheck source=jq-capture.sh
  builtin source "$JQ_CAPTURE"
else
  echo "ERROR: jq-capture.sh not found at $JQ_CAPTURE" >&2
  exit 2
fi

git_to() {
  local __g_var="$1"
  shift
  local __g_out __g_rc=0
  __g_out=$(command git "$@") || __g_rc=$?
  printf -v "$__g_var" '%s' "${__g_out//$'\r'/}"
  return "$__g_rc"
}

to_slashes_to() {
  printf -v "$1" '%s' "${2//\\//}"
}

split_lines_to() {
  local -n __sl_out="$1"
  local -
  set -f
  local IFS=$'\n'
  # shellcheck disable=SC2206  # splitting on newline with globbing off is the point
  __sl_out=($2)
}

spool_records_to() {
  local __sr_text
  local -x LC_ALL=C
  __sr_text=$(tr '\n\0' '\001\n' <"$SPOOL")
  if [[ "$__sr_text" == *$'\x01'* ]]; then
    mapfile -d '' -t "$1" <"$SPOOL"
  else
    split_lines_to "$1" "$__sr_text"
  fi
}

INSTALLED_JSON="${CACHE_CONTENT_INSTALLED_JSON:-${FLEET_STATE_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}}"
MARKETPLACES_JSON="${CACHE_CONTENT_MARKETPLACES_JSON:-${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}}"

MAX_REPORTED_PATHS=10

SENTINEL_SHAPE=$'\x01shape'
SENTINEL_UNKNOWN=$'\x01unknown'

usage() {
  local text
  IFS= read -r -d '' text <<'EOF' || true
cache-content-check.sh: read-only audit of whether each plugin cache directory
holds the files of the commit its install record names.

Usage:
  cache-content-check.sh --marketplace <name> [--scope user|project|all] [--json]
  cache-content-check.sh --all [--scope user|project|all] [--json]
  cache-content-check.sh --marketplace <name> [--scope user|project|all] --ids

Default output is one JSON object (--json is accepted and changes nothing);
--all wraps one object per marketplace. --ids prints the <name>@<marketplace>
id of every stale-content install, one per line, and cannot be combined with
--all. --scope defaults to user. Nothing is written and nothing is fetched.

Exit: 0 ran to completion (a per-install verdict is not an error); 2 usage
error, jq or git missing, an unknown marketplace, or a state file that does not
match its expected shape.

The verdicts are in the plugins skill's context/script-contracts.md and
context/stale-records-cache-content.md.
EOF
  printf '%s\n' "$text"
}

MODE="default"
TARGET=""
SCOPE="user"
IDS_MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    MODE="single"
    TARGET="${2:-}"
    if [[ -z "$TARGET" ]]; then
      echo "ERROR: --marketplace requires a name" >&2
      exit 2
    fi
    shift 2
    ;;
  --scope)
    SCOPE="${2:-}"
    if [[ -z "$SCOPE" ]]; then
      echo "ERROR: --scope requires user, project, or all" >&2
      exit 2
    fi
    shift 2
    ;;
  --all)
    MODE="all"
    shift
    ;;
  --ids)
    IDS_MODE="yes"
    shift
    ;;
  --json)
    shift
    ;;
  -h | --help)
    usage
    exit 0
    ;;
  *)
    echo "ERROR: unknown argument: $1 (see --help)" >&2
    exit 2
    ;;
  esac
done

case "$SCOPE" in
user | project | all) ;;
*)
  echo "ERROR: unknown --scope: $SCOPE (expected user, project, or all)" >&2
  exit 2
  ;;
esac

if [[ "$MODE" == "default" ]]; then
  echo "ERROR: one of --marketplace <name> or --all is required" >&2
  exit 2
fi

if [[ -n "$IDS_MODE" && "$MODE" == "all" ]]; then
  echo "ERROR: --ids cannot be combined with --all" >&2
  echo "  Run --ids once per marketplace with --marketplace <name>." >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git required" >&2
  exit 2
fi

SPOOL=$(mktemp 2>/dev/null) || {
  echo "ERROR: could not create a temporary file (mktemp)" >&2
  exit 2
}
trap 'rm -f -- "$SPOOL"' EXIT

for f in "$INSTALLED_JSON" "$MARKETPLACES_JSON"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: state file not found: $f" >&2
    exit 2
  fi
done

installed_bad() {
  echo "ERROR: $INSTALLED_JSON is not valid installed_plugins.json (expected an object with a .plugins map of arrays)" >&2
  exit 2
}
ALL_RECORDS=""
# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
jq_to ALL_RECORDS -r --arg scope "$SCOPE" '
  if (type == "object")
    and ((.plugins // {}) | type == "object")
    and ((.plugins // {}) | to_entries | all(.value | type == "array"))
  then
    (.plugins // {})
    | to_entries
    | map(.key as $id | .value[] | {
        id: $id,
        scope: (.scope // "user"),
        version: (.version // ""),
        sha: (.gitCommitSha // ""),
        installPath: (.installPath // ""),
        projectPath: (.projectPath // "")
      })
    | map(select($scope == "all" or (if $scope == "user" then .scope == "user" else .scope != "user" end)))
    | map([.id, .scope, .version, .sha, .installPath, .projectPath] | join("\u001f"))
    | .[]
  else
    "\u0001shape"
  end
' "$INSTALLED_JSON" 2>/dev/null || installed_bad
[[ "$ALL_RECORDS" != "$SENTINEL_SHAPE" ]] || installed_bad

marketplaces_bad() {
  echo "ERROR: $MARKETPLACES_JSON is not valid known_marketplaces.json (expected an object)" >&2
  exit 2
}

walk_cache_roots() {
  find "$@" \( -type f -o -type l \) \
    -not -path '*/.git/*' -not -path '*/.in_use/*' -print0 2>/dev/null
}

check_marketplace() {
  local mp="$1" install_loc="$2"
  local install_loc_native
  to_slashes_to install_loc_native "$install_loc"

  local checked=0 n_match=0 n_stale=0 n_unverifiable=0 n_not_checked=0 n_skipped=0
  local records_json=""
  local stale_ids=""

  local loc_verdict=""
  if [[ -z "$install_loc_native" || ! -d "$install_loc_native" ]]; then
    loc_verdict="no-install-location"
  elif ! git -C "$install_loc_native" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    loc_verdict="not-a-git-worktree"
  fi

  local -A source_by_sha_name=() source_map_loaded=()
  load_source_map() {
    local s="$1" raw="" parsed="" entry entry_key
    local -a entries=()
    [[ -z "${source_map_loaded[$s]+set}" ]] || return 0
    source_map_loaded["$s"]=1
    git_to raw -C "$install_loc_native" show "$s:.claude-plugin/marketplace.json" 2>/dev/null || return 0
    jq_to parsed -r '
      (.plugins // [])
      | map(select((.name | type == "string") and (.source | type == "string")))
      | map([.name, .source] | join("\u001f")) # delimiter is US (0x1f), as in fleet-state.sh
      | .[]
    ' <<<"$raw" 2>/dev/null || parsed=""
    split_lines_to entries "$parsed"
    for entry in ${entries+"${entries[@]}"}; do
      [[ "$entry" == *$'\x1f'* ]] || entry+=$'\x1f'
      entry_key="$s"$'\x1f'"${entry%%$'\x1f'*}"
      [[ -n "${source_by_sha_name[$entry_key]+set}" ]] ||
        source_by_sha_name["$entry_key"]="${entry#*$'\x1f'}"
    done
  }

  local -a i_id=() i_scope=() i_version=() i_sha=() i_ipath=() i_root=()
  local -a i_verdict=() i_srcdir=()
  local id scope version sha install_path project_path
  local project_path_native install_path_native pre_verdict
  while IFS=$'\x1f' read -r id scope version sha install_path project_path; do
    [[ -n "$id" ]] || continue
    [[ "$id" == *"@$mp" ]] || continue

    if [[ "$scope" != "user" && -n "$project_path" ]]; then
      to_slashes_to project_path_native "$project_path"
      if [[ ! -d "$project_path_native" ]]; then
        n_skipped=$((n_skipped + 1))
        continue
      fi
    fi

    checked=$((checked + 1))
    to_slashes_to install_path_native "$install_path"
    pre_verdict=""
    if [[ -n "$loc_verdict" ]]; then
      pre_verdict="$loc_verdict"
    elif [[ -z "$install_path_native" || ! -d "$install_path_native" ]]; then
      pre_verdict="install-path-missing"
    elif [[ -z "$sha" ]]; then
      pre_verdict="no-git-commit-sha"
    fi

    i_id+=("$id")
    i_scope+=("$scope")
    i_version+=("$version")
    i_sha+=("$sha")
    i_ipath+=("$install_path")
    i_root+=("$install_path_native")
    i_verdict+=("$pre_verdict")
    i_srcdir+=("")
  done <<<"$ALL_RECORDS"

  local n=${#i_id[@]}
  local k

  local head_read="" clone_head=""
  for ((k = 0; k < n; k++)); do
    [[ -z "${i_verdict[k]}" ]] || continue
    if [[ -z "$head_read" ]]; then
      head_read="yes"
      git_to clone_head -C "$install_loc_native" rev-parse --verify -q 'HEAD^{commit}' 2>/dev/null ||
        clone_head=""
    fi
    if [[ -z "$clone_head" ]]; then
      i_verdict[k]="no-clone-head"
    elif [[ "${i_sha[k]}" != "$clone_head" ]]; then
      i_verdict[k]="not-at-head"
    fi
  done

  local name_key src_dir
  for ((k = 0; k < n; k++)); do
    [[ -z "${i_verdict[k]}" ]] || continue
    load_source_map "${i_sha[k]}"
    name_key="${i_sha[k]}"$'\x1f'"${i_id[k]%@*}"
    src_dir="${source_by_sha_name[$name_key]-}"
    src_dir="${src_dir#./}"
    src_dir="${src_dir%/}"
    if [[ -z "$src_dir" ]]; then
      i_verdict[k]="no-source"
    else
      i_srcdir[k]="$src_dir"
    fi
  done

  local -a g_sha=() g_dir=() uniq_shas=()
  local -A g_seen=() uniq_seen=()
  local gkey gi
  for ((k = 0; k < n; k++)); do
    [[ -z "${i_verdict[k]}" ]] || continue
    gkey="${i_sha[k]}"$'\x1f'"${i_srcdir[k]}"
    [[ -z "${g_seen[$gkey]+set}" ]] || continue
    g_seen["$gkey"]=1
    g_sha+=("${i_sha[k]}")
    g_dir+=("${i_srcdir[k]}")
    [[ -n "${uniq_seen[${i_sha[k]}]+set}" ]] || {
      uniq_seen["${i_sha[k]}"]=1
      uniq_shas+=("${i_sha[k]}")
    }
  done

  local -a tree_rel=() tree_blob=()
  local -A tree_hash=() owner_idx=() tree_rc_bad=()
  local s rec meta path_rel blob owner walk rel idx tree_rc dir last_dir
  local -a owners=() dir_owners=()
  for s in ${uniq_shas+"${uniq_shas[@]}"}; do
    last_dir=$'\x02'
    local -a specs=()
    for ((gi = 0; gi < ${#g_sha[@]}; gi++)); do
      [[ "${g_sha[gi]}" == "$s" ]] || continue
      specs+=("${g_dir[gi]}")
    done
    local -a tree_recs=()
    tree_rc=0
    git -C "$install_loc_native" ls-tree -r -z "$s" -- "${specs[@]}" >"$SPOOL" 2>/dev/null || tree_rc=$?
    if [[ "$tree_rc" != "0" ]]; then
      tree_rc_bad["$s"]=1
      continue
    fi
    spool_records_to tree_recs
    for rec in ${tree_recs+"${tree_recs[@]}"}; do
      [[ -n "$rec" ]] || continue
      meta="${rec%%$'\t'*}"
      path_rel="${rec#*$'\t'}"
      blob="${meta##* }"
      case "$meta" in
      *" blob "*) ;;
      *) continue ;;
      esac
      owners=()
      gkey="$s"$'\x1f'"$path_rel"
      [[ -z "${g_seen[$gkey]+set}" ]] || owners+=("$path_rel")
      if [[ "$path_rel" == */* ]]; then
        dir="${path_rel%/*}"
      else
        dir=$'\x01'
      fi
      if [[ "$dir" != "$last_dir" ]]; then
        last_dir="$dir"
        dir_owners=()
        if [[ "$dir" != $'\x01' ]]; then
          walk="$dir"
          while :; do
            gkey="$s"$'\x1f'"$walk"
            [[ -z "${g_seen[$gkey]+set}" ]] || dir_owners+=("$walk")
            [[ "$walk" == */* ]] || break
            walk="${walk%/*}"
          done
        fi
      fi
      owners+=(${dir_owners+"${dir_owners[@]}"})
      for owner in ${owners+"${owners[@]}"}; do
        rel="${path_rel#"$owner"/}"
        idx=${#tree_rel[@]}
        tree_rel+=("$rel")
        tree_blob+=("$blob")
        tree_hash["$s"$'\x1f'"$owner"$'\x1f'"$rel"]="$blob"
        owner_idx["$s"$'\x1f'"$owner"]+=" $idx"
      done
    done
  done
  for ((k = 0; k < n; k++)); do
    [[ -z "${i_verdict[k]}" ]] || continue
    if [[ -n "${tree_rc_bad[${i_sha[k]}]+set}" ]]; then
      i_verdict[k]="no-source"
      continue
    fi
    gkey="${i_sha[k]}"$'\x1f'"${i_srcdir[k]}"
    [[ -n "${owner_idx[$gkey]+set}" ]] || i_verdict[k]="no-source-at-sha"
  done

  local -a roots=()
  local -A root_seen=() root_files=()
  local rt
  for ((k = 0; k < n; k++)); do
    [[ -z "${i_verdict[k]}" ]] || continue
    rt="${i_root[k]}"
    [[ -n "${root_seen[$rt]+set}" ]] || {
      root_seen["$rt"]=1
      roots+=("$rt")
    }
  done

  local -a cache_full=()
  if [[ ${#roots[@]} -gt 0 ]]; then
    {
      chunk=()
      chunk_len=0
      for rt in "${roots[@]}"; do
        if [[ ${#chunk[@]} -gt 0 ]] && ((chunk_len + ${#rt} + 1 > 16000)); then
          walk_cache_roots "${chunk[@]}"
          chunk=()
          chunk_len=0
        fi
        chunk+=("$rt")
        chunk_len=$((chunk_len + ${#rt} + 1))
      done
      if [[ ${#chunk[@]} -gt 0 ]]; then
        walk_cache_roots "${chunk[@]}"
      fi
    } | sort -z >"$SPOOL"
    spool_records_to cache_full
  fi

  local -a cache_rel=()
  local cache_i f walk_dir f_dir last_f_dir=$'\x02' f_root=""
  for ((cache_i = 0; cache_i < ${#cache_full[@]}; cache_i++)); do
    cache_rel[cache_i]=""
    f="${cache_full[cache_i]}"
    [[ -n "$f" ]] || continue
    f_dir=$'\x01'
    [[ "$f" != */* ]] || f_dir="${f%/*}"
    if [[ "$f_dir" != "$last_f_dir" ]]; then
      last_f_dir="$f_dir"
      f_root=""
      walk_dir="$f"
      while [[ "$walk_dir" == */* ]]; do
        walk_dir="${walk_dir%/*}"
        if [[ -n "${root_seen[$walk_dir]+set}" ]]; then
          f_root="$walk_dir"
          break
        fi
      done
    fi
    [[ -n "$f_root" ]] || continue
    root_files["$f_root"]+=" $cache_i"
    cache_rel[cache_i]="${f#"$f_root"/}"
  done

  local -a b_full=() b_owner=() b_rel=()
  local -a ins_batch_start=() ins_batch_end=()
  local -A cache_hash=() extras_idx=() extra_seen=()
  local -a extra_probe=()
  local src_key probe_key link_target one_hash
  for ((k = 0; k < n; k++)); do
    ins_batch_start[k]=${#b_full[@]}
    if [[ -n "${i_verdict[k]}" ]]; then
      ins_batch_end[k]=${#b_full[@]}
      continue
    fi
    rt="${i_root[k]}"
    src_dir="${i_srcdir[k]}"
    for cache_i in ${root_files[$rt]:-}; do
      f="${cache_full[cache_i]}"
      rel="${cache_rel[cache_i]}"
      src_key="${i_sha[k]}"$'\x1f'"$src_dir"$'\x1f'"$rel"
      if [[ -z "${tree_hash[$src_key]+set}" ]]; then
        extras_idx[$k]+=" $cache_i"
        probe_key="$src_dir/$rel"
        [[ -n "${extra_seen[$probe_key]+set}" ]] || {
          extra_seen["$probe_key"]=1
          extra_probe+=("$probe_key")
        }
        continue
      fi
      if [[ -L "$f" ]]; then
        link_target=$(readlink "$f" 2>/dev/null)
        if git_to one_hash -C "$install_loc_native" hash-object --stdin < <(printf '%s' "$link_target"); then
          cache_hash["$k"$'\x1f'"$rel"]="$one_hash"
        fi
        continue
      fi
      if [[ "$f" == *$'\n'* ]]; then
        if git_to one_hash -C "$install_loc_native" hash-object -- "$f"; then
          cache_hash["$k"$'\x1f'"$rel"]="$one_hash"
        fi
        continue
      fi
      b_full+=("$f")
      b_owner+=("$k")
      b_rel+=("$rel")
    done
    ins_batch_end[k]=${#b_full[@]}
  done

  local hi=0
  if [[ ${#b_full[@]} -gt 0 ]]; then
    local batch_in="" hash_out="" line
    local -a hash_lines=()
    printf -v batch_in '%s\n' "${b_full[@]}"
    if git_to hash_out -C "$install_loc_native" hash-object --stdin-paths <<<"${batch_in%$'\n'}"; then
      split_lines_to hash_lines "$hash_out"
      for line in ${hash_lines+"${hash_lines[@]}"}; do
        [[ $hi -lt ${#b_full[@]} ]] || break
        cache_hash["${b_owner[hi]}"$'\x1f'"${b_rel[hi]}"]="$line"
        hi=$((hi + 1))
      done
    fi
    for ((k = 0; k < n; k++)); do
      [[ -z "${i_verdict[k]}" ]] || continue
      ((ins_batch_end[k] > ins_batch_start[k])) || continue
      ((hi < ins_batch_end[k])) || continue
      i_verdict[k]="hash-batch-misaligned"
    done
  fi

  local -A ignored=()
  if [[ ${#extra_probe[@]} -gt 0 ]]; then
    local -a ignored_recs=()
    printf '%s\0' "${extra_probe[@]}" |
      git -C "$install_loc_native" check-ignore -z --no-index --stdin >"$SPOOL" 2>/dev/null
    spool_records_to ignored_recs
    for line in ${ignored_recs+"${ignored_recs[@]}"}; do
      [[ -n "$line" ]] || continue
      ignored["$line"]=1
    done
  fi

  local verdict n_differ n_missing n_extra ti filtered
  local j_id j_scope j_version j_sha j_path j_verdict
  local paths_json p np jp
  for ((k = 0; k < n; k++)); do
    verdict="${i_verdict[k]}"
    local -a paths=()
    n_differ=0
    n_missing=0
    n_extra=0

    if [[ -z "$verdict" ]]; then
      rt="${i_root[k]}"
      src_dir="${i_srcdir[k]}"
      gkey="${i_sha[k]}"$'\x1f'"$src_dir"

      for ti in ${owner_idx[$gkey]:-}; do
        rel="${tree_rel[ti]}"
        src_key="$k"$'\x1f'"$rel"
        if [[ -z "${cache_hash[$src_key]+set}" ]]; then
          n_missing=$((n_missing + 1))
          paths+=("missing-from-cache: $rel")
          continue
        fi
        [[ "${cache_hash[$src_key]}" != "${tree_blob[ti]}" ]] || continue
        filtered=""
        if git_to filtered -C "$install_loc_native" hash-object \
          --path "$src_dir/$rel" -- "$rt/$rel" 2>/dev/null &&
          [[ "$filtered" == "${tree_blob[ti]}" ]]; then
          continue
        fi
        n_differ=$((n_differ + 1))
        paths+=("differs: $rel")
      done

      for cache_i in ${extras_idx[$k]:-}; do
        rel="${cache_rel[cache_i]}"
        probe_key="$src_dir/$rel"
        [[ -z "${ignored[$probe_key]+set}" ]] || continue
        n_extra=$((n_extra + 1))
        paths+=("extra-in-cache: $rel")
      done

      if [[ $((n_differ + n_missing + n_extra)) -gt 0 ]]; then
        verdict="stale-content"
      else
        verdict="match"
      fi
    fi

    case "$verdict" in
    match) n_match=$((n_match + 1)) ;;
    stale-content)
      n_stale=$((n_stale + 1))
      stale_ids+="${i_id[k]}"$'\n'
      ;;
    not-at-head) n_not_checked=$((n_not_checked + 1)) ;;
    *) n_unverifiable=$((n_unverifiable + 1)) ;;
    esac

    json_string_to j_id "${i_id[k]}"
    json_string_to j_scope "${i_scope[k]}"
    json_string_to j_version "${i_version[k]}"
    json_string_to j_sha "${i_sha[k]}"
    json_string_to j_path "${i_ipath[k]}"
    json_string_to j_verdict "$verdict"

    paths_json=""
    np=0
    for p in "${paths[@]:-}"; do
      [[ -n "$p" ]] || continue
      np=$((np + 1))
      [[ $np -le $MAX_REPORTED_PATHS ]] || break
      json_string_to jp "$p"
      [[ $np -eq 1 ]] || paths_json+=","
      paths_json+="$jp"
    done

    [[ -z "$records_json" ]] || records_json+=","
    records_json+="{\"id\":$j_id,\"scope\":$j_scope,\"version\":$j_version,\"gitCommitSha\":$j_sha"
    records_json+=",\"installPath\":$j_path,\"verdict\":$j_verdict"
    records_json+=",\"differing\":$n_differ,\"missing_from_cache\":$n_missing,\"extra_in_cache\":$n_extra"
    if [[ -n "$install_loc_native" && -d "$install_loc_native/.changes/${i_id[k]%@*}" ]]; then
      records_json+=",\"unreleased_changes\":true"
    else
      records_json+=",\"unreleased_changes\":false"
    fi
    records_json+=",\"paths\":[$paths_json]}"
  done

  if [[ -n "$IDS_MODE" ]]; then
    printf '%s' "$stale_ids"
    return 0
  fi

  local j_mp j_scope_out
  json_string_to j_mp "$mp"
  json_string_to j_scope_out "$SCOPE"
  printf '{"marketplace":%s,"scope":%s,"checked":%d,"match":%d,"stale_content":%d,"unverifiable":%d,"not_checked":%d,"skipped_absent_project_paths":%d,"installs":[%s]}' \
    "$j_mp" "$j_scope_out" "$checked" "$n_match" "$n_stale" "$n_unverifiable" "$n_not_checked" "$n_skipped" "$records_json"
}

mp_loc=""
mp_pairs=""
j_name=""
j_err=""

if [[ "$MODE" == "single" ]]; then
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to mp_loc -r --arg mp "$TARGET" '
    if type != "object" then "\u0001shape"
    elif (has($mp) | not) then "\u0001unknown"
    else (.[$mp] as $v
          | if ($v | type) == "object" then ($v.installLocation // "" | tostring) else "" end)
    end
  ' "$MARKETPLACES_JSON" 2>/dev/null || marketplaces_bad
  [[ "$mp_loc" != "$SENTINEL_SHAPE" ]] || marketplaces_bad
  if [[ "$mp_loc" == "$SENTINEL_UNKNOWN" ]]; then
    echo "ERROR: unknown marketplace: $TARGET (not in $MARKETPLACES_JSON)" >&2
    exit 2
  fi
  out=""
  out=$(check_marketplace "$TARGET" "$mp_loc") || {
    echo "ERROR: could not read marketplace: $TARGET" >&2
    exit 2
  }
  printf '%s' "$out"
  [[ -n "$IDS_MODE" ]] || printf '\n'
  exit 0
fi

# shellcheck disable=SC2016  # a jq program: every $var is a jq variable
jq_to mp_pairs -r '
  if type != "object" then "\u0001shape"
  else (keys[] as $k
        | $k + "\u001f"
          + (.[$k] as $v
             | if ($v | type) == "object" then ($v.installLocation // "" | tostring) else "" end))
  end
' "$MARKETPLACES_JSON" 2>/dev/null || marketplaces_bad
[[ "$mp_pairs" != "$SENTINEL_SHAPE" ]] || marketplaces_bad

envelope=""
while IFS=$'\x1f' read -r mp mp_loc; do
  [[ -n "$mp" ]] || continue
  block=""
  if ! block=$(check_marketplace "$mp" "$mp_loc"); then
    json_string_to j_err "could not read marketplace"
    block="{\"error\":$j_err}"
  fi
  json_string_to j_name "$mp"
  [[ -z "$envelope" ]] || envelope+=","
  envelope+="$j_name:$block"
done <<<"$mp_pairs"
printf '{"marketplaces":{%s}}\n' "$envelope"
exit 0
