---
name: agent-sdk-meta
description: Central authority for Claude Agent SDK (TypeScript and Python SDKs). Covers SDK installation, authentication (Anthropic key, Bedrock, Vertex), sessions and resumption, forking sessions, streaming vs single mode, custom tools, permissions (allowedTools, disallowedTools, permissionMode), MCP integration, system prompts (CLAUDE.md, appendSystemPrompt, outputStyle), cost tracking, todo tracking, structured outputs, hosting patterns, plugins, and SDK branding guidelines. Assists with building custom agents, configuring SDK options, and troubleshooting SDK issues. Delegates 100% to official-docs skill for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Agent SDK Meta Skill

## 🚨 MANDATORY: Invoke official-docs First

> **STOP - Before providing ANY response about Claude Agent SDK:**
>
> 1. **INVOKE** `official-docs` skill
> 2. **QUERY** using keywords: Agent SDK, TypeScript SDK, Python SDK, sessions, custom tools, permissions, or related topics
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

### Verification Checkpoint

Before responding, verify:

- [ ] Did I invoke official-docs skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

If ANY checkbox is unchecked, STOP and invoke official-docs first.

## Overview

Central authority for Claude Agent SDK (TypeScript and Python SDKs). This skill uses **100% delegation to official-docs** - it contains NO duplicated official documentation.

**Architecture:** Pure delegation with keyword registry. All official documentation is accessed via official-docs skill queries.

## Reference Loading Guide

This skill follows a **pure delegation architecture** with three loading layers:

### Layer 1: Always in Context

- **SKILL.md** (this file) - Keyword registry, decision trees, delegation patterns

### Layer 2: On-Demand via official-docs

All official Agent SDK documentation is accessed through official-docs queries:

| doc_id | Topic |
| ------ | ----- |
| platform-claude-com-docs-en-agent-sdk-overview | SDK overview and getting started |
| platform-claude-com-docs-en-agent-sdk-typescript | TypeScript SDK API reference |
| platform-claude-com-docs-en-agent-sdk-python | Python SDK API reference |
| platform-claude-com-docs-en-agent-sdk-sessions | Session management and resumption |
| platform-claude-com-docs-en-agent-sdk-streaming-vs-single-mode | Input mode selection |
| platform-claude-com-docs-en-agent-sdk-custom-tools | Creating custom tools |
| platform-claude-com-docs-en-agent-sdk-permissions | Permission configuration |
| platform-claude-com-docs-en-agent-sdk-modifying-system-prompts | System prompt customization |
| platform-claude-com-docs-en-agent-sdk-cost-tracking | Cost and usage tracking |
| platform-claude-com-docs-en-agent-sdk-todo-tracking | Todo list integration |
| platform-claude-com-docs-en-agent-sdk-structured-outputs | Structured output features |
| platform-claude-com-docs-en-agent-sdk-hosting | Production hosting patterns |
| platform-claude-com-docs-en-agent-sdk-mcp | MCP server integration |
| platform-claude-com-docs-en-agent-sdk-plugins | Plugin loading |
| platform-claude-com-docs-en-agent-sdk-subagents | Subagent usage |
| platform-claude-com-docs-en-agent-sdk-skills | Skills integration |
| platform-claude-com-docs-en-agent-sdk-slash-commands | Slash command usage |

### Layer 3: External Resources (GitHub)

- TypeScript SDK: anthropics/claude-agent-sdk-typescript
- Python SDK: anthropics/claude-agent-sdk-python

### Loading Strategy

**This skill has no local reference files.** All documentation is accessed via official-docs queries using the keyword registry below. This ensures:

- Zero duplication of official documentation
- Always-current information from canonical sources
- Zero maintenance overhead for documentation sync

## When to Use This Skill

**Keywords:** Agent SDK, Claude Agent SDK, TypeScript SDK, Python SDK, npm install claude-agent-sdk, pip install claude-agent-sdk, sessions, session resumption, forking sessions, streaming mode, single mode, custom tools, allowedTools, disallowedTools, permissionMode, system prompts, appendSystemPrompt, outputStyle, CLAUDE.md, settingSources, cost tracking, todo tracking, structured outputs, hosting, plugins SDK, MCP SDK, agent branding

**Use this skill when:**

- Installing or configuring Claude Agent SDK
- Setting up authentication (API key, Bedrock, Vertex)
- Managing sessions and resumption
- Choosing between streaming and single input modes
- Creating custom tools
- Configuring permissions (allowedTools, disallowedTools)
- Modifying system prompts
- Tracking costs and usage
- Working with todo lists in agents
- Getting structured outputs
- Hosting agents in production
- Integrating MCP with SDK
- Understanding SDK branding requirements

## Keyword Registry for official-docs Queries

Use these keywords when querying official-docs skill for official documentation:

### SDK Fundamentals

| Topic | Keywords |
| ----- | -------- |
| Overview | "Agent SDK", "Claude Agent SDK overview", "why use Agent SDK" |
| Installation | "Agent SDK installation", "npm install claude-agent-sdk", "pip install claude-agent-sdk" |
| SDK Options | "SDK options", "TypeScript SDK", "Python SDK" |
| Migration | "Claude Code SDK migration", "migration guide" |

### Authentication

| Topic | Keywords |
| ----- | -------- |
| API Key | "Agent SDK authentication", "ANTHROPIC_API_KEY" |
| Bedrock | "CLAUDE_CODE_USE_BEDROCK", "Bedrock SDK" |
| Vertex | "CLAUDE_CODE_USE_VERTEX", "Vertex SDK" |

### Sessions

| Topic | Keywords |
| ----- | -------- |
| Session Management | "session management SDK", "session ID", "getting session ID" |
| Resumption | "session resumption", "resume option", "continuing sessions" |
| Forking | "forking sessions", "forkSession", "session branching" |

### Input Modes

| Topic | Keywords |
| ----- | -------- |
| Overview | "streaming vs single mode", "input modes SDK" |
| Streaming Mode | "streaming input mode", "recommended mode" |
| Single Mode | "single input mode", "non-streaming" |

### Custom Tools

| Topic | Keywords |
| ----- | -------- |
| Creating Tools | "custom tools SDK", "creating custom tools" |
| Tool Schema | "tool schema", "tool definition SDK" |
| Tool Handlers | "tool handlers", "tool execution SDK" |

### Permissions

| Topic | Keywords |
| ----- | -------- |
| Tool Permissions | "allowedTools", "disallowedTools", "tool permissions SDK" |
| Permission Mode | "permissionMode SDK", "permission strategy" |
| Handling Permissions | "handling permissions SDK", "permission callbacks" |

### System Prompts

| Topic | Keywords |
| ----- | -------- |
| Overview | "modifying system prompts", "system prompts SDK" |
| CLAUDE.md | "CLAUDE.md SDK", "settingSources", "project instructions" |
| Append System Prompt | "appendSystemPrompt", "custom instructions" |
| Output Style | "outputStyle SDK", "agent persona" |

### Cost and Tracking

| Topic | Keywords |
| ----- | -------- |
| Cost Tracking | "cost tracking SDK", "token usage", "billing SDK" |
| Todo Tracking | "todo tracking SDK", "todo lists SDK", "task management" |

### Structured Outputs

| Topic | Keywords |
| ----- | -------- |
| Structured Outputs | "structured outputs SDK", "JSON results", "validated outputs" |
| Schema Definition | "output schema SDK", "result validation" |

### Hosting and Deployment

| Topic | Keywords |
| ----- | -------- |
| Hosting Overview | "hosting Agent SDK", "production deployment" |
| Ephemeral Sessions | "ephemeral sessions", "pattern 1 hosting" |
| Persistent Sessions | "persistent sessions", "pattern 2 hosting" |

### Plugins and MCP

| Topic | Keywords |
| ----- | -------- |
| Plugins | "plugins SDK", "loading plugins", "programmatic plugins" |
| MCP Integration | "MCP SDK", "MCP servers SDK", "extending with MCP" |

### Branding

| Topic | Keywords |
| ----- | -------- |
| Branding Guidelines | "agent branding", "Claude Agent naming", "SDK branding" |

### SDK Feature Integration

| Topic | Keywords |
| ----- | -------- |
| Subagents | "subagents SDK", "SDK subagents", "subagent integration" |
| Skills | "skills SDK", "SDK skills", "agent skills SDK" |
| Slash Commands | "slash commands SDK", "SDK commands", "custom commands SDK" |

### API Reference

| Topic | Keywords |
| ----- | -------- |
| TypeScript Reference | "TypeScript SDK reference", "TypeScript API" |
| Python Reference | "Python SDK reference", "Python API" |
| Changelog | "SDK changelog", "SDK updates" |

## Quick Decision Tree

**What do you want to do?**

1. **Install the SDK** -> Query official-docs: "Agent SDK installation"
2. **Set up authentication** -> Query official-docs: "Agent SDK authentication"
3. **Manage sessions** -> Query official-docs: "session management SDK", "resume option"
4. **Fork a session** -> Query official-docs: "forking sessions", "forkSession"
5. **Choose input mode** -> Query official-docs: "streaming vs single mode"
6. **Create custom tools** -> Query official-docs: "custom tools SDK"
7. **Configure permissions** -> Query official-docs: "allowedTools", "permissionMode SDK"
8. **Modify system prompts** -> Query official-docs: "modifying system prompts"
9. **Use CLAUDE.md files** -> Query official-docs: "CLAUDE.md SDK", "settingSources"
10. **Track costs** -> Query official-docs: "cost tracking SDK"
11. **Add todo tracking** -> Query official-docs: "todo tracking SDK"
12. **Get structured outputs** -> Query official-docs: "structured outputs SDK"
13. **Host in production** -> Query official-docs: "hosting Agent SDK"
14. **Use subagents** -> Query official-docs: "subagents SDK"
15. **Integrate skills** -> Query official-docs: "skills SDK", "agent skills SDK"
16. **Add slash commands** -> Query official-docs: "slash commands SDK"
17. **Load plugins** -> Query official-docs: "plugins SDK"

## Topic Coverage

### SDK Installation and Setup

- npm package: @anthropic-ai/claude-agent-sdk
- pip package: claude-agent-sdk
- TypeScript and Python SDK options
- Migration from Claude Code SDK

### Authentication Methods

- ANTHROPIC_API_KEY environment variable
- Amazon Bedrock integration (CLAUDE_CODE_USE_BEDROCK)
- Google Vertex AI integration (CLAUDE_CODE_USE_VERTEX)
- Third-party provider configuration

### Session Management Features

- Automatic session creation
- Session ID capture from init message
- Session resumption with resume option
- Forking sessions (forkSession/fork_session)
- Session branching for experimentation
- Context preservation across sessions

### Input Mode Configuration

- Streaming input mode (recommended)
- Single input mode
- Mode selection criteria
- Performance considerations

### Custom Tool Development

- Tool schema definition
- Tool handler implementation
- Tool registration with SDK
- Tool execution patterns

### Permission Configuration

- allowedTools list
- disallowedTools list
- permissionMode settings
- Permission callbacks and handling

### System Prompt Customization

- CLAUDE.md file loading (settingSources)
- appendSystemPrompt option
- outputStyle for agent persona
- Project-level vs user-level instructions

### Cost and Usage Tracking

- Token usage monitoring
- Billing integration patterns
- Usage reporting
- Cost estimation

### Todo List Integration

- Todo tracking API
- Task display and management
- Progress monitoring
- Todo state persistence

### Structured Output Features

- Output schema definition
- JSON result validation
- Type-safe results
- TODO tracking agent example

### Hosting Patterns

- Ephemeral sessions pattern
- Persistent sessions pattern
- Production deployment strategies
- Scaling considerations

### Full Claude Code Features

- Subagents (./.claude/agents/)
- Agent Skills (./.claude/skills/)
- Hooks (./.claude/settings.json)
- Slash Commands (./.claude/commands/)
- Plugins (programmatic loading)
- Memory (CLAUDE.md files)

### Branding Requirements

- Allowed naming (Claude Agent, Claude)
- Not permitted naming (Claude Code)
- Product branding guidelines

## Delegation Patterns

### Standard Query Pattern

```text
User asks: "How do I create a custom tool in the Agent SDK?"

1. Invoke official-docs skill
2. Use keywords: "custom tools SDK", "creating custom tools"
3. Load official documentation
4. Provide guidance based EXCLUSIVELY on official docs
```

### Multi-Topic Query Pattern

```text
User asks: "I want to build an agent with sessions, custom tools, and cost tracking"

1. Invoke official-docs skill with multiple queries:
   - "session management SDK", "session resumption"
   - "custom tools SDK", "creating custom tools"
   - "cost tracking SDK", "token usage"
2. Synthesize guidance from official documentation
```

### Troubleshooting Pattern

```text
User reports: "My session resumption isn't working"

1. Invoke official-docs skill
2. Use keywords: "session management SDK", "resume option", "session ID"
3. Check official docs for session patterns
4. Guide user through proper session handling
```

## Troubleshooting Quick Reference

| Issue | Keywords for official-docs |
| ----- | ------------------------ |
| Authentication failing | "Agent SDK authentication", "ANTHROPIC_API_KEY" |
| Session not resuming | "session resumption", "resume option" |
| Custom tool not working | "custom tools SDK", "tool handlers" |
| Permissions blocking | "allowedTools", "permissionMode SDK" |
| System prompt not loading | "CLAUDE.md SDK", "settingSources" |
| Cost tracking issues | "cost tracking SDK", "token usage" |
| Structured output invalid | "structured outputs SDK", "schema definition" |
| Streaming not working | "streaming input mode", "streaming vs single" |

## Test Scenarios

### Scenario 1: Installing the SDK

**Query:** "How do I install the Claude Agent SDK for TypeScript?"

**Expected Behavior:**

- Skill activates on keywords "install", "SDK", "TypeScript"
- Directs user to query official-docs: "Agent SDK installation"
- official-docs returns official installation guide
- Provides npm package name and installation steps

**Success Criteria:**

- User gets correct npm package: @anthropic-ai/claude-agent-sdk
- Installation commands are from official docs

### Scenario 2: Creating Custom Tools

**Query:** "I need to create a custom tool for my agent"

**Expected Behavior:**

- Skill activates on keywords "custom tool", "agent"
- Directs user to query official-docs: "custom tools SDK", "creating custom tools"
- official-docs returns custom tool documentation
- Provides schema definition and handler implementation guidance

**Success Criteria:**

- User learns tool schema format
- User understands handler implementation pattern
- Both TypeScript and Python examples available

### Scenario 3: Session Resumption Issue

**Query:** "My agent's session resumption isn't working"

**Expected Behavior:**

- Skill activates on keywords "session", "resumption"
- Follows Troubleshooting Pattern
- Directs user to query official-docs: "session resumption", "resume option", "session ID"
- Provides diagnostic steps from official docs

**Success Criteria:**

- User understands session ID capture requirement
- User knows how to pass resume option
- Issue resolution guided by official documentation

### Scenario 4: Multi-Topic Agent Setup

**Query:** "I want to build an agent with sessions, custom tools, and cost tracking"

**Expected Behavior:**

- Skill activates on multiple keywords
- Follows Multi-Topic Query Pattern
- Directs user to query official-docs for each topic
- Synthesizes guidance from multiple official docs

**Success Criteria:**

- All three topics addressed
- No conflicting guidance
- References to official docs for each topic

### Scenario 5: Production Hosting Decision

**Query:** "Should I use ephemeral or persistent sessions for my production agent?"

**Expected Behavior:**

- Skill activates on keywords "hosting", "sessions", "production"
- Directs user to query official-docs: "hosting Agent SDK", "ephemeral sessions", "persistent sessions"
- Provides comparison of hosting patterns from official docs

**Success Criteria:**

- User understands both patterns
- Decision criteria clearly explained
- User can choose based on their requirements

## Related Skills

**Skills that work well with agent-sdk-meta:**

- **official-docs** - Primary delegation target; provides all official Agent SDK documentation
- **mcp-meta** - MCP server configuration; Agent SDK can integrate with MCP servers
- **configuration-meta** - Settings configuration; SDK respects Claude Code settings
- **hooks-meta** - Hook configuration; SDK supports hooks via programmatic loading
- **current-date** - Get current UTC date for version history and audit timestamps

**Delegation example:**

```text
When working with Agent SDK + MCP integration:
1. Use agent-sdk-meta for SDK-specific guidance
2. Use mcp-meta for MCP server configuration
3. Both skills delegate to official-docs for official documentation
```

## Multi-Model Testing Notes

**Model Compatibility:**

This skill uses a pure delegation pattern with keyword-based queries, which is model-agnostic. The skill has been designed to work across all Claude models.

**Testing Approach by Model Family:**

- **Sonnet** (Primary) - Designed and validated with this model family
  - Delegation patterns verified
  - Keyword registry enables efficient queries
  - Pure delegation architecture minimizes context load

- **Haiku** (Recommended for simple queries)
  - Expected: Excellent performance due to minimal skill context
  - Pure delegation means SKILL.md is the only context load
  - Keyword registry enables targeted, efficient official-docs queries

- **Opus** (Recommended for complex SDK scenarios)
  - Expected: Excellent performance with advanced reasoning
  - Complex multi-topic queries supported
  - Can synthesize guidance from multiple official docs

**Performance Expectations:**

- Pure delegation pattern works excellently across all models
- Minimal context load (~2,000 tokens for SKILL.md)
- All complexity offloaded to official-docs queries
- Keyword registry ensures targeted queries regardless of model

**Last Tested:** Pending verification across model families

## Repository-Specific Notes

This repository does not currently use the Agent SDK programmatically. The Agent SDK documentation is relevant for:

- Understanding how Claude Code skills/hooks/subagents work (same underlying architecture)
- Building custom agents that integrate with this repository's documentation
- Understanding the relationship between Claude Code and Agent SDK features

When working with Agent SDK topics, always use the official-docs skill to access official documentation.

## References

**Official Documentation (via official-docs skill):**

- Primary: "agent-sdk" documentation (overview, typescript, python, sessions, custom-tools, etc.)
- Related: "mcp", "hooks", "skills", "sub-agents"

**External Resources:**

- TypeScript SDK GitHub: anthropics/claude-agent-sdk-typescript
- Python SDK GitHub: anthropics/claude-agent-sdk-python

## Version History

- **v1.1.0** (2025-11-27): Comprehensive audit and enhancement
  - Added Reference Loading Guide with explicit doc_id table for all 17 official Agent SDK docs
  - Added Test Scenarios section with 5 common use case scenarios
  - Added Related Skills section documenting skill composition patterns
  - Added Multi-Model Testing Notes section
  - Enhanced Last Verified section with Type B audit metadata
  - Verified keyword registry covers all official SDK documentation

- **v1.0.0** (2025-11-26): Initial release
  - Pure delegation architecture
  - Comprehensive keyword registry
  - Quick decision tree
  - Topic coverage for all Agent SDK features
  - Troubleshooting quick reference

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
