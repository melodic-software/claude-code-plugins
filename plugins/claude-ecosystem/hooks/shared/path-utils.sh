#!/usr/bin/env bash
# path-utils.sh - Path manipulation utilities for Claude Code hooks
#
# Provides utilities for path validation, pattern matching, and resolution.
#
# Usage: Source this file in your hook script: source "$(dirname "$0")/../shared/path-utils.sh"

set -euo pipefail

# Check if a file is tracked by git
# Usage: is_tracked_file "path/to/file" && echo "tracked"
is_tracked_file() {
    local file_path="$1"
    git ls-files --error-unmatch "$file_path" &>/dev/null
}

# Resolve path relative to project root
# Usage: abs_path=$(resolve_project_path "relative/path")
resolve_project_path() {
    local rel_path="$1"
    local project_root="${CLAUDE_PROJECT_DIR:-.}"
    echo "${project_root}/${rel_path}"
}

# Check if path matches any pattern in array
# Usage: matches_pattern "/home/user/file" "^/home/[^/]+/" && echo "matches"
matches_pattern() {
    local path="$1"
    local pattern="$2"
    
    echo "$path" | grep -qE "$pattern"
}

# Check if file has extension from list
# Usage: has_extension "file.bak" ".bak .backup ~" && echo "has extension"
has_extension() {
    local file_path="$1"
    local extensions="$2"
    
    for ext in $extensions; do
        if [[ "$file_path" == *"$ext" ]]; then
            return 0
        fi
    done
    return 1
}

# Get file extension
# Usage: ext=$(get_extension "file.md")
get_extension() {
    local file_path="$1"
    echo "${file_path##*.}"
}

# Check if path is in temp directory
# Usage: is_temp_path ".claude/temp/file.txt" && echo "temp file"
# Note: Handles both Unix (/) and Windows (\) path separators
is_temp_path() {
    local file_path="$1"
    local temp_dirs="${2:-.claude/temp node_modules .git __pycache__}"

    # Normalize path separators (Windows backslash to forward slash)
    local normalized_path
    normalized_path=$(echo "$file_path" | tr '\\' '/')

    for temp_dir in $temp_dirs; do
        # Also normalize the temp_dir for consistent comparison
        local normalized_dir
        normalized_dir=$(echo "$temp_dir" | tr '\\' '/')

        if [[ "$normalized_path" == *"$normalized_dir"* ]]; then
            return 0
        fi
    done
    return 1
}

# Detect absolute path patterns in content
# Check if path contains generic placeholders
# Usage: is_generic_placeholder "C:\Users\[username]\path" && echo "is placeholder"
# Returns: 0 if placeholder found, 1 otherwise
is_generic_placeholder() {
    local path="$1"

    # Angle brackets <...> - invalid in paths on Windows and Unix, so always a placeholder
    if echo "$path" | grep -qE '<[^>]+>'; then
        return 0
    fi

    # Square brackets with common placeholder names: [username], [user], [YourUsername], [name]
    if echo "$path" | grep -qiE '\[(username|user|your.*username|name)\]'; then
        return 0
    fi

    # Curly braces with common placeholder names: {username}, {user}, {name}
    if echo "$path" | grep -qiE '\{(username|user|your.*username|name)\}'; then
        return 0
    fi

    # Shell/environment variable placeholders: ${VAR}, $VAR
    # Match ${...} or $WORD (uppercase letters, digits, underscores)
    if echo "$path" | grep -qE '\$\{[A-Za-z_][A-Za-z0-9_]*\}|\$[A-Z_][A-Z0-9_]*'; then
        return 0
    fi

    return 1
}

# Usage: detect_absolute_paths "$content" && echo "found absolute paths"
# Returns: 0 if absolute paths found, 1 otherwise
detect_absolute_paths() {
    local content="$1"

    # Extract potential paths first, then filter out placeholders
    local temp_file=$(mktemp)

    # Windows drive letters (C:\, D:\, C:/, D:/)
    echo "$content" | grep -oE '[A-Za-z]:[/\\][^ ]*' > "$temp_file" || true

    # Unix explicit user paths (/home/username/, /Users/username/, /root/)
    echo "$content" | grep -oE '/(home|Users)/[^/]+/[^ ]*|/root/[^ ]*' >> "$temp_file" || true

    # Check if any non-placeholder paths exist
    local found_real_path=false
    while IFS= read -r path; do
        if [ -n "$path" ] && ! is_generic_placeholder "$path"; then
            found_real_path=true
            break
        fi
    done < "$temp_file"

    rm -f "$temp_file"

    if [ "$found_real_path" = true ]; then
        return 0
    else
        return 1
    fi
}

# Extract absolute paths from content (excluding generic placeholders)
# Usage: paths=$(extract_absolute_paths "$content")
extract_absolute_paths() {
    local content="$1"

    # Find Windows paths
    echo "$content" | grep -oE '[A-Za-z]:[/\\][^ ]*' | while IFS= read -r path; do
        if ! is_generic_placeholder "$path"; then
            echo "$path"
        fi
    done

    # Find Unix user paths
    echo "$content" | grep -oE '/(home|Users)/[^/]+/[^ ]*|/root/[^ ]*' | while IFS= read -r path; do
        if ! is_generic_placeholder "$path"; then
            echo "$path"
        fi
    done
}

# Normalize path separators (convert backslash to forward slash)
# Usage: normalized=$(normalize_path "C:\path\to\file")
normalize_path() {
    local path="$1"
    echo "$path" | tr '\\' '/'
}

# Check if path exceeds maximum length
# Usage: path_too_long "very/long/path" 260 && echo "path too long"
path_too_long() {
    local path="$1"
    local max_length="${2:-260}"
    
    if [ ${#path} -gt $max_length ]; then
        return 0
    fi
    return 1
}

