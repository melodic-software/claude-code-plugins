#!/usr/bin/env bash
# Always exits 0: a failed install must not block the session.
set -uo pipefail

[[ "${EVAL_PLAYWRIGHT_SKIP_PYDEPS:-}" == 1 ]] && exit 0

data="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$data" ]] || exit 0

SCRIPT_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"
ROOT="${SCRIPT_DIR%/*}"

notice() {
  # shellcheck source=hook-utils.sh
  source "$SCRIPT_DIR/hook-utils.sh"
  hook::emit_skip_notice SessionStart "" "$1"
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
  notice "playwright: Python 3.12 or later was not found on the hook PATH; /playwright:demo-video will fail. Install it (https://www.python.org/downloads/) and start a new session."
  exit 0
fi

# to_native <path> -> the path as a native Windows Python reads it. Under Git Bash or Cygwin a POSIX
# path (/c/...) goes through cygpath -m: a session with MSYS path conversion switched off hands it
# over as is, and Python resolves it against the current drive (C:\c\...). Fails rather than
# return the unconverted path.
to_native() {
  if [[ "${OSTYPE:-}" == msys* || "${OSTYPE:-}" == cygwin* ]] && [[ "$1" == /* ]]; then
    local converted
    converted="$(cygpath -m "$1" 2>/dev/null)" && [[ -n "$converted" ]] && printf '%s' "$converted"
  else
    printf '%s' "$1"
  fi
}

if ! script="$(to_native "$ROOT/skills/demo-video/scripts/pydeps.py")" || ! data_dir="$(to_native "$data")"; then
  notice "playwright: cygpath could not convert its pydeps.py or data directory path to Windows form, so the demo-video Python packages are not installed and /playwright:demo-video will stop. Check that cygpath runs in Git Bash and start a new session."
  exit 0
fi

if ! out="$("$py" "$script" install --data-dir "$data_dir" </dev/null 2>&1)"; then
  notice "playwright: demo-video Python packages not installed; /playwright:demo-video will fail. ${out#playwright: }"
fi
exit 0
