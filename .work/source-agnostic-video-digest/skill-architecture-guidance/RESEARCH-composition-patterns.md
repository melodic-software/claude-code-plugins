---
topic: skill-architecture-guidance
section: composition-patterns
abstract: Nothing in 2026 supersedes one-skill-with-adapters for multi-source ingestion — dynamic workflows are ruled out by three documented constraints, and `context: fork` plus subagent `skills:` preload are the documented composition pair but neither is a dispatcher.
claims:
  - claim: "No 2026-era official pattern supersedes one-skill-with-adapters; multi-source ingestion is never named as a pattern in any Claude Code or platform doc."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "`context: fork` with `agent:` and subagent `skills:` preload are presented explicitly as the bidirectional skill/subagent composition mechanism."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://code.claude.com/docs/en/sub-agents"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Neither `context: fork` nor `skills:` preload provides per-source branching — neither is a dispatcher."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Dynamic workflows carry three constraints that rule them out for this pipeline: no mid-run user input, no direct filesystem or shell access from the script, and no module loading."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/workflows"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "`context:`, `agent:`, and `skills:` appear zero times across all 18 SKILL.md files in anthropics/skills — behavioral evidence that Anthropic's own skills do not use them."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "Plugin `dependencies` is install/version resolution, not composition; marketplace-internal symlinks are the one real cross-component file-sharing mechanism."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://code.claude.com/docs/en/plugin-dependencies"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
produced_by: phase-2-targeted
---

# Composition patterns — is there a newer (2026) shape for multi-source ingestion?

**Verdict: NO. Nothing supersedes one-skill-with-adapters. The docs remain SILENT on multi-source
ingestion as a named pattern.**

No official page contains "source adapter", "per-source", or "multi-source" guidance. Verified across
the changelog (**current through v2.1.232 / 2026-08-13**), what's-new w23–w32, `workflows.md`,
`agents.md`, `plugins-reference.md`, `plugin-dependencies.md`, `features-overview.md`, `glossary.md`.

## 1. Dynamic workflows — the only genuinely new 2026 orchestration primitive

<https://code.claude.com/docs/en/workflows>:

> A dynamic workflow is a JavaScript script that orchestrates subagents at scale. Claude writes the script for the task you describe, and a runtime executes it in the background while your session stays responsive.

> Reach for a workflow when a task needs more agents than one conversation can coordinate, or when you want the orchestration codified as a script you can read and rerun.

**Three documented constraints cut against using one for this pipeline:**

| Constraint | Text |
|---|---|
| No mid-run user input | *"Only agent permission prompts can pause a run. For sign-off between stages, run each stage as its own workflow"* |
| No filesystem/shell from the script | *"Agents read, write, and run commands. The script coordinates the agents"* |
| No module loading | *"a script that contains `import()` fails before the run starts"* |

Beyond the constraints: workflows are **Claude-authored at runtime**, and every documented example is
**homogeneous fan-out** (one agent per file / route / source) — **none branches by input *type***.
They are also absent from every "choose your extension shape" surface: `features-overview.md`'s
decision matrix has no workflow row, and `glossary.md` has no Workflow entry.

Its comparison table is nonetheless the **only** official skill-vs-subagent-vs-workflow matrix in the
docs and is worth reading during design:

> |  | Subagents | Skills | Agent teams | Workflows |
> | What it is | A worker Claude spawns | Instructions Claude follows | A lead agent supervising peer sessions | A script the runtime executes |
> | Who decides what runs next | Claude, turn by turn | Claude, following the prompt | The lead agent, turn by turn | The script |
> | Where intermediate results live | Claude's context window | Claude's context window | A shared task list | Script variables |
> | Scale | A few delegated tasks per turn | Same as subagents | A handful of long-running peers | Dozens to hundreds of agents per run |

## 2. `context: fork` and subagent `skills:` — the documented composition pair

The docs present these explicitly as bidirectional. `skills.md`, "Run skills in a subagent":

> Add `context: fork` to your frontmatter when you want a skill to run in isolation. The skill content becomes the prompt that drives the subagent. It won't have access to your conversation history.

> Skills and subagents work together in two directions:
>
> | Approach | System prompt | Task | Also loads |
> | Skill with `context: fork` | From agent type | SKILL.md content | CLAUDE.md, except when the agent is Explore or Plan |
> | Subagent with `skills` field | Subagent's markdown body | Claude's delegation message | Preloaded skills + CLAUDE.md |

`sub-agents.md`:

> Use the `skills` field to inject skill content into a subagent's context at startup. This gives the subagent domain knowledge without requiring it to discover and load skills during execution.

> This field controls which skills are preloaded, not which skills the subagent can access: without it, the subagent can still discover and invoke project, user, and plugin skills through the Skill tool during execution.

### Documented tradeoffs

- **Warning:** *"`context: fork` only makes sense for skills with explicit instructions. If your skill contains guidelines like 'use these API conventions' without a task, the subagent receives the guidelines but no actionable prompt, and returns without meaningful output."*
- Runs in the **background** by default; *"Set `background: false` in the frontmatter to instead wait for the result in the turn that invoked the skill."*
- *"A backgrounded fork also runs with the narrower tool set that applies to background subagents… If your skill's steps depend on a tool outside that set, set `background: false` to keep the full tool set."*
- *"A forked skill that runs in the background applies its edits outside your session's checkpoints, so `/rewind` doesn't undo them; use git to revert them."*
- Preload constraint: *"You can't preload skills that set `disable-model-invocation: true`."* A missing or disabled listed skill is skipped with a debug-log warning.

**Critical for this design: neither mechanism gives per-source *branching*.** `context: fork` isolates
a whole skill; `skills:` preloads static reference content into a worker. **Neither is a dispatcher.**

## 3. Behavioral evidence — Anthropic's own skills use none of it

`context:`, `agent:`, and `skills:` appear **zero times** across all 18 `SKILL.md` files in
`anthropics/skills`. Every one carries only `name`, `description`, and usually `license`.

Where those skills delegate, they do it in **prose** pointed at plain frontmatter-less instruction
files the skill itself owns — `skill-creator/SKILL.md`:

> The agents/ directory contains instructions for specialized subagents. Read them when you need to spawn the relevant subagent.
> - `agents/grader.md` — How to evaluate assertions against outputs
> - `agents/comparator.md` — How to do blind A/B comparison between two outputs

Those `agents/*.md` files have **no YAML frontmatter at all** — they are prompt bodies, not agent
definitions.

Cross-skill composition in the repo is essentially nil: grepping all 18 bodies for cross-skill
references yields one generic, unnamed hit (`web-artifacts-builder`: *"use available tools (including
other Skills or built-in tools like Playwright or Puppeteer)"*). **No skill says "use the pdf skill."**

## 4. Plugin-level mechanisms — install resolution, not composition

`plugins-reference.md`:

> | `dependencies` | array | Other plugins this plugin requires, optionally with semver version constraints |

`plugin-dependencies.md` confirms this is install/version resolution. Nothing about invocation, data
flow, or pipeline shape.

**The one genuine cross-component file mechanism**, relevant to a marketplace monorepo — symlinks:

> - **Within the plugin's own directory:** the symlink is preserved as a relative symlink in the cache…
> - **Elsewhere within the same marketplace:** the symlink is dereferenced. The target's content is copied into the cache in its place. This lets a meta-plugin's `skills/` directory link to skills defined by other plugins in the marketplace.
> - **Outside the marketplace:** the symlink is skipped for security.

> Copied plugins cannot reference files outside their directory. Paths that traverse outside the plugin root (such as `../shared-utils`) will not work after installation because those external files are not copied to the cache.

The nearest thing to agent-per-source in the docs is `features-overview.md`'s "Skill + Subagent"
combine row — *"A skill spawns subagents for parallel work… `/audit` skill kicks off security,
performance, and style subagents"* — but that is **parallel fan-out, not input-type branching**.

## 5. Bottom line

The incumbent shape is not superseded. The composition primitives that do exist are for *isolation*
and *preloading*, not *dispatch*, so an internal routing table inside one skill remains the only shape
the corpus actually supports for this problem.
