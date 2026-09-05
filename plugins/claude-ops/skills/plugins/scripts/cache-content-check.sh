#!/usr/bin/env bash
# Read-only cache-CONTENT audit for the `plugins` skill.
#
# `fleet-state.sh` answers "does the recorded version/sha look right". This
# script answers the question that check cannot: "do the FILES in the cache
# directory actually match the commit the install record claims". The two are
# not the same, and the gap between them is a real observed failure — see the
# mechanism note below. NEVER writes anything: no state file, no cache
# directory, no `git fetch`, no `claude plugin` call.
#
# Usage:
#   cache-content-check.sh --marketplace <name> [--scope user|project|all] [--json]
#   cache-content-check.sh --all [--scope user|project|all] [--json]
#   cache-content-check.sh --marketplace <name> [--scope …] --ids
#
# The mechanism this exists to catch (Claude Code 2.1.259, issue #3681
# evidence, not re-run since). `claude plugin update -y <plugin>@<marketplace>`
# re-points a record's `gitCommitSha` in `installed_plugins.json` without
# rewriting the cache directory when the manifest version number is unchanged.
# The version directory keeps the older build while the metadata claims the new
# commit, so a version-and-sha check passes while the files on disk are a
# different build, and any measurement or behaviour test against that cache is
# a test of the wrong thing. Six plugins were found in that state on one
# machine, twelve stale files in the worst case.
#
# How the compare works, and why it is two git processes per install rather
# than one per file. For each install record this script resolves the
# marketplace's `installLocation` (a git clone) and the plugin's `source`
# directory from that clone's own `.claude-plugin/marketplace.json`, then:
#   1. `git ls-tree -r <sha> -- <source>` — every blob id the commit says the
#      plugin's files should have;
#   2. one `git hash-object --stdin-paths` over every regular file in the cache
#      directory — the blob id each file on disk actually has.
# Set difference on the relative paths yields files present at the sha but
# missing from the cache and files in the cache but absent at the sha; hash
# inequality on the intersection yields changed files. No `git cat-file` pass
# is needed once ls-tree has carried the ids.
#
# Line endings. A raw `hash-object` applies no clean filter, so a path that
# `.gitattributes` checks out CRLF (a marketplace pinning `*.cmd text eol=crlf`
# is the observed case) would hash differently from its blob even when the
# content is identical. Rather than pay a per-file `--path` hash for the whole
# fleet, the raw batch runs first and only the MISMATCHES are re-hashed with
# `git hash-object --path <repo-relative-path>`, which does apply that path's
# attributes. A clean fleet therefore costs the two processes above; a dirty
# one pays one extra process per differing file, which is the population the
# operator is about to read one by one anyway.
#
# Excluded from the cache side, by name, never by guesswork: `.git` (a cache
# directory is a checkout, not a clone, but exclude it if one ever appears) and
# `.in_use` (Claude Code's own per-process refcount files, present in every
# cache version directory and never in any commit — folding them in would
# report the entire fleet as stale on their existence alone).
#
# Also excluded, and this one is load-bearing rather than cosmetic: a cache-only
# file that the marketplace repo's own `.gitignore` would ignore. A cache
# directory is a LIVE plugin root, so Python leaves `__pycache__` beside the
# scripts it runs and a plugin that vendors dependencies has a `node_modules`
# tree — generated state that was never in any commit. Without this filter the
# authoring machine reported three installs as stale purely on that state, one
# of them on 6,141 files, with zero genuinely differing bytes. The filter is one
# batched `git check-ignore` per plugin that has any cache-only file at all, and
# no process for a clean one.
#
# Verdicts, one per install record:
#   match                 every tree file present in the cache with the same
#                         blob id, and no extra file in the cache
#   stale-content         at least one file differs, is missing from the cache,
#                         or is in the cache and not at the sha. This is the
#                         finding; the record's paths[] lists up to
#                         MAX_REPORTED_PATHS of them
#   sha-not-local         the recorded `gitCommitSha` is not an object in the
#                         installLocation clone. NOT an error and NEVER fetched:
#                         a fetch is a network mutation this audit does not
#                         perform. This is the ORDINARY case, not an edge one —
#                         Claude Code clones a marketplace SHALLOW (a depth of 3
#                         observed on 2.1.261), so every record whose commit
#                         predates that window is legitimately unverifiable, and
#                         on the authoring machine 11 of 74 user-scope installs
#                         landed here. A report is only as strong as the share
#                         of installs it could actually compare
#   no-git-commit-sha     the record carries no `gitCommitSha` to compare against
#   no-install-location   the marketplace has no `installLocation`, or it is not
#                         a directory on this machine
#   not-a-git-worktree    the installLocation exists but is not a git work tree
#   no-source             the plugin id is absent from the marketplace's own
#                         marketplace.json, or its `source` is not a plain path
#                         string (a remote-source entry has no local tree here)
#   install-path-missing  the record's `installPath` is not a directory
#
# Output (stdout), default and with --json: one JSON object.
#   {marketplace, scope, checked, match, stale_content, unverifiable,
#    skipped_absent_project_paths, installs:[…]}
#   `unverifiable` counts every install whose verdict is neither `match` nor
#   `stale-content` — the audit looked and could not decide, which is reported
#   as its own number rather than folded into either side.
#   `skipped_absent_project_paths` counts project/local records whose
#   `projectPath` is not a directory on this machine. Those records are not
#   checked and not counted in `checked`. Absent is not dead: an unmounted
#   volume, an offline share, and a removed worktree are indistinguishable to a
#   directory test (see context/gotchas.md) — hence a count, never a verdict.
#   --all: {marketplaces: {"<name>": <single-marketplace shape>, …}}, and a
#   per-marketplace failure appears as {"<name>": {error: …}} inline rather
#   than aborting the sweep.
#
# Output (stdout) with --ids: NOT JSON — the fully-qualified
#   `<name>@<marketplace>` id of every `stale-content` install, one per line,
#   CR-free, and nothing else. Same contract as `fleet-state.sh --ids`: zero
#   matches is success with empty output (exit 0), and a rejected invocation
#   leaves stdout EMPTY so a `< <(…)` consumer can never read an error as an
#   id. `--ids` with `--all` is refused: there is no single block to project.
#
# Exit codes:
#   0  ran to completion (per-install verdicts, including every unverifiable
#      one, are reported in the body — a verdict is not an error)
#   2  fatal: jq or git missing, a usage error, a named marketplace that is not
#      in known_marketplaces.json, or an internal state file that is present
#      but does not match its expected shape (fail loud on schema drift)
#
#   Deliberate divergence from fleet-state.sh's vocabulary, stated so it does
#   not read as drift: fleet-state.sh exits 1 when a single marketplace cannot
#   be resolved. Here an unknown marketplace is exit 2, because the name came
#   from the caller's own argument and is a usage error, not a state-read
#   failure.
#
# Env overrides (testing only; production uses the real paths). Same names as
# fleet-state.sh, so a fixture built for one runs against the other:
#   CACHE_CONTENT_INSTALLED_JSON / FLEET_STATE_INSTALLED_JSON
#                                  — path to installed_plugins.json
#   CACHE_CONTENT_MARKETPLACES_JSON / FLEET_STATE_MARKETPLACES_JSON
#                                  — path to known_marketplaces.json
#   There is deliberately no catalog-directory override: this check needs a real
#   git clone at the marketplace's installLocation, so a fixture points
#   known_marketplaces.json at a throwaway repo instead of faking the catalog.

set -uo pipefail

# Resolve nothing through PATH-dependent helpers before the tool check; see
# fleet-state.sh's header for the environment-trust boundary this shares.
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq required (install with: winget install jqlang.jq | apt install jq | brew install jq)" >&2
  exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git required" >&2
  exit 2
fi

# --- jq capture ---------------------------------------------------------------
# Some native-Windows jq builds CRLF-terminate every line, including single-line
# compact output. `$(...)` strips only the trailing LF, so a stray CR survives
# and corrupts the value once re-parsed as JSON — and every id but the last in a
# line-oriented output arrives as `<name>@<marketplace>\r`. Every jq call goes
# through this helper, which strips ALL carriage returns in the shell (no `tr`
# process). Identical to fleet-state.sh's; see context/gotchas.md.
jq_to() {
  local __jq_var="$1"
  shift
  local __jq_out __jq_rc=0
  __jq_out=$(command jq "$@") || __jq_rc=$?
  printf -v "$__jq_var" '%s' "${__jq_out//$'\r'/}"
  return "$__jq_rc"
}

# git output gets the same treatment, for the same reason: a Windows git build
# writing CRLF would put a CR inside a path or a blob id.
git_to() {
  local __g_var="$1"
  shift
  local __g_out __g_rc=0
  __g_out=$(command git "$@") || __g_rc=$?
  printf -v "$__g_var" '%s' "${__g_out//$'\r'/}"
  return "$__g_rc"
}

# JSON string literal built with builtins, so the strings this shell assembles
# (paths, ids, verdicts) get the same escaping jq's own encoder applies.
json_string_to() {
  local __js_s="$2" __js_i __js_c __js_hex __js_out=""
  __js_s="${__js_s//\\/\\\\}"
  __js_s="${__js_s//\"/\\\"}"
  __js_s="${__js_s//$'\n'/\\n}"
  __js_s="${__js_s//$'\r'/\\r}"
  __js_s="${__js_s//$'\t'/\\t}"
  __js_s="${__js_s//$'\b'/\\b}" # portability-ok: JSON short escape for U+0008 in a parameter expansion, not a regex word boundary
  __js_s="${__js_s//$'\f'/\\f}"
  if [[ "$__js_s" == *[$'\x01'-$'\x1f']* ]]; then
    for ((__js_i = 0; __js_i < ${#__js_s}; __js_i++)); do
      __js_c="${__js_s:__js_i:1}"
      if [[ "$__js_c" == [$'\x01'-$'\x1f'] ]]; then
        printf -v __js_hex '\\u%04x' "'$__js_c"
        __js_out+="$__js_hex"
      else
        __js_out+="$__js_c"
      fi
    done
    __js_s="$__js_out"
  fi
  printf -v "$1" '"%s"' "$__js_s"
}

# Native Windows paths (`C:\Users\…`) come out of installed_plugins.json and
# known_marketplaces.json verbatim. Backslash is an escape character in the
# shell, so every such value is folded to forward slashes before any `-d` test
# or `git -C`; Git Bash accepts the `C:/…` spelling for both.
to_slashes_to() {
  printf -v "$1" '%s' "${2//\\//}"
}

INSTALLED_JSON="${CACHE_CONTENT_INSTALLED_JSON:-${FLEET_STATE_INSTALLED_JSON:-$HOME/.claude/plugins/installed_plugins.json}}"
MARKETPLACES_JSON="${CACHE_CONTENT_MARKETPLACES_JSON:-${FLEET_STATE_MARKETPLACES_JSON:-$HOME/.claude/plugins/known_marketplaces.json}}"

# How many differing paths a stale-content record lists. The count is always
# exact; the list is a sample, because a wholly-stale directory can differ in
# every file and a report naming all of them is not a report.
MAX_REPORTED_PATHS=10

# --- Arg parsing ---------------------------------------------------------------
# Parsed before any file is read, so a usage error costs no process.

MODE="default"
TARGET=""
SCOPE="user"
IDS_MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --marketplace)
    MODE="single"
    TARGET="${2:-}"
    # Guard BEFORE `shift 2`: with no following arg only one positional param
    # remains, `shift 2` fails (no set -e), $1 stays "--marketplace", and the
    # loop spins forever. Same reasoning as fleet-state.sh.
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
  *)
    echo "ERROR: unknown argument: $1" >&2
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

# --ids projects ONE marketplace's stale-content list; --all's envelope has no
# single block to project. Refused rather than invented.
if [[ -n "$IDS_MODE" && "$MODE" == "all" ]]; then
  echo "ERROR: --ids cannot be combined with --all" >&2
  echo "  Run --ids once per marketplace with --marketplace <name>." >&2
  exit 2
fi

# --- State files ---------------------------------------------------------------

for f in "$INSTALLED_JSON" "$MARKETPLACES_JSON"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: state file not found: $f" >&2
    exit 2
  fi
done

# Shape validation is its own pass and it fails LOUD. A malformed state file
# read leniently produces an empty install list, which is indistinguishable
# from a clean fleet — the one wrong answer this check must never give.
if ! jq_to _shape_ok -e '
  (type == "object")
  and ((.plugins // {}) | type == "object")
  and ((.plugins // {}) | to_entries | all(.value | type == "array"))
' "$INSTALLED_JSON" >/dev/null 2>&1; then
  echo "ERROR: $INSTALLED_JSON is not valid installed_plugins.json (expected an object with a .plugins map of arrays)" >&2
  exit 2
fi
if ! jq_to _shape_ok -e 'type == "object"' "$MARKETPLACES_JSON" >/dev/null 2>&1; then
  echo "ERROR: $MARKETPLACES_JSON is not valid known_marketplaces.json (expected an object)" >&2
  exit 2
fi

# --- Per-marketplace check -----------------------------------------------------

# Emits, on stdout, the single-marketplace JSON body for $1. Returns non-zero
# with a message on stderr only for a marketplace that cannot be named at all.
check_marketplace() {
  local mp="$1"
  local install_loc install_loc_native records
  local checked=0 n_match=0 n_stale=0 n_unverifiable=0 n_skipped=0
  local records_json="" first="yes"
  local stale_ids=""

  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to install_loc -r --arg mp "$mp" '.[$mp].installLocation // ""' "$MARKETPLACES_JSON" || return 1
  to_slashes_to install_loc_native "$install_loc"

  # Marketplace-wide preconditions, resolved ONCE rather than per install: the
  # source map and the worktree test are the same answer for every record.
  local loc_verdict="" source_map=""
  if [[ -z "$install_loc_native" || ! -d "$install_loc_native" ]]; then
    loc_verdict="no-install-location"
  elif ! git -C "$install_loc_native" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    loc_verdict="not-a-git-worktree"
  else
    local mp_json="$install_loc_native/.claude-plugin/marketplace.json"
    if [[ -f "$mp_json" ]]; then
      # name<TAB>source, only for entries whose source is a plain path string.
      # An object source names a remote checkout with no local tree here, and
      # is left out so the lookup miss becomes an honest `no-source` verdict.
      jq_to source_map -r '
        (.plugins // [])
        | map(select((.name | type == "string") and (.source | type == "string")))
        | map("\(.name)\t\(.source)")
        | .[]
      ' "$mp_json" 2>/dev/null || source_map=""
    fi
  fi

  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to records -r --arg mp "$mp" --arg scope "$SCOPE" '
    (.plugins // {})
    | to_entries
    | map(select(.key | endswith("@" + $mp)))
    | map(.key as $id | .value[] | {
        id: $id,
        scope: (.scope // "user"),
        version: (.version // ""),
        sha: (.gitCommitSha // ""),
        installPath: (.installPath // ""),
        projectPath: (.projectPath // "")
      })
    | map(select($scope == "all" or (if $scope == "user" then .scope == "user" else .scope != "user" end)))
    | map([.id, .scope, .version, .sha, .installPath, .projectPath] | @tsv)
    | .[]
  ' "$INSTALLED_JSON" || return 1

  local id scope version sha install_path project_path
  while IFS=$'\t' read -r id scope version sha install_path project_path; do
    [[ -n "$id" ]] || continue

    # A project/local record naming a directory that is not present is skipped
    # and counted, never verdicted: the cache directory may be perfectly fine
    # and the repo simply on an unmounted volume.
    if [[ "$scope" != "user" && -n "$project_path" ]]; then
      local project_path_native
      to_slashes_to project_path_native "$project_path"
      if [[ ! -d "$project_path_native" ]]; then
        n_skipped=$((n_skipped + 1))
        continue
      fi
    fi

    checked=$((checked + 1))
    local verdict="" paths=() n_differ=0 n_missing=0 n_extra=0
    local install_path_native
    to_slashes_to install_path_native "$install_path"

    local plugin_name="${id%@*}"
    local source_dir=""
    if [[ -n "$source_map" ]]; then
      local sm_name sm_source
      while IFS=$'\t' read -r sm_name sm_source; do
        if [[ "$sm_name" == "$plugin_name" ]]; then
          source_dir="$sm_source"
          break
        fi
      done <<<"$source_map"
    fi
    # marketplace.json spells a local source relative to the clone root and
    # commonly with a leading `./`, which ls-tree's pathspec does not want.
    source_dir="${source_dir#./}"
    source_dir="${source_dir%/}"

    if [[ -n "$loc_verdict" ]]; then
      verdict="$loc_verdict"
    elif [[ -z "$install_path_native" || ! -d "$install_path_native" ]]; then
      verdict="install-path-missing"
    elif [[ -z "$sha" ]]; then
      verdict="no-git-commit-sha"
    elif [[ -z "$source_dir" ]]; then
      verdict="no-source"
    elif ! git -C "$install_loc_native" cat-file -e "${sha}^{commit}" >/dev/null 2>&1; then
      # Never `git fetch` here. Fetching is a network mutation the audit does
      # not perform, and it would also silently repair the very condition the
      # verdict exists to report.
      verdict="sha-not-local"
    else
      local tree_out=""
      if ! git_to tree_out -C "$install_loc_native" ls-tree -r "$sha" -- "$source_dir"; then
        verdict="no-source"
      else
        # The two sides are indexed into associative arrays rather than walked
        # as parallel lists: a plugin that vendors `node_modules` carries
        # thousands of cache files, and a nested-loop membership test over both
        # directions is quadratic in exactly the population where it hurts.
        local -a tree_paths=() tree_hashes=()
        local -A tree_hash_by_path=() cache_hash_by_path=()
        local line meta path_rel blob
        while IFS= read -r line; do
          [[ -n "$line" ]] || continue
          meta="${line%%$'\t'*}"
          path_rel="${line#*$'\t'}"
          blob="${meta##* }"
          # Keep only blobs; a submodule (commit) entry has no file on disk to
          # compare and is not a stale-content signal.
          case "$meta" in
          *" blob "*) ;;
          *) continue ;;
          esac
          path_rel="${path_rel#"$source_dir"/}"
          tree_paths+=("$path_rel")
          tree_hashes+=("$blob")
          tree_hash_by_path["$path_rel"]="$blob"
        done <<<"$tree_out"

        # Cache side: one find, then one batched hash-object. `.in_use` is
        # Claude Code's own refcount directory and `.git` would be a checkout
        # artifact; both are excluded by name.
        local -a cache_paths=()
        local cache_list="" f
        while IFS= read -r f; do
          [[ -n "$f" ]] || continue
          cache_paths+=("${f#"$install_path_native"/}")
          cache_list+="$f"$'\n'
        done < <(find "$install_path_native" -type f \
          -not -path '*/.git/*' -not -path '*/.in_use/*' 2>/dev/null | sort)

        if [[ -n "$cache_list" ]]; then
          local hash_out="" hi=0
          if git_to hash_out -C "$install_loc_native" hash-object --stdin-paths <<<"${cache_list%$'\n'}"; then
            while IFS= read -r line; do
              [[ -n "$line" ]] || continue
              cache_hash_by_path["${cache_paths[hi]}"]="$line"
              hi=$((hi + 1))
            done <<<"$hash_out"
          fi
        fi

        local i
        # Direction 1: every tree path must exist in the cache with the same
        # blob id.
        for ((i = 0; i < ${#tree_paths[@]}; i++)); do
          if [[ -z "${cache_hash_by_path[${tree_paths[i]}]+set}" ]]; then
            n_missing=$((n_missing + 1))
            paths+=("missing-from-cache: ${tree_paths[i]}")
            continue
          fi
          if [[ "${cache_hash_by_path[${tree_paths[i]}]}" == "${tree_hashes[i]}" ]]; then
            continue
          fi
          # Raw hashes disagree. Re-hash THIS file with the repo-relative path
          # so `.gitattributes` (an `eol=crlf` pin, a clean filter) applies, and
          # only report a difference the filtered hash also sees. This is the
          # per-file process the batch above exists to avoid paying fleet-wide.
          local filtered=""
          if git_to filtered -C "$install_loc_native" hash-object \
            --path "$source_dir/${tree_paths[i]}" -- "$install_path_native/${tree_paths[i]}" 2>/dev/null &&
            [[ "$filtered" == "${tree_hashes[i]}" ]]; then
            continue
          fi
          n_differ=$((n_differ + 1))
          paths+=("differs: ${tree_paths[i]}")
        done

        # Direction 2: a file deleted at the sha but still sitting in the cache
        # is the same defect seen from the other side, and is exactly one of
        # the shapes the reported incident carried.
        #
        # Filtered through the marketplace's OWN .gitignore first, and that
        # filter is not an optimization — without it the check is wrong. A
        # cache directory is a live plugin root: Python writes `__pycache__`
        # beside the scripts it runs and a plugin that vendors dependencies has
        # a `node_modules` tree, none of which was ever in any commit. On the
        # authoring machine those alone reported three installs as stale, one
        # of them on 6,141 files, with zero genuinely differing bytes. A path
        # the marketplace repo itself declines to track is generated state, not
        # a stale build. One batched `git check-ignore` per plugin that has any
        # extra at all, and none for a clean one. `--no-index` so the answer is
        # the ignore rules' answer rather than "tracked, therefore not
        # ignored"; the paths are rewritten under the plugin's source directory
        # so a source-scoped rule matches the same way it would in the clone.
        local -a extras=()
        local cp
        for cp in "${cache_paths[@]:-}"; do
          [[ -n "$cp" ]] || continue
          [[ -z "${tree_hash_by_path[$cp]+set}" ]] || continue
          extras+=("$cp")
        done
        if [[ ${#extras[@]} -gt 0 ]]; then
          local ignore_in="" ignored_out=""
          local -A ignored=()
          for cp in "${extras[@]}"; do ignore_in+="$source_dir/$cp"$'\n'; done
          # check-ignore exits 1 when NOTHING matched, which is a valid answer,
          # so its status is deliberately not read as a failure.
          git_to ignored_out -C "$install_loc_native" check-ignore --no-index --stdin \
            <<<"${ignore_in%$'\n'}" || true
          while IFS= read -r line; do
            [[ -n "$line" ]] || continue
            ignored["${line#"$source_dir"/}"]=1
          done <<<"$ignored_out"
          for cp in "${extras[@]}"; do
            [[ -z "${ignored[$cp]+set}" ]] || continue
            n_extra=$((n_extra + 1))
            paths+=("extra-in-cache: $cp")
          done
        fi

        if [[ $((n_differ + n_missing + n_extra)) -gt 0 ]]; then
          verdict="stale-content"
        else
          verdict="match"
        fi
      fi
    fi

    case "$verdict" in
    match) n_match=$((n_match + 1)) ;;
    stale-content)
      n_stale=$((n_stale + 1))
      stale_ids+="$id"$'\n'
      ;;
    *) n_unverifiable=$((n_unverifiable + 1)) ;;
    esac

    local j_id j_scope j_version j_sha j_path j_verdict
    json_string_to j_id "$id"
    json_string_to j_scope "$scope"
    json_string_to j_version "$version"
    json_string_to j_sha "$sha"
    json_string_to j_path "$install_path"
    json_string_to j_verdict "$verdict"

    local paths_json="" p n=0 pfirst="yes" jp
    for p in "${paths[@]:-}"; do
      [[ -n "$p" ]] || continue
      n=$((n + 1))
      [[ $n -le $MAX_REPORTED_PATHS ]] || break
      json_string_to jp "$p"
      if [[ "$pfirst" == "yes" ]]; then
        pfirst="no"
      else
        paths_json+=","
      fi
      paths_json+="$jp"
    done

    if [[ "$first" == "yes" ]]; then
      first="no"
    else
      records_json+=","
    fi
    records_json+="{\"id\":$j_id,\"scope\":$j_scope,\"version\":$j_version,\"gitCommitSha\":$j_sha"
    records_json+=",\"installPath\":$j_path,\"verdict\":$j_verdict"
    records_json+=",\"differing\":$n_differ,\"missing_from_cache\":$n_missing,\"extra_in_cache\":$n_extra"
    records_json+=",\"paths\":[$paths_json]}"
  done <<<"$records"

  if [[ -n "$IDS_MODE" ]]; then
    printf '%s' "$stale_ids"
    return 0
  fi

  local j_mp j_scope_out
  json_string_to j_mp "$mp"
  json_string_to j_scope_out "$SCOPE"
  printf '{"marketplace":%s,"scope":%s,"checked":%d,"match":%d,"stale_content":%d,"unverifiable":%d,"skipped_absent_project_paths":%d,"installs":[%s]}' \
    "$j_mp" "$j_scope_out" "$checked" "$n_match" "$n_stale" "$n_unverifiable" "$n_skipped" "$records_json"
}

# --- Dispatch ------------------------------------------------------------------

# `known` is a write-only sink: the membership answer this run acts on is
# jq's EXIT STATUS under -e, not the `true`/`false` it also prints. Declared
# so `jq_to`'s indirect `printf -v` has a target the linter can see.
# shellcheck disable=SC2034
known=""
mp_names=""
envelope=""
j_name=""
j_err=""

if [[ "$MODE" == "single" ]]; then
  # shellcheck disable=SC2016  # a jq program: every $var is a jq variable
  jq_to known -e --arg mp "$TARGET" 'has($mp)' "$MARKETPLACES_JSON" >/dev/null 2>&1 || {
    echo "ERROR: unknown marketplace: $TARGET (not in $MARKETPLACES_JSON)" >&2
    exit 2
  }
  out=""
  out=$(check_marketplace "$TARGET") || {
    echo "ERROR: could not read marketplace: $TARGET" >&2
    exit 2
  }
  printf '%s' "$out"
  [[ -n "$IDS_MODE" ]] || printf '\n'
  exit 0
fi

jq_to mp_names -r 'keys[]' "$MARKETPLACES_JSON" || {
  echo "ERROR: could not enumerate marketplaces in $MARKETPLACES_JSON" >&2
  exit 2
}
envelope="" env_first="yes"
while IFS= read -r mp; do
  [[ -n "$mp" ]] || continue
  block=""
  if ! block=$(check_marketplace "$mp"); then
    json_string_to j_err "could not read marketplace"
    block="{\"error\":$j_err}"
  fi
  json_string_to j_name "$mp"
  if [[ "$env_first" == "yes" ]]; then
    env_first="no"
  else
    envelope+=","
  fi
  envelope+="$j_name:$block"
done <<<"$mp_names"
printf '{"marketplaces":{%s}}\n' "$envelope"
exit 0
