---
name: security-meta
description: Central authority for Claude Code security. Covers security fundamentals, permission-based architecture, prompt injection protection, sandboxing (filesystem and network isolation), IAM (Identity and Access Management), authentication methods, credential management, MCP security, cloud execution security, IDE security, enterprise managed policies, permission modes, tool-specific permission rules, and security best practices. Assists with configuring security settings, understanding protections, and troubleshooting security issues. Delegates 100% to official-docs skill for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Security Meta Skill

## 🚨 MANDATORY: Invoke official-docs First

> **STOP - Before providing ANY response about Claude Code security:**
>
> 1. **INVOKE** `official-docs` skill
> 2. **QUERY** for the user's specific topic
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

### Verification Checkpoint

Before responding, verify:

- [ ] Did I invoke official-docs skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

If ANY checkbox is unchecked, STOP and invoke official-docs first.

---

## Overview

Central authority for Claude Code security. This skill uses **100% delegation to official-docs** - it contains NO duplicated official documentation.

**Architecture:** Pure delegation with keyword registry. All official documentation is accessed via official-docs skill queries.

## When to Use This Skill

**Keywords:** security, sandboxing, permissions, IAM, authentication, credential management, prompt injection, trust verification, enterprise policies, permission modes, sandbox configuration, filesystem isolation, network isolation, bubblewrap, Seatbelt, OAuth, API keys, MCP security, cloud execution security, IDE security, VS Code security, JetBrains security, devcontainer security, security best practices

**Use this skill when:**

- Understanding Claude Code security architecture
- Configuring permission rules (allow, ask, deny)
- Setting up sandboxing (filesystem and network isolation)
- Managing authentication methods
- Configuring credential storage
- Protecting against prompt injection
- Setting up enterprise security policies
- Understanding MCP security considerations
- Configuring cloud execution security
- IDE security considerations
- Following security best practices

## Keyword Registry for official-docs Queries

Use these keywords when querying official-docs skill for official documentation:

### Security Fundamentals

| Topic | Keywords |
| ----- | -------- |
| Overview | "security", "security safeguards", "security foundation" |
| Permission Architecture | "permission-based architecture", "read-only permissions" |
| Built-in Protections | "built-in protections", "write access restriction" |
| User Responsibility | "user responsibility", "reviewing proposed code" |

### Prompt Injection Protection

| Topic | Keywords |
| ----- | -------- |
| Core Protections | "prompt injection", "core protections", "input sanitization" |
| Command Blocklist | "command blocklist", "curl wget blocked" |
| Privacy Safeguards | "privacy safeguards", "data retention" |
| Additional Safeguards | "network request approval", "isolated context windows", "trust verification" |

### Sandboxing

| Topic | Keywords |
| ----- | -------- |
| Overview | "sandboxing", "sandboxed bash tool", "/sandbox command" |
| Filesystem Isolation | "filesystem isolation", "sandbox filesystem", "blocked access" |
| Network Isolation | "network isolation", "sandbox network", "domain restrictions" |
| OS Enforcement | "bubblewrap", "Seatbelt", "OS-level enforcement" |
| Configuration | "sandbox configuration", "sandbox settings" |
| Escape Hatch | "dangerouslyDisableSandbox", "allowUnsandboxedCommands" |
| Security Limitations | "sandbox security limitations", "domain fronting" |

### IAM and Permissions

| Topic | Keywords |
| ----- | -------- |
| Authentication | "authentication methods", "Claude API authentication", "cloud provider authentication" |
| Permission System | "permission system", "tiered permissions", "approval required" |
| Permission Configuration | "configuring permissions", "/permissions command" |
| Permission Modes | "permission modes", "defaultMode", "acceptEdits", "bypassPermissions" |
| Tool Rules | "tool-specific permission rules", "Bash permissions", "Read Edit permissions" |
| MCP Permissions | "MCP permissions", "mcp__server", "MCP tool permissions" |
| Working Directories | "working directories", "additionalDirectories", "--add-dir" |

### Credential Management

| Topic | Keywords |
| ----- | -------- |
| Storage | "credential management", "API key storage", "macOS Keychain" |
| Custom Scripts | "apiKeyHelper", "credential scripts" |
| Refresh Intervals | "credential refresh", "CLAUDE_CODE_API_KEY_HELPER_TTL_MS" |

### Enterprise Security

| Topic | Keywords |
| ----- | -------- |
| Managed Policies | "enterprise managed policy", "managed-settings.json" |
| Settings Precedence | "settings precedence", "enterprise policies precedence" |
| Policy Paths | "enterprise policy paths", "policy file locations" |

### MCP Security

| Topic | Keywords |
| ----- | -------- |
| MCP Security | "MCP security", "MCP server trust", "MCP audit" |

### Cloud and IDE Security

| Topic | Keywords |
| ----- | -------- |
| Cloud Execution | "cloud execution security", "isolated virtual machines", "network access controls" |
| VS Code Security | "VS Code security", "IDE security VS Code" |
| JetBrains Security | "JetBrains security", "IDE security JetBrains" |
| DevContainer Security | "devcontainer security", "container security" |

### Security Best Practices

| Topic | Keywords |
| ----- | -------- |
| Sensitive Code | "working with sensitive code", "security best practices" |
| Team Security | "team security", "organizational standards" |
| Reporting Issues | "reporting security issues", "HackerOne", "vulnerability disclosure" |

## Quick Decision Tree

**What do you want to do?**

1. **Understand security architecture** -> Query official-docs: "security", "permission-based architecture"
2. **Configure permissions** -> Query official-docs: "configuring permissions", "/permissions command"
3. **Set up sandboxing** -> Query official-docs: "sandboxing", "/sandbox command"
4. **Configure filesystem isolation** -> Query official-docs: "filesystem isolation", "sandbox filesystem"
5. **Configure network isolation** -> Query official-docs: "network isolation", "domain restrictions"
6. **Understand permission modes** -> Query official-docs: "permission modes", "defaultMode"
7. **Set tool-specific rules** -> Query official-docs: "tool-specific permission rules"
8. **Manage credentials** -> Query official-docs: "credential management", "apiKeyHelper"
9. **Set up enterprise policies** -> Query official-docs: "enterprise managed policy", "managed-settings.json"
10. **Protect against prompt injection** -> Query official-docs: "prompt injection", "core protections"
11. **Configure MCP security** -> Query official-docs: "MCP security", "MCP permissions"
12. **Follow best practices** -> Query official-docs: "security best practices", "team security"

## Topic Coverage

### Security Architecture

- Permission-based architecture (read-only by default)
- Built-in protections (sandboxed bash, write restrictions)
- Prompt fatigue mitigation
- Accept Edits mode
- User responsibility model

### Prompt Injection Protections

- Core protection mechanisms
- Context-aware analysis
- Input sanitization
- Command blocklist (curl, wget)
- Privacy safeguards and data retention
- Network request approval
- Isolated context windows
- Trust verification
- Command injection detection
- Fail-closed matching

### Sandbox System

- Sandboxed bash tool overview
- /sandbox slash command
- Why sandboxing matters (approval fatigue, productivity, autonomy)
- OS-level enforcement (bubblewrap on Linux, Seatbelt on macOS)
- dangerouslyDisableSandbox escape hatch
- allowUnsandboxedCommands configuration
- Open source sandbox runtime

### Filesystem Isolation Configuration

- Default writes behavior
- Default read behavior
- Blocked access patterns
- Custom allowed and denied paths
- Protection against critical file modification

### Network Isolation Configuration

- Domain restrictions
- User confirmation for new domains
- Custom proxy support
- Comprehensive coverage for subprocesses
- httpProxyPort and socksProxyPort settings

### Permission System Details

- Tiered permission model (read-only, bash, file modification)
- Allow rules (auto-approve)
- Ask rules (confirmation required)
- Deny rules (prevent usage)
- Rule precedence (deny > ask > allow)
- Permission rule format

### Permission Modes

- default mode (standard prompting)
- acceptEdits mode (auto-accept file edits)
- plan mode (analyze only, no modifications)
- bypassPermissions mode (skip all prompts)

### Tool Permission Rules

- Bash permission patterns (exact match, prefix match)
- Bash pattern limitations
- Read and Edit gitignore-style patterns
- Path pattern types (absolute, home, relative)
- WebFetch domain permissions
- MCP tool permissions (no wildcards)
- Hooks for custom permission evaluation

### Credential Management System

- Secure storage (macOS Keychain)
- Supported authentication types
- apiKeyHelper custom scripts
- Credential refresh intervals

### Enterprise Policy Configuration

- managed-settings.json locations (macOS, Linux, Windows)
- Settings precedence hierarchy
- Unoverridable organizational policies

### Cloud Execution Security Features

- Isolated virtual machines
- Network access controls
- Credential protection
- Branch restrictions
- Audit logging
- Automatic cleanup

### IDE Security Considerations

- VS Code extension security
- JetBrains plugin security
- IDE-specific security contexts

### DevContainer Security

- Container isolation benefits
- Security features in devcontainer setup
- Integration with sandboxing

## Delegation Patterns

### Standard Query Pattern

```text
User asks: "How do I configure sandboxing?"

1. Invoke official-docs skill
2. Use keywords: "sandboxing", "/sandbox command", "sandbox configuration"
3. Load official documentation
4. Provide guidance based EXCLUSIVELY on official docs
```

### Multi-Topic Query Pattern

```text
User asks: "I want enterprise security with sandboxing and strict permissions"

1. Invoke official-docs skill with multiple queries:
   - "enterprise managed policy", "managed-settings.json"
   - "sandboxing", "sandbox configuration"
   - "configuring permissions", "deny rules"
2. Synthesize guidance from official documentation
```

### Troubleshooting Pattern

```text
User reports: "My sandbox keeps blocking commands I need"

1. Invoke official-docs skill
2. Use keywords: "sandbox configuration", "excludedCommands", "allowUnsandboxedCommands"
3. Check official docs for configuration options
4. Guide user through configuration based on official docs
```

## Troubleshooting Quick Reference

| Issue | Keywords for official-docs |
| ----- | ------------------------ |
| Permissions too restrictive | "configuring permissions", "allow rules" |
| Permissions too permissive | "permission modes", "deny rules" |
| Sandbox blocking legitimate commands | "excludedCommands", "allowUnsandboxedCommands" |
| Network requests blocked | "network isolation", "domain restrictions" |
| Credential issues | "credential management", "apiKeyHelper" |
| Enterprise policy not applied | "enterprise managed policy", "settings precedence" |
| MCP tools blocked | "MCP permissions", "mcp__server" |
| Prompt injection concerns | "prompt injection", "core protections" |

## Repository-Specific Notes

This repository follows security best practices including:

- **Permission configuration**: Defined in `.claude/settings.json`
- **Hooks for validation**: Custom hooks in `.claude/hooks/` for additional security enforcement
- **No sensitive data**: Repository contains only documentation, no secrets or credentials

When working with this repository, follow the security patterns documented in official Claude Code documentation.

## References

**Official Documentation (via official-docs skill):**

- Primary: "security", "sandboxing", "iam" documentation
- Related: "settings", "hooks", "devcontainer", "legal-and-compliance"

**Repository-Specific:**

- Security settings: `.claude/settings.json`
- Validation hooks: `.claude/hooks/`

## Version History

- **v1.0.0** (2025-11-26): Initial release
  - Pure delegation architecture
  - Comprehensive keyword registry
  - Quick decision tree
  - Topic coverage for all security features
  - Troubleshooting quick reference

---

## Last Updated

**Date:** 2025-11-28
**Model:** claude-opus-4-5-20251101
