#!/usr/bin/env python3
from __future__ import annotations
"""
Cross-platform hook wrapper for Claude Code plugins (shared version).

This is the CANONICAL version at shared/hooks/hook-wrapper.py.
All plugins reference this file via relative path from ${CLAUDE_PLUGIN_ROOT}.

Usage: python hook-wrapper.py <relative-script-path>
Example: python hook-wrapper.py /hooks/your-hook/script.sh

The relative-script-path is resolved relative to CLAUDE_PLUGIN_ROOT (the plugin's
root directory), NOT relative to this script's location.

Problem: On Windows, CLAUDE_PLUGIN_ROOT uses backslashes (C:\\Users\\...) but hook
commands in hooks.json use forward slashes. Claude Code fails to spawn bash with
mixed separator paths - the error occurs BEFORE bash can even run.

Solution: This Python wrapper uses pathlib to normalize paths before spawning bash.
Python handles Windows/Unix paths natively with no separator issues.

Performance: Uses CLAUDE_BASH_PATH environment variable and module-level caching
to avoid repeated filesystem checks. Detection runs once per session, not per hook.

Bash detection priority (Windows):
1. CLAUDE_BASH_PATH environment variable (cached from previous invocation)
2. Module-level cached value (same-process reuse)
3. C:\\Program Files\\Git\\usr\\bin\\bash.exe
4. C:\\Program Files (x86)\\Git\\usr\\bin\\bash.exe
5. Git installation derived from 'where git' output
6. shutil.which("bash") fallback

macOS/Linux: Uses "bash" from PATH directly (no detection needed).

Workaround for: https://github.com/anthropics/claude-code/issues/11984
"""
import os
import sys
import subprocess
from pathlib import Path

# Module-level singleton for same-process reuse (avoids repeated detection)
_cached_bash_path: str | None = None


def find_bash() -> str:
    """Find bash executable with caching for performance.

    Returns the path to bash, using multi-level caching to avoid repeated
    filesystem checks on Windows. Detection result is cached in:
    1. Environment variable CLAUDE_BASH_PATH (survives across child processes)
    2. Module-level variable (survives within same process)

    On non-Windows platforms, simply returns "bash" (no detection needed).
    """
    global _cached_bash_path

    # Non-Windows: just use bash from PATH (fast path)
    if sys.platform != "win32":
        return "bash"

    # Check environment variable cache first (highest priority, survives across processes)
    env_cached = os.environ.get("CLAUDE_BASH_PATH")
    if env_cached:
        # Verify cached path still exists (in case Git was uninstalled)
        if Path(env_cached).exists():
            return env_cached
        # Cache is stale, clear it
        del os.environ["CLAUDE_BASH_PATH"]

    # Check module-level cache (same-process reuse)
    if _cached_bash_path:
        if Path(_cached_bash_path).exists():
            return _cached_bash_path
        # Cache is stale, clear it
        _cached_bash_path = None

    # Detection needed - check multiple locations
    bash_path = _detect_bash_windows()

    # Cache the result at both levels
    _cached_bash_path = bash_path
    os.environ["CLAUDE_BASH_PATH"] = bash_path  # Propagate to child processes

    return bash_path


def _detect_bash_windows() -> str:
    """Detect bash on Windows by checking multiple locations.

    Checks locations in priority order:
    1. Standard Git for Windows installation (64-bit)
    2. Standard Git for Windows installation (32-bit)
    3. Custom Git installation (derived from 'where git')
    4. Any bash in PATH via shutil.which()
    """
    import shutil

    # Priority-ordered list of common Git Bash locations
    git_bash_locations = [
        r"C:\Program Files\Git\usr\bin\bash.exe",
        r"C:\Program Files (x86)\Git\usr\bin\bash.exe",
    ]

    # Check standard locations first (fastest)
    for location in git_bash_locations:
        if Path(location).exists():
            return location

    # Try to find Git installation via 'where git' and derive bash path
    try:
        result = subprocess.run(
            ["where", "git"],
            capture_output=True,
            text=True,
            timeout=5,
            creationflags=subprocess.CREATE_NO_WINDOW if hasattr(subprocess, 'CREATE_NO_WINDOW') else 0
        )
        if result.returncode == 0 and result.stdout.strip():
            # git.exe is typically at <git-root>/cmd/git.exe or <git-root>/bin/git.exe
            # bash.exe is at <git-root>/usr/bin/bash.exe
            git_path = Path(result.stdout.strip().split('\n')[0])
            git_root = git_path.parent.parent  # Go up from cmd/ or bin/
            derived_bash = git_root / "usr" / "bin" / "bash.exe"
            if derived_bash.exists():
                return str(derived_bash)
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError):
        pass

    # Fallback to PATH lookup (may find WSL bash or other)
    bash_from_path = shutil.which("bash")
    if bash_from_path:
        return bash_from_path

    # Last resort: return generic "bash" and let subprocess error handling deal with it
    return "bash"


def main():
    """Main entry point."""
    if len(sys.argv) != 2:
        print(f"ERROR: Usage: {sys.argv[0]} <relative-script-path>", file=sys.stderr)
        print(f"Example: {sys.argv[0]} /hooks/your-hook/script.sh", file=sys.stderr)
        sys.exit(1)

    relative_path = sys.argv[1]

    # Get plugin root from environment variable (set by Claude Code)
    plugin_root_env = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if not plugin_root_env:
        print("ERROR: CLAUDE_PLUGIN_ROOT environment variable not set.", file=sys.stderr)
        print("This script must be invoked by Claude Code hooks.", file=sys.stderr)
        sys.exit(1)

    # Use pathlib to normalize the path (handles mixed separators on Windows)
    plugin_root = Path(plugin_root_env).resolve()

    # Construct absolute path to target script
    # Remove leading slash from relative path for Path concatenation
    clean_relative = relative_path.lstrip("/\\")
    target_script = (plugin_root / clean_relative).resolve()

    # Security: Verify resolved path stays within plugin directory (prevent path traversal)
    plugin_root_resolved = plugin_root.resolve()
    try:
        target_script.relative_to(plugin_root_resolved)
    except ValueError:
        print(f"ERROR: Path traversal attempt detected: {relative_path}", file=sys.stderr)
        print(f"Target {target_script} is outside plugin root {plugin_root_resolved}", file=sys.stderr)
        sys.exit(1)

    # Verify target script exists
    if not target_script.exists():
        print(f"ERROR: Target script not found: {target_script}", file=sys.stderr)
        print(f"PLUGIN_ROOT: {plugin_root}", file=sys.stderr)
        print(f"RELATIVE_PATH: {relative_path}", file=sys.stderr)
        sys.exit(1)

    # Execute target script with stdin passthrough
    try:
        # Convert to POSIX-style path for bash
        # D:\repos\... -> D:/repos/...
        script_path = target_script.as_posix()

        # Get cached bash path (detection only happens once per session)
        bash_cmd = find_bash()

        result = subprocess.run(
            [bash_cmd, script_path],
            stdin=sys.stdin,
            stdout=sys.stdout,
            stderr=sys.stderr,
        )
        sys.exit(result.returncode)
    except FileNotFoundError:
        print("ERROR: bash not found. Ensure Git Bash or similar is installed.", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"ERROR: Failed to execute script: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
