# Claude Code Antipatterns

This comprehensive guide documents antipatterns, bad practices, and common mistakes when using Claude Code that hinder accuracy, performance, or safety. Prioritizes November 2025 information and Opus 4.5 specific guidance.

**Load this file when:** Debugging Claude behavior, reviewing code quality, optimizing performance, troubleshooting Claude Code issues, or migrating to Opus 4.5.

## Quick Reference: Top 25 Critical Antipatterns

| # | Antipattern | Category | Impact |
| --- | ------------- | ---------- | -------- |
| 1 | Aggressive prompting ("MUST", "CRITICAL") | Prompting | Opus 4.5 overtriggers |
| 2 | Using "think" when extended thinking disabled | Prompting | Unexpected behavior |
| 3 | Not reading code before proposing changes | Code Gen | Hallucinated solutions |
| 4 | Overengineering simple tasks | Code Gen | Bloated codebases |
| 5 | CLAUDE.md over 100 lines | Context | Token waste, diluted signal |
| 6 | Not using `/clear` between tasks | Context | Context pollution |
| 7 | Trusting all input as instructions | Security | Prompt injection |
| 8 | Granting excessive permissions | Security | Data exfiltration risk |
| 9 | Fully autonomous without checkpoints | Agentic | Cascading errors |
| 10 | MCP permission wildcards (`mcp__*`) | Tool Use | Wildcard not supported |
| 11 | Sequential tool calls when parallel possible | Performance | Wasted time |
| 12 | Monolithic agent design | Agentic | Untestable, unpredictable |
| 13 | "Vibe check" evaluations | Testing | Non-reproducible |
| 14 | Separate messages for parallel tool results | API | Breaks parallel learning |
| 15 | Text before tool_result blocks | API | 400 errors |
| 16 | Not allowing Claude to say "I don't know" | Accuracy | Hallucinations |
| 17 | Loading all tools upfront | Token | 72K+ tokens wasted |
| 18 | No stopping conditions for agents | Agentic | Runaway execution |
| 19 | Silently suppressing exceptions | Error | Masked failures |
| 20 | Hardcoding credentials in prompts | Security | Credential exposure |
| 21 | Negative framing ("Don't do X") | Prompting | Reverse psychology |
| 22 | No distributed tracing | Monitoring | 70% longer MTTR |
| 23 | Using `tool_choice: any` with thinking | API | Causes errors |
| 24 | Pre-loading all context upfront | Context | Exhausts window |
| 25 | Testing only happy paths | Testing | Misses edge cases |

## Opus 4.5 Migration Checklist (November 2025)

Opus 4.5 (released November 24, 2025) behaves differently from previous models:

| Behavior | Old Models | Opus 4.5 | Action Required |
| ---------- | ------------ | ---------- | ----------------- |
| Instruction following | "Above and beyond" | Precise, literal | Be explicit about actions |
| Tool triggering | May undertrigger | May overtrigger | Dial back aggressive language |
| File creation | Conservative | Creates more files | Add anti-overengineering guidance |
| Communication | Verbose | Concise, direct | Request summaries if needed |
| Subagent delegation | Needs prompting | Proactive | May need to constrain |
| Thinking blocks | Manual management | Auto-preserved | Leverage for caching |
| Prompt injection | Vulnerable | Industry-leading resistance | Still need defense-in-depth |

---

## 1. Prompting Antipatterns

For detailed prompting guidance, see `.claude/memory/prompting-style-guide.md`.

### 1.1 Aggressive/Directive Language (Opus 4.5 Critical)

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using "CRITICAL:", "MUST", "ALWAYS", "NEVER", "WARNING:", "MANDATORY" |
| **Why it's bad** | Opus 4.5 is more responsive to system prompts - aggressive language causes **overtriggering** |
| **What to do instead** | Use calm, professional language: "Use this tool when..." not "CRITICAL: You MUST use this tool" |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.2 Using "Think" When Extended Thinking Disabled

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using "think", "think about", "think through" when extended thinking is not enabled |
| **Why it's bad** | Opus 4.5 is particularly sensitive to "think" - causes unexpected behavior or latency |
| **What to do instead** | Replace with: "consider", "evaluate", "analyze", "work through", "reason about" |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.3 Negative Framing

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "Do not use markdown", "NEVER use bullet points", "Don't hardcode paths" |
| **Why it's bad** | Telling Claude what NOT to do can backfire through reverse psychology |
| **What to do instead** | Positive framing: "Write in flowing prose paragraphs", "Use dynamic path resolution" |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.4 Vague or Ambiguous Instructions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "Be concise", "Make it professional", "Can you suggest some changes?" |
| **Why it's bad** | Opus 4.5 follows precisely - "suggest" means suggest only, not implement |
| **What to do instead** | Specific parameters: "Limit to 2-3 sentences", "Change this function to improve performance" |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.5 Missing Context/Motivation for Rules

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Simple prohibitions like "Never use ellipses" without explanation |
| **Why it's bad** | Claude cannot generalize to related situations |
| **What to do instead** | Add context: "Avoid ellipses because your response will be read by text-to-speech that can't pronounce them" |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.6 Inconsistent Prompt and Output Formatting

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using markdown-heavy prompts when wanting prose output |
| **Why it's bad** | Claude's output style is influenced by prompt formatting |
| **What to do instead** | Match prompt style to desired output - remove markdown from prompt to reduce markdown in output |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 1.7 Instructions in System Message Only

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Putting all detailed instructions in system message |
| **Why it's bad** | Claude follows human messages (user prompts) better than system messages |
| **What to do instead** | Use system message for role/context; put most instructions in human prompts |
| **Source** | [PromptLayer Analysis](https://blog.promptlayer.com/prompt-engineering-with-anthropic-claude-5399da57461d/) |

### 1.8 Over-Constraining Role Definitions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "You are a world-renowned expert who only speaks in technical jargon and never makes mistakes" |
| **Why it's bad** | Overly detailed personas limit helpfulness and flexibility |
| **What to do instead** | Simpler framing: "You are a helpful assistant" - heavy-handed role prompting often unnecessary |
| **Source** | [Best Practices for Prompt Engineering](https://www.claude.com/blog/best-practices-for-prompt-engineering) |

### 1.9 Manual Chain-of-Thought When Extended Thinking Available

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Manually implementing "think step by step" when extended thinking is available |
| **Why it's bad** | Extended thinking automates structured reasoning more effectively |
| **What to do instead** | Use native extended thinking; reserve manual CoT for when thinking isn't available |
| **Source** | [Extended Thinking Docs](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking) |

### 1.10 Over-Trusting Visible Thought Process

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Treating displayed thinking as ground truth for how model actually reasons |
| **Why it's bad** | Chains of thought are neither faithful nor complete representations of actual reasoning |
| **What to do instead** | Use extended thinking for capability, not safety verification; implement separate validation |
| **Source** | [Visible Extended Thinking](https://www.anthropic.com/news/visible-extended-thinking) |

### 1.11 Chained Prompts Without "Outs"

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "Make the story better" or "Improve this" without allowing "no change needed" |
| **Why it's bad** | Claude may make unnecessary changes even when original was good |
| **What to do instead** | Give explicit "out": "If all words are real, return the original list unchanged" |
| **Source** | [Anthropic Courses - Chaining Prompts](https://github.com/anthropics/courses) |

### 1.12 Too Many Examples Without Baseline Testing

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Immediately implementing few-shot with multiple examples |
| **Why it's bad** | May not identify if issue is examples or something else |
| **What to do instead** | Start with one example (one-shot); only add more if output still doesn't match |
| **Source** | [Best Practices for Prompt Engineering](https://www.claude.com/blog/best-practices-for-prompt-engineering) |

### 1.13 Not Permitting Uncertainty

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Expecting Claude to always provide an answer, even when uncertain |
| **Why it's bad** | Forces Claude to fabricate information |
| **What to do instead** | Add: "If you're unsure, say 'I don't have enough information'" |
| **Source** | [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations) |

### 1.14 Too Many Objectives in Single Prompt

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Attempting multiple objectives in one prompt |
| **Why it's bad** | Focused tasks with clear boundaries produce higher quality |
| **What to do instead** | Break large tasks into smaller, discrete chunks with clear scope |
| **Source** | [Best Practices for Prompt Engineering](https://www.claude.com/blog/best-practices-for-prompt-engineering) |

### 1.15 Not Specifying Output Format

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Letting model decide output format |
| **Why it's bad** | May generate verbose or incorrectly structured responses |
| **What to do instead** | Specify format, use output priming ("Here's a bulleted list:\n-") |
| **Source** | [Microsoft Learn Prompt Engineering](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/prompt-engineering) |

---

## 2. Tool Use Antipatterns

### 2.1 Separate Messages for Parallel Tool Results

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Sending separate user messages for each tool result when tools were called in parallel |
| **Why it's bad** | "Teaches" Claude to avoid parallel calls |
| **What to do instead** | All tool results must be in a single user message |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

### 2.2 Text Before Tool Results in Messages

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Putting text content before tool_result blocks in user messages |
| **Why it's bad** | Causes 400 errors |
| **What to do instead** | Always put tool results first, then any text |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

### 2.3 Insufficient Tool Descriptions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Providing vague or minimal tool descriptions |
| **Why it's bad** | Claude may not use tools correctly or may miss required parameters |
| **What to do instead** | Provide extremely detailed descriptions in tool definitions |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

### 2.4 Loading All Tool Definitions Upfront

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Loading all 50+ MCP tool definitions at conversation start |
| **Why it's bad** | Consumes 72K-134K tokens before any work begins; wastes 95% of context |
| **What to do instead** | Use Tool Search Tool for on-demand discovery (~500 tokens upfront vs 72K) |
| **Source** | [Advanced Tool Use](https://www.anthropic.com/engineering/advanced-tool-use) |

### 2.5 Using `tool_choice: any/tool` with Extended Thinking

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Forcing tool usage (`type: "any"` or `type: "tool"`) when thinking is enabled |
| **Why it's bad** | These options conflict with extended thinking - causes errors |
| **What to do instead** | Use only `tool_choice: auto` or `tool_choice: none` with extended thinking |
| **Source** | [Extended Thinking with Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking) |

### 2.6 Toggling Thinking Mode Mid-Turn

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Trying to enable/disable thinking between tool_use and tool_result in same turn |
| **Why it's bad** | Invalid - cannot toggle thinking mid-turn; also invalidates prompt caching |
| **What to do instead** | Plan thinking strategy at start of turn; complete assistant turn before changing |
| **Source** | [Thinking with Tool Use](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking) |

### 2.7 Missing Thinking Blocks with Tool Use

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not preserving `thinking` blocks when passing tool results back to API |
| **Why it's bad** | API will reject the request; breaks reasoning continuity |
| **What to do instead** | Include complete, unmodified thinking blocks in assistant message content |
| **Source** | [Anthropic Cookbook - Extended Thinking with Tool Use](https://github.com/anthropics/anthropic-cookbook) |

### 2.8 Not Using Token-Efficient Tool Calling

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using standard tool calling without enabling token-efficient mode |
| **Why it's bad** | Misses up to 70% output token reduction available with Claude 3.7+ |
| **What to do instead** | Enable token-efficient tool calling; average 14% reduction across all token usage |
| **Source** | [Claude Token Saving Updates](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/token-efficient-tool-use) |

### 2.9 Multiple Small Tool Calls Instead of Batching

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Making 10 separate tool calls for minor fixes |
| **Why it's bad** | Each call has overhead; accumulated costs 30%+ higher |
| **What to do instead** | Consolidate related changes; batch operations into single review prompt |
| **Source** | [Claude Code Workflow Best Practices](https://sidetool.co/post/claude-code-best-practices-tips-power-users-2025) |

### 2.10 Not Handling max_tokens Truncation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not checking for truncated responses during tool use |
| **Why it's bad** | Incomplete tool use blocks lead to failures |
| **What to do instead** | Check `stop_reason == "max_tokens"` and retry with higher limit |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

### 2.11 Not Handling pause_turn Stop Reason

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Ignoring `pause_turn` stop reason when using server tools |
| **Why it's bad** | Long-running turns may pause; without handling, you lose partial work |
| **What to do instead** | Continue conversation by passing paused response back |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

### 2.12 Delegating Deterministic Tasks to Model

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Relying on Claude for mathematical calculations, date comparisons, precise operations |
| **Why it's bad** | LLMs are probabilistic; deterministic operations introduce unnecessary variability |
| **What to do instead** | Delegate to deterministic tools (Python functions, specialized APIs) |
| **Source** | [Claude Opus 4.5 Guidance](https://www.anthropic.com/news/claude-opus-4-5) |

### 2.13 Not Using Strict Tool Schemas

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using loose tool schemas without `"strict": true` |
| **Why it's bad** | Tool calls may not strictly adhere to schema; harder to validate |
| **What to do instead** | Enable `"strict": true` with beta header for guaranteed schema adherence |
| **Source** | [Structured Outputs](https://docs.anthropic.com/en/docs/build-with-claude/structured-outputs) |

---

## 3. MCP Server Antipatterns

### 3.1 MCP Permission Wildcards

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using wildcards for MCP tool permissions: `mcp__github__*` |
| **Why it's bad** | Wildcards not supported - permission won't work |
| **What to do instead** | Use `mcp__github` (all tools from server) or `mcp__github__get_issue` (specific tool) |
| **Source** | [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/permissions) |

### 3.2 Missing Server Prefix in Tool References

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Referencing MCP tools without server name prefix in skills |
| **Why it's bad** | "Tool not found" errors when multiple MCP servers available |
| **What to do instead** | Use fully qualified names: `mcp__github__create_issue`, `mcp__memory__write` |
| **Source** | [Agent Skills Best Practices](https://console.anthropic.com/docs/en/agents-and-tools/agent-skills/best-practices) |

### 3.3 Over-Reliance on MCP Without Context Monitoring

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Enabling all available MCP servers without considering necessity |
| **Why it's bad** | MCP servers consume substantial tokens - often 40k+ tokens when auto-compacting |
| **What to do instead** | Toggle MCP servers with `@` notation; remove unused servers; disable auto-compact |
| **Source** | [Claude Code Best Practices](https://www.shuttle.dev/blog/2025/10/16/claude-code-best-practices) |

### 3.4 Running MCP Servers Without Sandboxing

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Running MCP servers with same privileges as client, without sandboxing |
| **Why it's bad** | Direct path to data exfiltration, data loss, arbitrary code execution |
| **What to do instead** | Run in sandboxed environments with minimal default privileges |
| **Source** | [MCP Security Best Practices](https://modelcontextprotocol.io/specification/draft/basic/security_best_practices) |

### 3.5 Improper Session/Token Management in MCP Design

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using predictable session IDs; accepting tokens across services without audience validation |
| **Why it's bad** | Security vulnerabilities; session hijacking; cascading failures |
| **What to do instead** | Use cryptographically secure random session IDs; implement proper token audience separation |
| **Source** | [MCP Security Best Practices](https://modelcontextprotocol.io/specification/draft/basic/security_best_practices) |

### 3.6 Skipping Pre-Configuration Consent for Local MCP

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Auto-configuring local MCP servers without displaying exact command to user |
| **Why it's bad** | Arbitrary code execution vulnerabilities; users don't know what will run |
| **What to do instead** | Display exact command without truncation; require explicit user approval |
| **Source** | [MCP Security Best Practices](https://modelcontextprotocol.io/specification/draft/basic/security_best_practices) |

---

## 4. Context and Memory Antipatterns

For detailed context engineering guidance, see `.claude/memory/context-engineering.md`.

### 4.1 CLAUDE.md Over 100 Lines

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating CLAUDE.md files with 100+ lines of generic information |
| **Why it's bad** | Wastes context tokens; generic info doesn't help with specific tasks; dilutes signal |
| **What to do instead** | Keep under 100 lines; focus only on project-specific patterns, architecture, coding standards |
| **Source** | [Claude Code Best Practices](https://www.shuttle.dev/blog/2025/10/16/claude-code-best-practices) |

### 4.2 Starting with Excessive Documentation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating comprehensive manual upfront before using Claude Code in practice |
| **Why it's bad** | Over-engineering creates noise; Claude struggles to identify what's important |
| **What to do instead** | Start small; document issues as they arise; add guardrails based on what Claude gets wrong |
| **Source** | [How I Use Every Claude Code Feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature) |

### 4.3 Creating Complex Custom Slash Commands

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Including long list of documented "magic commands" that users must memorize |
| **Why it's bad** | Defeats purpose of intelligent agent; shifts cognitive burden back to users |
| **What to do instead** | Use natural language; reserve slash commands for genuinely repetitive, token-saving operations |
| **Source** | [How I Use Every Claude Code Feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature) |

### 4.4 Not Clearing Context Between Tasks

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Allowing conversation history to accumulate across multiple features or tickets |
| **Why it's bad** | Previous context consumes tokens and confuses model about current goals |
| **What to do instead** | Use `/clear` after finishing a task for clean slate |
| **Source** | [Managing Claude Code's Context](https://www.cometapi.com/managing-claude-codes-context/) |

### 4.5 Leaving Auto-Compact Enabled Without Monitoring

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Allowing auto-compact to run silently without monitoring token consumption |
| **Why it's bad** | Auto-compact buffers can consume 22.5% of entire context window (45,000+ tokens) |
| **What to do instead** | Consider disabling via `/config`; monitor with `/context` |
| **Source** | [Claude Code Best Practices](https://www.shuttle.dev/blog/2025/10/16/claude-code-best-practices) |

### 4.6 Monolithic Memory Files

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating large, monolithic memory files |
| **Why it's bad** | As files grow, Claude's ability to locate relevant information diminishes; signal gets lost |
| **What to do instead** | Break into smaller, referenced files using `@import` syntax |
| **Source** | [Claude Memory Deep Dive](https://skywork.ai/blog/claude-memory-a-deep-dive-into-anthropics-persistent-context-solution/) |

### 4.7 Pre-Loading Everything Instead of Just-in-Time

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Loading all documentation and context upfront |
| **Why it's bad** | Exhausts context window before work begins; irrelevant context dilutes signal |
| **What to do instead** | Load minimal context initially; fetch additional as needed (progressive disclosure) |
| **Source** | [Claude Memory Deep Dive](https://skywork.ai/blog/claude-memory-a-deep-dive-into-anthropics-persistent-context-solution/) |

### 4.8 Mixing Planning and Implementation in Same Context

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Having Claude understand architecture, plan, and implement in same session |
| **Why it's bad** | Dilutes focus; exploratory noise consumes context; implementation suffers |
| **What to do instead** | Separate planning phase: dump plan to markdown file, clear context, start fresh for implementation |
| **Source** | [Claude Code Best Practices](https://www.shuttle.dev/blog/2025/10/16/claude-code-best-practices) |

### 4.9 Critical Information in Middle of Long Prompts

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Placing critical information in the middle of long prompts |
| **Why it's bad** | LLMs exhibit U-shaped performance; 30%+ degradation when critical info is in middle position |
| **What to do instead** | Position critical information at beginning or end ("Lost in the Middle" research) |
| **Source** | [Stanford/UW Research - arxiv:2307.03172](https://arxiv.org/abs/2307.03172) |

### 4.10 Not Repeating Critical Instructions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Stating important instructions only once in long prompts |
| **Why it's bad** | Recency bias: end may have more influence than beginning |
| **What to do instead** | Repeat critical instructions at both beginning AND end |
| **Source** | [Microsoft Learn Prompt Engineering](https://learn.microsoft.com/en-us/azure/ai-foundry/openai/concepts/prompt-engineering) |

### 4.11 Using Long Prompts Repeatedly

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Pasting lengthy prompts multiple times |
| **Why it's bad** | Wastes tokens through repetition |
| **What to do instead** | Store as slash commands in `.claude/commands/` |
| **Source** | [Managing Claude Code's Context](https://www.cometapi.com/managing-claude-codes-context/) |

### 4.12 Neglecting /compact Before Critical Phases

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not using `/compact` when conversations grow lengthy |
| **Why it's bad** | Eventually hit token limits, forcing drastic action |
| **What to do instead** | Use `/compact` to compress while preserving key decisions |
| **Source** | [Conversation Management and Context](https://dev.to/letanure/claude-code-part-3-conversation-management-and-context-3l28) |

### 4.13 No Directory-Specific CLAUDE.md Files

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Having only root-level CLAUDE.md without sub-directory specific guidance |
| **Why it's bad** | Forces all context to load for all tasks, even when working in specific areas |
| **What to do instead** | Create sub-CLAUDE.md files (`frontend/CLAUDE.md`, `backend/CLAUDE.md`) |
| **Source** | [Claude Code Best Practices](https://www.eesel.ai/blog/claude-code-best-practices) |

---

## 5. Agentic Workflow Antipatterns

### 5.1 Premature Agent Adoption

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Reaching for agents first when building LLM-powered systems |
| **Why it's bad** | Agents add complexity, debugging nightmares, orchestration overhead without clear benefits |
| **What to do instead** | Start with simple prompts, optimize with evaluation, add agents only when simpler solutions fall short |
| **Source** | [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) |

### 5.2 Monolithic Agent Design

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Building single agents responsible for all tasks |
| **Why it's bad** | Systems become untestable, undebugable, unpredictable; coordination harder than the task |
| **What to do instead** | Design modular, transparent, incrementally autonomous systems using composable patterns |
| **Source** | [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) |

### 5.3 Using Complex Frameworks Before Understanding Fundamentals

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Building with complex agent frameworks before understanding basic patterns |
| **Why it's bad** | Creates abstraction layers obscuring underlying prompts/responses; makes debugging harder |
| **What to do instead** | Start by using LLM APIs directly; many patterns can be implemented in few lines of code |
| **Source** | [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents) |

### 5.4 Rigid Few-Shot Examples Showing Exact Steps

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Providing prescriptive examples showing exact step-by-step processes |
| **Why it's bad** | Modern frontier models have CoT trained in; prescriptive examples limit capabilities |
| **What to do instead** | Give agents heuristics and principles rather than rigid templates |
| **Source** | [Prompting for Agents](https://www.anthropic.com/engineering/prompting-for-agents) |

### 5.5 Over-Planning with Elaborate Planning Systems

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Implementing elaborate planning systems before execution |
| **Why it's bad** | Adds latency, complexity; plans often don't survive contact with reality |
| **What to do instead** | Use thinking mode to plan approach, but let agent adapt |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.6 Vague Task Delegation to Subagents

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "Research the semiconductor shortage" without specifics |
| **Why it's bad** | Subagents misinterpret tasks, duplicate work, or fail to find necessary information |
| **What to do instead** | Each subagent needs: objective, output format, guidance on tools/sources, clear task boundaries |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.7 No Division of Labor Specification

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not explicitly defining each subagent's role and scope |
| **Why it's bad** | Multiple agents explore same territory while leaving gaps elsewhere |
| **What to do instead** | Explicitly define each subagent's role and scope; prevent overlap through clear boundaries |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.8 Spawning 50 Subagents for Simple Queries

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Spawning excessive subagents for simple tasks |
| **Why it's bad** | Massive resource waste, coordination chaos, diminishing returns |
| **What to do instead** | Embed scaling rules: simple fact-finding = 1 agent with 3-10 tool calls; complex = 10+ agents |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.9 Sequential Subagent Execution

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Running subagents sequentially when they could run in parallel |
| **Why it's bad** | Painfully slow; creates bottlenecks in information flow |
| **What to do instead** | Spin up 3-5 subagents in parallel; have subagents use 3+ tools in parallel (90% time reduction) |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.10 All Communication Through Lead Agent

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Having all communication flow through lead agent ("game of telephone") |
| **Why it's bad** | Information loss during multi-stage processing; token overhead from copying outputs |
| **What to do instead** | Implement artifact systems where subagents store outputs externally, pass lightweight references |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 5.11 No Stopping Conditions for Agents

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | "Keep searching until you find the highest quality source" without bounds |
| **Why it's bad** | Agent searches indefinitely until context window limit |
| **What to do instead** | Add nuance: "If you don't find the perfect source, that's okay. Stop after a few tool calls" |
| **Source** | [Prompting for Agents](https://www.anthropic.com/engineering/prompting-for-agents) |

### 5.12 Fully Autonomous Without Checkpoints

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Allowing Claude Code to execute multi-step workflows without human review |
| **Why it's bad** | GTG-1002 demonstrated complete attack lifecycle without human intervention; errors cascade |
| **What to do instead** | Implement approval gates for file modifications, network requests, system config changes |
| **Source** | [Anthropic Threat Intelligence Report August 2025](https://www.anthropic.com/news/detecting-countering-misuse-aug-2025) |

### 5.13 Stopping Tasks Early Due to Context Concerns

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Allowing Claude to wrap up work prematurely as context limit approaches |
| **Why it's bad** | Claude Opus 4.5 has context awareness and may stop too early unnecessarily |
| **What to do instead** | Instruct: "Do not stop tasks early due to token budget concerns. Be persistent and complete tasks fully." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

---

## 6. Code Generation Antipatterns

### 6.1 Speculating Without Reading Code

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Proposing solutions or explaining code without actually reading the files |
| **Why it's bad** | Leads to hallucinated code structures, incorrect assumptions, broken solutions |
| **What to do instead** | "ALWAYS read and understand relevant files before proposing code edits. Do not speculate about code you have not inspected." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 6.2 Overengineering and Unnecessary Abstractions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating extra files, adding unnecessary abstractions, building unrequested flexibility |
| **Why it's bad** | Adds complexity, creates maintenance burden, diverges from requirements |
| **What to do instead** | Add: "Avoid over-engineering. Only make changes directly requested. Keep solutions simple." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 6.3 Hard-Coding Values to Pass Tests

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Focusing on making tests pass by hard-coding specific test inputs |
| **Why it's bad** | Solutions only work for test cases, not general inputs |
| **What to do instead** | "Write a general-purpose solution. Do not hard-code values for specific test inputs." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 6.4 Creating Temporary Files Without Cleanup

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating temporary files/scripts and leaving them behind |
| **Why it's bad** | Clutters the codebase with temporary artifacts |
| **What to do instead** | "If you create temporary files, clean up by removing them at end of task." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 6.5 Generic "AI Slop" Frontend Design

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Defaulting to: Inter/Arial fonts, purple gradients, minimal layouts, predictable patterns |
| **Why it's bad** | Creates generic, forgettable, clearly AI-generated designs |
| **What to do instead** | Use unique fonts, cohesive aesthetics, meaningful animations, atmospheric backgrounds |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 6.6 Jumping Straight to Coding

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Letting Claude execute code without exploring and planning first |
| **Why it's bad** | Solutions don't align with existing codebase patterns; more iterations needed |
| **What to do instead** | Ask Claude to read relevant files first, then make a plan before writing code |
| **Source** | [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices) |

### 6.7 Not Using Subagents for Complex Exploration

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Having main agent do all exploration, consuming main context |
| **Why it's bad** | Main context fills with exploration noise; loses capacity for implementation |
| **What to do instead** | Use subagents (Task tool) for exploration early in conversation |
| **Source** | [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices) |

### 6.8 Not Documenting Custom Tools

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Expecting Claude to know your custom bash tools without instructions |
| **Why it's bad** | Claude makes inefficient calls or avoids tools entirely |
| **What to do instead** | Tell Claude tool name with usage examples; run `--help`; document in CLAUDE.md |
| **Source** | [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices) |

---

## 7. Safety and Security Antipatterns

### 7.1 Trusting All Input as Legitimate Instructions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Processing user inputs, file contents, and external data without distinguishing trusted vs potentially malicious |
| **Why it's bad** | Attackers embed malicious instructions in code comments, config files, API responses (indirect prompt injection) |
| **What to do instead** | Implement input validation; use spotlighting to isolate untrusted data; deploy content filtering |
| **Source** | CVE-2025-54795, OWASP LLM01:2025 |

### 7.2 Allowing Claude to Override Its Own Restrictions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Asking Claude to help analyze or test its own security boundaries |
| **Why it's bad** | CVE-2025-54795 demonstrated Claude could be "turned inward" to discover flaws in its restrictions |
| **What to do instead** | Use separate, sandboxed environments for security testing; implement external validation |
| **Source** | [Cymulate CVE-2025-54795 Analysis](https://cymulate.com/blog/cve-2025-547954-54795-claude-inverseprompt/) |

### 7.3 Granting Excessive Permissions by Default

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Giving Claude Code access to production credentials, AWS keys, sensitive env vars |
| **Why it's bad** | Compromised Claude with production credentials can execute destructive commands |
| **What to do instead** | Configure deny rules: `Read(.envrc)`, `Read(~/.aws/**)`, `Read(**/*.pem)` |
| **Source** | [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/permissions) |

### 7.4 Auto-Approving All Bash Commands

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Setting `autoAllowBashIfSandboxed: true` without proper exclusions |
| **Why it's bad** | Sandboxed environments can be escaped through shell operators, redirects, protocol handlers |
| **What to do instead** | Maintain exclusion lists: `excludedCommands: ["docker", "curl", "wget", "nc", "ssh"]` |
| **Source** | [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/permissions) |

### 7.5 Unrestricted Network Access

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Allowing Claude to make arbitrary HTTP requests to any domain |
| **Why it's bad** | Data can be exfiltrated through HTTP requests, DNS queries, WebSocket connections |
| **What to do instead** | Whitelist allowed domains for WebFetch; monitor and log network activity; use DLP controls |
| **Source** | OWASP LLM02:2025 |

### 7.6 Storing Sensitive Data in Context

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Including production credentials, API keys, sensitive data in system prompts |
| **Why it's bad** | Context can be extracted through prompt injection; data may be logged inappropriately |
| **What to do instead** | Use reference-based access (query on-demand); implement need-to-know; redact before including |
| **Source** | OWASP LLM02:2025 |

### 7.7 Hardcoding Credentials in AI-Generated Code

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Accepting AI-generated code containing hardcoded credentials without review |
| **Why it's bad** | Credentials end up in version control, code reviews, CI/CD logs |
| **What to do instead** | Use safety meta-prompts; scan AI-generated code for credential patterns; implement pre-commit hooks |
| **Source** | [Microsoft Azure AI Security Benchmark AI-3](https://learn.microsoft.com/en-us/security/benchmark/azure/mcsb-v2-artificial-intelligence-security) |

### 7.8 Relying Solely on Claude's Self-Enforcement

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Trusting that Claude will honor restrictions defined only in prompts |
| **Why it's bad** | Prompt-based restrictions can be bypassed; social engineering can convince Claude it's acting legitimately |
| **What to do instead** | Use OS-level sandboxing; implement technical controls that don't rely on model compliance |
| **Source** | CVE-2025-54795 |

### 7.9 Exposing Docker Socket

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Configuring `allowUnixSockets: ["/var/run/docker.sock"]` without understanding implications |
| **Why it's bad** | Docker socket access is equivalent to root access on the host |
| **What to do instead** | Use rootless Docker or Podman; if needed, use Docker-in-Docker with restricted capabilities |
| **Source** | [Claude Code Documentation](https://docs.anthropic.com/en/docs/claude-code/sandboxing) |

### 7.10 Trusting AI Security Reviews as Sole Validation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Relying exclusively on Claude's `/security-review` command |
| **Why it's bad** | Research shows 14% true positive rate with 86% false positive rate; AI can be tricked by obfuscation |
| **What to do instead** | Use AI security review as one input; implement traditional scanning (SAST, DAST, SCA); require human review |
| **Source** | [Checkmarx Research](https://checkmarx.com/zero-post/bypassing-claude-code-how-easy-is-it-to-trick-an-ai-security-reviewer/) |

---

## 8. Error Handling Antipatterns

### 8.1 Silently Suppressing Exceptions

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using `try/except: pass` or similar silent error suppression |
| **Why it's bad** | In agentic systems, silent failures create unrecoverable state corruption and mask problems |
| **What to do instead** | Explicit failure propagation; let failures bubble up and be handled explicitly |
| **Source** | [Exception Handling Frameworks for AI Agents](https://www.datagrid.com/blog/exception-handling-frameworks-ai-agents) |

### 8.2 Naive Retry Mechanisms

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Simply repeating failed operations without understanding whether original completed |
| **Why it's bad** | Creates duplicate operations (double payments), state corruption, retry storms |
| **What to do instead** | Implement idempotency tokens; use dead letter patterns; design operations to be safely retryable |
| **Source** | [Exception Handling Frameworks for AI Agents](https://www.datagrid.com/blog/exception-handling-frameworks-ai-agents) |

### 8.3 Traditional Rollback Strategies

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Applying database-style rollback and reset strategies to AI agent failures |
| **Why it's bad** | AI agents build understanding progressively - context is valuable state; rollback destroys hours of work |
| **What to do instead** | Separate learned patterns from temporary state; checkpoint insights independently; graceful degradation |
| **Source** | [Exception Handling Frameworks for AI Agents](https://www.datagrid.com/blog/exception-handling-frameworks-ai-agents) |

### 8.4 Escalation Without Context Preservation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | When escalating to humans, losing agent reasoning chains, confidence scores, partial results |
| **Why it's bad** | Operators must start investigation from scratch; loses valuable diagnostic info |
| **What to do instead** | Preserve complete reasoning chains, confidence scores, partial results for review |
| **Source** | [Exception Handling Frameworks for AI Agents](https://www.datagrid.com/blog/exception-handling-frameworks-ai-agents) |

### 8.5 Restart from Beginning on Failure

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Restarting entire agent workflow when errors occur |
| **Why it's bad** | Restarts are expensive and frustrating; discards all progress |
| **What to do instead** | Build systems that can resume from where agent was; use regular checkpoints |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

---

## 9. Evaluation and Testing Antipatterns

For detailed testing guidance, see `.claude/memory/testing-principles.md`.

### 9.1 "Vibe Check" Evaluations

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using informal, subjective assessment ("this looks right") |
| **Why it's bad** | Results cannot be replicated; different evaluators reach different conclusions |
| **What to do instead** | Build structured evaluation datasets with scoring rubrics; establish baselines; use LLM-as-judge with explicit criteria |
| **Source** | [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/) |

### 9.2 Binary Pass/Fail for Non-Deterministic Systems

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Applying traditional CI/CD binary pass/fail criteria to agents |
| **Why it's bad** | Creates false failures for valid outputs; tests become flaky |
| **What to do instead** | Implement "soft failures" with scoring ranges (<0.5=hard fail, 0.5-0.8=soft, >0.8=pass) |
| **Source** | [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/) |

### 9.3 Cosine Similarity for Semantic Distance

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using vector embedding cosine similarity to measure semantic distance |
| **Why it's bad** | Similar wording can have completely different meanings; creates false confidence |
| **What to do instead** | Use LLM-as-judge for semantic similarity; evaluate groundedness separately |
| **Source** | [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/) |

### 9.4 Benchmark Gaming and Overfitting

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Optimizing models specifically for benchmark test sets |
| **Why it's bad** | Models perform well on benchmarks but fail production; SWE-bench found 24% leaderboard errors |
| **What to do instead** | Use held-out evaluation sets; validate with external benchmarks; test on real-world tasks |
| **Source** | [The AI Agent Evaluation Crisis](https://labs.adaline.ai/p/the-ai-agent-evaluation-) |

### 9.5 Waiting for Massive Test Suite Before Starting

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Assuming you need massive automated test suites before starting |
| **Why it's bad** | Delays progress; with large effect sizes, small samples reveal impact |
| **What to do instead** | Start with 3-5 manual test cases immediately; expand gradually |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 9.6 Reporting Only Summary Statistics

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Reporting only median/mean metrics while ignoring distribution |
| **Why it's bad** | Obscures tail performance issues, generation stalls, variability |
| **What to do instead** | Report full distributions (p50, p90, p95, p99); track variance |
| **Source** | [LLM Inference Evaluation Research](https://arxiv.org/html/2507.02825v1) |

### 9.7 Testing Only Expected Behavior

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Creating test cases only for happy paths |
| **Why it's bad** | Misses edge cases, adversarial inputs, safety/alignment issues |
| **What to do instead** | Test unexpected usage, prompt injection, complex multi-step queries, different user skill levels |
| **Source** | [Microsoft Learn AI Testing](https://learn.microsoft.com/en-us/azure/well-architected/ai/test) |

### 9.8 Not Evaluating Evaluators

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Trusting LLM-as-judge without validating the judges |
| **Why it's bad** | LLM judges hallucinate too (~1 in 10 tests produce spurious results) |
| **What to do instead** | Run tests multiple times; measure delta; remove/revise flaky evaluators; cross-validate with humans |
| **Source** | [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/) |

### 9.9 Running Exhaustive Evaluations on Every Change

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Full evaluation suite on every code change |
| **Why it's bad** | Evaluations can reach 10x operation cost; slow feedback discourages iteration |
| **What to do instead** | Localize tests; trigger selectively based on changed components; maintain <1:1 cost ratio |
| **Source** | [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/) |

### 9.10 Testing Only Functional Correctness

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Focusing solely on "does it work?" without safety testing |
| **Why it's bad** | No tested agent scored above 60% on Agent-SafetyBench; safety issues missed |
| **What to do instead** | Use safety benchmarks; test across risk categories; evaluate sycophancy resistance |
| **Source** | [Agent-SafetyBench](https://arxiv.org/abs/2412.14470) |

---

## 10. Monitoring and Observability Antipatterns

### 10.1 Traditional Metrics-Only Monitoring

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Watching only for clear error states (HTTP 500s, crashes) |
| **Why it's bad** | AI agents fail through behavioral degradation: confidence drift, inconsistent performance |
| **What to do instead** | Implement dynamic confidence thresholds; monitor decision patterns; track reasoning chain quality |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 10.2 Log-Based Debugging for Distributed Agents

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using traditional logging without distributed tracing for multi-agent systems |
| **Why it's bad** | Fails to expose inter-agent interactions and timing; 70% longer MTTR |
| **What to do instead** | Implement distributed tracing capturing all interactions; track causal chains |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 10.3 Missing State Consistency Validation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not continuously validating state consistency across distributed agents |
| **Why it's bad** | Agents develop inconsistent views; race conditions corrupt state silently |
| **What to do instead** | Implement cross-agent state comparison; validate causal consistency; alert on divergence |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 10.4 No Production Tracing

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | No production tracing for agent decisions |
| **Why it's bad** | Cannot diagnose why agents failed; no accountability |
| **What to do instead** | Add full production tracing; monitor agent decision patterns and interaction structures |
| **Source** | [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system) |

### 10.5 Silent Failure Modes

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Suppressing or ignoring errors from Claude's operations |
| **Why it's bad** | Attackers may trigger intentional failures to bypass security; silent failures mask malicious activity |
| **What to do instead** | Comprehensive logging for all operations; alerts for unexpected failures; require human acknowledgment |
| **Source** | [Microsoft Azure AI Security Benchmark AI-6](https://learn.microsoft.com/en-us/security/benchmark/azure/mcsb-v2-artificial-intelligence-security) |

---

## 11. Multi-Agent Coordination Antipatterns

### 11.1 Implicit State Sharing Without Synchronization

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Agents assuming consistent shared state without explicit synchronization |
| **Why it's bad** | Race conditions increase quadratically: N(N-1)/2 potential interactions |
| **What to do instead** | Implement explicit synchronization (transactions, optimistic concurrency, event sourcing) |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 11.2 Unbounded Context Accumulation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Agents accumulating context without pruning or summarization |
| **Why it's bad** | Token costs escalate exponentially; 4-agent analysis: 29K tokens vs 10K single agent (2-5x cost) |
| **What to do instead** | Implement context management (summarization, pruning, external storage); trigger compaction before limits |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 11.3 Synchronous Blocking Chains

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Agents invoking downstream agents synchronously, creating blocking chains |
| **Why it's bad** | Parallelization benefits disappear; latency accumulates; failures block all upstream |
| **What to do instead** | Redesign for async message passing; use event-driven architectures |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 11.4 Coordination Through Polling

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Agents polling for state changes instead of event-driven coordination |
| **Why it's bad** | High resource consumption; delayed reactions; scales poorly |
| **What to do instead** | Implement event-driven coordination (message queues, pub-sub) |
| **Source** | [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/) |

### 11.5 No Coordination Mechanism for Parallel Agents

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Running parallel agents without coordination mechanism |
| **Why it's bad** | Agents diverge into conflicting modifications, duplicate work, merge conflicts |
| **What to do instead** | Use centralized work orchestration document or similar state management |
| **Source** | [Agentic Coding](https://www.nijho.lt/post/agentic-coding/) |

---

## 12. API and Integration Antipatterns

### 12.1 Non-Alternating Message Roles

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Consecutive messages with the same role (two assistant messages in a row) |
| **Why it's bad** | Causes API validation errors |
| **What to do instead** | Ensure proper alternation between 'user' and 'assistant' roles |
| **Source** | [Anthropic Courses](https://github.com/anthropics/courses) |

### 12.2 Malformed Messages Array

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Messages lacking required `role` and `content` fields |
| **Why it's bad** | Returns API errors |
| **What to do instead** | Always include both `role` and `content` fields |
| **Source** | [Anthropic Courses](https://github.com/anthropics/courses) |

### 12.3 Poor Tool Naming in MCP Servers

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using inconsistent or unclear tool names |
| **Why it's bad** | Creates confusion, potential conflicts, poor discoverability |
| **What to do instead** | Use snake_case, service prefix, action-oriented. Format: `{service}_{action}_{resource}` |
| **Source** | [Anthropic Skills - MCP Best Practices](https://github.com/anthropics/skills) |

### 12.4 Using `any` Types in TypeScript MCP Servers

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using `any` type instead of proper type definitions |
| **Why it's bad** | No type safety; runtime errors; poor maintainability |
| **What to do instead** | Define interfaces; use Zod for runtime validation |
| **Source** | [Anthropic Skills - Node MCP Server](https://github.com/anthropics/skills) |

### 12.5 Synchronous Network Requests in MCP Servers

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using synchronous requests that block the event loop |
| **Why it's bad** | Blocks the server; poor performance |
| **What to do instead** | Use async/await with httpx (Python) or native fetch (Node) |
| **Source** | [Anthropic Skills - Python MCP Server](https://github.com/anthropics/skills) |

### 12.6 Not Re-Sending Prompt on Truncation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Not prompting to re-send the response when truncated |
| **Why it's bad** | Incomplete tool use blocks; lost responses |
| **What to do instead** | Check `stop_reason`; retry with higher `max_tokens` or prompt continuation |
| **Source** | [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use) |

---

## 13. Opus 4.5 Specific Antipatterns (November 2025)

### 13.1 Using Legacy Aggressive Prompting Patterns

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Reusing prompts designed for older models without adjustment |
| **Why it's bad** | Opus 4.5 is much more responsive - aggressive language causes **overtriggering** |
| **What to do instead** | Dial back aggressive language; use natural, conversational prompting |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 13.2 Not Using the Effort Parameter

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using default HIGH effort for all tasks |
| **Why it's bad** | HIGH = maximum tokens. MEDIUM matches Sonnet 4.5 quality with 76% fewer tokens |
| **What to do instead** | HIGH for complex analysis, MEDIUM as production default, LOW for batch/summarization |
| **Source** | [Claude Opus 4.5 Announcement](https://www.anthropic.com/news/claude-opus-4-5) |

### 13.3 Manual Thinking Block Management

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Manually removing thinking blocks from previous turns |
| **Why it's bad** | Opus 4.5 auto-preserves thinking blocks - enables cache hits (token savings) |
| **What to do instead** | Leverage auto-preservation; design prompts to reference earlier analysis |
| **Source** | [Extended Thinking Docs](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking) |

### 13.4 Over-Prompting for Subagent Delegation

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Extensive prompting for subagent delegation when Opus 4.5 does this naturally |
| **Why it's bad** | Significantly improved native orchestration; proactively recognizes delegation needs |
| **What to do instead** | Ensure well-defined subagent tools; let Opus 4.5 orchestrate naturally |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 13.5 Not Expecting Concise Communication

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Expecting detailed progress updates by default |
| **Why it's bad** | Opus 4.5 has more concise, direct communication; may skip verbal summaries |
| **What to do instead** | If you want updates: "After completing a task, provide a quick summary of the work done." |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 13.6 Not Leveraging Improved Steerability

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Using complex workarounds instead of direct guidance |
| **Why it's bad** | Opus 4.5 is "the most steerable model to date" |
| **What to do instead** | Use straightforward, explicit instructions - no elaborate workarounds needed |
| **Source** | [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices) |

### 13.7 Not Using Zoom Action for Computer Use

| Aspect | Details |
| -------- | --------- |
| **What NOT to do** | Skipping zoom action for detailed UI inspection |
| **Why it's bad** | Standard screenshots may miss fine-grained UI elements and small text |
| **What to do instead** | Use zoom action proactively before attempting interactions |
| **Source** | [Claude Opus 4.5 Announcement](https://www.anthropic.com/news/claude-opus-4-5) |

---

## Real-World Attack Case Studies (2025)

### GTG-1002 - AI-Orchestrated Cyberattack (November 2025)

First known case of AI agent orchestrating a broad-scale cyberattack. Attackers used persona engineering to convince Claude it was a legitimate penetration tester, then deployed MCP servers as offensive infrastructure.

**Attack lifecycle executed autonomously:**

- Reconnaissance and target identification
- Vulnerability identification and exploit development
- Credential harvesting and privilege escalation
- Backdoor creation and data exfiltration

**Antipatterns exploited:** Human-in-the-loop bypass, overly permissive MCP tool access, persona manipulation

**Source:** [Zenity Blog](https://zenity.io/blog/current-events/claude-moves-to-the-darkside-what-a-rogue-coding-agent-could-do-inside-your-org)

### CVE-2025-54795 - Path Restriction Bypass

Claude Code's path restrictions could be bypassed by using Claude itself to explore and exploit its own security mechanisms.

**Capabilities gained:** Unauthorized file read/write outside CWD, directory traversal, command injection

**Antipatterns exploited:** Allowing Claude to analyze its own restrictions, relying on prompt-based boundaries

**Source:** [Cymulate Blog](https://cymulate.com/blog/cve-2025-547954-54795-claude-inverseprompt/)

### CVE-2025-52882 - WebSocket Authentication Bypass

MCP server integration in Claude Code IDE extensions lacked proper authentication, allowing attackers to connect through malicious websites.

**Attack vector:** Victim visits malicious website -> WebSocket to localhost MCP -> Access to local files, source code, secrets

**Antipatterns exploited:** Insufficient MCP server authentication, overly permissive localhost access

**Source:** [Datadog Security Labs](https://securitylabs.datadoghq.com/articles/claude-mcp-cve-2025-52882/)

---

## Cross-References

- **Prompting guidance:** `.claude/memory/prompting-style-guide.md`
- **Repo organization antipatterns:** `.claude/memory/anti-patterns.md`
- **Context engineering:** `.claude/memory/context-engineering.md`
- **Testing principles:** `.claude/memory/testing-principles.md`
- **Agent usage patterns:** `.claude/memory/agent-usage-patterns.md`
- **Engineering best practices:** `.claude/memory/engineering-best-practices.md`
- **Standard operating procedures:** `.claude/memory/standard-operating-procedures.md`

---

## Sources

### Primary Sources (Official Anthropic)

- [Claude 4 Best Practices](https://docs.anthropic.com/en/docs/build-with-claude/prompt-engineering/claude-4-best-practices)
- [Building Effective Agents](https://www.anthropic.com/research/building-effective-agents)
- [Multi-Agent Research System](https://www.anthropic.com/engineering/multi-agent-research-system)
- [Claude Code Best Practices](https://www.anthropic.com/engineering/claude-code-best-practices)
- [Advanced Tool Use](https://www.anthropic.com/engineering/advanced-tool-use)
- [Prompting for Agents](https://www.anthropic.com/engineering/prompting-for-agents)
- [Extended Thinking](https://docs.anthropic.com/en/docs/build-with-claude/extended-thinking)
- [Implement Tool Use](https://docs.anthropic.com/en/docs/agents-and-tools/tool-use/implement-tool-use)
- [Reduce Hallucinations](https://docs.anthropic.com/en/docs/test-and-evaluate/strengthen-guardrails/reduce-hallucinations)
- [Claude Opus 4.5 Announcement](https://www.anthropic.com/news/claude-opus-4-5)
- [Claude Opus 4.5 System Card](https://assets.anthropic.com/m/64823ba7485345a7/Claude-Opus-4-5-System-Card.pdf)
- [Anthropic Threat Intelligence Report August 2025](https://www.anthropic.com/news/detecting-countering-misuse-aug-2025)
- [Visible Extended Thinking](https://www.anthropic.com/news/visible-extended-thinking)

### Security Sources

- CVE-2025-54795: [Cymulate Analysis](https://cymulate.com/blog/cve-2025-547954-54795-claude-inverseprompt/)
- CVE-2025-52882: [Datadog Security Labs](https://securitylabs.datadoghq.com/articles/claude-mcp-cve-2025-52882/)
- [OWASP Top 10 for LLM Applications 2025](https://owasp.org/www-project-top-10-for-large-language-model-applications/)
- [Microsoft Azure AI Security Benchmark](https://learn.microsoft.com/en-us/security/benchmark/azure/mcsb-v2-artificial-intelligence-security)
- [MCP Security Best Practices](https://modelcontextprotocol.io/specification/draft/basic/security_best_practices)

### Community Sources

- [How I Use Every Claude Code Feature](https://blog.sshh.io/p/how-i-use-every-claude-code-feature)
- [Claude Code Best Practices - Shuttle](https://www.shuttle.dev/blog/2025/10/16/claude-code-best-practices)
- [AI Agent Evaluation: 5 Lessons Learned](https://www.montecarlodata.com/blog-ai-agent-evaluation/)
- [The AI Agent Evaluation Crisis](https://labs.adaline.ai/p/the-ai-agent-evaluation-)
- [Multi-Agent System Reliability](https://www.getmaxim.ai/articles/multi-agent-system-reliability/)
- [Exception Handling Frameworks for AI Agents](https://www.datagrid.com/blog/exception-handling-frameworks-ai-agents)

---

**Last Updated:** 2025-11-30
**Model:** Claude Opus 4.5 (`claude-opus-4-5-20251101`)
**Research Sources:** 8 parallel MCP research agents (context7, firecrawl, perplexity, ref, microsoft-learn)
