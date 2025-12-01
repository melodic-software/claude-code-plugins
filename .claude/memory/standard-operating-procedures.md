# Standard Operating Procedures

> All procedures derived from official Anthropic engineering documentation.
> Source: docs-management canonical storage (docs.claude.com, code.claude.com, anthropic.com/engineering)

**Keywords:** SOP, best practices, procedures, guidelines, agent execution, tool use, context engineering, error handling, performance optimization, evaluation, safety, skills architecture, prompt engineering, multi-agent, subagents, parallelization, recovery, checkpointing, transparency, verification

---

## 1. Context Engineering

**Source:** "Effective Context Engineering for AI Agents" (anthropic.com/engineering)

### Core Principles

- **Context is a finite resource** with diminishing marginal returns - every token depletes the model's "attention budget"
- **Find the smallest set of high-signal tokens** that maximizes likelihood of desired outcome
- Context management should **inform every architectural decision**
- Context engineering is the progression from prompt engineering - curating optimal tokens during inference

### System Prompt Design

- Find the right **"altitude"** - balance between brittle and vague
- **Anti-pattern:** Hardcoding complex if-else logic in prompts (too brittle)
- **Anti-pattern:** Overly vague guidance assuming shared context (too vague)
- **Optimal:** Specific enough to guide behavior, flexible enough to provide heuristics
- **Organize into distinct sections** using XML tags or Markdown headers (background, instructions, tool guidance, output)
- **Start with minimal prompt + best model**, then add instructions based on observed failures
- Strive for the **minimal set of information** that fully outlines expected behavior

### Just-in-Time Loading

- **Maintain lightweight identifiers** (file paths, stored queries, web links) instead of pre-loading everything
- **Load data dynamically at runtime** using tools
- This mirrors human cognition - retrieve on-demand rather than memorizing entire corpuses
- **Hybrid strategy is optimal:** retrieve some data upfront, pursue further autonomous exploration at agent's discretion
- Claude Code uses this pattern: CLAUDE.md loaded naively, glob/grep enable just-in-time retrieval

### Long-Horizon Context Management

- **Compaction:** Summarize conversation when nearing context limit, preserve architectural decisions and bugs, discard redundant outputs
- **Tool result clearing:** Safest, lightest-touch form of compaction - clear results once tool has been called deep in history
- **Structured note-taking:** Agent maintains notes in persistent memory outside context window (to-do lists, NOTES.md files)
- **Sub-agent architectures:** Specialized agents handle focused tasks with isolated context windows, return condensed summaries

### Trade-offs

- Compaction maintains conversational flow for back-and-forth tasks
- Note-taking excels for iterative development with clear milestones
- Multi-agent handles complex research with parallel exploration
- "Do the simplest thing that works" remains best advice

---

## 2. Tool Use and Design

**Source:** "Writing Tools for Agents", "Advanced Tool Use" (anthropic.com/engineering)

### Tool Selection Principles

- **Fewer, thoughtful tools** targeting specific high-impact workflows over exhaustive coverage
- **Don't merely wrap existing software functionality** or API endpoints
- Each tool needs a **clear, distinct purpose**
- Tools should enable agents to **subdivide and solve tasks like humans would**
- If multiple tools overlap in functionality, agents may get confused about which to use

### Tool Consolidation

- One tool **can handle multiple discrete operations** under the hood
- **Example:** `schedule_event` instead of separate `list_users`, `list_events`, `create_event`
- **Example:** `search_logs` returning relevant lines with context instead of `read_logs` dumping everything
- **Example:** `get_customer_context` compiling all relevant info instead of `get_customer_by_id`, `list_transactions`, `list_notes`
- **Benefit:** Reduces intermediate context consumption significantly

### Tool Namespacing

- **Group related tools under common prefixes** (e.g., `asana_search`, `jira_search`)
- Use namespace by service (`asana_search`) and by resource (`asana_projects_search`)
- Choose between **prefix- and suffix-based namespacing** based on your evaluations
- Clear boundaries help agents select the right tool at the right time
- Well-selected tool names **reduce the number of tools loaded into context**

### Returning Meaningful Context

- **Return only high-signal information** - prioritize contextual relevance over flexibility
- **Use natural language names** over cryptic identifiers (UUIDs, technical IDs)
- Resolving arbitrary IDs to semantically meaningful language **significantly improves precision**
- Implement **`response_format` parameter** (concise vs detailed) to control verbosity
- Concise responses use ~1/3 the tokens while still providing necessary information

### Token Efficiency

- Implement **pagination, filtering, truncation** with sensible defaults
- Truncate responses (Claude Code defaults to ~25K tokens)
- Provide **helpful truncation instructions** steering agents toward token-efficient strategies
- **Actionable error responses** guide agents on correct parameter usage
- Test different response structures (XML, JSON, Markdown) - effects vary by task

### Tool Documentation

- **Describe as you would to a new team member** - make implicit context explicit
- Parameter names should be **unambiguous** (`user_id` not just `user`)
- **Express conventions in descriptions**, not just structural validity in schemas
- Tool descriptions in context **steer agents toward effective behaviors**
- Bad tool descriptions can send agents down completely wrong paths

### Advanced Tool Features

- **Tool Search Tool:** For libraries >10K tokens, mark tools with `defer_loading: true` for on-demand discovery (85% token reduction)
- **Programmatic Tool Calling:** Claude writes orchestration code instead of individual requests (37% token savings, improved accuracy)
- **Tool Use Examples:** Provide `input_examples` showing minimal, partial, and full specification patterns (72% -> 90% accuracy improvement)

---

## 3. Agent Execution Loop

**Source:** "Building Agents with the Claude Agent SDK" (anthropic.com/engineering)

### Core Loop Pattern

- **Gather context -> Take action -> Verify work -> Repeat**
- This loop applies across all agent types (coding, research, support, finance)
- The loop offers a useful way to think about agent capabilities needed

### Context Gathering Approaches

- **Agentic search:** Use bash scripts like grep and tail to load data into context
- **File system structure** becomes a form of context engineering
- Semantic search is usually faster but less accurate and harder to maintain
- **Start with agentic search**, only add semantic search if you need faster results

### Subagents

- Enable **parallelization** - spin up multiple subagents on different tasks simultaneously
- Help **manage context** - subagents use isolated context windows, return only relevant information
- Ideal for tasks requiring **sifting through large amounts of information**

### Verification and Feedback

- **Code linting** provides rules-based feedback (multiple feedback layers)
- **Visual feedback** (screenshots) for UI generation and testing tasks
- **LLM-as-judge** for fuzzy rules evaluation
- TypeScript + linting provides stronger feedback than pure JavaScript

### Agent Design Principle

- **Give Claude a computer** - the same tools programmers use every day
- File operations, code execution, search, and debug capabilities enable general-purpose agents
- Code is precise, composable, infinitely reusable

---

## 4. Long-Running Agents

**Source:** "Effective Harnesses for Long-Running Agents" (anthropic.com/engineering)

### Environment Management

- Create **comprehensive feature requirements file** expanding on initial prompt
- Mark features as **"failing" initially** so agent has clear outline of full functionality
- Use **JSON format** to reduce inappropriate changes vs Markdown
- Use **strongly-worded instructions:** "It is unacceptable to remove or edit tests"

### Incremental Progress (Critical)

- **Work on one feature at a time** - addresses tendency to do too much at once
- **Leave environment in clean state** after changes
- **Commit progress to git** with descriptive messages
- **Write summaries in progress file**
- Git enables reverting bad changes and recovering working states

### Testing

- Claude **tends to mark features complete without proper testing**
- **Explicitly prompt** to use browser automation tools
- Test **as a human user would** (end-to-end)
- This dramatically improves performance and bug identification

### Session Initialization

- Run `pwd` to understand directory boundaries
- **Read git logs and progress files** to understand recent work
- Choose **highest-priority unfinished feature**
- Saves tokens by not requiring agent to figure out testing approach

### Failure Mode Solutions

| Problem | Solution |
| ------- | -------- |
| Declares victory too early | Create feature list file; read it each session; choose one feature |
| Undocumented progress | Write git commit + progress update at session end; verify at start |
| Marks features done prematurely | Self-verify all features; mark passing only after careful testing |
| Time on setup | Write init.sh script; read it at session start |

### Initializer vs Coding Agent Split

- **Initializer agent** sets up environment on first run (creates init.sh, progress log, initial commit)
- **Coding agents** work on single features, leaving clean state
- Fast understanding via progress file + git history

---

## 5. Multi-Agent Systems

**Source:** "How We Built Our Multi-Agent Research System" (anthropic.com/engineering)

### Architecture

- **Orchestrator-worker pattern:** Lead agent coordinates, specialized subagents operate in parallel
- **95% of performance variance** explained by: token usage (80%), number of tool calls, model choice
- Multi-agent systems use **~15x more tokens** than chat (reserve for valuable tasks with high ROI)
- **Best for:** Heavy parallelization, information exceeding single context windows, numerous complex tools
- **Less suitable for:** Domains requiring all agents to share context or with many dependencies

### Delegation

- Each subagent needs: **objective, output format, tool/source guidance, clear task boundaries**
- Without detailed task descriptions, agents **duplicate work or leave gaps**
- **Specify temporal context** in queries ("research 2021 automotive chip crisis" vs "current 2025 supply chains")

### Scaling Effort to Query Complexity

- **Simple fact-finding:** 1 agent, 3-10 tool calls
- **Direct comparisons:** 2-4 subagents, 10-15 calls each
- **Complex research:** 10+ subagents with divided responsibilities
- Prevents overinvestment in simple queries

### Tool Selection Heuristics

- **Examine all available tools first**
- **Match to user intent**
- **Prefer specialized over generic**
- Bad tool descriptions send agents down wrong paths entirely
- Each tool needs distinct purpose and clear description

### Self-Improvement

- **Let agents diagnose why agents fail** and suggest improvements
- Create tool-testing agents to rewrite tool descriptions
- **40% decrease in task completion time** from improved tool descriptions

### Research Strategy

- **Start wide, then narrow down** - explore landscape before drilling specifics
- Counteract agent tendency toward overly specific queries
- Start with short, broad queries; evaluate; progressively narrow

### Extended Thinking for Multi-Agent

- Use as **controllable scratchpad**
- Lead agent plans approach using thinking
- Subagents use **interleaved thinking** after tool results
- Improves instruction-following, reasoning, efficiency

### Parallelization

- Lead agent spins up **3-5 subagents in parallel**
- Subagents use **3+ tools in parallel**
- Reduces research time by **up to 90%** for complex queries

---

## 6. Agent Safety and Trust

**Source:** "Our Framework for Developing Safe and Trustworthy Agents" (anthropic.com/news)

### Keeping Humans in Control

- **Balance agent autonomy with human oversight**
- **Default read-only permissions:** Can analyze/review without approval, must ask before modifying systems
- **Users can stop Claude and redirect at any time**
- **Persistent permissions** for routine trusted tasks
- Right balance varies dramatically across scenarios

### Transparency

- **Show planned actions** through real-time to-do checklist
- Users can **jump in to ask about or adjust** workplan
- Find right level of detail - too little leaves uncertainty, too much overwhelms
- Provide **visibility into problem-solving processes**

### Value Alignment

- Agents sometimes take actions reasonable to system but **not what humans intended**
- Example: "Organize files" might lead to automatic deletion of duplicates and restructuring
- Agents may pursue goals in ways that **work against user interests**
- Use transparency and control principles as **key mitigations**

### Privacy

- Agents might **carry sensitive information** from one context to another
- Tools should be designed with **appropriate privacy protections**
- MCP includes controls for **allowing/preventing access** to specific tools
- Offer **one-time or permanent access grants**
- Access permissions, authentication, data segregation critical for protecting data

### Security

- Guard against **prompt injection attacks**
- Guard against **exploitation of vulnerabilities** in tools or subagents
- Claude uses classifiers to detect and guard against misuses
- Anthropic-reviewed MCP directory enforces security, safety, compatibility standards

---

## 7. Agent Skills Architecture

**Source:** "Equipping Agents for Real-World with Agent Skills" (anthropic.com/engineering)

### Progressive Disclosure Pattern

- **Load information only as needed**
- **Level 1:** Skill name and description loaded into system prompt at startup
- **Level 2:** Full SKILL.md loaded when Claude thinks skill is relevant
- **Level 3+:** Additional files (reference.md, forms.md) loaded only when needed
- Enables **unbounded skill complexity** possible with filesystem + code execution tools

### Skill Structure

- **Required:** SKILL.md file with YAML frontmatter (name, description)
- **Optional:** Additional files referenced from SKILL.md
- Keep core SKILL.md **lean**, reference additional files for specific scenarios
- Bundle **executable code (scripts)** that Claude can execute or reference

### Skill Development Guidelines

1. **Start with evaluation** - Identify gaps by running agents on representative tasks
2. **Structure for scale** - Split SKILL.md into separate files when unwieldy
3. **Think from Claude's perspective** - Monitor real-world usage, iterate on observations
4. **Iterate with Claude** - Ask Claude to capture successful approaches into reusable context/code

### Security Considerations

- **Install skills only from trusted sources**
- **Audit skills before use** - read file contents, check dependencies
- Pay attention to instructions/code that connect to **untrusted external sources**

---

## 8. Prompt Engineering

**Source:** Platform docs (docs.claude.com), "Advanced Tool Use"

### Role Prompting

- Use `system` parameter for role/context
- Put task-specific instructions in `user` messages
- **Enhanced accuracy** in complex scenarios (legal analysis, financial modeling)
- **Tailored tone** adjusts communication to domain expert level
- Role prompting is **more powerful than generic instructions**

### Chain of Thought

- Use for **complex tasks requiring step-by-step reasoning** (math, logic, analysis)
- Trade-off: Increased output length may impact latency
- **Basic:** "Think step-by-step" (lacks guidance on HOW to think)
- **Guided:** Outline specific thinking steps (lacks structure for separating thinking from answer)
- **Structured:** Use XML tags (`<thinking>` and `<answer>`) - **best for separating reasoning from final answer**
- **Critical:** "Always have Claude output its thinking. Without outputting its thought process, no thinking occurs!"

### Extended Thinking

- Claude creates **`thinking` content blocks** with internal reasoning
- Set `budget_tokens` (minimum 1,024, **recommend 16k+** for complex tasks)
- **Preserve thinking blocks** when passing tool results back to API
- **Interleaved thinking** allows Claude to think between tool calls
- Use for **complex math, coding, analysis**
- **Don't use with** temperature/top_k modifications or forced tool use

### Thinking Keywords (Claude Code)

- "think" < "think hard" < "think harder" < "ultrathink"
- Each level allocates progressively more thinking budget
- Particularly useful when making plans or evaluating multiple approaches

---

## 9. Error Handling and Recovery

**Source:** "Multi-Agent Research System", "Long-Running Agents"

### Design Principles

- **Agents are stateful - errors compound**
- Can't just restart from beginning
- Need systems that **resume from where error occurred**
- **Let agents adapt gracefully** when tools fail

### Recovery Patterns

- **Use git for recovery** - agents can revert bad changes and recover working states
- Combine **AI adaptability with deterministic safeguards** (retry logic, checkpoints)
- **Actionable error messages** guide agents on correct parameter usage
- Design tools to be **self-contained, robust to error**

### Production Reliability

- Add **full production tracing** for debugging
- **Monitor agent decision patterns** and interaction structures (not conversation contents for privacy)
- Diagnose why agents failed
- **Rainbow deployments** to avoid disrupting running agents - gradually shift traffic from old to new versions

### Graceful Degradation

- Let agents **adapt when tools fail**
- Provide **fallback behavior** when preferred options unavailable
- **Fail gracefully** with clear error messages

---

## 10. Performance Optimization

**Source:** Multiple engineering articles

### General Principles

- **Start simple, add complexity only when needed**
- Validate changes against **comprehensive evaluations**
- **Don't delay evals** waiting for perfect large-scale testing
- Start small (20 queries) to identify **high-impact changes**
- Early changes often have **dramatic effects** (30% -> 80% success)

### Model Selection

- Use **model choice strategically**
- **Sonnet:** Complex reasoning tasks
- **Haiku:** Simple, fast tasks
- Model choice explains **significant performance variance**

### Token Management

- **Profile token usage** and identify optimizations
- Multi-agent = **~15x more tokens than chat** (reserve for high-value tasks where ROI justifies cost)
- **Tool Search Tool:** Reduces context bloat for large tool libraries
- **Programmatic Tool Calling:** Reduces intermediate context pollution (37% savings)

### Complexity Trade-offs

- Complexity trades off with **latency, cost, and reliability**
- "Do the simplest thing that works"
- Add guardrails, tools, and complexity based on **observed failure modes**

---

## 11. Evaluation and Testing

**Source:** "Building Effective Agents", "Multi-Agent Research System"

### Evaluation Process

- **Start evaluating immediately** with small samples (20 queries)
- Large effect sizes early allow spotting changes with **few test cases**
- Don't delay waiting for perfect large-scale testing
- Early changes often dramatic improvements

### LLM-as-Judge

- **Scales well** when done properly
- Single LLM call with rubric
- Scores 0.0-1.0 with pass-fail grades
- Especially effective when **test cases have clear answers**

### Human Evaluation

- **Catches what automation misses:**
  - Hallucinations on unusual queries
  - System failures
  - Subtle biases (choosing SEO content over authoritative sources)
- Essential complement to automated evaluation

### Multi-Turn Task Evaluation

- **End-state evaluation** for multi-turn tasks vs turn-by-turn analysis
- Use **checkpoints, external memory**
- Fresh subagents with **clean contexts**

### Evaluation-Driven Improvement

- Generate diverse, canonical examples portraying expected behavior
- Examples are **"pictures worth a thousand words"** for LLMs
- Run evaluation programmatically with simple agentic loops
- Collect metrics: accuracy, runtime, tool call count, token consumption, tool errors
- **Let agents analyze results** and improve tools

---

## 12. Autonomous Operation

**Source:** "Enabling Claude Code to Work More Autonomously" (anthropic.com/news)

### Checkpointing

- **Automatically saves code state** before each change
- **Instant rewind** (Esc x 2 or /rewind)
- Pursue **ambitious tasks** knowing you can return to prior state
- Restore code, conversation, or both
- **Use with version control** for best results

### Autonomous Features

- **Subagents:** Delegate specialized tasks (parallel workflows)
- **Hooks:** Automatically trigger actions (run tests, lint)
- **Background Tasks:** Keep processes active (dev servers) without blocking progress

### Course Correction

- **Course correct early and often**
- Make a plan before coding, don't code until plan is confirmed
- Press Escape to interrupt during any phase (preserves context)
- Double-tap Escape to jump back in history and edit previous prompt
- Use `/clear` frequently between tasks to reset context window
- Ask Claude to undo changes and take different approach
- **Active collaboration** produces better results than first-attempt-only execution

---

## Quick Reference: Critical SOPs

### Before Starting Any Task

1. **Assess complexity** - determine if single agent or multi-agent approach needed
2. **Gather context** with minimal token consumption (just-in-time loading)
3. **Plan before executing** - don't code until plan is confirmed
4. **Verify tools available** and select appropriate ones

### During Execution

1. **One feature at a time** - avoid doing too much at once
2. **Leave clean state** after each change
3. **Verify work** before moving on (gather-action-verify loop)
4. **Commit progress** frequently with descriptive messages

### After Completion

1. **Test as a human would** - end-to-end verification
2. **Document progress** in progress file
3. **Don't declare victory early** - self-verify all features

### When Things Go Wrong

1. **Errors compound** - address immediately, don't let them accumulate
2. **Use git for recovery** - revert bad changes
3. **Adapt gracefully** when tools fail
4. **Provide actionable error information**

---

## Last Verified

**Date:** 2025-11-30
**Source:** docs-management canonical documentation
**Documents Referenced:**

- Effective Context Engineering for AI Agents
- Writing Tools for Agents
- Advanced Tool Use
- Building Agents with the Claude Agent SDK
- Effective Harnesses for Long-Running Agents
- How We Built Our Multi-Agent Research System
- Our Framework for Developing Safe and Trustworthy Agents
- Equipping Agents for Real-World with Agent Skills
- Enabling Claude Code to Work More Autonomously
- Platform documentation (docs.claude.com, code.claude.com)
