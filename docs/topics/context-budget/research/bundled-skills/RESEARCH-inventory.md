---
topic: bundled-skills
section: inventory
abstract: Claude Code v2.1.232 registers 37 bundled skills in-binary while the public commands reference documents 13, because most are availability-gated; "bundled skill" is one of three distinct categories and no single version "introduced" the mechanism.
claims:
  - claim: "Claude Code ships bundled skills as a distinct category, registered in-binary via registerBundledSkill; v2.1.232 has 37 registration call sites."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local: node_modules/@anthropic-ai/claude-code-linux-x64/claude v2.1.232, grep of registerBundledSkill call sites"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/commands"
        tier: 1
        pool: "Anthropic (docs)"
  - claim: "The public commands reference marks exactly 13 commands as bundled skills, plus one bundled workflow (/deep-research)."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/commands.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/skills.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local binary grep: 13 rows carrying the **[Skill](/docs/en/skills#bundled-skills).** badge"
        tier: 0
        pool: "Anthropic (docs artifact, fetched raw)"
  - claim: "Bundled skills, built-in prompt commands, and builtin-plugin skills are three separate categories with different disable behaviour."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local binary: getSkills returns {skillDirCommands, pluginSkills, bundledSkills, builtinPluginSkills}; predicate dpv(e)=e.type==='prompt'&&e.source==='bundled'"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/commands.md"
        tier: 1
        pool: "Anthropic (docs)"
produced_by: phase-1+phase-2
---

# Inventory of bundled skills

All local Tier-0 evidence is from the shipped binary
`node_modules/@anthropic-ai/claude-code-linux-x64/claude`, **version 2.1.232**, inspected
2026-08-17. All doc URLs were fetched 2026-08-17.

## Three categories, not one

This is the single most important structural finding, and getting it wrong makes every disable
question unanswerable. The binary's skill loader returns four disjoint buckets:

```
{skillDirCommands, pluginSkills, bundledSkills, builtinPluginSkills}
```

| Category | Discriminator (Tier 0, from the binary) | Example |
|---|---|---|
| **Bundled skill** | `type === "prompt" && source === "bundled"` | `/code-review`, `/debug`, `/dataviz` |
| **Built-in prompt command** | `type === "prompt" && source === "builtin"` | `/init` |
| **Built-in plugin skill** | registered with `pluginName`/`pluginCommand` | `/security-review` |
| Built-in coded command | `type` is `local` / `local-jsx` — behaviour coded in the CLI | `/compact`, `/help` |

The official docs draw the same line in prose: the commands reference says most entries are
"built-in commands whose behavior is coded into the CLI", and marks bundled skills separately as
"a prompt handed to Claude, which Claude can also invoke automatically when relevant"
(<https://code.claude.com/docs/en/commands>, fetched 2026-08-17).

**Consequence for the caller:** `/doctor` is a bundled skill (since v2.1.205), `/init` is *not* —
it is a built-in prompt command. `/security-review` is *neither* — it is a builtin-plugin skill.
`pdf` / `docx` / `xlsx` / `pptx` / `skill-creator` are **not Claude Code bundled skills at all**
(see "What is not a bundled skill" below). The dispatch question's example list mixes all four
categories.

## The documented inventory — 13 bundled skills

Extracted from the raw markdown of the commands reference by the `**[Skill](…#bundled-skills).**`
badge that page uses to mark them (<https://code.claude.com/docs/en/commands.md>, fetched
2026-08-17):

`/batch`, `/claude-api`, `/code-review`, `/dataviz`, `/debug`, `/design-sync`, `/doctor`,
`/fewer-permission-prompts`, `/loop`, `/run`, `/run-skill-generator`, `/simplify`, `/verify`

Plus one **bundled workflow**, badged separately: `/deep-research`.

The skills page names a consistent subset in prose: "Claude Code includes a set of bundled skills,
such as `/doctor`, `/code-review`, `/batch`, `/debug`, `/loop`, and `/claude-api`"
(<https://code.claude.com/docs/en/skills>, fetched 2026-08-17).

## The in-binary registry — 37 call sites

`grep` of `registerBundledSkill` (minified `nd(`) call sites in v2.1.232 returns **37**. Thirty-four
resolve to string literals:

```
artifact-capabilities   artifact-components   artifact-design    artifact-diagramming
artifact-pr-review      batch                 claude-api         claude-code-docs
claude-in-chrome        code-review           commit             cowork-plugin
dataviz                 debug                 design             design-sync
doctor                  explain-usage         fewer-permission-prompts
keybindings-help        loop                  memory-types       plan-artifact
pr                      prototype             run                run-skill-generator
schedule                setup-cowork          simplify           update-config
verify                  whiteboard            workshop
```

The remaining call sites are loop/template-driven and register the artifact document kinds
(`doc`, `sheet`, `slides`) from a `v2w` table — I did **not** fully resolve whether these land as
`doc`/`sheet`/`slides` or as `artifact-doc`/`artifact-sheet`/`artifact-slides`, because both a
bare-`name:e` loop and a `` name:`artifact-${e}` `` template appear in the binary. **Marked
unresolved**; it does not affect any disable answer.

## Why 37 in-binary but 13 documented — conflict resolved

Not a docs error. Registrations carry `isEnabled` predicates and an `availability` array whose
cases include `"claude-ai"` and `"console"` (Tier 0, binary). The commands reference states the
rule in its own words:

> "Not every command appears for every user. Availability depends on your platform, plan, and
> environment."
> — <https://code.claude.com/docs/en/commands.md>, fetched 2026-08-17

The artifact/Cowork-oriented registrations (`artifact-*`, `workshop`, `prototype`, `whiteboard`,
`design`, `cowork-plugin`, `setup-cowork`, `plan-artifact`) are gated to surfaces other than the
plain terminal CLI — one is gated literally on
`CLAUDE_CODE_ENTRYPOINT === "remote_cowork"`. **The 13-item list is the terminal-CLI-visible set;
the 37-item list is the ceiling across all surfaces.** A context-trimming tool must measure the
session it is in, not assume either number.

## What is *not* a bundled skill

- **`pdf`, `docx`, `xlsx`, `pptx`, `skill-creator`, `morning`** — in the session this research ran
  in, these live at `~/.claude/skills/synced/`, i.e. skills synced from the claude.ai account, and
  additionally at the container mount `/mnt/skills/public/`. Neither path is the Claude Code
  bundled registry, and neither is governed by `disableBundledSkills`. **Tier 0**, from directory
  inspection this turn.
- **`/init`** — a built-in prompt command (`type:"prompt", name:"init"` in the binary).
- **`/security-review`** — a builtin-plugin skill (`pluginName:"security-review"`).
- **`artifact-design` / `artifact-diagramming` / `artifact-capabilities` / `dataviz`** — these *are*
  in the bundled registry, but are availability-gated and absent from the documented 13.

## Which version introduced the mechanism — NOT RESOLVED

I could not pin a single introducing version, and I am not going to invent one. What the upstream
changelog (<https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md>, fetched
2026-08-17) actually supports:

| Version | Entry |
|---|---|
| 2.1.30 | "Added `/debug` for Claude to help troubleshoot the current session" |
| 2.1.63 | "Added `/simplify` and `/batch` **bundled slash commands**" — earliest use of "bundled" for this feature |
| 2.1.129 | "`skillOverrides` setting now works…" |
| 2.1.153 | earliest changelog use of the exact phrase "**bundled skills**" |
| 2.1.169 | "Added a `disableBundledSkills` setting and `CLAUDE_CODE_DISABLE_BUNDLED_SKILLS` environment variable" |
| 2.1.205 | `/doctor` converted from built-in command to bundled skill (per the skills doc's Note) |
| 2.1.198 | "Added `/dataviz` skill" |

The changelog spans 365 version headings down to `0.2.21`. There is **no entry announcing a
"bundled skill mechanism"** as a discrete feature; the category was introduced incrementally and
the *name* stabilised around 2.1.63–2.1.153. Sources checked: the full upstream `CHANGELOG.md`, the
skills doc, the commands reference. Sources **left unchecked**: the closed-source binary's history
(no public VCS for it — `anthropics/claude-code` is issues + changelog only), and any pre-2.x
release notes that may exist off-changelog.
