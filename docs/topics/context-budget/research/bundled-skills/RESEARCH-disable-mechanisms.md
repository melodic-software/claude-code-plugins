---
topic: bundled-skills
section: disable-mechanisms
abstract: Five supported mechanisms exist — disableBundledSkills, CLAUDE_CODE_DISABLE_BUNDLED_SKILLS, per-skill skillOverrides, Skill-tool permission deny rules, and name-shadowing — and individual bundled skills CAN be disabled, so it is not all-or-nothing.
claims:
  - claim: "disableBundledSkills is a boolean settings.json key that removes bundled skills and workflows entirely and hides built-in slash commands from the model, leaving plugin/.claude skills unaffected."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local binary v2.1.232 zod schema .describe() text for disableBundledSkills"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — 2.1.169"
        tier: 1
        pool: "Anthropic (upstream changelog)"
  - claim: "CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 is the exact env-var equivalent; the resolver reads the env var first and the setting second."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local binary v2.1.232: O9(e){return Y.CLAUDE_CODE_DISABLE_BUNDLED_SKILLS||(e??Go()).disableBundledSkills===!0}"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/env-vars.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — 2.1.169"
        tier: 1
        pool: "Anthropic (upstream changelog)"
  - claim: "Individual bundled skills CAN be disabled via a skillOverrides entry; the resolver consults skillOverrides for bundled skills and short-circuits only for plugin skills."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local binary v2.1.232: rVe(e) — returns 'on' when e.source==='plugin'; otherwise returns the skillOverrides value for bundled skills"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/skills.md — 'To hide it, set the DISABLE_DOCTOR_COMMAND environment variable or a skillOverrides entry of \"doctor\": \"off\"'"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md — 2.1.129"
        tier: 1
        pool: "Anthropic (upstream changelog)"
  - claim: "/doctor is exempt from disableBundledSkills — it is the sole kill-switch survivor — and needs DISABLE_DOCTOR_COMMAND or skillOverrides to hide."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local binary v2.1.232: survivesBundledKillSwitch:!0 occurs exactly once, on the doctor registration"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/skills.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/env-vars.md — DISABLE_DOCTOR_COMMAND"
        tier: 1
        pool: "Anthropic (docs)"
  - claim: "The Skill tool accepts permission rules: bare `Skill` denies all skills, `Skill(name)` exact and `Skill(name *)` prefix deny/allow individual ones."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/skills.md §Restrict Claude's skill access"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local binary v2.1.232: L1s(e,t,r){if(e!=='Skill')return; ... return t.skill} — extracts the skill name for rule matching"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/permissions.md"
        tier: 1
        pool: "Anthropic (docs)"
produced_by: phase-2+phase-3
---

# Every supported way to disable bundled skills

Exact spellings verified against current docs **and** the shipped v2.1.232 binary, both
2026-08-17. Case is significant in all of them.

## Answer to Q3 — the mechanisms that exist

### 1. `disableBundledSkills` — settings.json, wholesale

```json
{ "disableBundledSkills": true }
```

Type: boolean. Verbatim documentation:

> "Set to `true` to disable the [skills](/docs/en/skills) and workflows included with Claude Code:
> bundled skills and workflows are removed entirely, while built-in commands like `/init` stay
> typable but are hidden from the model. `/doctor` stays typable like the built-in commands; hide
> it with [`DISABLE_DOCTOR_COMMAND`](/docs/en/env-vars) instead. Skills from plugins,
> `.claude/skills/`, and `.claude/commands/` are unaffected. Equivalent to setting
> `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` to `1`"
> — <https://code.claude.com/docs/en/settings.md>, fetched 2026-08-17

Added in **v2.1.169**: "Added a `disableBundledSkills` setting and
`CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` environment variable to hide bundled skills, workflows, and
built-in slash commands from the model"
(<https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>, fetched 2026-08-17).

**Note the asymmetry, which matters for a trim tool:** bundled skills are *removed entirely*
(their listing cost goes to zero), but built-in slash commands are only *hidden from the model*
while staying typable. Tier 0 confirms: `getBundledSkills` filters the registry down to
kill-switch survivors, whereas built-in prompt commands are merely forced to
`user-invocable-only`.

### 2. `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` — env var, wholesale

```bash
CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1 claude
```

Tier-0 resolver from the binary:

```js
function O9(e){ return Y.CLAUDE_CODE_DISABLE_BUNDLED_SKILLS || (e ?? Go()).disableBundledSkills === !0 }
```

Two behaviours worth knowing: the **env var is checked first** and is a plain truthiness test, so
any non-empty value (not just `1`) enables it and it **cannot be overridden back off by
settings.json**; the setting requires a strict `=== true`.

### 3. `skillOverrides` — settings.json, per-skill. **This is the individual lever.**

```json
{ "skillOverrides": { "dataviz": "off", "code-review": "name-only" } }
```

Four states, exact spellings (docs table, <https://code.claude.com/docs/en/skills.md>, fetched
2026-08-17):

| Value | Listed to Claude | In `/` menu |
|---|---|---|
| `"on"` | Name and description | Yes |
| `"name-only"` | **Name only** | Yes |
| `"user-invocable-only"` | Hidden | Yes |
| `"off"` | Hidden | Hidden |

Absent = `"on"`. Written by the `/skills` menu into `.claude/settings.local.json` (highlight a
skill, `Space` cycles states, `Enter` saves). Became functional in **v2.1.129**.

**For the caller's trim tool, `"name-only"` is the precision instrument**: it keeps the skill
invocable while cutting its always-loaded cost from `name+4+desc` down to `name+2` characters. The
docs recommend exactly this use: "To free budget for other skills, set low-priority entries to
`\"name-only\"` in `skillOverrides` so they list without a description."

### 4. Permission deny rules on the Skill tool — per-skill or wholesale

From <https://code.claude.com/docs/en/skills.md> §"Restrict Claude's skill access", fetched
2026-08-17:

> **Disable all skills** by denying the Skill tool in `/permissions`:
>
> ```
> Skill
> ```
>
> **Allow or deny specific skills** using permission rules:
>
> ```
> Skill(commit)
> Skill(review-pr *)
> Skill(deploy *)
> ```
>
> "Permission syntax: `Skill(name)` for exact match, `Skill(name *)` for prefix match with any
> arguments."

The same section notes: "A few built-in commands are also available through the Skill tool,
including `/init` and `/security-review`. Other built-in commands such as `/compact` are not."

**Caveat the caller must not miss:** these rules govern *invocation*, and I found **no first-party
statement that a Skill deny rule removes the skill's description from the listing**. The listing
size is computed by the budget path from `skillOverrides` state, not from permission rules
(Tier 0: `rVe` reads `skillOverrides`; the budget's collapse set is keyed on that). A secondary
source claims bare tool names strip definitions from the payload while scoped rules do not — that
source is **egress-blocked from this environment and unverified** (see Gaps). **Treat "deny rules
shrink the listing" as unverified; use `skillOverrides` for size.**

### 5. Name shadowing — per-skill, no settings edit

A user or project skill with the same name replaces the bundled one. Corroborated by the upstream
changelog at **v2.1.233**: "Fixed bundled skill aliases like `/checkup` and `/review` reporting
'Unknown command' … when a user or project skill shadows the bundled skill". The binary carries
`shadowedBundledSkills` and `dropShadowedBundledSkills` (Tier 0). The skills doc documents the same
for `/verify`: a recorded `.claude/skills/verify/SKILL.md` "replaces the bundled `/verify`".
This substitutes cost rather than removing it.

### 6. Targeted env vars for specific bundled skills

Present in the binary's env table (Tier 0) — only the first is documented in env-vars.md:

| Env var | Effect | Doc status |
|---|---|---|
| `DISABLE_DOCTOR_COMMAND` | "Set to `1` to hide the `/doctor` setup checkup skill and its `/checkup` alias." | **Documented** (env-vars.md) |
| `CLAUDE_CODE_DISABLE_CLAUDE_API_SKILL` | presumed to disable `/claude-api` | **Undocumented** — inferred from the name only, behaviour NOT verified |
| `CLAUDE_CODE_DISABLE_CLAUDE_CODE_SKILL` | presumed to disable `/claude-code-docs` | **Undocumented** — inferred from the name only, behaviour NOT verified |
| `CLAUDE_CODE_DISABLE_POLICY_SKILLS` | presumed to disable policy-pushed skills | **Undocumented** — inferred from the name only, behaviour NOT verified |

The last three are Tier-0 *existence* evidence with **no verified semantics**. Do not build on them.

### 7. `--disable-slash-commands` — CLI flag, broadest

`claude --help` (Tier 0, v2.1.232) documents it as, verbatim: **"Disable all skills"**. Broader
than `disableBundledSkills` — it is not bundled-specific and takes user/project/plugin skills with
it.

## What does NOT exist

- **No `/config` path.** I searched the commands reference and the settings docs; `/config` is not
  documented as exposing `disableBundledSkills` or `skillOverrides`. The **`/skills` menu** is the
  interactive surface, and it writes `skillOverrides` to `.claude/settings.local.json`. Sources
  checked: commands.md, settings.md, skills.md (all fetched 2026-08-17). Sources left unchecked:
  the live interactive `/config` TUI (not runnable in this non-interactive session).
- **No plugin-level disable for bundled skills.** Bundled skills are not plugin skills; `/plugin`
  governs plugin skills only, and `skillOverrides` explicitly "does not apply to plugin skills".
  The two sets are disjoint.

## Answer to Q4 — individual disable IS supported. Not all-or-nothing

This is the falsification-tested finding, and it came out the opposite way from the phrasing the
dispatch question anticipated.

`disableBundledSkills` *alone* is all-or-nothing — the skills doc says so plainly: it "disables
every bundled skill except `/doctor`". But it is not the only lever. The decisive first-party
sentence is in the skills doc's `/doctor` note:

> "To hide it, set the `DISABLE_DOCTOR_COMMAND` environment variable **or a `skillOverrides` entry
> of `\"doctor\": \"off\"`**."
> — <https://code.claude.com/docs/en/skills.md>, fetched 2026-08-17

`doctor` is a bundled skill. The docs therefore prescribe `skillOverrides` as the way to turn off
one bundled skill. Tier 0 confirms the resolver reaches bundled skills:

```js
function rVe(e){
  if((e.type==="local-jsx"||e.type==="local") && qob.has(e.name))
    return Go().skillOverrides?.[e.name]==="off" ? "off" : "on";
  if(e.type!=="prompt" || e.source==="plugin") return "on";        // ← only plugin skills bypass
  let t=Go(), r=t.skillOverrides,
      n = r?.[e.name] ?? (e.unqualifiedName!=null ? r?.[e.unqualifiedName] : void 0) ?? "on";
  if(l5o(e,t)) return n==="off" ? "off" : "user-invocable-only";   // builtin prompt cmds under kill switch
  return n;                                                        // ← bundled skills: value honoured
}
```

A bundled skill is `type === "prompt"`, `source === "bundled"`, so it falls through to the final
`return n` — its `skillOverrides` value is honoured verbatim. The binary's own error string closes
it, listing both causes together for one skill: *"by the `disableBundledSkills` setting or
`CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` env var, **and by an explicit `skillOverrides` entry**"*.

**Summary for the caller:**

| Goal | Mechanism | Granularity |
|---|---|---|
| Remove all bundled skills' listing cost | `disableBundledSkills: true` / `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS=1` | all but `/doctor` |
| Remove one bundled skill entirely | `skillOverrides: {"<name>": "off"}` | per-skill |
| Keep it invocable, drop its description cost | `skillOverrides: {"<name>": "name-only"}` | per-skill |
| Hide from model, keep `/name` typable | `skillOverrides: {"<name>": "user-invocable-only"}` | per-skill |
| Block invocation (not necessarily listing) | `Skill(<name>)` deny rule | per-skill |
| Also remove `/doctor` | `DISABLE_DOCTOR_COMMAND=1` or `skillOverrides: {"doctor":"off"}` | that one skill |
