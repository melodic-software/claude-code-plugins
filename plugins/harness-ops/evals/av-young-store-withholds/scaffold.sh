#!/usr/bin/env bash
# A plugins-layout checkout with three skills; the run home holds no usage history.
set -euo pipefail
skill() {
  mkdir -p "plugins/$1/.claude-plugin" "plugins/$1/skills/$2"
  printf '{"name":"%s","version":"0.1.0","description":"%s plugin"}\n' "$1" "$1" >"plugins/$1/.claude-plugin/plugin.json"
  printf -- '---\ndescription: "%s"\n---\n\nBody.\n' "$3" >"plugins/$1/skills/$2/SKILL.md"
}
skill notes capture "Capture meeting notes into a dated markdown file. Use when: 'take notes', 'capture this meeting'."
skill notes search "Search captured notes by keyword. Use when: 'find my notes about X'."
skill release bump "Bump a package version and write a changelog line. Use when: 'bump the version', 'cut a release'."
