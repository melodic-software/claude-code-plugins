# Claude Code Ecosystem Reference

## CRITICAL REQUIREMENT: Official Documentation First

**MANDATORY RULE FOR ALL CLAUDE CODE TOPICS:**

1. **ALWAYS use the `docs-management` skill** to access official canonical documentation BEFORE answering questions, making changes, or providing guidance about ANY Claude Code topic
2. **NEVER make assumptions** or rely on memory - official documentation is the single source of truth
3. **ALL changes/modifications MUST be driven 100% by official canonical documentation** - this includes creating examples, providing configuration guidance, implementing features, writing documentation, and troubleshooting
4. **If official documentation is unclear or missing**, explicitly state this rather than guessing
5. **Verify against official docs** before claiming any feature exists or works a certain way

This applies to ALL Claude Code topics: hooks, memory, skills, subagents, MCP, plugins, settings, model config, workflows, SDK, and every other feature.

## Enforcement: Layered Defense

Specialized skills provide keyword registries and navigation, but **ALL authoritative content comes from docs-management**:

| Layer | Mechanism | Purpose |
| ----- | --------- | ------- |
| 1 | UserPromptSubmit Hook | Early warning at prompt time |
| 2 | MANDATORY Section in Skills | Direct enforcement when skill loads |
| 3 | CLAUDE.md Rule | Global backstop |

### Verification Checkpoint (MANDATORY)

Before responding to ANY Claude Code topic after a specialized skill loads:

- [ ] Did I invoke docs-management skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

**If ANY checkbox is unchecked, STOP and invoke docs-management first.**

### Failure Mode to Avoid

**WRONG:** Skill loads → Answer from keyword registry → Never invoke docs-management

**CORRECT:** Skill loads → Read keyword guidance → Invoke docs-management → Load official docs → Answer based on official docs

## Available Skills

Skills are provided by the **`claude-ecosystem` plugin** from the `claude-code-plugins` marketplace.

**Installation:** `/plugin install claude-ecosystem@claude-code-plugins`

| Topic | Skill | Purpose |
| ----- | ----- | ------- |
| Hooks | `hook-management` | Hook events, configuration, matchers, decision control |
| Memory | `memory-management` | CLAUDE.md, import syntax, hierarchy, commands |
| Skills | `skill-development` | Skill creation, YAML frontmatter, best practices |
| Subagents | `subagent-development` | Agent files, tool access, model selection |
| Slash Commands | `command-development` | Command creation, patterns, vs skills |
| Plugins | `plugin-development` | Plugin creation, distribution, hooks |
| MCP | `mcp-integration` | MCP servers, tools, connectors |
| Settings | `settings-management` | Settings files, hierarchy, environment vars |
| Output Styles | `output-customization` | Built-in styles, custom styles, switching |
| Status Line | `status-line-customization` | Custom status lines, JSON input, scripts |
| Security | `enterprise-security` | Security best practices, sandboxing, permissions |
| Permissions | `permission-management` | Permission rules, modes, tool access |
| Sandboxing | `sandbox-configuration` | Sandboxed bash, isolation, escape hatches |
| Agent SDK | `agent-sdk-development` | TypeScript/Python SDK, sessions, tools |
| Documentation | `docs-management` | Official Claude Code documentation access |

## Delegation Pattern

When a user asks about any Claude Code topic:

1. **Check for specialized skill**: Look up the topic in the Available Skills table above
2. **If specialized skill exists**: Invoke it first - it provides optimized keyword registries and decision trees
3. **Skill delegates to docs-management**: The specialized skill will guide efficient `docs-management` queries
4. **For topics without specialized skills**: Invoke `docs-management` directly with keywords from the topics index
5. **Base all guidance EXCLUSIVELY on official documentation** - no assumptions or memory

**Pattern Summary:**

- Topics WITH specialized skills: `User Question → Specialized Skill → docs-management → Official Docs`
- Topics WITHOUT specialized skills: `User Question → docs-management → Official Docs`

## Topics Index

For comprehensive topic listings with keywords, see `.claude/memory/claude-code-topics-index.md`. Load when you need to look up specific features, find keywords for docs-management queries, or navigate the Claude Code documentation.

---

**Last Updated:** 2025-11-30
