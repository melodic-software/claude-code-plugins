#!/usr/bin/env bash
# integration.test.sh - Integration tests for suggest-official-docs-delegation hook
#
# Tests the UserPromptSubmit hook that detects Claude Code ecosystem topics
# and injects context reminders to use official-docs skill.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${SCRIPT_DIR}/test-helpers.sh"

# Helper function to run hook and capture output
run_hook() {
    local prompt="$1"
    local payload="{\"prompt\": \"$prompt\"}"
    echo "$payload" | bash "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" 2>/dev/null
}

# Helper function to check if output contains additionalContext
has_context_injection() {
    local output="$1"
    [[ "$output" == *"additionalContext"* ]]
}

# Helper function to check if output contains specific topic
has_topic() {
    local output="$1"
    local topic="$2"
    [[ "$output" == *"$topic"* ]]
}

# Helper function to check if output mentions specific meta-skill
has_meta_skill() {
    local output="$1"
    local meta_skill="$2"
    [[ "$output" == *"$meta_skill"* ]]
}

test_suite_start "suggest-official-docs-delegation Integration Tests"

# ============================================================================
# SECTION 1: Hook Setup
# ============================================================================
test_section "Hook Setup"

assert_file_exists "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" "Hook script exists"
assert_file_exists "${PLUGIN_ROOT}/hooks/hooks.json" "Hook hooks.json exists"
assert_file_exists "${PLUGIN_ROOT}/hooks/shared/json-utils.sh" "Shared json-utils.sh exists"
assert_file_exists "${PLUGIN_ROOT}/hooks/shared/config-utils.sh" "Shared config-utils.sh exists"

# ============================================================================
# SECTION 2: Pattern Detection - Hooks Topics
# ============================================================================
test_section "Pattern Detection: Hooks Topics"

OUTPUT=$(run_hook "How do I create a PreToolUse hook?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "hooks"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects PreToolUse hook pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect PreToolUse hook pattern"
    echo "  Output: $OUTPUT"
fi

OUTPUT=$(run_hook "What is a hook event?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "hooks"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'hook event' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'hook event' pattern"
fi

OUTPUT=$(run_hook "How do I configure a PostToolUse hook?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "hooks-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests hooks-meta for PostToolUse"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest hooks-meta for PostToolUse"
fi

# ============================================================================
# SECTION 3: Pattern Detection - Memory/CLAUDE.md Topics
# ============================================================================
test_section "Pattern Detection: Memory/CLAUDE.md Topics"

OUTPUT=$(run_hook "How do I edit CLAUDE.md for my project?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "memory"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects CLAUDE.md pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect CLAUDE.md pattern"
fi

OUTPUT=$(run_hook "What is static memory in Claude Code?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "memory-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests memory-meta for static memory"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest memory-meta for static memory"
fi

OUTPUT=$(run_hook "How does the memory hierarchy work?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "memory"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'memory hierarchy' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'memory hierarchy' pattern"
fi

# ============================================================================
# SECTION 4: Pattern Detection - Skills Topics
# ============================================================================
test_section "Pattern Detection: Skills Topics"

OUTPUT=$(run_hook "How do I create an agent skill?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "skills"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'agent skill' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'agent skill' pattern"
fi

OUTPUT=$(run_hook "What goes in the YAML frontmatter for skills?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "skills-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests skills-meta for YAML frontmatter"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest skills-meta for YAML frontmatter"
fi

OUTPUT=$(run_hook "How do allowed-tools restrictions work?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "skills"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'allowed-tools' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'allowed-tools' pattern"
fi

# ============================================================================
# SECTION 5: Pattern Detection - Subagents Topics
# ============================================================================
test_section "Pattern Detection: Subagents Topics"

OUTPUT=$(run_hook "How do I create a custom subagent?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "subagents"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'subagent' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'subagent' pattern"
fi

OUTPUT=$(run_hook "What is the Explore agent for?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "subagents-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests subagents-meta for Explore agent"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest subagents-meta for Explore agent"
fi

OUTPUT=$(run_hook "How does the Task tool spawn an agent?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "subagents"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'Task tool' + 'agent' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'Task tool' + 'agent' pattern"
fi

# ============================================================================
# SECTION 6: Pattern Detection - MCP Topics
# ============================================================================
test_section "Pattern Detection: MCP Topics"

OUTPUT=$(run_hook "How do I add an MCP server?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "mcp"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'MCP server' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'MCP server' pattern"
fi

OUTPUT=$(run_hook "What is the Model Context Protocol?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "mcp-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests mcp-meta for Model Context Protocol"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest mcp-meta for Model Context Protocol"
fi

# ============================================================================
# SECTION 7: Pattern Detection - Plugins Topics
# ============================================================================
test_section "Pattern Detection: Plugins Topics"

OUTPUT=$(run_hook "How do I create a Claude Code plugin?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "plugins"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'Claude Code plugin' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'Claude Code plugin' pattern"
fi

OUTPUT=$(run_hook "What goes in plugin.json?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "plugins-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests plugins-meta for plugin.json"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest plugins-meta for plugin.json"
fi

# ============================================================================
# SECTION 8: Pattern Detection - Configuration Topics
# ============================================================================
test_section "Pattern Detection: Configuration Topics"

OUTPUT=$(run_hook "How do I configure settings.json?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "configuration"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'settings.json' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'settings.json' pattern"
fi

OUTPUT=$(run_hook "What is a permission setting?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "configuration-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests configuration-meta for permission setting"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest configuration-meta for permission setting"
fi

# ============================================================================
# SECTION 9: Pattern Detection - Security Topics
# ============================================================================
test_section "Pattern Detection: Security Topics"

OUTPUT=$(run_hook "How does Claude Code security work?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "security"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'Claude Code security' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'Claude Code security' pattern"
fi

OUTPUT=$(run_hook "What is sandboxing in Claude Code?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "security-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests security-meta for sandboxing"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest security-meta for sandboxing"
fi

# ============================================================================
# SECTION 10: Pattern Detection - Agent SDK Topics
# ============================================================================
test_section "Pattern Detection: Agent SDK Topics"

OUTPUT=$(run_hook "How do I use the Agent SDK?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "agent-sdk"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'Agent SDK' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'Agent SDK' pattern"
fi

OUTPUT=$(run_hook "Can you show me the TypeScript SDK setup?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "agent-sdk-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests agent-sdk-meta for TypeScript SDK"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest agent-sdk-meta for TypeScript SDK"
fi

# ============================================================================
# SECTION 11: Pattern Detection - Output Styles Topics
# ============================================================================
test_section "Pattern Detection: Output Styles Topics"

OUTPUT=$(run_hook "How do I change the output style?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "output-styles"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'output style' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'output style' pattern"
fi

OUTPUT=$(run_hook "What is the explanatory style?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "output-styles-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests output-styles-meta for explanatory style"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest output-styles-meta for explanatory style"
fi

# ============================================================================
# SECTION 12: Pattern Detection - Slash Commands Topics
# ============================================================================
test_section "Pattern Detection: Slash Commands Topics"

OUTPUT=$(run_hook "How do I create a slash command?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "slash-commands"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'slash command' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'slash command' pattern"
fi

OUTPUT=$(run_hook "What is a custom command in Claude Code?")
if has_context_injection "$OUTPUT" && has_meta_skill "$OUTPUT" "slash-commands-meta"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Suggests slash-commands-meta for custom command"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should suggest slash-commands-meta for custom command"
fi

# ============================================================================
# SECTION 13: Pattern Detection - How-To Questions
# ============================================================================
test_section "Pattern Detection: How-To Questions"

OUTPUT=$(run_hook "How can I configure Claude Code hooks?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "how-to-question"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'how can I' + 'Claude Code' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'how can I' + 'Claude Code' pattern"
fi

OUTPUT=$(run_hook "How do I set up skills in my project?")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "how-to-question"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'how do I' + 'skills' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'how do I' + 'skills' pattern"
fi

OUTPUT=$(run_hook "Help me create a Claude Code plugin")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "how-to-question"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects 'help...create' + 'plugin' pattern"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect 'help...create' + 'plugin' pattern"
fi

# ============================================================================
# SECTION 14: No Pattern Detection (Should Not Trigger)
# ============================================================================
test_section "No Pattern Detection: Unrelated Tasks"

OUTPUT=$(run_hook "Fix the typo in README")
if [[ -z "$OUTPUT" ]] || ! has_context_injection "$OUTPUT"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: No context injection for simple fix"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should NOT inject context for simple fix"
fi

OUTPUT=$(run_hook "Write a Python function to sort a list")
if [[ -z "$OUTPUT" ]] || ! has_context_injection "$OUTPUT"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: No context injection for generic coding task"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should NOT inject context for generic coding task"
fi

OUTPUT=$(run_hook "Hello, how are you?")
if [[ -z "$OUTPUT" ]] || ! has_context_injection "$OUTPUT"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: No context injection for greeting"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should NOT inject context for greeting"
fi

OUTPUT=$(run_hook "What is the weather like today?")
if [[ -z "$OUTPUT" ]] || ! has_context_injection "$OUTPUT"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: No context injection for unrelated question"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should NOT inject context for unrelated question"
fi

# ============================================================================
# SECTION 15: Exit Code Verification (Always 0)
# ============================================================================
test_section "Exit Code Verification"

# Hook should NEVER block - always exit 0
echo '{"prompt": "How do I create a hook?"}' | bash "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook always exits 0 (pattern detected)"

echo '{"prompt": "Fix typo"}' | bash "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook always exits 0 (no pattern)"

echo '{"prompt": ""}' | bash "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook always exits 0 (empty prompt)"

echo '{}' | bash "${PLUGIN_ROOT}/scripts/hooks/suggest-official-docs-delegation.sh" &>/dev/null
EXIT_CODE=$?
assert_exit_code 0 $EXIT_CODE "Hook always exits 0 (missing prompt field)"

# ============================================================================
# SECTION 16: JSON Output Validation
# ============================================================================
test_section "JSON Output Validation"

# Verify valid JSON output when pattern detected
OUTPUT=$(run_hook "How do I create a PreToolUse hook?")
if command -v jq &>/dev/null; then
    if echo "$OUTPUT" | jq empty 2>/dev/null; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: Output is valid JSON"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: Output is not valid JSON"
        echo "  Output: $OUTPUT"
    fi

    # Verify hookSpecificOutput structure
    HOOK_OUTPUT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.hookEventName // empty' 2>/dev/null)
    assert_equals "UserPromptSubmit" "$HOOK_OUTPUT" "hookSpecificOutput.hookEventName is UserPromptSubmit"

    # Verify additionalContext exists
    CONTEXT=$(echo "$OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
    if [[ -n "$CONTEXT" ]]; then
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_PASSED=$((TESTS_PASSED + 1))
        echo -e "${GREEN}✓${NC} PASS: additionalContext field exists"
    else
        TESTS_RUN=$((TESTS_RUN + 1))
        TESTS_FAILED=$((TESTS_FAILED + 1))
        echo -e "${RED}✗${NC} FAIL: additionalContext field missing"
    fi
else
    skip_test "jq not installed - skipping JSON validation tests"
fi

# ============================================================================
# SECTION 17: Context Injection Content
# ============================================================================
test_section "Context Injection Content"

OUTPUT=$(run_hook "How do I create a hook?")
assert_contains "$OUTPUT" "CLAUDE CODE DOCUMENTATION REQUIREMENT DETECTED" "Contains header message"
assert_contains "$OUTPUT" "official-docs skill" "References official-docs skill"
assert_contains "$OUTPUT" "system-reminder" "Wrapped in system-reminder tags"
assert_contains "$OUTPUT" "MANDATORY ACTION" "Contains mandatory action instruction"
assert_contains "$OUTPUT" "Claude Code documentation" "References Claude Code documentation"

# ============================================================================
# SECTION 18: Multiple Topic Detection
# ============================================================================
test_section "Multiple Topic Detection"

# Should detect multiple topics in one prompt
OUTPUT=$(run_hook "How do I create a hook that uses the Agent SDK?")
TOPIC_COUNT=0
[[ "$OUTPUT" == *"hooks"* ]] && TOPIC_COUNT=$((TOPIC_COUNT + 1))
[[ "$OUTPUT" == *"agent-sdk"* ]] && TOPIC_COUNT=$((TOPIC_COUNT + 1))
[[ "$OUTPUT" == *"how-to-question"* ]] && TOPIC_COUNT=$((TOPIC_COUNT + 1))

if [[ $TOPIC_COUNT -ge 2 ]]; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects multiple topics in one prompt ($TOPIC_COUNT topics)"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect multiple topics (found $TOPIC_COUNT)"
fi

# ============================================================================
# SECTION 19: Direct Meta-Skill Mentions
# ============================================================================
test_section "Direct Meta-Skill Mentions"

OUTPUT=$(run_hook "Use the hooks-meta skill")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "meta-skill-direct"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSED=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects direct hooks-meta mention"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect direct hooks-meta mention"
fi

OUTPUT=$(run_hook "Invoke the memory-meta skill")
if has_context_injection "$OUTPUT" && has_topic "$OUTPUT" "meta-skill-direct"; then
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_PASSES=$((TESTS_PASSED + 1))
    echo -e "${GREEN}✓${NC} PASS: Detects direct memory-meta mention"
else
    TESTS_RUN=$((TESTS_RUN + 1))
    TESTS_FAILED=$((TESTS_FAILED + 1))
    echo -e "${RED}✗${NC} FAIL: Should detect direct memory-meta mention"
fi

test_suite_end
