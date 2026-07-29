# Lane: docs-prose

Markdown prose: project docs and skill bodies (BODY only — never frontmatter). The narrowest, lowest-risk lane in the rotation: bad tidyings here don't break builds; they just produce noise the next reviewer can ignore. Use this lane for the most aggressive prose hunts.

## Scope

```text
docs/**.md
README.md
.claude/skills/*/SKILL.md         # BODY only — never frontmatter
.claude/skills/*/**.md            # supporting prose files
```

Retarget this to the consuming project's actual documentation layout with a project lane at `.claude/tidy-lanes/docs-prose.md`. A project `Scope` block **replaces** the globs above (see [Merge semantics](#merge-semantics)); it does not have to restate the sections it keeps.

**Critical:** SKILL.md frontmatter (YAML between `---` markers) is HARD-EXCLUDED. The body (everything below the closing `---`) is in scope.

## Merge semantics

This lane is layered per the [config-cascade contract](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md) ("Merge semantics"). A project lane at `.claude/tidy-lanes/docs-prose.md` is **not** meant to replace this file wholesale — it merges with the bundled lane **per section**, so bundled improvements to sections the project does not touch keep reaching the repo. This is the declaration a project lane adopts (by reference or by restating it); it is the recommended shape for this lane:

- **`Scope`** — **per-section override.** A project `Scope` block replaces the bundled globs entirely; retargeting doc layout is the whole reason a project writes a lane, and two glob sets do not meaningfully concatenate. A project lane that omits `Scope` keeps the bundled globs.
- **`Watch-for patterns`** — **additive (concatenate).** A project's watch-for entries are **appended** to the bundled P-1..P-6; the generic patterns are never frozen out, and new bundled patterns flow to the project on upgrade. A project adds repo-specific patterns here; it does not restate or replace the bundled ones.
- **Every other section** (`Lane-specific extra exclusions`, `Verification commands`, `Conventional Commits type`, `Preferred research sources`) — **per-section override**, same as `Scope`: a section the project supplies replaces the bundled one; a section it omits keeps the bundled value.

When a project lane at `.claude/tidy-lanes/docs-prose.md` includes a `## Merge semantics` section, `/code-tidying:tidy` reads **both** that project lane and this bundled lane and merges them per **the project lane's** declaration — which is why adopting the shape above (`Merge semantics: per the bundled lane's declaration`) is what puts these rules in force. A project lane without that section resolves project-only, and none of the above applies to it.

## Watch-for patterns

- **P-1 — Dead-link removal** — internal cross-references to files/sections that no longer exist. `markdownlint-cli2` catches some; broken relative `(./x.md)` paths often slip through. Grep for relative markdown links and walk the matches
- **P-2 — Stale cross-reference repair** — references to merged-but-renamed files
- **P-3 — Redundant-paragraph dedup** — when two docs explain the same concept, the canonical explanation should live in one place; the other should reference it. Beck #13 (One Pile) for prose
- **P-4 — Reading order in prose** — within a single doc, sections should flow from "what is it" → "how to use it" → "when not to use it" → "advanced". When the order is inverted without cause, fix it
- **P-5 — Explaining comments** — for code-shaped prose (CLI commands, configuration snippets), an inline `# explains the next line` comment often beats a separate paragraph above the snippet
- **P-6 — Delete redundant prose** — boilerplate like "This document explains..." at the top of a doc whose title already explains it
- **Markdown style consistency** — heading hierarchy skipping levels, inconsistent list markers, trailing whitespace, hard tabs (markdownlint catches these)

## Lane-specific extra exclusions

Beyond the global HARD/SOFT lists:

- **Skill frontmatter is HARD-EXCLUDED.** Frontmatter changes have functional effects (auto-discovery, permission gates, model selection); not prose tidyings
- **Skill Action Router / argument-grammar sections are HARD-EXCLUDED.** A skill's argument grammar is a contract with its users — changing it is behavioral
- **Skill HARD/SOFT exclusion lists are HARD-EXCLUDED.** Those lists ARE the safety mechanism for autonomous runs
- **The project's top-level `CLAUDE.md` is SOFT-EXCLUDED.** Too central; prose tidyings there deserve dedicated human review
- **`.claude/rules/**` is HARD-EXCLUDED** (also caught globally). Convention files are not "prose" in the tidy sense — they're enforcement specs
- **Append-only / historical records are HARD-EXCLUDED** — changelogs, release notes, accepted ADRs, and any file that declares itself append-only or immutable. Supersede, don't edit history

## Verification commands

```bash
npx markdownlint-cli2 <changed .md files>    # use the project's own markdownlint config when present
```

Plus relative-link integrity on changed files: for each `](<relative>.md)` reference, confirm the target exists.

## Conventional Commits type

`docs:`. Example squash titles:

- `docs(skills): repair stale cross-references`
- `docs: dedup hook-chain explanation across guides`

## Preferred research sources

- **Anthropic skill-authoring best-practices guide** (`platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices`) — for "is this prose effective for Claude" questions
- **Boris Cherny** — Claude Code creator; canonical patterns for skill content and progressive disclosure
- **Diátaxis framework** (`diataxis.fr`) — for "is this doc the right kind of doc" reading-order questions
