#!/usr/bin/env bash
# SessionStart hook: install the hash-locked Python packages (requirements.txt) into
# ${CLAUDE_PLUGIN_DATA} on demand, so the produce skill runs against them and nothing fetches a
# package while a skill runs (docs/conventions/on-demand-dependencies, Python). A no-op once the
# set loads. A failed install is a notice on both channels with the repair line, never a silent
# skip. Always exits 0: a failed install must not block the session.
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

# Any Python starts pydeps.py, which hands over to the first Python 3.12 or 3.13 on PATH and says so
# when there is none. A zero-length WindowsApps alias opens the Store instead of running: skip it.
py=""
for candidate in python3.13 python3.12 python3 python; do
  resolved="$(command -v "$candidate" 2>/dev/null)" || continue
  [[ "$resolved" == *[Ww]indows[Aa]pps* && ! -s "$resolved" ]] && continue
  py="$candidate"
  break
done

if [[ -z "$py" ]]; then
  notice "explainer-video: Python 3.12 or 3.13 was not found on PATH, so ManimCE is not installed and /explainer-video:produce will stop. Install Python 3.13 (https://www.python.org/downloads/) and start a new session."
  exit 0
fi

if ! out="$("$py" "$ROOT/scripts/pydeps.py" install --data-dir "$data" </dev/null 2>&1)"; then
  notice "explainer-video: its Python packages (ManimCE) could not be installed, so /explainer-video:produce will stop until they are. $out"
fi
exit 0
