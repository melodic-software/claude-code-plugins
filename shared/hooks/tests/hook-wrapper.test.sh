#!/usr/bin/env bash
# hook-wrapper.test.sh - Cross-platform tests for shared hook-wrapper.py
#
# Tests the Python wrapper that handles Windows/Unix path normalization.
# Works on Windows (Git Bash/MSYS2), macOS, and Linux without platform-specific tools.
#
# IMPORTANT: This tests the SHARED hook-wrapper.py at shared/hooks/hook-wrapper.py
# which reads CLAUDE_PLUGIN_ROOT from the environment.
#
# No dependencies on: cygpath, MSYS_NO_PATHCONV, or other platform-specific utilities.

set -euo pipefail

# Resolve paths (portable across all platforms)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPER="${SCRIPT_DIR}/../hook-wrapper.py"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"

# For testing, we'll use claude-ecosystem as our test plugin
TEST_PLUGIN_ROOT="${REPO_ROOT}/plugins/claude-ecosystem"

# Find Python executable (cross-platform)
find_python() {
    if command -v python3 &>/dev/null; then
        echo "python3"
    elif command -v python &>/dev/null; then
        echo "python"
    else
        echo ""
    fi
}

PYTHON=$(find_python)
if [[ -z "$PYTHON" ]]; then
    echo "ERROR: Python not found. Tests require Python 3." >&2
    exit 1
fi

# Detect platform for Windows-only tests
is_windows() {
    [[ "$(uname -s)" == MINGW* ]] || [[ "$(uname -s)" == MSYS* ]] || [[ "$(uname -s)" == CYGWIN* ]]
}

# Get Windows-compatible path for Python (handles /d/repos -> D:/repos conversion)
# Python's pathlib doesn't understand MSYS-style paths (/d/repos/...), so we convert first
get_python_path() {
    local path="$1"
    $PYTHON -c "
import re
import sys
from pathlib import Path

path = r'''$path'''

# Detect MSYS-style path: /c/Users/... or /d/repos/...
# Pattern: starts with /<single-letter>/
msys_match = re.match(r'^/([a-zA-Z])(/.*)?$', path)
if msys_match:
    drive = msys_match.group(1).upper()
    rest = msys_match.group(2) or ''
    path = f'{drive}:{rest}'

print(Path(path).resolve())
"
}

# Test counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Colors (disabled in non-TTY environments)
if [[ -t 1 ]]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    RED=''
    YELLOW=''
    NC=''
fi

pass_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}PASS${NC}: $1"
}

fail_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}FAIL${NC}: $1"
    if [[ -n "${2:-}" ]]; then
        echo "      Details: $2"
    fi
}

skip_test() {
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    echo -e "${YELLOW}SKIP${NC}: $1"
}

# Resolve wrapper path for Python
WRAPPER_RESOLVED=$(get_python_path "$WRAPPER")
TEST_PLUGIN_ROOT_RESOLVED=$(get_python_path "$TEST_PLUGIN_ROOT")

echo ""
echo "=========================================="
echo "Test Suite: hook-wrapper.py (shared)"
echo "=========================================="
echo "Platform: $(uname -s)"
echo "Shell: ${BASH_VERSION:-unknown}"
echo "Python: $($PYTHON --version 2>&1)"
echo "Wrapper: $WRAPPER_RESOLVED"
echo "Test Plugin: $TEST_PLUGIN_ROOT_RESOLVED"
echo "=========================================="
echo ""

# --- Test Section: Wrapper Setup ---
echo "--- Wrapper Setup ---"

# Test 1: Wrapper script exists
if [[ -f "$WRAPPER" ]]; then
    pass_test "Wrapper script exists"
else
    fail_test "Wrapper script not found at $WRAPPER"
    exit 1
fi

# Test 2: Wrapper has correct shebang
if head -1 "$WRAPPER" | grep -q "#!/usr/bin/env python3"; then
    pass_test "Wrapper has correct shebang"
else
    fail_test "Wrapper missing or incorrect shebang"
fi

# Test 3: Wrapper is valid Python syntax
if $PYTHON -m py_compile "$WRAPPER_RESOLVED" 2>/dev/null; then
    pass_test "Wrapper is valid Python"
else
    fail_test "Wrapper has Python syntax errors"
fi

# --- Test Section: Environment Variable Handling ---
echo ""
echo "--- Environment Variable Handling ---"

# Test 4: Wrapper requires CLAUDE_PLUGIN_ROOT
OUTPUT=$($PYTHON "$WRAPPER_RESOLVED" "/hooks/test.sh" 2>&1) || true
if echo "$OUTPUT" | grep -q "CLAUDE_PLUGIN_ROOT"; then
    pass_test "Wrapper reports missing CLAUDE_PLUGIN_ROOT"
else
    fail_test "Wrapper should require CLAUDE_PLUGIN_ROOT" "$OUTPUT"
fi

# --- Test Section: Error Handling ---
echo ""
echo "--- Error Handling ---"

# Test 5: Wrapper shows usage when no arguments
OUTPUT=$($PYTHON "$WRAPPER_RESOLVED" 2>&1) || true
if echo "$OUTPUT" | grep -q "Usage:"; then
    pass_test "Wrapper shows usage when no arguments"
else
    fail_test "Wrapper should show usage when no arguments" "$OUTPUT"
fi

# Test 6: Wrapper handles missing script gracefully
OUTPUT=$(CLAUDE_PLUGIN_ROOT="$TEST_PLUGIN_ROOT_RESOLVED" $PYTHON "$WRAPPER_RESOLVED" "nonexistent/path/script.sh" 2>&1) || true
if echo "$OUTPUT" | grep -q "not found"; then
    pass_test "Wrapper reports missing scripts"
else
    fail_test "Wrapper should report missing scripts" "$OUTPUT"
fi

# --- Test Section: Script Execution ---
echo ""
echo "--- Script Execution ---"

# Test 7: Execute a real hook script
EXEC_RESULT=$($PYTHON -c "
import subprocess
import sys
import os
from pathlib import Path

wrapper = Path(r'''$WRAPPER_RESOLVED''')
plugin_root = Path(r'''$TEST_PLUGIN_ROOT_RESOLVED''')

# Look for test scripts
test_scripts = [
    'hooks/inject-current-date/bash/inject-current-date.sh',
    'hooks/inject-best-practices/bash/inject-best-practices.sh',
    'hooks/prevent-backup-files/bash/prevent-backup-files.sh',
]

found_script = None
for script in test_scripts:
    full_path = plugin_root / script
    if full_path.exists():
        found_script = '/' + script
        break

if not found_script:
    print('SKIP:No testable hook found')
    sys.exit(0)

# Run the wrapper with the found script and CLAUDE_PLUGIN_ROOT set
env = os.environ.copy()
env['CLAUDE_PLUGIN_ROOT'] = str(plugin_root)

result = subprocess.run(
    [sys.executable, str(wrapper), found_script],
    input=b'{}',
    capture_output=True,
    timeout=30,
    env=env
)

if result.returncode == 0:
    print(f'PASS:{found_script}')
else:
    print(f'FAIL:{result.returncode}:{result.stderr.decode()}')
" 2>&1) || EXEC_RESULT="ERROR:$?"

if [[ "$EXEC_RESULT" == PASS:* ]]; then
    SCRIPT_NAME="${EXEC_RESULT#PASS:}"
    pass_test "Wrapper executes real hook script ($SCRIPT_NAME)"
elif [[ "$EXEC_RESULT" == SKIP:* ]]; then
    skip_test "${EXEC_RESULT#SKIP:}"
else
    fail_test "Wrapper failed to execute hook" "$EXEC_RESULT"
fi

# Test 8: Wrapper preserves exit codes
EXIT_CODE_RESULT=$($PYTHON -c "
import subprocess
import sys
import tempfile
import os
from pathlib import Path

wrapper = Path(r'''$WRAPPER_RESOLVED''')
plugin_root = Path(r'''$TEST_PLUGIN_ROOT_RESOLVED''')

# Create temp script that exits with code 42
fd, temp_path = tempfile.mkstemp(suffix='.sh', dir=str(plugin_root))
os.write(fd, b'#!/usr/bin/env bash\nexit 42\n')
os.close(fd)

try:
    temp_name = Path(temp_path).name
    env = os.environ.copy()
    env['CLAUDE_PLUGIN_ROOT'] = str(plugin_root)

    result = subprocess.run(
        [sys.executable, str(wrapper), '/' + temp_name],
        capture_output=True,
        timeout=10,
        env=env
    )
    print(f'EXIT:{result.returncode}')
finally:
    os.unlink(temp_path)
" 2>&1) || EXIT_CODE_RESULT="ERROR"

if [[ "$EXIT_CODE_RESULT" == "EXIT:42" ]]; then
    pass_test "Wrapper preserves exit codes"
else
    fail_test "Wrapper should preserve exit codes (expected 42, got $EXIT_CODE_RESULT)"
fi

# Test 9: Wrapper passes stdin to target script
STDIN_RESULT=$($PYTHON -c "
import subprocess
import sys
import tempfile
import os
from pathlib import Path

wrapper = Path(r'''$WRAPPER_RESOLVED''')
plugin_root = Path(r'''$TEST_PLUGIN_ROOT_RESOLVED''')

# Create temp script that echoes stdin
fd, temp_path = tempfile.mkstemp(suffix='.sh', dir=str(plugin_root))
os.write(fd, b'#!/usr/bin/env bash\ncat\n')
os.close(fd)

try:
    temp_name = Path(temp_path).name
    env = os.environ.copy()
    env['CLAUDE_PLUGIN_ROOT'] = str(plugin_root)

    result = subprocess.run(
        [sys.executable, str(wrapper), '/' + temp_name],
        input=b'test-stdin-passthrough-data',
        capture_output=True,
        timeout=10,
        env=env
    )
    if b'test-stdin-passthrough-data' in result.stdout:
        print('PASS')
    else:
        print(f'FAIL:{result.stdout.decode()}')
finally:
    os.unlink(temp_path)
" 2>&1) || STDIN_RESULT="ERROR"

if [[ "$STDIN_RESULT" == "PASS" ]]; then
    pass_test "Wrapper passes stdin to target script"
else
    fail_test "Wrapper should pass stdin" "$STDIN_RESULT"
fi

# --- Test Section: Caching Behavior (Windows Only) ---
echo ""
echo "--- Caching Behavior ---"

# Test 10: Wrapper uses CLAUDE_BASH_PATH when set
if is_windows; then
    CACHE_TEST=$($PYTHON -c "
import os
import sys
from pathlib import Path

# Test that wrapper respects CLAUDE_BASH_PATH
wrapper_path = Path(r'''$WRAPPER_RESOLVED''')
wrapper_code = wrapper_path.read_text()

# Execute just the function definitions
exec(wrapper_code.split('if __name__')[0])

# Set a known valid bash path
git_bash = r'C:\Program Files\Git\usr\bin\bash.exe'
if Path(git_bash).exists():
    os.environ['CLAUDE_BASH_PATH'] = git_bash
    result = find_bash()
    if result == git_bash:
        print('PASS')
    else:
        print(f'FAIL:got {result}')
else:
    print('SKIP:no git bash')
" 2>&1) || CACHE_TEST="ERROR"

    if [[ "$CACHE_TEST" == "PASS" ]]; then
        pass_test "Wrapper respects CLAUDE_BASH_PATH environment variable"
    elif [[ "$CACHE_TEST" == SKIP:* ]]; then
        skip_test "CLAUDE_BASH_PATH test (${CACHE_TEST#SKIP:})"
    else
        fail_test "Wrapper should use CLAUDE_BASH_PATH" "$CACHE_TEST"
    fi
else
    skip_test "CLAUDE_BASH_PATH caching (Windows-only feature)"
fi

# Test 11: Wrapper sets CLAUDE_BASH_PATH after detection
if is_windows; then
    CACHE_SET_TEST=$($PYTHON -c "
import os
import sys
from pathlib import Path

wrapper_path = Path(r'''$WRAPPER_RESOLVED''')
wrapper_code = wrapper_path.read_text()

# Clear any existing cache
if 'CLAUDE_BASH_PATH' in os.environ:
    del os.environ['CLAUDE_BASH_PATH']

# Execute function definitions
exec(wrapper_code.split('if __name__')[0])

# Run detection
bash = find_bash()

# Check if it was cached
cached = os.environ.get('CLAUDE_BASH_PATH', '')
if cached and Path(cached).exists():
    print('PASS')
elif cached:
    print(f'FAIL:cached invalid path {cached}')
else:
    print('FAIL:not cached')
" 2>&1) || CACHE_SET_TEST="ERROR"

    if [[ "$CACHE_SET_TEST" == "PASS" ]]; then
        pass_test "Wrapper caches bash path in CLAUDE_BASH_PATH"
    else
        fail_test "Wrapper should cache bash path after detection" "$CACHE_SET_TEST"
    fi
else
    skip_test "Bash path caching verification (Windows-only feature)"
fi

# --- Test Summary ---
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo "Tests run:    $TESTS_RUN"
echo -e "Tests passed: ${GREEN}$TESTS_PASSED${NC}"
echo -e "Tests failed: ${RED}$TESTS_FAILED${NC}"
echo -e "Tests skipped: ${YELLOW}$TESTS_SKIPPED${NC}"
echo ""

if [[ $TESTS_FAILED -gt 0 ]]; then
    echo -e "${RED}FAILED${NC} - Some tests did not pass"
    exit 1
else
    echo -e "${GREEN}SUCCESS${NC} - All tests passed!"
    exit 0
fi
