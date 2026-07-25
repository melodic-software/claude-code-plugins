# Section-digestion brief — read this before starting

## Your job

You own **one section** of `source-article.md` (in this directory). Digest it completely and turn it
into applicable criteria for this repository. Read the whole article for context; produce findings
only for your assigned section.

## Hard fences — violating these invalidates your output

You are deliberately being run **blind**. A prior effort already interpreted this article, and the
operator wants an independent read. Do **not** read, list, grep, or reference any of:

- `docs/topics/context-engineering-claude-5/**` (any path, any worktree, any branch)
- `docs/topics/fable-field-guide-audit/**` and `.work/fable-field-guide-audit/**`
- `<worktrees-root>/context-engineering-claude-5/**`
- `<worktrees-root>/fable-field-guide-audit/**`
- Any checkout of this repository other than your own working directory
- Any other agent's output file under `sections/`

If you encounter a prior analysis of this article by accident, stop reading it, and say so in your
output under `## Fence events`.

Everything else in your own working directory is fair game — read the repo freely.

## What you may consult

1. `source-article.md` — the source of truth for what is being applied.
2. This repository's tree (your own working directory only).
3. **Current official Claude Code documentation**, fetched this session via WebFetch. Never assert a
   Claude Code behavior from memory. Index: <https://code.claude.com/docs/llms.txt>.

## Two audiences, both in scope

Findings must distinguish them, because remediation routes differ:

- **This repository** — a Claude Code plugin marketplace. 60 plugins, ~181 skills under
  `plugins/*/skills/*/SKILL.md`, plus agent definitions, hooks, plugin READMEs, and repo-level
  `CLAUDE.md` / `docs/`.
- **User-global scope** — `~/.claude/CLAUDE.md`, `~/.claude/docs/*`, user hooks and settings. This
  surface is chezmoi-managed and **read-only to you**: you may read it and propose changes, but
  never edit it. Findings there are emitted as routed recommendations.

## Output

Write `sections/S<n>-<slug>.md` in this directory. Structure:

```markdown
# S<n> — <section title>

## Claims
One numbered row per distinct claim in your section. Quote the source verbatim for each. Do not
merge two claims to be tidy; do not invent a claim the text does not make.

## Evidence status
Per claim: CONFIRMED / PARTIAL / UNBACKED against current official documentation, with the fetched
URL. UNBACKED means the article asserts it and no official page says it — that is a legitimate and
expected outcome for some claims, not a failure. State it plainly.

## Criteria
Per claim that survives into something checkable: a testable rule. State the surface it applies to
(SKILL.md body, skill frontmatter/description, CLAUDE.md, agent definition, hook, tool/skill
description, README, plan/spec artifact), the observable that decides pass/fail, and at least one
case it must NOT flag.

## Targets in this repo
Concrete files or file classes your section's criteria would hit. Cite `path:line`. Estimate the
population size by command (e.g. a `find`/`rg` you actually ran), never by guess.

## Conflicts and ambiguity
Where the claim contradicts another part of the article, contradicts official documentation,
contradicts something this repository already does deliberately, or does not generalize beyond the
narrow case the article describes. This section is high-value — do not leave it thin to look tidy.

## Open questions for the operator
Decisions you cannot make. One line each, with your recommendation.

## Fence events
Any accidental contact with fenced material, or "none".
```

Also return a compressed summary by value: claim count, evidence-status tally, the single
highest-leverage criterion, and the sharpest conflict you found.

## Discipline

- Every concrete specific — a path, a count, a default, a doc behavior — is verified from the live
  tree or a fetched page, or explicitly labeled unverified.
- Absence findings state where you looked.
- You are digesting, not deciding. Do not edit any repository file outside `sections/`.
