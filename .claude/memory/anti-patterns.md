# Anti-Patterns to Avoid

This document captures common anti-patterns to avoid when working with Claude Code, AI agents, and documentation systems.

## Do NOT

### 1. Use absolute paths in documentation or examples

- ❌ Bad: `D:\repos\gh\melodic\project\.gitignore` in documentation
- ❌ Bad: `/home/user/projects/project/docs/` in examples
- ❌ Bad: `/Users/jane/repos/project/CLAUDE.md` in skill references
- ✅ Good: `<project-root>/.gitignore` or `.gitignore` (relative path)
- ✅ Good: `docs/guide.md` (relative from root)
- ℹ️ Exception: Platform-specific teaching examples using generic placeholders (`C:\Users\[YourUsername]\`, `/home/[username]/`)
- See `.claude/memory/path-conventions.md` for comprehensive path convention guidance

### 2. Overload CLAUDE.md with @-file imports

- ❌ Bad: Import 20+ files using `@.claude/memory/*.md` totaling 50K+ tokens
- ❌ Bad: Import every memory file "just in case it's needed"
- ❌ Bad: Mention file paths without `@` prefix (Claude often ignores them)
- ✅ Good: Reserve `@` imports for truly essential, always-needed files (~10-15K tokens max)
- ✅ Good: Use "pitch" pattern for conditional files - explain WHEN and WHY to load them
- ✅ Good: Track token budgets explicitly in CLAUDE.md comments
- ℹ️ See `.claude/memory/context-engineering.md#the--file-loading-trade-off` for the pitch pattern

### 3. Over-engineer slash commands with procedural logic

- ❌ Bad: Slash command with 15 numbered steps, if-else branches, and tool sequences
- ❌ Bad: Duplicating skill logic in command markdown
- ❌ Bad: Hardcoding tool invocations that become brittle when interfaces change
- ✅ Good: Natural language describing intent and desired outcome
- ✅ Good: Delegate complex logic to skills or scripts with stable interfaces
- ✅ Good: Let the agent determine best execution approach
- ℹ️ See `.claude/memory/natural-language-guidance.md` for guidance on agentic prompting

### 4. Block agent operations at wrong timing

- ❌ Bad: PreToolUse blocking on Write/Edit for style/formatting issues
- ❌ Bad: Interrupting multi-step plans with non-critical validation
- ❌ Bad: Using /compact when you need control over preserved context
- ✅ Good: Block at natural boundaries (commit time, not write time)
- ✅ Good: Use PostToolUse with auto-fix for style issues
- ✅ Good: Use /clear + targeted reload instead of /compact
- ℹ️ Principle: "Blocking agent mid-plan disrupts coherent execution"
- ℹ️ See `.claude/memory/hook-timing-philosophy.md` for decision tree

### 5. Create specialized subagents that gatekeep context

- ❌ Bad: "PythonTests" subagent that hides all testing context from main agent
- ❌ Bad: Custom subagents that force rigid, human-defined workflows
- ❌ Bad: Encoding exact delegation patterns that prevent dynamic adaptation
- ✅ Good: Put key context in CLAUDE.md (accessible to all agents)
- ✅ Good: Use Task() to spawn clones with full CLAUDE.md context
- ✅ Good: Let main agent decide when/how to delegate dynamically
- ✅ Exception: Specialized subagents for truly isolated domains (security scanning, different permissions)
- ℹ️ See `.claude/memory/agent-usage-patterns.md#context-gatekeeping-vs-full-context-clones`

## Design Decisions & Rationale

### Why Prefer Task() Clones Over Custom Subagents?

**Full Context Access**: Task() clones inherit the complete CLAUDE.md context, enabling holistic reasoning across the codebase. Custom subagents can gatekeep context, hiding important information from the main agent.

**Dynamic Delegation**: The main agent can decide when and how to delegate based on the actual task at hand. Custom subagents encode rigid workflows that prevent adaptation.

**Lower Maintenance**: CLAUDE.md serves as single source of truth. Custom subagents require separate maintenance and can drift from main context.

**When Custom Subagents ARE Appropriate**:

- Truly specialized domains (security scanning, specific toolchains)
- Well-defined narrow scope with clear boundaries
- Context isolation is a FEATURE (prevent cross-contamination)
- Different tool access needed (different permissions)

### Why Block at Natural Boundaries?

**Coherent Execution**: Blocking agent mid-plan disrupts the agent's ability to complete coherent work units. The agent may retry the same operation repeatedly or become confused about what was completed.

**Natural Retry Points**: Commit time is a natural boundary - if validation fails, the agent understands "commit failed, fix and retry." This is clearer than mid-write interruptions.

**Auto-Fix Opportunity**: PostToolUse hooks can auto-fix issues (like formatting) without the agent ever seeing an "error." This is more efficient than blocking and requiring explicit fixes.

### Why Natural Language Over Procedural Logic?

**Maintainability**: Tool interfaces and APIs evolve. Natural language instructions remain valid even as implementation details change.

**Adaptability**: Agents can interpret natural language and adapt their approach based on available tools and context. Rigid procedural steps cannot adapt.

**Clarity**: Natural language focuses on "what" and "why" rather than "how," making instructions clearer and more understandable.

---

**Last Updated:** 2025-11-30
