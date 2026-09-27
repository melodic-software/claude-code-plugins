#!/usr/bin/env bash
# Print <plugin:skill>@<version> for each <plugin:skill> argument, one line each.
#
# Version source, first hit wins:
#   1. REPO_SWEEP_PLUGIN_DIRS: colon-separated plugin dirs (as loaded with --plugin-dir).
#      The dir whose .claude-plugin/plugin.json "name" is the plugin supplies its
#      "version" (unknown when it has none).
#   2. REPO_SWEEP_INSTALLED_PLUGINS (default ~/.claude/plugins/installed_plugins.json):
#      installs under keys <plugin>@<marketplace>. A project- or local-scope install whose
#      projectPath is this repo's main checkout wins, else the user-scope install.
# Versions print verbatim (SHA-style included). Nothing found: @unknown.
#
# An argument with no plugin prefix names a bundled skill unless a same-named skill replaces
# it, first hit wins: @personal for ${CLAUDE_CONFIG_DIR:-~/.claude}/skills/<name>/SKILL.md,
# @project for .claude/skills/<name>/SKILL.md at this checkout's top level. Otherwise
# @builtin-<version> from `claude --version`, @unknown when that prints no version. A bundled
# skill's existence is not checked: nothing outside a running session lists them.
set -euo pipefail

installed=${REPO_SWEEP_INSTALLED_PLUGINS:-$HOME/.claude/plugins/installed_plugins.json}
main=""
if common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null); then
  main=$(dirname "$common")
fi
top=$(git rev-parse --show-toplevel 2>/dev/null) || top=$PWD
IFS=: read -ra dirs <<<"${REPO_SWEEP_PLUGIN_DIRS:-}"
cc=""

for arg in "$@"; do
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
  for d in "${dirs[@]+"${dirs[@]}"}"; do
    manifest="$d/.claude-plugin/plugin.json"
    if [[ -f $manifest && $(jq -r '.name' "$manifest") == "$plugin" ]]; then
      version=$(jq -r '.version // "unknown"' "$manifest")
      break
    fi
  done
  if [[ -z $version && -f $installed ]]; then
    version=$(jq -r --arg p "$plugin@" --arg main "$main" '
      [.plugins | to_entries[] | select(.key | startswith($p)) | .value[]] as $all
      | first(($all[] | select(.scope != "user" and .projectPath == $main)),
              ($all[] | select(.scope == "user")))
      | .version // empty' "$installed")
  fi
  printf '%s@%s\n' "$arg" "${version:-unknown}"
done
