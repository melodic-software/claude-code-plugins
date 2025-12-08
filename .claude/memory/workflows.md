# Claude Code Workflow Patterns

**Token Budget:** ~4,400 tokens | **Load Type:** Context-dependent (load when planning workflows)

General workflow patterns for using Claude Code effectively, extracted from Anthropic's best practices.

**Source:** Use docs-management skill to find "claude-code-best-practices" documentation

## Course Correction Tools

Course correct early and often - active collaboration produces better results than first-attempt-only execution:

**Four key tools:**

1. **Press Escape to interrupt** Claude during any phase (thinking, tool calls, file edits), preserving context so you can redirect or expand instructions
2. **Double-tap Escape to jump back in history**, edit a previous prompt, and explore a different direction - edit and repeat until you get desired results
3. **Use `/clear` frequently between tasks** to reset the context window when it fills with irrelevant conversation, file contents, or commands
4. **Ask Claude to undo changes** and take a different approach, often in conjunction with interruption

**Additional strategies:**

- Ask Claude to make a plan before coding - explicitly tell it not to code until you've confirmed the plan looks good
- Use separate working scratchpads (Markdown files) for complex workflows - Claude can use them as checklists and working notes

## Planning Mode with Inspection Checkpoints

For "large" features (multi-file changes, architectural decisions), planning with explicit checkpoints is essential.

**Why Planning Mode Matters:**

- Align on approach before implementation begins
- Define inspection checkpoints where Claude must stop and show work
- Reduce wasted work from misalignment
- Enable course correction at natural boundaries

**Inspection Checkpoint Pattern:**

When creating a plan, define explicit checkpoints where Claude should pause for approval:

| Checkpoint     | When to Use                              | What to Review                    |
| -------------- | ---------------------------------------- | --------------------------------- |
| Design         | Before any coding                        | Overall approach, architecture    |
| Interface      | After API/contract design                | Types, signatures, boundaries     |
| Implementation | After core logic complete                | Algorithm, data flow, edge cases  |
| Integration    | After components connected               | End-to-end behavior, interactions |
| Final          | Before PR/merge                          | Polish, docs, tests               |

**Checkpoint Trigger Phrases:**

- "Stop and show me X before continuing"
- "Get my approval before Y"
- "Present options for Z and wait for my choice"
- "Create a checkpoint after completing the data model"

**When to Use Planning Mode:**

- Multi-file changes
- Architectural decisions
- New feature development
- Complex refactors
- Unfamiliar codebases

**When to Skip Planning:**

- Simple bug fixes with obvious solutions
- Single-file changes
- Routine updates (dependencies, configs)
- Tasks you've done many times before

## Explore, Plan, Code, Commit Workflow

Versatile workflow suited for many problems:

1. **Ask Claude to read relevant files, images, or URLs** - provide general pointers ("read the file that handles logging") or specific filenames ("read logging.py"), but explicitly tell it not to write any code yet
   - Consider strong use of subagents, especially for complex problems - subagents verify details or investigate questions early, preserving context availability
2. **Ask Claude to make a plan** - use "think" keywords for extended thinking: "think" < "think hard" < "think harder" < "ultrathink" (each level allocates progressively more thinking budget)
   - If results seem reasonable, have Claude create a document or GitHub issue with its plan as a reset point if implementation isn't what you want
3. **Ask Claude to implement its solution** - also ask it to explicitly verify reasonableness of solution as it implements pieces
4. **Ask Claude to commit and create pull request** - update READMEs or changelogs with explanation of what was done

**Key insight:** Steps #1-#2 are crucial - without them, Claude tends to jump straight to coding. Asking Claude to research and plan first significantly improves performance for problems requiring deeper thinking.

## Test-Driven Development (TDD) Workflow

Anthropic-favorite workflow for changes easily verifiable with unit, integration, or end-to-end tests:

1. **Ask Claude to write tests** based on expected input/output pairs - be explicit you're doing TDD so it avoids creating mock implementations for non-existent functionality
2. **Tell Claude to run the tests and confirm they fail** - explicitly tell it not to write implementation code at this stage
3. **Ask Claude to commit the tests** when satisfied with them
4. **Ask Claude to write code that passes the tests** - instruct it not to modify tests, keep going until all tests pass (usually takes a few iterations)
   - At this stage, ask it to verify with independent subagents that implementation isn't overfitting to tests
5. **Ask Claude to commit the code** once satisfied with changes

**Principle:** Claude performs best with clear targets to iterate against - tests provide expected outputs that enable incremental improvement until success.

## Visual Iteration Workflow

Similar to TDD workflow, but using visual targets:

1. **Give Claude a way to take browser screenshots** (e.g., Puppeteer MCP server, iOS simulator MCP server, or manually copy/paste screenshots)
2. **Give Claude a visual mock** - copy/paste or drag-drop image, or provide image file path
3. **Ask Claude to implement the design** - take screenshots of result, iterate until result matches mock
4. **Ask Claude to commit** when satisfied

**Principle:** Like humans, Claude's outputs improve significantly with iteration - first version might be good, but after 2-3 iterations typically looks much better. Give Claude tools to see its outputs for best results.

## Extended Thinking Keywords

For extended thinking configuration including budget tokens and detection phrases, see `.claude/memory/prompting-style-guide.md#extended-thinking-in-claude-code`. Quick reference: "think" < "think hard" < "think harder" < "ultrathink".

## Multi-Claude Workflows

Run multiple Claude instances in parallel for more powerful applications:

**One Claude writes, another verifies:**

1. Use Claude to write code
2. Run `/clear` or start second Claude in another terminal
3. Have second Claude review first Claude's work
4. Start another Claude (or `/clear` again) to read both code and review feedback
5. Have this Claude edit code based on feedback

**With tests:** Have one Claude write tests, another write code to make tests pass. Claude instances can communicate via separate working scratchpads (tell them which to write to and read from).

**Multiple git checkouts:**

1. Create 3-4 git checkouts in separate folders
2. Open each folder in separate terminal tabs
3. Start Claude in each folder with different tasks
4. Cycle through to check progress and approve/deny permission requests

**Git worktrees (lighter-weight alternative):**

1. Create worktrees: `git worktree add ../project-feature-a feature-a`
2. Launch Claude in each worktree: `cd ../project-feature-a && claude`
3. Create additional worktrees as needed (repeat in new terminal tabs)

**Tips for git worktrees:**

- Use consistent naming conventions
- Maintain one terminal tab per worktree
- Use separate IDE windows for different worktrees
- Clean up when finished: `git worktree remove ../project-feature-a`

**Benefit:** Separation often yields better results than single Claude handling everything. Each Claude can work independently without waiting for others or dealing with merge conflicts.

## Headless Mode Automation

Use `claude -p` (headless mode) for non-interactive contexts like CI, pre-commit hooks, build scripts, and automation.

**Basic usage:**

- `claude -p "<your prompt>"` - Run prompt in headless mode
- `claude -p "<your prompt>" --output-format stream-json` - Stream JSON output for pipeline processing
- Use `--verbose` flag for debugging (turn off in production for cleaner output)

**Note:** Headless mode does not persist between sessions - you must trigger it each session.

**Two primary patterns:**

**1. Fanning out** (handles large migrations or analyses):

1. Have Claude write a script to generate a task list (e.g., list of 2k files needing migration)
2. Loop through tasks, calling Claude programmatically: `claude -p "migrate foo.py from React to Vue. When done, you MUST return the string OK if succeeded, or FAIL if failed." --allowedTools Edit Bash(git commit:*)`
3. Run script several times and refine prompt to get desired outcome

**2. Pipelining** (integrates Claude into existing pipelines):

- `claude -p "<your prompt>" --json | your_command` - Pipe JSON output to next pipeline step
- JSON output provides structure for easier automated processing

**Use cases:**

- Issue triage automation (GitHub Actions triggered by new issues)
- Code review automation (subjective code reviews beyond traditional linting)
- Batch processing (analyzing sentiment in hundreds of logs, processing thousands of CSVs)
- CI/CD integration (pre-commit hooks, build scripts)

## Codebase Q&A Workflow

When onboarding to a new codebase, use Claude Code for learning and exploration:

**Simply ask questions** - Claude will agentically search the codebase to answer:

- "How does logging work?"
- "How do I make a new API endpoint?"
- "What does `async move { ... }` do on line 134 of `foo.rs`?"
- "What edge cases does `CustomerOnboardingFlowImpl` handle?"
- "Why are we calling `foo()` instead of `bar()` on line 333?"
- "What's the equivalent of line 334 of `baz.py` in Java?"

**No special prompting required** - ask questions like you would ask another engineer when pair programming. Claude explores the code to find answers automatically.

**Benefit:** This workflow significantly improves ramp-up time and reduces load on other engineers.

---

**Last Updated:** 2025-12-06
