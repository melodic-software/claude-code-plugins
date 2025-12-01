# Claude Code Topics Index

This file contains comprehensive topic listings with keywords for all Claude Code features. Use this to find keywords for `docs-management` queries or navigate the Claude Code documentation.

**Important:** Always invoke `docs-management` skill with these keywords to get official documentation. This index provides navigation, not authoritative content.

**Note:** Specialized skills (e.g., `hook-management`, `skill-development`) are provided by the `claude-ecosystem` plugin. Install with: `/plugin install claude-ecosystem@claude-code-plugins`

## Core Features

### Hooks

**Delegation:** Invoke `hook-management` skill.

**Keywords:** hooks, hook events, PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, SessionStart, SessionEnd, PreCompact, Notification, PermissionRequest, hook configuration, hook matchers, hook input output, hook decision control, hook environment variables, command-based hooks, prompt-based hooks, hook JSON output, hook exit codes, hook timing, block-at-submit, block-at-write, auto-fix hooks

**Topics:** Hook event types and lifecycle, Hook configuration (settings.json), Matcher patterns, Decision control (allow, deny, block, ask), JSON output schemas, Exit codes and blocking behavior, Environment variables, Command-based vs prompt-based hooks, MCP tools integration, Plugin hooks, Hook timing philosophy - see `.claude/memory/hook-timing-philosophy.md`

### Memory (CLAUDE.md Static Memory)

**Delegation:** Invoke `memory-management` skill.

**Topics:** Static memory system implementation, Memory hierarchy (enterprise, project, user, local), Import syntax (`@.claude/memory/file.md`), Memory commands (`/init`, `/memory`, `#` shortcut), Agent SDK integration (settingSources)

### Skills

**Delegation:** Invoke `skill-development` skill.

**Keywords:** skills, agent skills, progressive disclosure, YAML frontmatter, skill structure, allowed-tools, skill creation, skill name description, skill locations, skill supporting files, skill validation, skill best practices, skill patterns, skill development

**Topics:** Agent skills overview and architecture, Progressive disclosure pattern, YAML frontmatter requirements, Skill structure and organization, Tool restrictions (allowed-tools), Skill locations (personal, project, plugin), Skill creation workflow, Skill validation and quality checks, Best practices and patterns, Skill composition

### Subagents

**Delegation:** Invoke `subagent-development` skill.

**Keywords:** subagents, sub-agents, agent configuration, agent YAML frontmatter, agent tools, agent model selection, automatic delegation, agent SDK subagents, agent CLI, /agents command, agent file format, agent file locations, agent priority resolution

**Topics:** Subagent overview and benefits, Agent file format and YAML frontmatter, Tool access configuration, Model selection (inherit, sonnet, haiku, opus), Automatic vs explicit invocation, Agent lifecycle and resumption, CLI usage (`/agents` command), Agent SDK integration, Priority resolution, Built-in agents

### Slash Commands

**Delegation:** Invoke `command-development` skill.

**Keywords:** slash commands, command creation, command patterns, command vs skills, slash command configuration

**Topics:** Slash command overview, Creating custom slash commands, Command vs skills decision guide, Command patterns and best practices

### Plugins

**Delegation:** Invoke `plugin-development` skill.

**Keywords:** plugins, plugin creation, plugin distribution, plugin marketplaces, plugin hooks, plugin skills

**Topics:** Plugin overview and architecture, Creating plugins, Plugin distribution and marketplaces, Plugin hooks integration, Plugin skills reference, Plugin configuration

### MCP (Model Context Protocol)

**Delegation:** Invoke `mcp-integration` skill.

**Keywords:** MCP, MCP servers, MCP tools, MCP connector, remote MCP servers, MCP integration

**Topics:** MCP overview and architecture, MCP servers configuration, MCP tools integration, MCP connector setup, Remote MCP servers, MCP with hooks

### Settings

**Delegation:** Invoke `settings-management` skill.

**Keywords:** settings, configuration files, settings hierarchy, environment variables, settings.json, HTTPS_PROXY, timeout, apiKeyHelper, session management, --resume, --continue, debugging

**Topics:** Settings file locations and hierarchy, Configuration options, Environment variables, Settings precedence, Session configuration and debugging - see `.claude/memory/session-configuration.md`

### Model Configuration

**Keywords:** model configuration, model selection, model settings, extended thinking, prompt caching

**Topics:** Model selection (sonnet, haiku, opus), Extended thinking configuration, Prompt caching settings, Model-specific configurations

### Output Styles

**Delegation:** Invoke `output-customization` skill.

**Keywords:** output styles, controlling output format, output behavior

**Topics:** Output format configuration, Controlling output behavior, Output style options

### Statusline

**Delegation:** Invoke `status-line-customization` skill.

**Keywords:** statusline, terminal status line, status line configuration

**Topics:** Status line configuration, Status line customization

### Terminal Config

**Keywords:** terminal config, terminal configuration, terminal settings

**Topics:** Terminal configuration options, Terminal settings and customization

## Workflows & Modes

### Common Workflows

**Keywords:** common workflows, plan mode, verification, resume previous work, custom workflows

**Topics:** Plan mode usage, Verification workflows, Resuming previous work, Custom workflow patterns

### Interactive Mode

**Keywords:** interactive mode, interactive session, interactive behavior

**Topics:** Interactive session behavior, Interactive mode configuration

### Headless Mode

**Keywords:** headless mode, non-interactive execution, headless

**Topics:** Headless execution, Non-interactive mode configuration

### Checkpointing

**Keywords:** checkpointing, save work state, resume work state

**Topics:** Checkpointing overview, Saving and resuming work state

## Integration & Deployment

### CLI Reference

**Keywords:** CLI reference, command-line interface, CLI flags, CLI options

**Topics:** Command-line interface overview, CLI flags and options, CLI usage patterns

### Agent SDK

**Delegation:** Invoke `agent-sdk-development` skill.

**Keywords:** Agent SDK, TypeScript SDK, Python SDK, sessions, streaming vs single mode, custom tools, permissions, hosting, cost tracking, todo tracking, modifying system prompts, Agent SDK configuration

**Topics:** Agent SDK overview (TypeScript and Python), Sessions and session management, Streaming vs single mode, Custom tools implementation, Permissions configuration, Hosting and deployment, Cost tracking, Todo tracking, Modifying system prompts, SDK integration patterns

### GitHub Actions

**Keywords:** GitHub Actions, CI/CD integration, GitHub Actions patterns, PR-from-anywhere, ops log review, batch processing, issue triage, code review automation, headless mode

**Topics:** GitHub Actions integration, CI/CD patterns, Workflow examples, PR-from-anywhere pattern, Ops log review, Batch processing patterns - see `.claude/memory/github-actions-patterns.md`

### GitLab CI/CD

**Keywords:** GitLab CI/CD, GitLab integration, GitLab patterns

**Topics:** GitLab CI/CD integration, GitLab workflow patterns

### Third-Party Integrations

**Keywords:** Amazon Bedrock, Google Vertex AI, LLM Gateway, third-party integrations

**Topics:** Amazon Bedrock integration, Google Vertex AI integration, LLM Gateway configuration

### VS Code

**Keywords:** VS Code, VS Code integration, VS Code extension

**Topics:** VS Code integration, VS Code extension usage

### JetBrains

**Keywords:** JetBrains, JetBrains IDE, JetBrains integration

**Topics:** JetBrains IDE integration, JetBrains plugin usage

### DevContainer

**Keywords:** devcontainer, development container, container setup

**Topics:** DevContainer setup, Development container configuration

### Claude Code on the Web

**Keywords:** Claude Code on the web, cloud execution, network policy, container registries

**Topics:** Cloud execution overview, Network policy configuration, Container registries, Web-based execution patterns

## Security & Compliance

### Security

**Delegation:** Invoke `enterprise-security` skill.

**Keywords:** security, security best practices, sandboxing, IAM, security configuration

**Topics:** Security best practices, Sandboxing configuration, IAM, Security settings

### Sandboxing

**Keywords:** sandboxing, code execution isolation, sandbox configuration

**Topics:** Sandboxing overview, Code execution isolation, Sandbox configuration

### Network Config

**Keywords:** network config, network configuration, network policies

**Topics:** Network configuration, Network policies, Network settings

### Data Usage

**Keywords:** data usage, data handling, privacy, data configuration

**Topics:** Data handling and privacy, Data usage configuration, Privacy settings

### Legal and Compliance

**Keywords:** legal and compliance, compliance requirements

**Topics:** Compliance requirements, Legal considerations

## Monitoring & Costs

### Monitoring Usage

**Keywords:** monitoring usage, usage tracking, analytics, usage monitoring

**Topics:** Usage tracking, Analytics and monitoring, Usage reports

### Costs

**Keywords:** costs, cost management, cost optimization, pricing

**Topics:** Cost management, Cost optimization strategies, Pricing information

### Analytics

**Keywords:** analytics, Analytics API, Claude Code Analytics API

**Topics:** Analytics API usage, Claude Code Analytics API, Analytics configuration

## Advanced Topics

### Prompt Engineering

**Keywords:** prompt engineering, system prompts, chain-of-thought, extended thinking, multishot prompting, prompt templates, prompt improver, prompt generator, XML tags, prefill responses, prompt best practices

**Topics:** System prompts, Chain-of-thought prompting, Extended thinking tips, Multishot prompting, Prompt templates and variables, Prompt improver tool, Prompt generator, XML tags usage, Prefilling Claude's response, Prompt best practices

### Context Windows

**Keywords:** context windows, context management, long context tips, context window configuration

**Topics:** Context window overview, Context management strategies, Long context tips, Context window configuration

### Context Editing

**Keywords:** context editing, context manipulation, editing context

**Topics:** Context editing overview, Context manipulation techniques

### Streaming

**Keywords:** streaming, streaming responses, streaming configuration

**Topics:** Streaming overview, Streaming configuration, Streaming patterns

### Structured Outputs

**Keywords:** structured outputs, structured response formats, structured data

**Topics:** Structured outputs overview, Structured response formats, Structured data patterns

### Token Counting

**Keywords:** token counting, token usage, token optimization, token limits

**Topics:** Token counting and usage, Token optimization strategies, Token limits

### Files

**Keywords:** files, file handling, file operations, file management

**Topics:** File handling overview, File operations, File management patterns

### Vision

**Keywords:** vision, image processing, image analysis, vision capabilities

**Topics:** Vision capabilities, Image processing, Image analysis patterns

### PDF Support

**Keywords:** PDF support, PDF handling, PDF processing

**Topics:** PDF support overview, PDF handling patterns, PDF processing

### Embeddings

**Keywords:** embeddings, embedding generation, embeddings API

**Topics:** Embeddings overview, Embedding generation, Embeddings API usage

### Citations

**Keywords:** citations, citation handling, citation format

**Topics:** Citations overview, Citation handling, Citation formats

### Search Results

**Keywords:** search results, search integration, search API

**Topics:** Search results overview, Search integration patterns, Search API usage

### Multilingual Support

**Keywords:** multilingual support, internationalization, i18n, language support

**Topics:** Multilingual support overview, Internationalization patterns, Language support configuration

### Batch Processing

**Keywords:** batch processing, batch operations, batch API

**Topics:** Batch processing overview, Batch operations, Batch API usage

### Administration API

**Keywords:** Administration API, admin API, API keys, organization management, workspace management, user management

**Topics:** Administration API overview, API key management, Organization management, Workspace management, User management

## Tools

### Tool Use

**Keywords:** tool use, bash tool, code execution tool, computer use tool, text editor tool, web fetch tool, web search tool, memory tool, fine-grained tool streaming, token-efficient tool use, implementing tool use

**Topics:** Tool use overview, Bash tool, Code execution tool, Computer use tool, Text editor tool, Web fetch tool, Web search tool, Memory tool (API), Fine-grained tool streaming, Token-efficient tool use, Implementing custom tools

## Testing & Evaluation

### Testing

**Keywords:** testing, test development, eval tool, define success, test evaluation

**Topics:** Test development, Eval tool usage, Defining success criteria, Test evaluation patterns

### Guardrails

**Keywords:** guardrails, handle streaming refusals, increase consistency, keep in character, mitigate jailbreaks, reduce hallucinations, reduce latency, reduce prompt leak

**Topics:** Guardrails overview, Handling streaming refusals, Increasing consistency, Keeping Claude in character, Mitigating jailbreaks, Reducing hallucinations, Reducing latency, Reducing prompt leak

---

**Last Updated:** 2025-11-30
