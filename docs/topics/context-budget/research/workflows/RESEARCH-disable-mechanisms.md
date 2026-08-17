---
topic: claude-code-workflows-context-cost-and-disable
section: disable-mechanisms
abstract: Five supported full-disable mechanisms exist — a /config toggle, disableWorkflows in settings, CLAUDE_CODE_DISABLE_WORKFLOWS, managed settings, and the admin page — plus plan gating; the env var uses truthiness not literal 1, and disableWorkflows is not a managed-precedence exception.
claims:
  - claim: "The documented per-user disable mechanisms are exactly three: the /config 'Dynamic workflows' toggle, `\"disableWorkflows\": true` in settings.json, and `CLAUDE_CODE_DISABLE_WORKFLOWS=1`."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "local: claude.exe v2.1.232, predicate Fkr()/jD()"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
  - claim: "`CLAUDE_CODE_DISABLE_WORKFLOWS` disables on ANY truthy value, not only the literal `1` the docs show, and it is OR-ed with the setting so no settings scope can re-enable workflows against it."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local: claude.exe v2.1.232, `function Fkr(){return Y.CLAUDE_CODE_DISABLE_WORKFLOWS||U5()?.settings.disableWorkflows===!0}`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
  - claim: "Organization-wide disabling is `\"disableWorkflows\": true` in managed settings or the toggle on the Claude Code admin settings page; disableWorkflows is NOT in the exceptions-to-managed-settings-precedence table, so a managed value cannot be overridden by any lower scope."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/server-managed-settings"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
  - claim: "Workflows are plan-gated: available on all paid plans, Anthropic API access, Bedrock, Google Cloud's Agent Platform and Microsoft Foundry, and on Pro they are off until turned on in /config."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/feature-availability"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "local: claude.exe v2.1.232, `jD()` reading `{available, defaultOn}` per host plus `gs(\"allow_workflows\")`"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
produced_by: phase-2-and-3
---

# Every supported disable mechanism, its exact spelling, scope, and precedence

All URLs fetched **2026-08-17**. Tier 0 from the installed **v2.1.232** binary.

## The prompt's spellings were correct — both were verified, not assumed

The dispatch asked me not to trust the names it supplied. Both check out against current docs:

- **`disableWorkflows`** — [settings](https://code.claude.com/docs/en/settings), verbatim:
  > "**Default**: `false`. Disable [dynamic workflows](/docs/en/workflows#turn-workflows-off) and the
  > bundled workflow commands. Equivalent to setting `CLAUDE_CODE_DISABLE_WORKFLOWS` to `1`"
- **`CLAUDE_CODE_DISABLE_WORKFLOWS`** — [env-vars](https://code.claude.com/docs/en/env-vars), verbatim:
  > "Set to `1` to disable [workflows](/docs/en/workflows#turn-workflows-off). Equivalent to the
  > [`disableWorkflows`](/docs/en/settings#available-settings) setting"

**Methodology warning worth passing to the skill author.** A `WebFetch` of each of those two pages
answered that neither key exists. Both answers were wrong — an artifact of truncation on pages that
are 334 KB and 404 KB of markdown. The keys were found only after downloading the pages with `curl`
and grepping them on disk. **A skill that inventories settings by asking a summarizer to read the
settings page will silently miss keys.** Enumerate from the downloaded page, not from a summary.

## The canonical list — the docs' own "Turn workflows off" section

Verbatim from <https://code.claude.com/docs/en/workflows> (fetched 2026-08-17):

> Workflows are available in the CLI, the Desktop app, the IDE extensions, non-interactive mode with
> `claude -p`, and the Agent SDK. **The same disable settings apply on every surface.**
>
> To turn workflows off for yourself:
>
> - Toggle Dynamic workflows off in `/config`. Persists across sessions.
> - Set `"disableWorkflows": true` in `~/.claude/settings.json`. Persists across sessions.
> - Set `CLAUDE_CODE_DISABLE_WORKFLOWS=1`. Read at startup, so it applies wherever you set it.
>
> To turn workflows off for your whole organization, set `"disableWorkflows": true` in
> [managed settings](/docs/en/server-managed-settings), or use the toggle on the
> [Claude Code admin settings](https://claude.ai/admin-settings/claude-code) page.
>
> When workflows are disabled, the bundled workflow commands are unavailable, the `ultracode`
> keyword no longer triggers a run, and `ultracode` is removed from the `/effort` menu.

## Full mechanism table with scope and precedence

| # | Mechanism | Exact spelling | Scope | Beaten by |
|---|---|---|---|---|
| 1 | `/config` toggle | **Dynamic workflows** (writes the `enableWorkflows` key — see below) | User | Mechanisms 2–5 |
| 2 | Settings key | `"disableWorkflows": true` | Any settings file: user / project / local / `--settings` / managed | Nothing, once set at the winning scope; managed beats all |
| 3 | Environment variable | `CLAUDE_CODE_DISABLE_WORKFLOWS` | Process environment | **Nothing** — OR-ed ahead of settings (see below) |
| 4 | Managed settings | `"disableWorkflows": true` in a managed source | Organization | Nothing — not a precedence exception |
| 5 | Admin page toggle | <https://claude.ai/admin-settings/claude-code> | Organization | Delivered as server-managed settings |
| 6 | Plan / provider gate | not user-settable | Account & host | n/a — gates before all of the above |

### Mechanism 3 has two behaviors the docs understate

Tier 0, `claude.exe` v2.1.232:

```js
function Fkr(){ return Y.CLAUDE_CODE_DISABLE_WORKFLOWS || U5()?.settings.disableWorkflows === !0 }
```

Two consequences a trimming skill should encode:

1. **Truthiness, not equality.** The setting arm tests `=== true` strictly, but the env arm is a bare
   truthiness check. `CLAUDE_CODE_DISABLE_WORKFLOWS=0` and `=false` are **non-empty strings and
   therefore disable workflows**, contrary to what "Set to `1`" implies. Never write a
   "disabled" value other than by unsetting the variable.
2. **OR semantics defeat precedence.** Because the env var is OR-ed with the setting, the ordinary
   settings hierarchy never gets to re-enable workflows against it. `"disableWorkflows": false` in
   managed settings does **not** override the env var.

### Precedence for mechanisms 2, 4 and 5

`disableWorkflows` is an ordinary settings key, so it follows the standard ladder from
[settings](https://code.claude.com/docs/en/settings) (fetched 2026-08-17), highest first:

1. **Managed** — "can't be overridden by any other scope, apart from the exceptions to managed
   settings precedence"
2. Command line arguments
3. Local (`.claude/settings.local.json`)
4. Project (`.claude/settings.json`)
5. User (`~/.claude/settings.json`)

**I checked the exceptions table directly, and `disableWorkflows` is not in it.** The only keys
listed are `disableClaudeAiConnectors`, `isolatePeerMachines`, `remoteControlAtStartup`, and
`crossSessionInbound`. So a managed `disableWorkflows` is absolute — no user, project, local, or
`--settings` value can re-enable workflows. Within the managed tier itself, sources do not merge:
server-managed settings are checked first, then endpoint-managed (MDM / `managed-settings.json`), and
"if server-managed settings deliver any keys at all, other endpoint-managed settings are ignored"
([server-managed-settings](https://code.claude.com/docs/en/server-managed-settings), fetched
2026-08-17).

## An undocumented sixth key: `enableWorkflows`

The `/config` toggle does not write `disableWorkflows`. Tier 0 shows a separate key:

```js
function jD(){
  if(Fkr())                     return !1;   // disableWorkflows / env var
  if(!uBo())                    return !1;   // gs("allow_workflows") entitlement gate
  let {available:e, defaultOn:t} = B4s();    // resolved per host/plan
  if(!e)                        return !1;
  return U5()?.settings.enableWorkflows ?? t // per-user opt-in, else plan default
}
```

and the settings schema in the same binary describes it as:

> `enableWorkflows` — "Enable or disable the Workflows feature for this user. Unset = default by plan
> once the feature is available."

**`enableWorkflows: false` is a real, working disable that is absent from the settings reference.**
I grepped the full downloaded settings page and found no `enableWorkflows` row. Treat it as
**Tier 0-only and undocumented**: it is the mechanism behind the documented `/config` toggle and the
Pro opt-in, so it is not a secret, but a skill should prefer `disableWorkflows` for anything it
writes, since undocumented keys can be renamed without a changelog entry.

Note the precedence *within* `jD()`: `Fkr()` is checked first, so `disableWorkflows` and the env var
beat `enableWorkflows: true`. You cannot re-enable workflows with `enableWorkflows` once either
documented disable is set.

## Adjacent keys that are NOT full disables

A trimming skill must not treat these as substitutes — none of them removes the `Workflow` tool.

| Key | What it actually does | Source |
|---|---|---|
| `workflowKeywordTriggerEnabled` | **Default `true`.** Only stops the `ultracode` keyword from triggering a run. Verbatim: "The `ultracode` effort setting, `/workflows`, and saved workflow commands are unaffected." | [settings](https://code.claude.com/docs/en/settings) |
| `disableBundledSkills` | Removes bundled **skills and workflows** (i.e. `/deep-research`) — the bundled *commands*, not the `Workflow` tool. Equivalent to `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS`. | [settings](https://code.claude.com/docs/en/settings) |
| `workflowSizeGuideline` | Advisory agent-count guideline (`unrestricted`/`small`/`medium`/`large`, default `medium`). Not a cap, not a disable. v2.1.219+. | [settings](https://code.claude.com/docs/en/settings), [workflows](https://code.claude.com/docs/en/workflows) |
| `CLAUDE_CODE_WORKFLOW_PREFIX_STAGGER_MS` | Fan-out prompt-cache stagger, default `5000`; `0` disables the hold. Performance only. | [env-vars](https://code.claude.com/docs/en/env-vars), [workflows](https://code.claude.com/docs/en/workflows) |

## Plan and provider gating

From [workflows](https://code.claude.com/docs/en/workflows): available "on all paid plans, with
Anthropic API access, and on Amazon Bedrock, Google Cloud's Agent Platform, and Microsoft Foundry",
and "On Pro, turn them on from the Dynamic workflows row in `/config`."
[feature-availability](https://code.claude.com/docs/en/feature-availability) lists Workflows among
features that "work on every provider". Tier 0 corroborates the shape: `jD()` consults an
`allow_workflows` entitlement gate and a per-host `{available, defaultOn}` resolution, so on a plan
where `defaultOn` is false (Pro) the tool is absent until the user opts in — **which means a Pro user
already pays no Workflow-tool context cost by default.**
