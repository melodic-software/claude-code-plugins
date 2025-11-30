---
name: gemini-config-management
description: Expert guide for configuring Google Gemini CLI. Covers global vs project settings (settings.json), Trusted Folders security model, Policy Engine, environment variables, and scope precedence. Delegates to gemini-cli-docs for official references.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Configuration Management

## 🚨 MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before providing ANY response about Gemini configuration:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific configuration topic (e.g., "trusted folders", "settings.json schema")
> 3. **BASE** all responses EXCLUSIVELY on official documentation loaded
>
> **Skipping this step results in outdated or incorrect information.**

## Overview

Expert skill for managing Google Gemini CLI configuration. It handles the hierarchy of settings, security policies, and environment overrides.

## When to Use This Skill

**Keywords:** gemini config, settings.json, .gemini folder, trusted folders, folder trust, security policy, environment variables, scope, global settings, project settings, telemetry, ui configuration

**Use this skill when:**

- Configuring `settings.json` (Global `~/.gemini/settings.json` or Project `.gemini/settings.json`)
- Managing **Trusted Folders** (`security.folderTrust.enabled`)
- Setting up **Policy Engine** rules
- Configuring **UI & Telemetry** (mouse support, sticky headers, disable telemetry)
- Troubleshooting configuration precedence (User > Project > Default)
- Configuring proxy settings or network behaviors

## Configuration Scopes

Gemini CLI uses a cascading configuration system:

1.  **Global Scope:** `~/.gemini/settings.json` (User-wide defaults)
2.  **Project Scope:** `.gemini/settings.json` (Per-project overrides)
3.  **Environment Variables:** `GEMINI_*` (Runtime overrides)

## Trusted Folders Security

The **Trusted Folders** feature is a critical security boundary.

*   **Enabled via:** `"security.folderTrust.enabled": true` in `settings.json`.
*   **States:**
    *   **Trusted:** Full access (MCP, extensions, shell execution).
    *   **Untrusted:** Restricted "Safe Mode" (No shell, no MCP, read-only).
*   **Storage:** Decisions saved in `~/.gemini/trustedFolders.json`.

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
| :--- | :--- |
| **Settings Schema** | `settings.json schema`, `configuration options` |
| **Trusted Folders** | `trusted folders`, `folder trust`, `safe mode` |
| **Policy Engine** | `policy engine`, `execution policies`, `allow list` |
| **Network** | `proxy settings`, `network configuration`, `timeout` |
| **UI & Telemetry** | `telemetry configuration`, `mouse support`, `sticky headers` |

## Quick Decision Tree

**What do you want to do?**

1.  **Enable Trusted Folders** -> Query `gemini-cli-docs`: "enable trusted folders settings"
2.  **Edit Global Settings** -> Query `gemini-cli-docs`: "global settings.json location"
3.  **Override for Project** -> Query `gemini-cli-docs`: "project specific settings .gemini"
4.  **Configure UI/Telemetry** -> Query `gemini-cli-docs`: "telemetry configuration settings"
5.  **Debug Config** -> Query `gemini-cli-docs`: "debug configuration loading"

## Troubleshooting

**Issue:** "My settings aren't applying."
**Check:** Is the folder trusted? If Untrusted, project settings are IGNORED.
**Action:** Run `/permissions` to check trust status.

## References

**Official Documentation:**
Query `gemini-cli-docs` for:
- "configuration"
- "trusted folders"
- "policy engine"
