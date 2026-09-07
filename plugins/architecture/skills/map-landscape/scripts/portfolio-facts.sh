#!/usr/bin/env bash
# Collect portfolio facts for one or more repositories, as JSON.
#
# WHY. The landscape and portfolio artifacts are only as trustworthy as the
# facts under them, and a model reading manifests by hand guesses: it infers a
# runtime from a directory name, an owner from a commit author, a framework
# from a memory of the ecosystem. Every fact this script emits comes from a
# named file in the repository, and anything no probe could derive is the
# literal string "unknown" rather than a plausible value.
#
# Usage:
#   portfolio-facts.sh <repo-path> [<repo-path>...]
#   portfolio-facts.sh --help
#
# Output: JSON Lines on stdout, one object per repository, in argument order:
#
#   {"name":…,"path":…,"remote":…,"owner":…,"runtime":…,
#    "target_framework":…,"dependencies":[…],"last_touched":…,"evidence":{…}}
#
#   name              directory basename
#   path              absolute path, as the shell resolved it
#   remote            `origin` URL, or "unknown"
#   owner             CODEOWNERS default rule, else the remote's owner segment,
#                     else "unknown". Never a commit author.
#   runtime           comma-joined list of every detected runtime, primary first,
#                     or "unknown"
#   target_framework  the primary runtime's framework/version declaration, or
#                     "unknown"
#   dependencies      sorted, de-duplicated, capped at 25
#   last_touched      `git log -1 --format=%cI` on the given checkout (local
#                     HEAD; nothing here fetches), or "unknown"
#   evidence          per fact, the repo-relative file that supplied it, or the
#                     reason it is unknown
#
# Portability: bash plus POSIX awk/grep/sed. No jq, no `grep -P`, no python.
#
# Exit: 0 = every path produced a record; 1 = one or more paths were not
# readable directories (a record is still emitted for the rest); 2 = usage.
set -uo pipefail

DEP_CAP=25
PROBE_DEPTH=3

usage() {
  # Print the header comment block only. Selecting by comment marker rather
  # than a hardcoded last line keeps --help correct when the header grows or
  # shrinks; a fixed range silently leaks `set -uo pipefail` the moment the
  # block changes length.
  sed -n '2,${/^#/!q;p;}' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  printf 'usage: portfolio-facts.sh <repo-path> [<repo-path>...]\n' >&2
  exit 2
fi

# ---------------------------------------------------------------------------
# JSON emission helpers
# ---------------------------------------------------------------------------

# Escape a scalar for a JSON string body into JSON_ESC. Backslash first, then
# quote, then the control characters JSON forbids raw: a Windows path is full of
# backslashes, so getting this order wrong corrupts every `path` field.
#
# Pure parameter expansion, and it assigns a global rather than printing,
# because BOTH an external process and a command substitution cost a fork. This
# runs once per emitted field, so the obvious `printf | awk` spelling inside
# `$(...)` measured near a second per field on a Windows checkout and dominated
# the whole collector.
JSON_ESC=""
json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\n'/\\n}"
  JSON_ESC="$s"
}

# ---------------------------------------------------------------------------
# Probe helpers
# ---------------------------------------------------------------------------

# ONE bounded walk per repository, restricted to the manifest names any probe
# below can consume, sorted, repo-relative. Every probe then filters this
# cached list. Thirteen separate `find` invocations over the same tree is the
# obvious spelling and is minutes slower per repository on a filesystem with
# per-open overhead, which is exactly where a fleet-wide run lives.
REPO_FILES=""
index_repo_files() {
  local root="$1"
  REPO_FILES="$(
    find "$root" -maxdepth "$PROBE_DEPTH" \
      \( -name node_modules -o -name vendor -o -name .venv -o -name .git \) -prune -o \
      -type f \( \
      -name '*.csproj' -o -name '*.fsproj' -o -name 'global.json' \
      -o -name 'package.json' \
      -o -name 'pyproject.toml' -o -name 'requirements*.txt' -o -name 'setup.py' \
      -o -name 'go.mod' -o -name 'Cargo.toml' \
      -o -name 'pom.xml' -o -name 'build.gradle*' \
      -o -name 'Gemfile' -o -name 'composer.json' \
      -o -name '*.sh' -o -name '*.ps1' \
      \) -print 2>/dev/null |
      sed "s|^${root}/||" | LC_ALL=C sort
  )"
}

# First indexed file whose basename matches the glob, into FIND_HIT. Returns 1
# and clears FIND_HIT when nothing matches. Assigns rather than prints for the
# same reason json_escape does: a command substitution per probe is a fork per
# probe, and there are a dozen probes per repository.
FIND_HIT=""
find_first() {
  local pattern="$1" line base
  FIND_HIT=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    base="${line##*/}"
    # An unquoted variable in a case pattern is a glob, which is the point:
    # callers pass `*.csproj`, not a literal name.
    # shellcheck disable=SC2254
    case "$base" in
    $pattern)
      FIND_HIT="$line"
      return 0
      ;;
    *) ;;
    esac
  done <<<"$REPO_FILES"
  return 1
}

# Every indexed file whose basename matches the glob, one per line.
find_all() {
  local pattern="$1" line base
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    base="${line##*/}"
    # shellcheck disable=SC2254  # deliberate glob, as in find_first above
    case "$base" in
    $pattern) printf '%s\n' "$line" ;;
    *) ;;
    esac
  done <<<"$REPO_FILES"
}

# The owner segment of a git remote URL. Handles scheme://host/owner/repo,
# user@host:owner/repo, and host/owner/repo. Prints nothing when the shape does
# not yield an owner rather than guessing at one.
remote_owner() {
  local url="$1" rest owner
  url="${url%.git}"
  url="${url#*://}"
  # Strip a `user@` only when the `@` precedes the first path separator, so an
  # `@` inside a path segment is left alone.
  case "$url" in
  *@*)
    case "${url%%@*}" in
    */*) ;;
    *) url="${url#*@}" ;;
    esac
    ;;
  *) ;;
  esac
  # scp-style `host:owner/repo` becomes `host/owner/repo`.
  case "$url" in
  *:*) url="${url%%:*}/${url#*:}" ;;
  *) ;;
  esac
  case "$url" in
  */*) rest="${url#*/}" ;;
  *) return 1 ;;
  esac
  owner="${rest%%/*}"
  # A local-path remote yields a drive letter or a dot segment, not an owner.
  case "$owner" in
  "" | . | ..) return 1 ;;
  *[!A-Za-z0-9._-]*) return 1 ;;
  *) ;;
  esac
  printf '%s' "$owner"
}

# The first owner of the default `*` rule in a CODEOWNERS file.
codeowners_default() {
  awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == "*" && NF >= 2 { o = $2; sub(/^@/, "", o); print o; exit }
  ' "$1"
}

# Keys of a top-level JSON object member, one per line. Walks the text with a
# depth and string-state machine because a package.json is not line-oriented
# and an anchored grep would miss a one-line manifest entirely.
json_object_keys() {
  awk -v want="$2" '
    { buf = buf $0 "\n" }
    END {
      i = index(buf, "\"" want "\"")
      if (i == 0) exit 0
      n = length(buf)
      while (i <= n && substr(buf, i, 1) != "{") {
        c = substr(buf, i, 1)
        # A member whose value is not an object has no keys to report.
        if (c == "[" || (c == "," && i > 1)) exit 0
        i++
      }
      if (i > n) exit 0
      i++
      depth = 1; instr = 0; esc = 0; expectkey = 1; collecting = 0; key = ""
      while (i <= n && depth > 0) {
        c = substr(buf, i, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") {
            instr = 0
            if (collecting) { print key; collecting = 0 }
          } else if (collecting) { key = key c }
        } else if (c == "\"") {
          instr = 1
          if (depth == 1 && expectkey) { collecting = 1; key = "" }
        } else if (c == "{") { depth++ }
        else if (c == "}") { depth-- }
        else if (c == ":" && depth == 1) { expectkey = 0 }
        else if (c == "," && depth == 1) { expectkey = 1 }
        i++
      }
    }
  ' "$1"
}

# Values of a TOML table's keys, or the key names themselves.
toml_table_keys() {
  awk -v want="$2" '
    { sub(/\r$/, "") }
    /^[[:space:]]*\[/ {
      sec = $0
      sub(/^[[:space:]]*\[/, "", sec)
      sub(/\].*$/, "", sec)
      insec = (sec == want)
      next
    }
    insec && /^[[:space:]]*[A-Za-z0-9_.-]+[[:space:]]*=/ {
      k = $0
      sub(/[[:space:]]*=.*$/, "", k)
      gsub(/[[:space:]]/, "", k)
      gsub(/"/, "", k)
      if (k != "") print k
    }
  ' "$1"
}

# A scalar `key = "value"` (or bare value) anywhere in a TOML/mod file.
scalar_value() {
  awk -v want="$2" '
    { sub(/\r$/, "") }
    matched { next }
    $0 ~ "^[[:space:]]*" want "[[:space:]]*=" {
      v = $0
      sub(/^[^=]*=[[:space:]]*/, "", v)
      sub(/[[:space:]]*(#.*)?$/, "", v)
      gsub(/"/, "", v)
      if (v != "") { print v; matched = 1 }
    }
  ' "$1"
}

# Package names from a requirements-style line set: the leading name token,
# with any version specifier, extra, or environment marker dropped.
requirements_names() {
  awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*-/ { next }
    {
      n = $0
      sub(/^[[:space:]]*/, "", n)
      sub(/[[:space:]].*$/, "", n)
      sub(/[[<>=!~;[].*$/, "", n)
      if (n != "") print n
    }
  '
}

# ---------------------------------------------------------------------------
# Per-repository collection
# ---------------------------------------------------------------------------

exit_code=0

for raw_path in "$@"; do
  if [[ ! -d "$raw_path" ]]; then
    printf 'portfolio-facts.sh: not a directory, skipped: %s\n' "$raw_path" >&2
    exit_code=1
    continue
  fi

  repo="$(cd "$raw_path" 2>/dev/null && pwd)" || {
    printf 'portfolio-facts.sh: unreadable, skipped: %s\n' "$raw_path" >&2
    exit_code=1
    continue
  }
  name="$(basename "$repo")"
  index_repo_files "$repo"

  # --- remote --------------------------------------------------------------
  remote="$(git -C "$repo" remote get-url origin 2>/dev/null)" || remote=""
  [[ -n "$remote" ]] || remote="unknown"

  # --- owner (CODEOWNERS, then the remote's owner segment) ------------------
  owner="unknown"
  owner_evidence="no CODEOWNERS default rule and no origin remote owner"
  for candidate in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
    [[ -f "$repo/$candidate" ]] || continue
    found_owner="$(codeowners_default "$repo/$candidate")"
    if [[ -n "$found_owner" ]]; then
      owner="$found_owner"
      owner_evidence="$candidate"
      break
    fi
  done
  if [[ "$owner" == "unknown" && "$remote" != "unknown" ]]; then
    if found_owner="$(remote_owner "$remote")"; then
      owner="$found_owner"
      owner_evidence="origin remote URL"
    fi
  fi

  # --- runtime (first hit is primary, every hit is listed) ------------------
  runtimes=()
  runtime_evidence=""
  add_runtime() {
    runtimes+=("$1")
    [[ -n "$runtime_evidence" ]] && runtime_evidence="$runtime_evidence, "
    runtime_evidence="$runtime_evidence$1: $2"
  }

  dotnet_proj=""
  for pattern in '*.csproj' '*.fsproj' 'global.json'; do
    if find_first "$pattern"; then
      hit="$FIND_HIT"
      [[ -z "$dotnet_proj" ]] && dotnet_proj="$hit"
      break
    fi
  done
  [[ -n "$dotnet_proj" ]] && add_runtime dotnet "$dotnet_proj"

  node_manifest=""
  if find_first 'package.json'; then
    node_manifest="$FIND_HIT"
    js_runtime="node"
    if [[ -f "$repo/bun.lockb" || -f "$repo/bun.lock" || -f "$repo/bunfig.toml" ]]; then
      js_runtime="bun"
    elif [[ -f "$repo/deno.json" || -f "$repo/deno.jsonc" || -f "$repo/deno.lock" ]]; then
      js_runtime="deno"
    fi
    add_runtime "$js_runtime" "$node_manifest"
  else
    node_manifest=""
  fi

  py_manifest=""
  for pattern in 'pyproject.toml' 'requirements*.txt' 'setup.py'; do
    if find_first "$pattern"; then
      hit="$FIND_HIT"
      py_manifest="$hit"
      break
    fi
  done
  [[ -n "$py_manifest" ]] && add_runtime python "$py_manifest"

  go_manifest=""
  if find_first 'go.mod'; then go_manifest="$FIND_HIT"; else go_manifest=""; fi
  [[ -n "$go_manifest" ]] && add_runtime go "$go_manifest"

  rust_manifest=""
  if find_first 'Cargo.toml'; then rust_manifest="$FIND_HIT"; else rust_manifest=""; fi
  [[ -n "$rust_manifest" ]] && add_runtime rust "$rust_manifest"

  jvm_manifest=""
  for pattern in 'pom.xml' 'build.gradle*'; do
    if find_first "$pattern"; then
      hit="$FIND_HIT"
      jvm_manifest="$hit"
      break
    fi
  done
  [[ -n "$jvm_manifest" ]] && add_runtime jvm "$jvm_manifest"

  ruby_manifest=""
  if find_first 'Gemfile'; then ruby_manifest="$FIND_HIT"; else ruby_manifest=""; fi
  [[ -n "$ruby_manifest" ]] && add_runtime ruby "$ruby_manifest"

  php_manifest=""
  if find_first 'composer.json'; then php_manifest="$FIND_HIT"; else php_manifest=""; fi
  [[ -n "$php_manifest" ]] && add_runtime php "$php_manifest"

  # `shell` only when nothing else claimed the repository.
  if [[ ${#runtimes[@]} -eq 0 ]]; then
    for pattern in '*.sh' '*.ps1'; do
      if find_first "$pattern"; then
        hit="$FIND_HIT"
        add_runtime shell "$hit"
        break
      fi
    done
  fi

  if [[ ${#runtimes[@]} -eq 0 ]]; then
    runtime="unknown"
    runtime_evidence="no runtime manifest under depth $PROBE_DEPTH"
  else
    runtime="$(
      IFS=,
      printf '%s' "${runtimes[*]}"
    )"
  fi

  primary="${runtimes[0]:-unknown}"

  # --- target framework (from the primary runtime's declaration) ------------
  target_framework="unknown"
  tf_evidence="no framework declaration for runtime $primary"
  case "$primary" in
  dotnet)
    if [[ -n "$dotnet_proj" && "$dotnet_proj" == *.*proj ]]; then
      tf="$(grep -oE '<TargetFrameworks?>[^<]*</TargetFrameworks?>' "$repo/$dotnet_proj" 2>/dev/null |
        head -1 | sed 's/<[^>]*>//g')"
      if [[ -n "$tf" ]]; then
        target_framework="$tf"
        tf_evidence="$dotnet_proj"
      fi
    fi
    ;;
  node | bun | deno)
    tf="$(tr '\n' ' ' <"$repo/$node_manifest" 2>/dev/null |
      grep -oE '"engines"[[:space:]]*:[[:space:]]*\{[^}]*\}' |
      grep -oE '"node"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 |
      sed 's/.*:[[:space:]]*"//; s/"$//')"
    if [[ -n "$tf" ]]; then
      target_framework="$tf"
      tf_evidence="$node_manifest (engines.node)"
    fi
    ;;
  python)
    if [[ "$py_manifest" == *pyproject.toml ]]; then
      tf="$(scalar_value "$repo/$py_manifest" 'requires-python')"
      if [[ -n "$tf" ]]; then
        target_framework="$tf"
        tf_evidence="$py_manifest (requires-python)"
      fi
    fi
    ;;
  go)
    tf="$(awk '{ sub(/\r$/, "") } /^go[[:space:]]+[0-9]/ { print $2; exit }' "$repo/$go_manifest" 2>/dev/null)"
    if [[ -n "$tf" ]]; then
      target_framework="$tf"
      tf_evidence="$go_manifest (go directive)"
    fi
    ;;
  rust)
    tf="$(scalar_value "$repo/$rust_manifest" 'rust-version')"
    tf_key="rust-version"
    if [[ -z "$tf" ]]; then
      tf="$(scalar_value "$repo/$rust_manifest" 'edition')"
      tf_key="edition"
    fi
    if [[ -n "$tf" ]]; then
      target_framework="$tf"
      tf_evidence="$rust_manifest ($tf_key)"
    fi
    ;;
  *) ;;
  esac

  # --- dependencies (every detected runtime family contributes) -------------
  dep_raw=""
  dep_sources=""
  note_dep_source() {
    [[ -n "$dep_sources" ]] && dep_sources="$dep_sources, "
    dep_sources="$dep_sources$1"
  }

  # `global.json` alone marks the runtime but carries no references, so it must
  # not claim a dependency source that produced nothing.
  if [[ "$dotnet_proj" == *.*proj ]]; then
    while IFS= read -r projfile; do
      [[ -n "$projfile" ]] || continue
      hits="$(grep -oE '<(Package|Project)Reference[^>]*Include="[^"]*"' "$repo/$projfile" 2>/dev/null |
        sed 's/.*Include="//; s/"$//')"
      [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    done < <(
      find_all '*.csproj'
      find_all '*.fsproj'
    )
    note_dep_source "*.csproj/*.fsproj Package/ProjectReference"
  fi

  if [[ -n "$node_manifest" ]]; then
    hits="$(
      json_object_keys "$repo/$node_manifest" dependencies
      json_object_keys "$repo/$node_manifest" peerDependencies
    )"
    [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    note_dep_source "$node_manifest (dependencies + peerDependencies)"
  fi

  if [[ -n "$py_manifest" ]]; then
    if [[ "$py_manifest" == *pyproject.toml ]]; then
      hits="$(awk '
        { sub(/\r$/, "") }
        /^[[:space:]]*\[/ {
          sec = $0; sub(/^[[:space:]]*\[/, "", sec); sub(/\].*$/, "", sec)
          insec = (sec == "project"); next
        }
        insec && /^[[:space:]]*dependencies[[:space:]]*=/ { grab = 1 }
        grab { buf = buf $0; if (index($0, "]") > 0) grab = 0 }
        END {
          while (match(buf, /"[^"]*"/)) {
            s = substr(buf, RSTART + 1, RLENGTH - 2)
            sub(/[[<>=!~;[].*$/, "", s)
            gsub(/[[:space:]]/, "", s)
            if (s != "") print s
            buf = substr(buf, RSTART + RLENGTH)
          }
        }
      ' "$repo/$py_manifest")"
    else
      hits="$(requirements_names <"$repo/$py_manifest")"
    fi
    [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    note_dep_source "$py_manifest"
  fi

  if [[ -n "$go_manifest" ]]; then
    hits="$(awk '
      { sub(/\r$/, "") }
      /^require[[:space:]]*\(/ { inblk = 1; next }
      inblk && /^[[:space:]]*\)/ { inblk = 0; next }
      inblk && /^[[:space:]]*[^\/[:space:]]/ { print $1; next }
      /^require[[:space:]]+[^([:space:]]/ { print $2 }
    ' "$repo/$go_manifest")"
    [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    note_dep_source "$go_manifest (require)"
  fi

  if [[ -n "$rust_manifest" ]]; then
    hits="$(toml_table_keys "$repo/$rust_manifest" dependencies)"
    [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    note_dep_source "$rust_manifest ([dependencies])"
  fi

  dependencies=()
  if [[ -n "$dep_raw" ]]; then
    while IFS= read -r dep; do
      [[ -n "$dep" ]] || continue
      dependencies+=("$dep")
    done < <(printf '%s' "$dep_raw" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u | head -"$DEP_CAP")
  fi
  [[ -n "$dep_sources" ]] || dep_sources="no dependency manifest"

  # --- last touched (local HEAD; nothing here fetches) ----------------------
  last_touched="$(git -C "$repo" log -1 --format=%cI 2>/dev/null)" || last_touched=""
  if [[ -n "$last_touched" ]]; then
    lt_evidence="git log -1 --format=%cI (local HEAD)"
  else
    last_touched="unknown"
    lt_evidence="no git history readable at this path"
  fi

  # --- emit ----------------------------------------------------------------
  record='{'
  json_escape "$name" && record="$record\"name\":\"$JSON_ESC\","
  json_escape "$repo" && record="$record\"path\":\"$JSON_ESC\","
  json_escape "$remote" && record="$record\"remote\":\"$JSON_ESC\","
  json_escape "$owner" && record="$record\"owner\":\"$JSON_ESC\","
  json_escape "$runtime" && record="$record\"runtime\":\"$JSON_ESC\","
  json_escape "$target_framework" && record="$record\"target_framework\":\"$JSON_ESC\","
  record="$record\"dependencies\":["
  for ((di = 0; di < ${#dependencies[@]}; di++)); do
    [[ "$di" -gt 0 ]] && record="$record,"
    json_escape "${dependencies[$di]}"
    record="$record\"$JSON_ESC\""
  done
  record="$record],"
  json_escape "$last_touched" && record="$record\"last_touched\":\"$JSON_ESC\","
  record="$record\"evidence\":{"
  json_escape "$owner_evidence" && record="$record\"owner\":\"$JSON_ESC\","
  json_escape "$runtime_evidence" && record="$record\"runtime\":\"$JSON_ESC\","
  json_escape "$tf_evidence" && record="$record\"target_framework\":\"$JSON_ESC\","
  json_escape "$dep_sources" && record="$record\"dependencies\":\"$JSON_ESC\","
  json_escape "$lt_evidence" && record="$record\"last_touched\":\"$JSON_ESC\""
  record="$record}}"
  printf '%s\n' "$record"

  unset -f add_runtime note_dep_source
done

exit "$exit_code"
