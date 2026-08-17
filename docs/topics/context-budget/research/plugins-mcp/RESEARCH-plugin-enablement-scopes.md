---
topic: plugins-mcp-context-budget
section: plugin-enablement-scopes
abstract: Plugins are enabled/disabled by the single key `enabledPlugins` at four scopes (managed/user/project/local) with precedence managed > CLI > local > project > user, falling back to the plugin's own `defaultEnabled`.
claims:
  - claim: "The only plugin enable/disable key is `enabledPlugins`, an object mapping `\"<plugin>@<marketplace>\"` to a boolean. There is no `disabledPlugins` key."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "local read of ~/.claude/settings.json (keys: enabledPlugins, extraKnownMarketplaces)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "binary-extracted /doctor bundled-skill prompt, 'Disable mechanics' block"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
  - claim: "Plugin enablement has four scopes, and settings precedence is Managed > CLI args > Local > Project > User."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/debug-your-config"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "claude plugin enable --help / claude plugin disable --help (v2.1.232)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
  - claim: "A plugin with no `enabledPlugins` entry at any scope falls back to its `defaultEnabled` value, which defaults to enabled."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/plugins-reference#default-enablement"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/settings#enabledplugins"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
produced_by: phase-1-phase-2
---

# Q1 — Every scope a plugin can be enabled/disabled at

All doc URLs below were fetched **2026-08-17** (verbatim `.md` page variants via `curl`, e.g.
`https://code.claude.com/docs/en/settings.md`). All CLI output is from the locally installed
**Claude Code v2.1.232**, run 2026-08-17.

## The key — exact spelling

There is exactly **one** key, and it is an object, not a list:

```json
{
  "enabledPlugins": {
    "formatter@acme-tools": true,
    "deployer@acme-tools": true,
    "analyzer@security-plugins": false
  }
}
```

> "Controls which plugins are enabled. Format: `"plugin-name@marketplace-name": true/false`. A
> plugin with no entry at any scope falls back to its `defaultEnabled` value."
> — <https://code.claude.com/docs/en/settings> (fetched 2026-08-17)

**There is no `disabledPlugins` key.** Disabling is `false` in the same map. Confirmed three ways:
the settings reference lists only `enabledPlugins`; the `/doctor` bundled skill's own disable
mechanics write `{"<name>@<marketplace>": false}`; and this machine's `~/.claude/settings.json`
carries only `enabledPlugins` and `extraKnownMarketplaces`.

The key is **marketplace-qualified**. `plugin-name` alone is not a valid entry — the `@marketplace`
suffix is part of the identity, which is also how managed-settings trust is scoped ("Trust is
granted by full `plugin@marketplace` ID, so a plugin with the same name from a different marketplace
stays blocked", <https://code.claude.com/docs/en/settings>, fetched 2026-08-17).

## The four scopes

| Scope | File | CLI flag | Notes |
|---|---|---|---|
| **Managed** | `managed-settings.json` (system path), plist / registry, or server-managed | *(not settable via `claude plugin`)* | Org policy. Blocks installation at all scopes and hides the plugin from the marketplace |
| **User** | `~/.claude/settings.json` | `-s user` | Personal, across all projects. `claude plugin install` default |
| **Project** | `.claude/settings.json` | `-s project` | Committed, shared with the team |
| **Local** | `.claude/settings.local.json` | `-s local` | Per-machine, gitignored when Claude Code saves a setting to it |

Source: <https://code.claude.com/docs/en/settings> ("Available scopes" and the `enabledPlugins`
**Scopes** list) and <https://code.claude.com/docs/en/plugins-reference#plugin-installation-scopes>,
both fetched 2026-08-17. The plugins-reference table names `managed` as a fourth *installation*
scope explicitly, described as "Managed plugins (read-only, update only)".

**Tier-0 confirmation of the settable scopes** (v2.1.232, run 2026-08-17):

```text
$ claude plugin disable --help
Options:
  -a, --all            Disable all enabled plugins
  -s, --scope <scope>  Installation scope: user, project, local (default: auto-detect)
```

Note the CLI exposes **only three** — `user`, `project`, `local`. `managed` is deliberately not
writable from the CLI. This is a real seam for a trimming skill: it can propose and apply changes at
three scopes and can only *report* a managed-scope pin.

## Precedence when scopes disagree

Verbatim from <https://code.claude.com/docs/en/settings> ("How scopes interact", fetched
2026-08-17):

> 1. **Managed** (highest): can't be overridden by any other scope, apart from the exceptions to
>    managed settings precedence
> 2. **Command line arguments**: temporary session overrides
> 3. **Local**: overrides project and user settings
> 4. **Project**: overrides user settings
> 5. **User** (lowest): applies when nothing else specifies the setting

The doc calls out the consequence that most often bites an operator trying to trim:

> "Project settings take precedence over user settings, so setting a plugin to `false` in
> `~/.claude/settings.json` does not disable a plugin that the project's `.claude/settings.json`
> enables. To opt out of a project-enabled plugin on your machine, set it to `false` in
> `.claude/settings.local.json` instead. Plugins force-enabled by managed settings cannot be
> disabled this way, since managed settings override local settings."
> — <https://code.claude.com/docs/en/settings> (fetched 2026-08-17)

The `/doctor` skill encodes exactly this rule in its own disable mechanics (Tier 0, binary-extracted
2026-08-17):

> "Settings precedence is user < project < local, so if the plugin is enabled by checked-in
> `.claude/settings.json`, the `false` must go in `.claude/settings.local.json` — a `false` in
> `~/.claude/settings.json` would be silently overridden."

**Design consequence for the skill:** writing `false` at the wrong scope is a silent no-op. Any
trimming skill must resolve *which* scope currently carries the `true` before choosing where to
write the `false`.

## The fallback when no scope has an entry

`defaultEnabled` in `plugin.json` (or in the plugin's marketplace entry, which takes precedence over
`plugin.json`):

> "`defaultEnabled` is the fallback when nothing else has decided the plugin's state. Two things
> take precedence over it: **The user's setting**: an entry for the plugin in `enabledPlugins` at
> any settings scope. Once written, it persists across plugin updates and reinstalls […] **A
> dependency requirement**: when a plugin is required by another one that is active, Claude Code
> writes `true` for it at install or enable time."
> — <https://code.claude.com/docs/en/plugins-reference#default-enablement> (fetched 2026-08-17)

`defaultEnabled: false` requires v2.1.154 or later; earlier versions ignore the field and enable on
install.

**Dependency interaction (a trap for a trimming skill):** disabling a plugin that another active
plugin depends on is not a simple `false` — Claude Code writes `true` for required plugins at
install/enable time, giving them an explicit setting. See
<https://code.claude.com/docs/en/plugin-dependencies> (fetched 2026-08-17), which routes managed
force-enablement through `enabledPlugins` in managed settings.

## Managed scope, precisely

Managed settings are the top tier and are further split: **server-managed settings and
endpoint-managed settings both occupy the highest tier**
(<https://code.claude.com/docs/en/server-managed-settings#settings-precedence>, fetched
2026-08-17). Within managed delivery, `managed-settings.json` merges first as the base and drop-in
`*.json` files merge alphabetically on top, with later files overriding scalars and deep-merging
objects (<https://code.claude.com/docs/en/settings>, fetched 2026-08-17). So two managed drop-ins
disagreeing about one plugin resolves alphabetically, not by specificity.

## What I could NOT verify

- **Whether `enabledPlugins` is deep-merged across scopes or replaced whole.** The doc states
  scalar override and object deep-merge *within the managed drop-in directory*, and states
  per-setting precedence across scopes, but I found no sentence stating explicitly that a
  project-scope `enabledPlugins` containing plugin A leaves a user-scope entry for plugin B intact.
  Behaviour strongly implies per-key merge (the "set it to `false` in `.claude/settings.local.json`
  instead" advice only works under per-key merge), but that is inference, **not a sourced claim**.
  Sources checked: `settings.md`, `plugins-reference.md`, `plugin-dependencies.md`,
  `plugin-marketplaces.md`. Unchecked: the `agent-sdk/*` pages, and the running binary's merge code.
