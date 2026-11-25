#!/usr/bin/env bash
set -uo pipefail

DEP_CAP=25
PROBE_DEPTH=3

usage() {
  cat <<'EOF'
Collect portfolio facts for one or more repositories, one JSON object per line.
Usage: portfolio-facts.sh <repo-path> [<repo-path>...]
Exit: 0 every path produced a record; 1 one or more paths were not readable directories
(a record is still emitted for the rest); 2 usage.
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ $# -lt 1 ]]; then
  printf 'usage: portfolio-facts.sh <repo-path> [<repo-path>...]\n' >&2
  exit 2
fi

_ARCH_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../lib" && pwd)"
# shellcheck source=../../../lib/dotnet-references.sh
source "$_ARCH_LIB/dotnet-references.sh"
# shellcheck source=../../../lib/github-remote.sh
source "$_ARCH_LIB/github-remote.sh"
# shellcheck source=../../../lib/json-escape.sh
source "$_ARCH_LIB/json-escape.sh"


JSON_ARR=""
json_name_array() {
  local item
  JSON_ARR=""
  [[ -n "$1" ]] || return 0
  while IFS= read -r item; do
    json_escape "$item"
    JSON_ARR="$JSON_ARR${JSON_ARR:+,}\"$JSON_ESC\""
  done < <(printf '%s' "$1" | grep -v '^[[:space:]]*$' | LC_ALL=C sort -u | head -"$DEP_CAP")
}

append_csv() {
  local current="${!1}"
  printf -v "$1" '%s%s%s' "$current" "${current:+, }" "$2"
}


REPO_FILES=""
index_repo_files() {
  local root="$1"
  REPO_FILES="$(
    find "$root" -mindepth 1 -maxdepth "$PROBE_DEPTH" \
      \( \( -name '.?*' \
      ! -name '.github' ! -name '.gitlab' ! -name '.circleci' \
      ! -name '.devcontainer' \) \
      -o -name node_modules -o -name vendor \) -prune -o \
      -type f \( \
      -name '*.csproj' -o -name '*.fsproj' -o -name 'global.json' \
      -o -name 'package.json' \
      -o -name 'pyproject.toml' -o -name 'requirements*.txt' -o -name 'setup.py' \
      -o -name 'go.mod' -o -name 'Cargo.toml' \
      -o -name 'pom.xml' -o -name 'build.gradle*' \
      -o -name 'Gemfile' -o -name 'composer.json' \
      -o -name '*.sh' -o -name '*.ps1' \
      \) -print 2>/dev/null |
      ROOT="$root/" awk 'index($0, ENVIRON["ROOT"]) == 1 { $0 = substr($0, length(ENVIRON["ROOT"]) + 1) } { print }' | LC_ALL=C sort
  )"
}

FIND_HIT=""
find_first() {
  local pattern="$1" line base first_hit=""
  FIND_HIT=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    base="${line##*/}"
    # shellcheck disable=SC2254
    case "$base" in
    $pattern)
      [[ -n "$first_hit" ]] || first_hit="$line"
      case "$line" in
      */*) ;;
      *)
        FIND_HIT="$line"
        return 0
        ;;
      esac
      ;;
    *) ;;
    esac
  done <<<"$REPO_FILES"
  [[ -n "$first_hit" ]] || return 1
  FIND_HIT="$first_hit"
  return 0
}

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

remote_owner() {
  local url="$1" rest owner had_scheme=0
  url="${url%.git}"
  case "$url" in
  *://*)
    had_scheme=1
    url="${url#*://}"
    case "$url" in
    /*) return 1 ;;
    *) ;;
    esac
    ;;
  *)
    case "$url" in
    /* | ./* | ../* | ~*) return 1 ;;
    */*:*) return 1 ;;
    *:*) ;;
    *) return 1 ;;
    esac
    ;;
  esac
  case "$url" in
  *@*)
    case "${url%%@*}" in
    */*) ;;
    *) url="${url#*@}" ;;
    esac
    ;;
  *) ;;
  esac
  if [[ "$had_scheme" -eq 1 ]]; then
    case "$url" in
    *:*)
      case "${url%%/*}" in
      *:*) url="${url%%:*}/${url#*/}" ;;
      *) ;;
      esac
      ;;
    *) ;;
    esac
  else
    case "$url" in
    *:*) url="${url%%:*}/${url#*:}" ;;
    *) ;;
    esac
  fi
  case "$url" in
  */*) rest="${url#*/}" ;;
  *) return 1 ;;
  esac
  owner="${rest%%/*}"
  case "$owner" in
  "" | . | ..) return 1 ;;
  *[!A-Za-z0-9._-]*) return 1 ;;
  *) ;;
  esac
  printf '%s' "$owner"
}

codeowners_default() {
  awk '
    { sub(/\r$/, "") }
    /^[[:space:]]*#/ { next }
    /^[[:space:]]*$/ { next }
    $1 == "*" && NF >= 2 { o = $2; sub(/^@/, "", o); print o; exit }
  ' "$1"
}

json_object_keys() {
  awk -v want="$2" '
    { buf = buf $0 "\n" }
    END {
      n = length(buf)
      depth = 0; instr = 0; esc = 0
      expectkey = 0; collecting = 0; key = ""; target = 0; done = 0
      for (i = 1; i <= n; i++) {
        c = substr(buf, i, 1)
        if (instr) {
          if (esc) { esc = 0 }
          else if (c == "\\") { esc = 1 }
          else if (c == "\"") {
            instr = 0
            if (collecting) {
              collecting = 0
              # The last key seen at this depth names the value about to open.
              keyat[depth] = key
              if (target != 0 && depth == target) print key
            }
          } else if (collecting) { key = key c }
          continue
        }
        if (c == "\"") {
          instr = 1
          if (expectkey) { collecting = 1; key = "" }
        } else if (c == "{") {
          depth++; isobj[depth] = 1; expectkey = 1
          if (!done && target == 0 && depth == 2 && keyat[1] == want) target = 2
        } else if (c == "[") {
          depth++; isobj[depth] = 0; expectkey = 0
        } else if (c == "}" || c == "]") {
          if (target != 0 && depth == target) { target = 0; done = 1 }
          depth--; expectkey = 0
        } else if (c == ":") {
          expectkey = 0
        } else if (c == ",") {
          expectkey = (depth >= 1 && isobj[depth] == 1) ? 1 : 0
        }
      }
    }
  ' "$1"
}

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


node_manifest_scope() {
  local file="$1"
  if [[ -n "$(
    json_object_keys "$file" dependencies
    json_object_keys "$file" peerDependencies
  )" ]]; then
    printf 'runtime'
  elif [[ -n "$(json_object_keys "$file" devDependencies)" ]]; then
    printf 'development'
  else
    printf 'runtime'
  fi
}

requirements_scope() {
  case "${1##*/}" in
  *-dev.txt | *_dev.txt | *-dev-*.txt | dev-*.txt | \
    *-ci.txt | *_ci.txt | *-ci-*.txt | ci-*.txt | \
    *-test.txt | *_test.txt | test-*.txt | \
    *-lint.txt | *-docs.txt | *-typing.txt)
    printf 'development'
    ;;
  *) printf 'runtime' ;;
  esac
}

dotdir_path() {
  case "/$1" in
  */.*/*) return 0 ;;
  *) return 1 ;;
  esac
}

effective_scope() {
  if dotdir_path "$1"; then printf 'development'; else printf '%s' "$2"; fi
}

pyproject_scope() {
  if grep -q '^[[:space:]]*\[project\]' "$1" 2>/dev/null; then
    printf 'runtime'
  elif grep -q '^[[:space:]]*\[dependency-groups\]' "$1" 2>/dev/null; then
    printf 'development'
  else
    printf 'runtime'
  fi
}


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
  index_repo_files "$repo"

  remote="$(git -C "$repo" remote get-url origin 2>/dev/null)" || remote=""
  if [[ "$remote" =~ ^(https?://)[^/@]*@(.*)$ ]]; then
    remote="${BASH_REMATCH[1]}${BASH_REMATCH[2]}"
  elif [[ "$remote" =~ ^([A-Za-z][A-Za-z0-9+.-]*://[^/@:]*):[^/@]*@(.*)$ ]]; then
    remote="${BASH_REMATCH[1]}@${BASH_REMATCH[2]}"
  fi
  [[ -n "$remote" ]] || remote="unknown"

  name="$(github_repo_name "$remote")" || name="$(basename "$repo")"

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

  runtimes=()
  toolings=()
  runtime_evidence=""
  tooling_evidence=""
  add_family() {
    local scope
    scope="$(effective_scope "$2" "$3")"
    if [[ "$scope" == "development" ]]; then
      toolings+=("$1")
      append_csv tooling_evidence "$1: $2 (development scope)"
    else
      runtimes+=("$1")
      append_csv runtime_evidence "$1: $2"
    fi
  }

  dotnet_proj=""
  for pattern in '*.csproj' '*.fsproj' 'global.json'; do
    if find_first "$pattern"; then
      dotnet_proj="$FIND_HIT"
      break
    fi
  done
  [[ -n "$dotnet_proj" ]] && add_family dotnet "$dotnet_proj" runtime

  node_manifest=""
  node_scope="runtime"
  if find_first 'package.json'; then
    node_manifest="$FIND_HIT"
    node_scope="$(effective_scope "$node_manifest" "$(node_manifest_scope "$repo/$node_manifest")")"
    js_runtime="node"
    if [[ -f "$repo/bun.lockb" || -f "$repo/bun.lock" || -f "$repo/bunfig.toml" ]]; then
      js_runtime="bun"
    elif [[ -f "$repo/deno.json" || -f "$repo/deno.jsonc" || -f "$repo/deno.lock" ]]; then
      js_runtime="deno"
    fi
    add_family "$js_runtime" "$node_manifest" "$node_scope"
  fi

  py_manifest=""
  py_dev_manifest=""
  py_scope="runtime"
  if find_first 'pyproject.toml'; then
    py_manifest="$FIND_HIT"
    py_scope="$(effective_scope "$py_manifest" "$(pyproject_scope "$repo/$py_manifest")")"
  else
    while IFS= read -r hit; do
      [[ -n "$hit" ]] || continue
      if [[ "$(effective_scope "$hit" "$(requirements_scope "$hit")")" == "development" ]]; then
        [[ -n "$py_dev_manifest" ]] || py_dev_manifest="$hit"
      elif [[ "$hit" != */* ]]; then
        py_manifest="$hit"
        break
      fi
    done < <(find_all 'requirements*.txt')
    if [[ -z "$py_manifest" ]] && find_first 'setup.py'; then
      py_manifest="$FIND_HIT"
    fi
    if [[ -z "$py_manifest" && -n "$py_dev_manifest" ]]; then
      py_manifest="$py_dev_manifest"
      py_scope="development"
    fi
  fi
  [[ -n "$py_manifest" ]] && add_family python "$py_manifest" "$py_scope"

  go_manifest=""
  find_first 'go.mod' && go_manifest="$FIND_HIT" && add_family go "$go_manifest" runtime

  rust_manifest=""
  find_first 'Cargo.toml' && rust_manifest="$FIND_HIT" && add_family rust "$rust_manifest" runtime

  for pattern in 'pom.xml' 'build.gradle*'; do
    if find_first "$pattern"; then
      add_family jvm "$FIND_HIT" runtime
      break
    fi
  done

  find_first 'Gemfile' && add_family ruby "$FIND_HIT" runtime
  find_first 'composer.json' && add_family php "$FIND_HIT" runtime

  if [[ ${#runtimes[@]} -eq 0 ]]; then
    for pattern in '*.sh' '*.ps1'; do
      if find_first "$pattern"; then
        add_family shell "$FIND_HIT" runtime
        break
      fi
    done
  fi

  if [[ ${#runtimes[@]} -eq 0 ]]; then
    runtime="unknown"
    runtime_evidence="no runtime-scope manifest under depth $PROBE_DEPTH"
  else
    runtime="$(
      IFS=,
      printf '%s' "${runtimes[*]}"
    )"
  fi

  if [[ ${#toolings[@]} -eq 0 ]]; then
    tooling="unknown"
    tooling_evidence="no development-scope manifest under depth $PROBE_DEPTH"
  else
    tooling="$(
      IFS=,
      printf '%s' "${toolings[*]}"
    )"
  fi

  primary="${runtimes[0]:-unknown}"

  target_framework="unknown"
  tf_evidence="no framework declaration for runtime $primary"
  tf=""
  tf_source=""
  case "$primary" in
  dotnet)
    if [[ "$dotnet_proj" == *.*proj ]]; then
      tf="$(grep -oE '<TargetFrameworks?>[^<]*</TargetFrameworks?>' "$repo/$dotnet_proj" 2>/dev/null |
        head -1 | sed 's/<[^>]*>//g')"
      tf_source="$dotnet_proj"
    fi
    ;;
  node | bun | deno)
    tf="$(tr '\n' ' ' <"$repo/$node_manifest" 2>/dev/null |
      grep -oE '"engines"[[:space:]]*:[[:space:]]*\{[^}]*\}' |
      grep -oE '"node"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 |
      sed 's/.*:[[:space:]]*"//; s/"$//')"
    tf_source="$node_manifest (engines.node)"
    ;;
  python)
    if [[ "$py_manifest" == *pyproject.toml ]]; then
      tf="$(scalar_value "$repo/$py_manifest" 'requires-python')"
      tf_source="$py_manifest (requires-python)"
    fi
    ;;
  go)
    tf="$(awk '{ sub(/\r$/, "") } /^go[[:space:]]+[0-9]/ { print $2; exit }' "$repo/$go_manifest" 2>/dev/null)"
    tf_source="$go_manifest (go directive)"
    ;;
  rust)
    tf="$(scalar_value "$repo/$rust_manifest" 'rust-version')"
    tf_source="$rust_manifest (rust-version)"
    if [[ -z "$tf" ]]; then
      tf="$(scalar_value "$repo/$rust_manifest" 'edition')"
      tf_source="$rust_manifest (edition)"
    fi
    ;;
  *) ;;
  esac
  if [[ -n "$tf" ]]; then
    target_framework="$tf"
    tf_evidence="$tf_source"
  fi

  dep_raw=""
  dep_sources=""
  dev_dep_raw=""
  dev_dep_sources=""

  if [[ "$dotnet_proj" == *.*proj ]]; then
    while IFS= read -r projfile; do
      [[ -n "$projfile" ]] || continue
      hits="$(dotnet_reference_includes "$repo/$projfile")"
      [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    done < <(
      find_all '*.csproj'
      find_all '*.fsproj'
    )
    append_csv dep_sources "*.csproj/*.fsproj Package/ProjectReference"
  fi

  if [[ -n "$node_manifest" ]]; then
    if [[ "$node_scope" != "development" ]]; then
      hits="$(
        json_object_keys "$repo/$node_manifest" dependencies
        json_object_keys "$repo/$node_manifest" peerDependencies
      )"
      [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
      append_csv dep_sources "$node_manifest (dependencies + peerDependencies)"
    fi
    hits="$(json_object_keys "$repo/$node_manifest" devDependencies)"
    if [[ -n "$hits" ]]; then
      dev_dep_raw="$dev_dep_raw$hits"$'\n'
      append_csv dev_dep_sources "$node_manifest (devDependencies)"
    fi
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
    if [[ "$py_scope" == "development" ]]; then
      if [[ -n "$hits" ]]; then
        dev_dep_raw="$dev_dep_raw$hits"$'\n'
        append_csv dev_dep_sources "$py_manifest (development scope)"
      fi
    else
      [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
      append_csv dep_sources "$py_manifest"
    fi
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
    append_csv dep_sources "$go_manifest (require)"
  fi

  if [[ -n "$rust_manifest" ]]; then
    hits="$(toml_table_keys "$repo/$rust_manifest" dependencies)"
    [[ -n "$hits" ]] && dep_raw="$dep_raw$hits"$'\n'
    append_csv dep_sources "$rust_manifest ([dependencies])"
  fi

  [[ -n "$dep_sources" ]] || dep_sources="no runtime-scope dependency manifest"
  [[ -n "$dev_dep_sources" ]] || dev_dep_sources="no development-scope dependency manifest"

  last_touched="$(git -C "$repo" log -1 --format=%cI 2>/dev/null)" || last_touched=""
  if [[ -n "$last_touched" ]]; then
    lt_evidence="git log -1 --format=%cI (local HEAD)"
  else
    last_touched="unknown"
    lt_evidence="no git history readable at this path"
  fi

  record='{'
  json_escape "$name" && record="$record\"name\":\"$JSON_ESC\","
  json_escape "$repo" && record="$record\"path\":\"$JSON_ESC\","
  json_escape "$remote" && record="$record\"remote\":\"$JSON_ESC\","
  json_escape "$owner" && record="$record\"owner\":\"$JSON_ESC\","
  json_escape "$runtime" && record="$record\"runtime\":\"$JSON_ESC\","
  json_escape "$tooling" && record="$record\"tooling\":\"$JSON_ESC\","
  json_escape "$target_framework" && record="$record\"target_framework\":\"$JSON_ESC\","
  json_name_array "$dep_raw"
  record="$record\"dependencies\":[$JSON_ARR],"
  json_name_array "$dev_dep_raw"
  record="$record\"dev_dependencies\":[$JSON_ARR],"
  json_escape "$last_touched" && record="$record\"last_touched\":\"$JSON_ESC\","
  record="$record\"evidence\":{"
  json_escape "$owner_evidence" && record="$record\"owner\":\"$JSON_ESC\","
  json_escape "$runtime_evidence" && record="$record\"runtime\":\"$JSON_ESC\","
  json_escape "$tooling_evidence" && record="$record\"tooling\":\"$JSON_ESC\","
  json_escape "$tf_evidence" && record="$record\"target_framework\":\"$JSON_ESC\","
  json_escape "$dep_sources" && record="$record\"dependencies\":\"$JSON_ESC\","
  json_escape "$dev_dep_sources" && record="$record\"dev_dependencies\":\"$JSON_ESC\","
  json_escape "$lt_evidence" && record="$record\"last_touched\":\"$JSON_ESC\""
  record="$record}}"
  printf '%s\n' "$record"

  unset -f add_family
done

exit "$exit_code"
