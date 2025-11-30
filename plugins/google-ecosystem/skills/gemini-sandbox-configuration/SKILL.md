---
name: gemini-sandbox-configuration
description: Central authority for Gemini CLI sandboxing and isolation. Covers sandbox methods (Docker, Podman, macOS Seatbelt), profiles, configuration, and security boundaries. Delegates 100% to gemini-cli-docs for official documentation.
allowed-tools: Read, Glob, Grep, Skill
---

# Gemini Sandbox Configuration

## MANDATORY: Invoke gemini-cli-docs First

> **STOP - Before providing ANY response about Gemini sandboxing:**
>
> 1. **INVOKE** `gemini-cli-docs` skill
> 2. **QUERY** for the specific sandbox topic
> 3. **BASE** responses EXCLUSIVELY on official documentation loaded

## Overview

Meta-skill for configuring Gemini CLI's sandbox isolation. Sandboxing isolates potentially dangerous operations from your host system.

## When to Use This Skill

**Keywords:** sandbox, docker, podman, seatbelt, isolation, container, safe execution, -s flag, GEMINI_SANDBOX

**Use this skill when:**

- Enabling sandboxing for the first time
- Choosing between sandbox methods
- Configuring Seatbelt profiles (macOS)
- Troubleshooting sandbox issues
- Understanding security boundaries

## Sandbox Methods

| Method | Platform | Isolation |
|--------|----------|-----------|
| Docker | All | Full container |
| Podman | All | Rootless container |
| Seatbelt | macOS | Process sandbox |

## Configuration

### Enable via Command Flag

```bash
gemini -s -p "command"
```

### Enable via Environment

```bash
export GEMINI_SANDBOX=true
gemini -p "command"

# Or specify method
export GEMINI_SANDBOX=docker
export GEMINI_SANDBOX=podman
export GEMINI_SANDBOX=sandbox-exec
```

### Enable via Settings

Add to `settings.json`:

```json
{
  "tools": {
    "sandbox": true
  }
}
```

Or specify method:

```json
{
  "tools": {
    "sandbox": "docker"
  }
}
```

## Seatbelt Profiles (macOS)

Set via `SEATBELT_PROFILE` environment variable:

| Profile | Writes | Network |
|---------|--------|---------|
| `permissive-open` (default) | Restricted | Allowed |
| `permissive-closed` | Restricted | Blocked |
| `permissive-proxied` | Restricted | Via proxy |
| `restrictive-open` | Strict | Allowed |
| `restrictive-closed` | Strict | Blocked |

## Custom Sandbox Flags

For container-based sandboxing, inject custom flags:

```bash
export SANDBOX_FLAGS="--security-opt label=disable"
```

## Keyword Registry (Delegates to gemini-cli-docs)

| Topic | Query Keywords |
|-------|----------------|
| Enable | `enable sandbox`, `-s flag`, `GEMINI_SANDBOX` |
| Docker | `docker sandbox`, `container isolation` |
| Podman | `podman sandbox`, `rootless container` |
| Seatbelt | `seatbelt profiles`, `sandbox-exec macos` |
| Custom flags | `SANDBOX_FLAGS`, `custom docker flags` |
| Troubleshooting | `sandbox troubleshooting`, `operation not permitted` |

## Quick Decision Tree

**What do you want to do?**

1. **Enable sandbox quickly** -> Use `-s` flag
2. **Make it persistent** -> Add to settings.json
3. **Use Docker** -> Set `GEMINI_SANDBOX=docker`
4. **Use stricter macOS** -> Set `SEATBELT_PROFILE=restrictive-closed`
5. **Debug issues** -> Use `DEBUG=1 gemini -s`

## Troubleshooting

| Error | Cause | Solution |
|-------|-------|----------|
| "Operation not permitted" | Sandbox restriction | Expected behavior |
| "Docker not found" | Docker not running | Start Docker daemon |
| Network blocked | Restrictive profile | Use `permissive-open` |
| Missing commands | Not in sandbox image | Add to custom Dockerfile |

## Security Notes

- Sandboxing reduces but doesn't eliminate all risks
- Use most restrictive profile that allows your work
- GUI applications may not work in sandbox
- Container overhead is minimal after first build

## Verification Checkpoint

- [ ] Did I invoke gemini-cli-docs skill?
- [ ] Did official documentation load?
- [ ] Is my response based EXCLUSIVELY on official docs?

## References

Query `gemini-cli-docs` for official documentation on:

- "sandbox"
- "seatbelt profiles"
- "docker sandbox"
