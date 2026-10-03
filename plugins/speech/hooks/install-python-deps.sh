#!/usr/bin/env bash
# SessionStart hook: install the hash-locked Python packages (requirements.txt) into
# ${CLAUDE_PLUGIN_DATA} on demand, so the skills run against them and nothing fetches a package
# while a skill runs (docs/conventions/on-demand-dependencies, Python). A no-op once the set
# loads. A failed install is a notice on both channels with the repair line, never a silent skip.
# Always exits 0: a failed install must not block the session.
set -uo pipefail

data="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$data" ]] || exit 0

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"

# Loaded only when there is something to report: the common run installs nothing and says nothing.
notice() {
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  hook::emit_skip_notice SessionStart "$1"
}

# python3.12+, skipping a zero-length WindowsApps alias: it opens the Store instead of running.
py=""
for candidate in python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  [[ "$resolved" == *[Ww]indows[Aa]pps* && ! -s "$resolved" ]] && continue
  if "$candidate" -c 'import sys; raise SystemExit(sys.version_info < (3, 12))' 2>/dev/null; then
    py="$candidate"
    break
  fi
done

if [[ -z "$py" ]]; then
  notice "speech: Python 3.12 or later was not found on PATH, so its numpy and onnxruntime packages are not installed and /speech:narrate will stop. Install Python 3.12 or later (https://www.python.org/downloads/) and start a new session."
  exit 0
fi

if ! out="$("$py" "$ROOT/scripts/pydeps.py" install --data-dir "$data" </dev/null 2>&1)"; then
  notice "speech: its Python packages could not be installed, so /speech:narrate will stop until they are. $out"
fi
exit 0
