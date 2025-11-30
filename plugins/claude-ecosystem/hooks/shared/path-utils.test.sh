#!/usr/bin/env bash
# path-utils.test.sh - Unit tests for path-utils functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"
source "${SCRIPT_DIR}/path-utils.sh"

test_suite_start "path-utils Tests"

# ============================================
# is_generic_placeholder Tests
# ============================================
test_section "is_generic_placeholder - Angle Brackets (Universal)"

# Any <...> pattern should be recognized as placeholder (chars invalid in paths)
is_generic_placeholder "<drive>:\Users\username" && result=0 || result=1
assert_exit_code 0 "$result" "<drive> recognized as placeholder"

is_generic_placeholder "<home>/username/.config" && result=0 || result=1
assert_exit_code 0 "$result" "<home> recognized as placeholder"

is_generic_placeholder "<project-root>/file.txt" && result=0 || result=1
assert_exit_code 0 "$result" "<project-root> recognized as placeholder"

is_generic_placeholder 'C:\Users\<username>\AppData' && result=0 || result=1
assert_exit_code 0 "$result" "<username> in angle brackets recognized"

is_generic_placeholder "/home/<user>/projects" && result=0 || result=1
assert_exit_code 0 "$result" "<user> in angle brackets recognized"

is_generic_placeholder "<anything-here>" && result=0 || result=1
assert_exit_code 0 "$result" "Any arbitrary <...> pattern recognized"

test_section "is_generic_placeholder - Square Brackets"

is_generic_placeholder 'C:\Users\[username]\path' && result=0 || result=1
assert_exit_code 0 "$result" "[username] recognized as placeholder"

is_generic_placeholder 'C:\Users\[user]\path' && result=0 || result=1
assert_exit_code 0 "$result" "[user] recognized as placeholder"

is_generic_placeholder 'C:\Users\[YourUsername]\path' && result=0 || result=1
assert_exit_code 0 "$result" "[YourUsername] recognized as placeholder"

is_generic_placeholder "/home/[name]/projects" && result=0 || result=1
assert_exit_code 0 "$result" "[name] recognized as placeholder"

test_section "is_generic_placeholder - Curly Braces"

is_generic_placeholder 'C:\Users\{username}\path' && result=0 || result=1
assert_exit_code 0 "$result" "{username} recognized as placeholder"

is_generic_placeholder "/home/{user}/projects" && result=0 || result=1
assert_exit_code 0 "$result" "{user} recognized as placeholder"

test_section "is_generic_placeholder - Shell Variables"

is_generic_placeholder "\${HOME}/projects" && result=0 || result=1
assert_exit_code 0 "$result" "\${HOME} recognized as placeholder"

is_generic_placeholder "\${USERNAME}/path" && result=0 || result=1
assert_exit_code 0 "$result" "\${USERNAME} recognized as placeholder"

is_generic_placeholder "\$HOME/projects" && result=0 || result=1
assert_exit_code 0 "$result" "\$HOME recognized as placeholder"

test_section "is_generic_placeholder - Real Paths (Should NOT Match)"

is_generic_placeholder 'C:\Users\john\Documents' && result=0 || result=1
assert_exit_code 1 "$result" "Real Windows path NOT recognized as placeholder"

is_generic_placeholder "/home/john/projects" && result=0 || result=1
assert_exit_code 1 "$result" "Real Unix path NOT recognized as placeholder"

is_generic_placeholder "/Users/jane/Library" && result=0 || result=1
assert_exit_code 1 "$result" "Real macOS path NOT recognized as placeholder"

is_generic_placeholder 'D:\repos\project\file.txt' && result=0 || result=1
assert_exit_code 1 "$result" "Real project path NOT recognized as placeholder"

# ============================================
# detect_absolute_paths Tests
# ============================================
test_section "detect_absolute_paths - Should Detect Real Paths"

detect_absolute_paths 'Check C:\Users\john\Documents for files' && result=0 || result=1
assert_exit_code 0 "$result" "Detects Windows absolute path"

detect_absolute_paths "Look in /home/john/projects" && result=0 || result=1
assert_exit_code 0 "$result" "Detects Unix /home path"

detect_absolute_paths "Config at /Users/jane/Library/config" && result=0 || result=1
assert_exit_code 0 "$result" "Detects macOS /Users path"

test_section "detect_absolute_paths - Should NOT Detect Placeholders"

detect_absolute_paths 'Example: <drive>:\Users\<username>\' && result=0 || result=1
assert_exit_code 1 "$result" "Does NOT flag angle bracket placeholders"

detect_absolute_paths 'Use C:\Users\[username]\path' && result=0 || result=1
assert_exit_code 1 "$result" "Does NOT flag square bracket placeholders"

detect_absolute_paths 'Path is ${HOME}/projects' && result=0 || result=1
assert_exit_code 1 "$result" "Does NOT flag shell variable placeholders"

test_section "detect_absolute_paths - Mixed Content"

detect_absolute_paths 'Template <drive>:\path but also C:\real\path' && result=0 || result=1
assert_exit_code 0 "$result" "Detects real path even with placeholder present"

detect_absolute_paths 'Only placeholders: <home>/<user>/.config and <drive>:\Users\<name>' && result=0 || result=1
assert_exit_code 1 "$result" "All placeholders = no detection"

# ============================================
# has_extension Tests
# ============================================
test_section "has_extension Tests"

has_extension "file.md" ".md .txt .rst" && result=0 || result=1
assert_exit_code 0 "$result" ".md extension matches"

has_extension "file.txt" ".md .txt .rst" && result=0 || result=1
assert_exit_code 0 "$result" ".txt extension matches"

has_extension "file.py" ".md .txt .rst" && result=0 || result=1
assert_exit_code 1 "$result" ".py extension does NOT match"

has_extension "README" ".md .txt" && result=0 || result=1
assert_exit_code 1 "$result" "No extension does NOT match"

# ============================================
# is_temp_path Tests
# ============================================
test_section "is_temp_path Tests"

is_temp_path ".claude/temp/file.md" && result=0 || result=1
assert_exit_code 0 "$result" ".claude/temp path recognized"

is_temp_path "node_modules/package/file.js" && result=0 || result=1
assert_exit_code 0 "$result" "node_modules path recognized"

is_temp_path ".git/objects/abc123" && result=0 || result=1
assert_exit_code 0 "$result" ".git path recognized"

is_temp_path "src/components/Button.tsx" && result=0 || result=1
assert_exit_code 1 "$result" "Regular path NOT recognized as temp"

# Windows-style paths
is_temp_path '.claude\temp\file.md' && result=0 || result=1
assert_exit_code 0 "$result" "Windows-style .claude\temp path recognized"

test_suite_end
