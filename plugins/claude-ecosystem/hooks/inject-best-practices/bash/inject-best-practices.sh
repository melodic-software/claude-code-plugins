#!/usr/bin/env bash
# inject-best-practices.sh - Inject best practices reminder at session start
#
# Event: SessionStart
# Purpose: Remind Claude about core best practices from CLAUDE.md and memory files
#
# This hook injects context at session start to reinforce behavioral rules,
# ensuring consistent adherence to skill encapsulation, progressive disclosure,
# and other critical patterns.
#
# Configuration: Set CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED=0 to disable

set -euo pipefail

# Read and discard stdin (required but not used for context injection)
cat > /dev/null

# Check if hook is disabled (default: enabled)
if [[ "${CLAUDE_HOOK_INJECT_BEST_PRACTICES_ENABLED:-1}" == "0" ]]; then
    echo '{"hookSpecificOutput":{"hookEventName":"SessionStart"}}'
    exit 0
fi

# Build context injection message
read -r -d '' CONTEXT_MSG << 'EOF' || true
<best-practices-reminder>
CLAUDE CODE BEST PRACTICES (Session Reminder)

## Skills & Execution
- Skills-First: Check for matching skill before using raw tools
- Execute Skills: Skills are WORKFLOWS - execute instructions as provided, verify results through execution
- Skill Encapsulation: Reference skills by NAME only - keep internal paths within skills
- Proactive Delegation: For multi-item tasks, parallelize with subagents (3-5 agents = 90% speedup)
- Command/Skill Dual Awareness: When commands invoke skills, track BOTH levels - complete all steps

## Tool Constraints
- Read Before Edit: Read files first in the conversation before using Edit tool
- PowerShell Commands: Use absolute paths or separate commands for reliability
- Path Resolution: Resolve paths absolutely from repo root before operations
- File Paths: Use forward slashes even on Windows (e.g., src/utils/helper.ts)
- Natural Language: Use natural language describing intent for agentic instructions
- MCP Permissions: Use explicit tool names in permission rules - wildcards like mcp__* are not supported

## Context & Efficiency
- Progressive Disclosure: Load content on-demand as needed
- Exploration Before Solutions: Read and understand code before proposing changes
- Research Before Planning: Understand current state before implementing
- Context Persistence: Continue working through context refreshes - save progress and persist
- Prefer Script Automation: Scripts over manual file manipulation - saves tokens, faster

## Behavioral
- Positive Framing: Use "do X" instructions rather than "don't do Y" - positive guidance is clearer
- Zero Complacency: Surface ALL errors/warnings explicitly - transparency builds trust
- Implementation Integrity: Do things correctly - choose quality over shortcuts
- Security-First: Protect secrets, validate inputs, apply least privilege
- Test Preservation: Keep tests intact - if they seem wrong, discuss with user first
- Minimal Focused Edits: Small intentional changes that preserve existing structure
- Start Simple: Find the simplest solution first - add complexity only when demonstrably needed
- Ship Working Solutions: Good enough that works beats perfect that ships late - refine iteratively
- Complete Handoffs: Finish tasks fully including all cleanup and verification steps
- Communication Style: Concise, fact-based progress reports grounded in actual results
- Opus 4.5 Precision: Follow instructions precisely and literally - be explicit about intended actions

## Workflow
- Course Correction: Plan before coding, use /clear between tasks, interrupt early when off-track
- Extended Thinking: Prompt "think" for basic reasoning. Intensify with "think hard", "think harder", "think more", "ultrathink" for deeper analysis.
- Temporary Workspace: Use .claude/temp/ for scratch files (gitignored, UTC timestamps)
- Clean Up: Remove temporary files before task completion, verify with git status
- Verify Model Identity: Check system context for model info before reporting which model you are

## Memory & Documentation
- Anti-Duplication: Every piece of info in ONE place - link to canonical sources
- Claude Code Topics: Invoke docs-management skill AND spawn claude-code-guide subagent in parallel
- Base guidance on official docs - verify through documentation rather than assumptions

## Success Indicators
- Using skill when one exists for the task
- Referencing skills by name only (encapsulation preserved)
- Executing skill instructions rather than assuming results
- Loading content progressively as needed
- Linking to canonical sources rather than copying content
- Persisting through context refreshes to completion
- Completing all command/skill levels before reporting done

## Quick Verification
- [ ] Did I check for existing skill?
- [ ] Am I referencing skills by name only?
- [ ] Did I invoke docs-management for Claude Code topics?
- [ ] Did I complete the task fully (including outer command steps)?
</best-practices-reminder>
EOF

# JSON escape function
json_escape() {
    local str="$1"
    # Escape backslashes first
    str="${str//\\/\\\\}"
    # Escape double quotes
    str="${str//\"/\\\"}"
    # Escape newlines
    str="${str//$'\n'/\\n}"
    # Escape carriage returns
    str="${str//$'\r'/}"
    # Escape tabs
    str="${str//$'\t'/\\t}"
    echo "$str"
}

# Escape the context message
ESCAPED_MSG=$(json_escape "$CONTEXT_MSG")

# Output JSON with additionalContext
cat << EOF
{
  "systemMessage": "inject-best-practices: reminder loaded",
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "$ESCAPED_MSG"
  }
}
EOF

exit 0
