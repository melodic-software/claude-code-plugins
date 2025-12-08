# MCP Server Usage Patterns

**Token Budget:** ~650 tokens | **Load Type:** Context-dependent (load when MCP guidance needed)

Use appropriate MCP servers to access current, official documentation before planning or making changes. Use MCP servers proactively.

## Technology-Specific MCP Selection

### Microsoft Technologies

**Use `microsoft-learn` MCP** for: .NET, C#, F#, Visual Basic, Azure, PowerShell, Windows, Visual Studio, VS Code, GitHub, TypeScript, npm

- Fetch official Microsoft Learn documentation before Microsoft-related work
- Validate current best practices, API changes, breaking changes
- Check version compatibility and migration guides
- Examples: "Fetch latest .NET 9 documentation", "Get Azure Functions best practices", "Check PowerShell 7.4 changes"

### Third-Party Libraries & GitHub Repositories

**Use `context7` + `ref` MCPs** for: any npm package, PyPI package, NuGet package, open-source project

- `context7`: Analyze GitHub repo structure, README, documentation, recent changes
- `ref`: Fetch official API reference documentation
- Understand current versions, breaking changes, deprecations
- Examples: "Analyze react GitHub repo for Hooks best practices", "Fetch lodash API reference", "Check pandas latest documentation"

### General Enrichment & Cross-Validation

**Use `perplexity` + `firecrawl` MCPs** for: best practices, recent developments, community knowledge

- `perplexity`: AI-powered search with citations for recent changes, comparisons, troubleshooting
- `firecrawl`: Extract documentation from websites not covered by other MCPs
- Use for cross-referencing, validation, finding edge cases
- Examples: "Search for recent Node.js 22 breaking changes", "Compare webpack vs vite performance", "Fetch Tailwind CSS v4 docs"

## Execution Pattern

Use MCP servers **before** writing code/docs, not after.

**Workflow:** Research (MCP) -> Plan -> Implement -> Verify

## Selection Guide

When uncertain which MCP to use:

1. Start with technology-specific MCP (microsoft-learn for MS tech, context7/ref for libraries)
2. Enrich with perplexity/firecrawl if needed

## Related Documentation

- `.claude/memory/claude-code-ecosystem.md` - Claude Code ecosystem and skill references
- `.claude/memory/natural-language-guidance.md` - Prompting guidance for MCP queries

**Last Updated:** 2025-12-06
