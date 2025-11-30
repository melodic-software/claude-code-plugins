#!/usr/bin/env bash
# git-utils.sh - Git command utilities for Claude Code hooks
#
# Provides utilities for detecting and parsing git commands.
#
# Usage: Source this file in your hook script: source "$(dirname "$0")/../shared/git-utils.sh"

set -euo pipefail

# Check if command is a git command
# Usage: is_git_command "git commit -m 'message'" && echo "is git"
is_git_command() {
    local command="$1"
    echo "$command" | grep -qE '^\s*git\s+'
}

# Check if command is a git commit command
# Usage: is_git_commit "git commit -m 'message'" && echo "is commit"
is_git_commit() {
    local command="$1"
    echo "$command" | grep -qE '^\s*git\s+(commit|ci)\s+'
}

# Check if git command has specific flag
# Usage: has_git_flag "git commit --no-gpg-sign" "--no-gpg-sign" && echo "has flag"
has_git_flag() {
    local command="$1"
    local flag="$2"
    
    echo "$command" | grep -qE "(^|\s)${flag}(\s|$)"
}

# Check if git command has any blocked flags
# Usage: has_blocked_flag "git commit --no-verify" "--no-verify --no-gpg-sign" && echo "blocked"
has_blocked_flag() {
    local command="$1"
    local blocked_flags="$2"
    
    for flag in $blocked_flags; do
        if has_git_flag "$command" "$flag"; then
            return 0
        fi
    done
    return 1
}

# Extract git subcommand (commit, push, pull, etc.)
# Usage: subcommand=$(get_git_subcommand "git commit -m 'test'")
get_git_subcommand() {
    local command="$1"
    # Use sed instead of grep -oP for macOS compatibility
    echo "$command" | sed -n 's/^[[:space:]]*git[[:space:]]\+\([a-z-]*\).*/\1/p' | head -1
}

# Check if command is using git-commit skill (allowed pattern)
# Usage: is_git_commit_skill_invocation "invoke git-commit skill" && echo "using skill"
is_git_commit_skill_invocation() {
    local command="$1"
    
    # Check for skill invocation patterns (not direct git commands)
    if echo "$command" | grep -qE '(skill|git-commit skill|/commit)'; then
        return 0
    fi
    return 1
}

# Extract commit message from git commit command
# Usage: message=$(extract_commit_message "git commit -m 'my message'")
extract_commit_message() {
    local command="$1"
    
    # Try -m flag
    if echo "$command" | grep -qE '\s+-m\s+'; then
        echo "$command" | sed -n "s/.*-m\s\+['\"]\\(.*\\)['\"].*/\\1/p"
        return
    fi
    
    # Try --message flag
    if echo "$command" | grep -qE '\s+--message\s*='; then
        echo "$command" | sed -n "s/.*--message=\\s*['\"]\\(.*\\)['\"].*/\\1/p"
        return
    fi
    
    echo ""
}

# Check if git command is a direct commit (not through skill)
# Usage: is_direct_git_commit "git commit -m 'test'" && echo "direct commit"
is_direct_git_commit() {
    local command="$1"
    
    # Must be a git commit command
    if ! is_git_commit "$command"; then
        return 1
    fi
    
    # Must NOT be through skill
    if is_git_commit_skill_invocation "$command"; then
        return 1
    fi
    
    return 0
}

# Get list of staged files
# Usage: staged=$(get_staged_files)
get_staged_files() {
    git diff --cached --name-only 2>/dev/null || echo ""
}

# Check if there are staged changes
# Usage: has_staged_changes && echo "has changes"
has_staged_changes() {
    [ -n "$(get_staged_files)" ]
}

# Check if GPG signing is configured
# Usage: is_gpg_signing_enabled && echo "GPG enabled"
is_gpg_signing_enabled() {
    local gpg_sign=$(git config --get commit.gpgsign 2>/dev/null || echo "false")
    [ "$gpg_sign" = "true" ]
}

# Get current branch name
# Usage: branch=$(get_current_branch)
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo ""
}

