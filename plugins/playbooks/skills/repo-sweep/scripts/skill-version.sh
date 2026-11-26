#!/usr/bin/env bash
set -euo pipefail

installed=${REPO_SWEEP_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}
main=""
if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  main=$(dirname "$common")
fi
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
IFS=: read -ra dirs <<<"${REPO_SWEEP_PLUGIN_DIRS:-}"
cc=""

loaded_version() {
  local plugin=$1 d=${2//\\//} manifest segment
  local path=$d
  d=${d%/}
  while [[ -n $d ]]; do
    manifest="$d/.claude-plugin/plugin.json"
    if [[ -f $manifest ]]; then
      [[ $(jq -r '.name // empty' "$manifest") == "$plugin" ]] || return 0
      segment=$(jq -r '.version // empty' "$manifest")
      [[ -z $segment ]] || { printf '%s\n' "$segment"; return 0; }
      break
    fi
    [[ $d == */* ]] || break
    d=${d%/*}
  done
  segment=$(printf '%s\n' "$path" | sed -nE "s#^.*/cache/[^/]+/${plugin//./\\.}/([^/]+)(/.*)?\$#\\1#p")
  [[ -n $segment ]] && printf '%s\n' "$segment"
  return 0
}

installed_version() {
  [[ -f $installed ]] || return 0
  jq -r --arg p "$1@" --arg main "$main" '
    [.plugins | to_entries[] | select(.key | startswith($p)) | .value[]] as $all
    | first(($all[] | select(.scope != "user" and .projectPath == $main)),
            ($all[] | select(.scope == "user")))
    | .version // empty' "$installed"
}

loaded_dir=""
while (($#)); do
  if [[ $1 == --dir ]]; then
    if (($# < 3)) || [[ -z $2 || $3 == --dir ]]; then
      echo "skill-version.sh: --dir takes a directory and must precede a skill" >&2
      exit 2
    fi
    loaded_dir=$2
    shift 2
    continue
  fi
  arg=$1
  shift
  dir_for_arg=$loaded_dir
  loaded_dir=""
  if [[ $arg != *:* ]]; then
    if [[ -f ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/skills/$arg/SKILL.md ]]; then
      printf '%s@personal\n' "$arg"
    elif [[ -f $top/.claude/skills/$arg/SKILL.md ]]; then
      printf '%s@project\n' "$arg"
    else
      if [[ -z $cc ]]; then
        cc=$(claude --version 2>/dev/null | awk 'NR == 1 { print $1 }') || true
        if [[ $cc =~ ^[0-9][A-Za-z0-9.+-]*$ ]]; then cc=builtin-$cc; else cc=unknown; fi
      fi
      printf '%s@%s\n' "$arg" "$cc"
    fi
    continue
  fi
  plugin=${arg%%:*}
  version=""
  if [[ -n $dir_for_arg ]]; then
    version=$(loaded_version "$plugin" "$dir_for_arg")
    if [[ -n $version ]]; then
      recorded=$(installed_version "$plugin")
      if [[ -n $recorded && $recorded != "$version" ]]; then
        printf 'skill-version.sh: %s loaded %s, installed_plugins.json records %s: it updated mid-session\n' \
          "$plugin" "$version" "$recorded" >&2
      fi
    fi
  fi
  if [[ -z $version ]]; then
    for d in "${dirs[@]+"${dirs[@]}"}"; do
      manifest="$d/.claude-plugin/plugin.json"
      if [[ -f $manifest && $(jq -r '.name' "$manifest") == "$plugin" ]]; then
        version=$(jq -r '.version // "unknown"' "$manifest")
        break
      fi
    done
  fi
  [[ -n $version ]] || version=$(installed_version "$plugin")
  printf '%s@%s\n' "$arg" "${version:-unknown}"
done
