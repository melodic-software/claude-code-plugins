#!/usr/bin/env bash
# Contract tests for hop_chain.py: runs its --dry-run self-test and its
# --budget projection. Neither mode reaches the API, so this suite spends
# nothing; the live hop-chain run is an operator action, never a test.
#
# SKIPs (exit 0) when Python 3.10+ is unavailable, matching the repo test-runner
# convention for optional toolchains.
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")" || exit 1

source "../../lib/python-probe.sh"

PY=""
python_probe::floor_interpreter_to PY

if [[ -z "$PY" ]]; then
  echo "SKIP: Python 3.10+ not found"
  exit 0
fi

status=0

echo "== permission_prompts_args"
if ! "$PY" -X utf8 -c '
import hop_chain
import claude_cli
assert hop_chain.parse_claude_version("2.1.282 (Claude Code)") == (2, 1, 282)
assert hop_chain.parse_claude_version("nope") is None
claude_cli._CLAUDE_VERSION_CACHE = (2, 1, 259)
assert hop_chain.permission_prompts_args("claude") == ["--permission-prompts", "none"]
claude_cli._CLAUDE_VERSION_CACHE = (2, 1, 258)
assert hop_chain.permission_prompts_args("claude") == []
claude_cli._CLAUDE_VERSION_CACHE = None
assert hop_chain.permission_prompts_args("claude") == []
print("ok")
'; then
  echo "FAIL: permission_prompts_args"
  status=1
fi

echo "== is_write_indicator save_point"
if ! "$PY" -X utf8 -c '
import hop_chain
assert not hop_chain.is_write_indicator("python3 /p/scripts/save_point.py memory-root")
assert hop_chain.is_write_indicator("python3 /p/scripts/save_point.py new --topic x --no-previous")
print("ok")
'; then
  echo "FAIL: is_write_indicator save_point"
  status=1
fi

echo "== hop_chain.py --dry-run"
if ! "$PY" -X utf8 hop_chain.py --dry-run; then
  echo "FAIL: --dry-run self-test"
  status=1
fi

# --budget writes a 20-hop chain; give it its own scratch dir in mixed form so
# the native interpreter reads the same path Git Bash printed (windows-path-emit).
work="$(mktemp -d)"
if command -v cygpath >/dev/null 2>&1; then
  work="$(cygpath -m "$work")"
fi

echo "== hop_chain.py --budget"
if ! "$PY" -X utf8 hop_chain.py --budget --work-dir "$work"; then
  echo "FAIL: --budget projection"
  status=1
fi
rm -rf "$work"

if [[ "$status" -eq 0 ]]; then
  echo "PASS: hop_chain.py contract tests"
fi
exit "$status"
