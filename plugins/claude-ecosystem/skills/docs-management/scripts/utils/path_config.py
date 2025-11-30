#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Path Configuration - Single Source of Truth for All Paths

Provides centralized path resolution using configuration from config_registry.
All scripts should use these functions instead of hardcoding paths.

Usage:
    from path_config import get_base_dir, get_index_path, get_temp_dir
    
    base_dir = get_base_dir()
    index_path = get_index_path(base_dir)
    temp_dir = get_temp_dir()
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bootstrap; skill_dir = bootstrap.skill_dir; config_dir = bootstrap.config_dir

from .common_paths import find_repo_root

# Import config registry for defaults (bootstrap already set up paths)
try:
    if str(config_dir) not in sys.path:
        sys.path.insert(0, str(config_dir))
    from config.config_registry import get_default
except ImportError:
    # Fallback if config registry not available
    def get_default(section: str, key: str, default: any) -> any:
        return default

def get_base_dir(start: Path | None = None) -> Path:
    """
    Get the base directory for canonical documentation storage.

    Uses config from defaults.yaml (paths.base_dir) with fallback to
    'canonical' subdirectory of the skill. Resolves relative paths from
    the skill directory (not CWD) to ensure portable plugin operation.

    Args:
        start: Optional starting directory (ignored, kept for API compatibility).

    Returns:
        Path to base directory (absolute)

    Example:
        >>> base_dir = get_base_dir()
        >>> print(base_dir)
        /path/to/skill/canonical
    """
    # Get base_dir from config (default: "canonical" - relative to skill dir)
    base_dir_str = get_default('paths', 'base_dir', 'canonical')

    # Handle legacy config values that used full path from repo root
    # Convert them to skill-relative paths
    if '.claude/skills/docs-management/canonical' in base_dir_str:
        base_dir_str = 'canonical'
    elif base_dir_str == '.claude/references':
        base_dir_str = 'canonical'

    base_dir = Path(base_dir_str)

    # If relative, resolve from skill directory (NOT repo root or CWD)
    # This ensures the plugin works correctly regardless of where it's invoked from
    if not base_dir.is_absolute():
        base_dir = skill_dir / base_dir

    return base_dir.resolve()

def get_index_path(base_dir: Path | None = None) -> Path:
    """
    Get the path to index.yaml file.
    
    Args:
        base_dir: Optional base directory. If None, uses get_base_dir().
    
    Returns:
        Path to index.yaml (absolute)
    
    Example:
        >>> index_path = get_index_path()
        >>> print(index_path)
        /path/to/repo/.claude/skills/docs-management/canonical/index.yaml
    """
    if base_dir is None:
        base_dir = get_base_dir()
    
    # Get index filename from config (default: "index.yaml")
    index_filename = get_default('paths', 'index_filename', 'index.yaml')
    
    # Fallback to filesystem section for backward compatibility
    if index_filename == 'index.yaml':
        index_filename = get_default('filesystem', 'default_index_filename', 'index.yaml')
    
    return base_dir / index_filename

def get_temp_dir(start: Path | None = None) -> Path:
    """
    Get the temporary directory for reports and logs.

    Uses config from defaults.yaml (paths.temp_dir) with fallback to
    'temp' subdirectory of the skill. Resolves relative paths from
    the skill directory (not CWD) to ensure portable plugin operation.

    Args:
        start: Optional starting directory (ignored, kept for API compatibility).

    Returns:
        Path to temp directory (absolute)

    Example:
        >>> temp_dir = get_temp_dir()
        >>> print(temp_dir)
        /path/to/skill/temp
    """
    # Get temp_dir from config (default: "temp" - relative to skill dir)
    temp_dir_str = get_default('paths', 'temp_dir', 'temp')

    # Handle legacy config values that used path from repo root
    if temp_dir_str == '.claude/temp':
        temp_dir_str = 'temp'

    temp_dir = Path(temp_dir_str)

    # If relative, resolve from skill directory (NOT repo root or CWD)
    # This ensures the plugin works correctly regardless of where it's invoked from
    if not temp_dir.is_absolute():
        temp_dir = skill_dir / temp_dir

    return temp_dir.resolve()

if __name__ == '__main__':
    """Self-test for path_config module."""
    print("Path Configuration Self-Test")
    print("=" * 60)
    
    print("\nTesting get_base_dir()...")
    try:
        base_dir = get_base_dir()
        print(f"✓ Base directory: {base_dir}")
        print(f"  Exists: {base_dir.exists()}")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    print("\nTesting get_index_path()...")
    try:
        index_path = get_index_path()
        print(f"✓ Index path: {index_path}")
        print(f"  Exists: {index_path.exists()}")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    print("\nTesting get_temp_dir()...")
    try:
        temp_dir = get_temp_dir()
        print(f"✓ Temp directory: {temp_dir}")
        print(f"  Exists: {temp_dir.exists()}")
    except Exception as e:
        print(f"✗ Failed: {e}")
    
    print("\n" + "=" * 60)
    print("Self-test complete!")

