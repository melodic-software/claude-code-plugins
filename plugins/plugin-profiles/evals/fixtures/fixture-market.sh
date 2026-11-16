#!/usr/bin/env bash
# Seeds the run's temporary home with a local marketplace, fixture-market, and installs from it.
#   both:         notes-hooks (ships a SessionStart hook and the skill jot) and draw (skill sketch)
#   draw-missing: notes-hooks only; draw stays in the marketplace, not installed
# Refuses to run anywhere but a claude plugin eval run's temporary home, so it never touches a
# real Claude Code configuration.
set -euo pipefail
mode="${1:?mode: both or draw-missing}"

here="$(pwd -P)"
home="$(cd "${HOME:-/nonexistent}" 2>/dev/null && pwd -P || true)"
run="$(dirname "${home:-/}")"
if [[ -z "${home}" || "$(basename "${home}")" != home || "$(basename "${run}")" != claude-eval-* || -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
  echo "refusing to scaffold: HOME (${HOME:-unset}) is not a claude plugin eval run's temporary home" >&2
  exit 3
fi
case "${here}" in
  / | "${home}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
  *) ;;
esac

market="${home}/fixture-market"
mkdir -p "${market}/.claude-plugin" \
  "${market}/plugins/notes-hooks/.claude-plugin" "${market}/plugins/notes-hooks/hooks" "${market}/plugins/notes-hooks/skills/jot" \
  "${market}/plugins/draw/.claude-plugin" "${market}/plugins/draw/skills/sketch"

cat >"${market}/.claude-plugin/marketplace.json" <<'JSON'
{
  "name": "fixture-market",
  "owner": { "name": "Fabrikam Fixture" },
  "plugins": [
    { "name": "notes-hooks", "source": "./plugins/notes-hooks", "description": "Notes with a session-start reminder." },
    { "name": "draw", "source": "./plugins/draw", "description": "Sketch diagrams." }
  ]
}
JSON
cat >"${market}/plugins/notes-hooks/.claude-plugin/plugin.json" <<'JSON'
{ "name": "notes-hooks", "version": "1.0.0", "description": "Notes with a session-start reminder." }
JSON
cat >"${market}/plugins/notes-hooks/hooks/hooks.json" <<'JSON'
{ "hooks": { "SessionStart": [{ "hooks": [{ "type": "command", "command": "true" }] }] } }
JSON
printf -- '---\ndescription: "Jot a note. Use when the user asks to jot something down."\ndisable-model-invocation: false\n---\n\nAppend the note to notes.md.\n' \
  >"${market}/plugins/notes-hooks/skills/jot/SKILL.md"
cat >"${market}/plugins/draw/.claude-plugin/plugin.json" <<'JSON'
{ "name": "draw", "version": "1.0.0", "description": "Sketch diagrams." }
JSON
printf -- '---\ndescription: "Sketch a diagram. Use when the user asks for a sketch."\ndisable-model-invocation: false\n---\n\nDraw it as ASCII.\n' \
  >"${market}/plugins/draw/skills/sketch/SKILL.md"

claude plugin marketplace add "${market}"
claude plugin install notes-hooks@fixture-market --scope user
if [[ "${mode}" == both ]]; then
  claude plugin install draw@fixture-market --scope user
fi
