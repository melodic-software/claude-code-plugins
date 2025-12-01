# Command and Skill Execution Protocol

## Critical Pattern: Maintaining Dual-Level Awareness

When executing slash commands that invoke skills or agents, you must maintain awareness of TWO levels:

1. **Command Level** (orchestrator): The slash command's steps and requirements
2. **Skill/Agent Level** (worker): The skill's instructions and checklist

## The Danger: Context Collapse

**Context collapse** occurs when you:

1. Start executing a command
2. Invoke a skill or agent as part of the command
3. Skill/agent loads and becomes your entire focus
4. Complete skill/agent work and think "done!"
5. **Forget to return to command level to verify all command steps**

This is a critical failure pattern that leads to skipped steps, incomplete execution, and broken workflows.

## Another Danger: Assuming Instead of Executing

**Skill instruction failure** occurs when you:

1. Load a skill successfully
2. Skill provides clear instructions (e.g., "Run this command")
3. Instead of executing the instruction, you state a result from assumptions or memory
4. This defeats the entire purpose of the skill

**Example Failure (current-date skill):**

❌ **WRONG:**

```text
1. Invoke current-date skill ✓
2. Skill loads, instructs: "Run `date -u +...`" ✓
3. Think: "I know the date, it's 2025-01-17" ✗ Did not execute
4. State incorrect date without verification ✗ Critical failure
```

✅ **CORRECT:**

```text
1. Invoke current-date skill ✓
2. Skill loads, instructs: "Run `date -u +...`" ✓
3. Execute the exact command skill instructed ✓
4. Report actual output from execution ✓
```

**Why This Happens:**

- Model training cutoffs create stale date assumptions
- Memory and context can contain outdated information
- Confidence in "knowing" the answer leads to skipping verification
- Speed optimization instinct ("I can skip this simple step") backfires

**Prevention Rules:**

- Skills exist because assumptions are unreliable
- If a skill says "run this command," run it - do not paraphrase or assume results
- Complete execution steps rather than skipping them to "save time" or "be efficient"
- Verification through execution is essential
- When you think "I already know the answer," that's exactly when verification matters most

**Red Flags:**

🚩 Skill loads with command examples → Execute them rather than paraphrasing
🚩 Skill says "verify by running..." → Run the verification
🚩 You think "I already know the answer" → This is exactly when verification matters most
🚩 Stating results without tool output → Missing execution step
🚩 Skill provides bash/PowerShell commands → Execute them rather than just referencing

**Applies To All Skills:**

This failure mode can affect ANY skill that provides commands or instructions:

- current-date skill (verify date/time)
- git-* skills (execute git commands)
- markdown-linting skill (run linting commands)
- Any skill providing verification commands

**The pattern is universal:** Load skill → Read instructions → **EXECUTE** instructions → Report results

## Third Danger: Deviating from Skill Execution Patterns

**Execution pattern deviation** occurs when you:

1. Load a skill successfully ✓
2. Skill provides clear execution pattern (e.g., "run in foreground, don't poll") ✓
3. Execute using a different pattern (background + polling) ✗
4. This defeats the skill's designed workflow ✗

**Example Failure (docs-management skill):**

❌ **WRONG:**

```text
1. Invoke docs-management skill ✓
2. Skill instructs: "Run in foreground, rely on streaming logs" ✓
3. Execute: Bash(script, run_in_background=true) ✗ Incorrect
4. Poll output repeatedly with BashOutput ✗ Incorrect
5. Recognize mistake but continue anyway ✗ Critical failure
```

✅ **CORRECT:**

```text
1. Invoke docs-management skill ✓
2. Skill instructs: "Run in foreground, rely on streaming logs" ✓
3. Verify planned execution matches pattern ✓
4. Execute: Bash(script) [foreground, no polling] ✓
5. Rely on streaming logs and exit code ✓
```

**Why This Happens:**

- "Efficiency optimization" instinct overrides explicit instructions
- Pattern matching from other contexts (background+polling works elsewhere)
- Incomplete reading of skill workflow section
- Assumption that "my way is better" than skill's designed pattern

**Prevention Rules:**

- Skills design execution patterns intentionally - follow them exactly
- If skill says foreground, use foreground (not background)
- If skill says don't poll, avoid polling loops
- If skill specifies a pattern, that is the correct pattern
- Your "optimization" is actually a deviation that breaks things

**Immediate Correction Protocol:**

If you realize you deviated from skill execution pattern:

1. Stop immediately - cancel the incorrect execution
2. Kill/cleanup the wrong approach (kill background jobs, cancel operations)
3. Report the deviation explicitly to the user
4. Execute correctly according to skill instructions
5. Verify the corrected execution matches skill pattern

Avoid continuing with incorrect execution hoping "it will work out."

**Red Flags:**

🚩 Skill says "foreground" but you use `run_in_background=true`
🚩 Skill says "don't poll" but you use `BashOutput` loops
🚩 Skill says "run once" but you run repeatedly
🚩 Skill says "rely on X" but you implement Y instead
🚩 You think "I know a better way" → Follow the skill instead

**Applies To All Skills:**

This failure mode can affect ANY skill with execution patterns:

- docs-management skill (foreground execution, no polling)
- git-commit skill (exact command sequences)
- markdown-linting skill (specific tool invocation patterns)
- Any skill providing workflow instructions

**The pattern is universal:** Load skill → Read execution pattern → **MATCH** pattern exactly → Execute

## Reference vs Execution Context

**IMPORTANT**: Skills can be invoked in two contexts - understand which one applies:

### Reference Context (Learning/Planning)

User asks: "How do I set up Git?" or "What's the process for committing?"

- Skill loaded for INFORMATION/GUIDANCE
- You explain the process, show commands, provide context
- User will execute commands themselves later
- **No immediate execution required**

### Execution Context (Doing the Task)

User asks: "Set up Git for me" or "Create a commit" or "What's today's date?"

- Skill loaded to PERFORM THE TASK
- Execute the commands the skill provides
- User expects results, not just guidance
- Immediate execution is required

### How to Tell the Difference

**Execution context indicators:**

- User says "do X," "run Y," "execute Z"
- User asks for current state/status (date, version, config)
- User asks you to perform an action
- Verification-only skills (like current-date)
- Task is time-sensitive or blocking other work

**Reference context indicators:**

- User says "how do I...," "what's the process for...," "explain..."
- User is planning future work
- User wants to understand before acting
- User explicitly says "show me how" or "explain the steps"

### Special Case: Verification Skills

Some skills exist specifically for verification (current-date, version checks, status checks):

- These are always execution context
- Loading them without executing defeats their purpose
- If user invokes them, they want immediate verified results
- Provide verified answers, not assumed answers, for verification skills

### When in Doubt

If you're uncertain whether to execute or reference:

1. Check the user's exact phrasing
2. Consider the skill's purpose (verification vs guidance)
3. **Default to execution** - it's safer to execute when unsure
4. Ask the user for clarification if genuinely ambiguous

**The pattern is universal:** Load skill → Read instructions → **EXECUTE** instructions → Report results (when in execution context)

## Prevention Strategy: Step Verification Protocol

**Before reporting ANY command completion:**

1. ✅ **Re-read the command from top to bottom**
2. ✅ **Verify you executed EVERY numbered step**
3. ✅ **Pay special attention to steps labeled "CRITICAL"**
4. ✅ **Check for cleanup/sync/finalization steps at the end**
5. ✅ **Only report completion after all steps verified**

## Red Flags to Watch For

**🚩 "CRITICAL" in all caps** → This step is essential, complete it regardless of other factors

**🚩 Numbered steps (Step 1, Step 2, Step 3...)** → Complete all in order

**🚩 "After all X are complete..."** → This applies to single and multiple X

**🚩 Sync/validation/cleanup steps** → These often come last and are easy to skip

**🚩 Final steps that feel like "housekeeping"** → These are required, not optional

## Example Failure: Multi-Step Command Execution

**What I did (WRONG):**

```text
1. Parse args ✓
2. Invoke skill ✓
3. *Skill completes* → "Done!" ✗ Skipped steps 4 & 5
```

**What I should have done (CORRECT):**

```text
1. Parse args ✓
2. Read command's ALL steps ✓
3. Note: Command has Steps 1, 2, 3, 4, 5 ✓
4. Invoke skill for Step 3 ✓
5. Skill completes ✓
6. Return to command context ✓
7. Execute Step 4 (update state/logs) ✓
8. Execute Step 5 (sync/cleanup - CRITICAL) ✓
9. Verify all 5 steps complete ✓
10. Report completion ✓
```

## Mental Model Visualization

```text
╔══════════════════════════════════════╗
║  COMMAND LEVEL (never forget this!)  ║
║  ┌────────────────────────────────┐  ║
║  │ Step 1: Setup                  │  ║
║  ├────────────────────────────────┤  ║
║  │ Step 2: Execute Work           │  ║
║  │   ┌─────────────────────────┐  │  ║
║  │   │ SKILL/AGENT LEVEL       │  │  ║
║  │   │ - Do work               │  │  ║
║  │   │ - Return result         │  │  ║
║  │   └─────────────────────────┘  │  ║
║  ├────────────────────────────────┤  ║
║  │ Step 3: Cleanup (Essential)   │◄─── Complete this step!
║  ├────────────────────────────────┤  ║
║  │ Step 4: Report                 │  ║
║  └────────────────────────────────┘  ║
╚══════════════════════════════════════╝
     ↑
     Maintain awareness of this outer context
     even while inside skill/agent execution
```

## Failure Mode Recognition

**If you catch yourself thinking:**

- "The hard work is done, I can wrap up quickly" → ⚠️ DANGER
- "This last step is just housekeeping" → ⚠️ DANGER
- "I did the main task, I'm basically done" → ⚠️ DANGER
- "The skill/agent finished, so I'm finished" → ⚠️ DANGER

**Stop and verify ALL command steps are complete before reporting.**

## When Skills/Agents Do Everything (Preferred Pattern)

The best architecture is when skills/agents handle ALL operations (including cleanup/sync):

- The command becomes a thin wrapper
- Less risk of context collapse
- Single checklist to follow (the skill's/agent's)

**This is the preferred architecture when possible.**

When designing new commands:

- ✅ **Prefer**: Delegate everything to skill/agent
- ❌ **Avoid**: Split logic between command and skill/agent

## Checkpoint Questions Before Reporting "Done"

Ask yourself:

1. Did I re-read the command's ALL steps?
2. Did I verify EVERY step was executed?
3. Are there any "CRITICAL" steps I might have skipped?
4. Are there cleanup/sync/finalization steps at the end?
5. Would the user be satisfied with what I've done, or did I cut corners?

**If the answer to ANY question is uncertain, STOP and verify.**

## Application to Common Commands

This protocol applies to:

- ✅ Any command that spawns Task agents
- ✅ Any command that invokes Skills
- ✅ Any multi-step command with orchestration logic
- ✅ Any command with cleanup/sync/finalization steps
- ✅ Any command with "CRITICAL" steps
- ✅ Any command with cleanup/sync/finalization phases

## Summary

**Context collapse is predictable and preventable.**

The solution:

1. Maintain dual-level awareness (command + skill/agent)
2. Verify ALL steps before reporting completion
3. Watch for red flags (CRITICAL, numbered steps, cleanup phases)
4. Prefer architectures where skills/agents do everything

**Your reputation depends on thoroughness, not speed.**

**Last Updated:** 2025-11-30
