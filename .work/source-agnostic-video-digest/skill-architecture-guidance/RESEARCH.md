# RESEARCH — Skill architecture guidance (index)

**Topic slug:** `skill-architecture-guidance`
**Run date:** 2026-08-14
**Sidecars:** 6

## Task restatement

Establish current official Anthropic / Claude Code guidance on **skill architecture for a skill that
must serve multiple input sources behind one pipeline**, to decide (i) whether one-skill-with-adapters
is the officially-blessed shape or merely the incumbent choice, (ii) whether a planned hub-and-spoke
split of a 410-line `SKILL.md` will pay for itself, and (iii) whether renaming the skill is safe.

Six sub-questions were assigned: (a) one skill with internal adapters vs. sibling skills vs.
skill-invokes-skill; (b) the hub-and-spoke / progressive-disclosure pattern, and specifically whether
moving lines into spokes reduces context cost **only** when spokes load conditionally — flagged in the
brief as the load-bearing question, because a peer reviewer argued an unconditional "read all spokes"
instruction makes the split pure line-shuffling; (c) the real status of the `SKILL.md` line budgets,
including whether a ~200-line target is official or local convention — **escalated mid-run to a
decision-blocking deliverable**; (d) the `description` / `when_to_use` field as trigger mechanism, its
character budget, and how to write one that triggers on multiple distinct URL shapes; (e) whether
renaming an installed skill is a breaking change, and whether aliases or redirects exist; (f) any
newer 2026 pattern superseding one-skill-with-adapters for multi-source ingestion.

Standing constraints from the brief: **do not be biased by what the codebase already does** — if
research shows a better way, that better way wins; prefer primary Anthropic/Claude Code documentation
over blog posts and community write-ups; and **explicitly separate documented behavior from
convention**.

## Method note — why the quotes are trustworthy

Every quote in every sidecar was re-derived from **raw markdown** via `curl -sL` or `gh api`, not
WebFetch. WebFetch's summarizer was observed **paraphrasing while presenting text as verbatim** on
`anthropic.com` and `claude.com` pages during this run, and a web-search synthesis asserted outright
that *"Anthropic's own guidance targets under 200 lines"* — a claim falsified directly against the raw
primary pages. Two initially-abridged skill descriptions (`pptx`, `xlsx`) were re-pulled complete.

Source tiers follow the research discipline's vocabulary: **Tier 0** direct tool output captured this
turn, **Tier 1** official docs fetched this turn with URL, **Tier 2** secondary/synthesized
(corroborator only), **Tier 3** ungrounded (not accepted).

## Sidecar abstracts

Copied verbatim from each sidecar's `abstract` header field.

- **line-budget** — No authoritative source states a 200-line SKILL.md target; the binding official constraint is `< 5,000 tokens`, which the current 410-line/38KB SKILL.md violates at roughly 2x while passing the 500-line cap.
- **progressive-disclosure** — Spoke files cost nothing until read, so moving lines out of SKILL.md reduces context only when the spokes load CONDITIONALLY; an unconditional "read all spokes" split is net-negative, not merely neutral.
- **skill-granularity** — The docs are silent on multi-source ingestion, so one-skill-with-adapters is not officially blessed — but it survives independent re-derivation via the coherent-unit test, Anthropic's own claude-api dispatcher precedent, and two Claude Code mechanics that penalize sibling skills.
- **description-trigger** — There is no URL-pattern activation field — `paths:` is file globs — so description keyword matching is the entire mechanism by which an x.com URL can reach the skill, bounded by two distinct caps (1,024 spec validation vs 1,536 Claude Code listing).
- **rename-mechanics** — No alias, redirect, or migration path exists for a renamed skill command; the frontmatter `name:` field is the only stability seam and youtube-digest does not pin it, so a directory rename is a command rename today with five consumer surfaces that fail silently.
- **composition-patterns** — Nothing in 2026 supersedes one-skill-with-adapters for multi-source ingestion — dynamic workflows are ruled out by three documented constraints, and `context: fork` plus subagent `skills:` preload are the documented composition pair but neither is a dispatcher.

## Section → file + anchor

| Section | Brief sub-question | File | Anchor for the headline |
|---|---|---|---|
| `line-budget` | (c) — **decision-blocking** | `RESEARCH-line-budget.md` | `#1-the-authoritative-figures-verbatim` |
| `progressive-disclosure` | (b) — load-bearing | `RESEARCH-progressive-disclosure.md` | `#1-the-mechanism-is-conditionality` |
| `skill-granularity` | (a) | `RESEARCH-skill-granularity.md` | `#2-behavioral-evidence--anthropics-own-skills-cut-both-ways-along-that-line` |
| `description-trigger` | (d) | `RESEARCH-description-trigger.md` | `#1-two-distinct-caps--do-not-conflate-them` |
| `rename-mechanics` | (e) | `RESEARCH-rename-mechanics.md` | `#2-the-one-real-stability-seam--and-a-live-gap-in-this-repo` |
| `composition-patterns` | (f) | `RESEARCH-composition-patterns.md` | `#1-dynamic-workflows--the-only-genuinely-new-2026-orchestration-primitive` |

## Fetch log

One entry per source pool actually retrieved this turn. All fetches 2026-08-14.

| Claim served | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| 500-line cap; progressive disclosure; description guidance; "optimal performance" undefined | `platform.claude.com/…/agent-skills/best-practices.md` (1,185 lines) | 1 (vendor doc) | `curl -sL` | carries the claim |
| 500-line Tip; 1,536 listing cap; 1% budget; compaction 5,000/25,000; frontmatter table; command-name rules; no alias | `code.claude.com/docs/en/skills.md` (1,059 lines) | 1 | WebFetch → raw persist | carries the claim |
| `< 5,000 tokens`; 500 lines; one-level-deep references | `agentskills.io/specification.md` (274 lines) | 1 | `curl -sL` | carries the claim |
| Both figures attributed to the spec; coherent-unit test; when-to-load routing | `agentskills.io/skill-creation/best-practices.md` | 1 | `curl -sL` | carries the claim |
| `<500 lines ideal`; >300-line ToC; domain-organization pattern; "pushy" descriptions | `raw.githubusercontent.com/anthropics/skills/main/skills/skill-creator/SKILL.md` (485 lines) | 1 | `curl -sL` | carries the claim |
| claude-api dispatcher; docx/pptx/xlsx descriptions; copy-pasted `scripts/office/`; zero `context:`/`agent:`/`skills:` | `github.com/anthropics/skills` | 1 | `gh api` + `base64 -d` | carries the claim |
| Plugin-root `name` fallback scoping (`:39`); `dependencies`; symlink rules | `code.claude.com/docs/en/plugins-reference.md` (1,316 lines) | 1 | `curl -sL` | carries the claim |
| Marketplace `renames`; `displayName`; append-only chains | `code.claude.com/docs/en/plugin-marketplaces.md` | 1 | delegated raw fetch | carries the claim |
| Coexistence / trigger-stealing; recall limits; start-narrow-consolidate-later | `platform.claude.com/…/agent-skills/enterprise.md` | 1 | delegated raw fetch | carries the claim |
| Workflow constraints and comparison matrix | `code.claude.com/docs/en/workflows.md` | 1 | delegated raw fetch | carries the claim |
| Skill-invokes-skill described as pre-native | `claude.com/blog/lessons-from-building-claude-code-how-we-use-skills` | 2 | `curl -sL` (raw, after paraphrase detected) | carries the claim |
| Mutual-exclusivity split condition | `anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills` | 2 | `curl -sL` (raw) | carries the claim |
| **200-line target** | all six primary sources above | 1 | `curl -sL` + grep | **does not exist** for this claim class — full primary sweep, not one clean surface |
| **Skill-level alias / redirect / migration path** | `skills.md`, `plugins-reference.md`, `plugin-marketplaces.md`, `plugins.md`, `plugin-dependencies.md`, `permissions.md`, 3 Agent SDK pages | 1 | raw grep of complete schema tables | **does not exist** for this claim class |
| **Multi-source ingestion as a named pattern** | changelog through v2.1.232 (2026-08-13), what's-new w23–w32, `features-overview.md`, `glossary.md` | 1 | delegated raw fetch | **does not exist** for this claim class |
| 200 as community convention | `skills.rest/skill/compress-skill` (author `dvy1987`, 2026-04-17) | 2 | `curl -sL` | carries the claim |
| Rename cliff reproduction, closed as not planned | `github.com/anthropics/claude-code/issues/58102` | 2 | delegated | carries the claim |
| Local measurements: 410 lines / 38,436 chars / 4,723 words; no `name:`; `LINE_SOFT_CAP=200` uncited | `wc`, `awk`, `sed`, `grep` over the worktree | 0 | Bash | carries the claim |
| Recency cross-check | Claude Code changelog v2.1.232, 2026-08-13 | 1 | delegated raw fetch | v2.1.232 (2026-08-13) — **current** |

`whats-new/2026-w31.md` returns 404 (no such page) — recorded so a later run does not re-chase it.

## Explicit silences — cross-cutting, do not fill by inference

- **No numeric granularity rule anywhere.** Every official number (500 lines, `< 5,000` tokens, 1,024 chars, 1,536 chars, 1% listing budget, 5,000/25,000 compaction tokens, 8 skills per API request) is a **progressive-disclosure or budget trigger, never a split-the-skill trigger**.
- **No definition of "optimal performance"** behind the 500-line figure — so no attention or recall benefit of a shorter body can be claimed from official sources.
- **No skill-invokes-skill contract** in the reference docs. Blog only, self-described as pre-native and model-mediated.
- **No frontmatter dependency / requires / includes / sub-skill field**, verified against the complete frontmatter table.
- **No ordering, precedence, or conflict-resolution semantics** between two co-loaded skills' instructions. `enterprise.md` names "conflict with other Skills" as a risk; nothing says how it resolves.
- **No semver or breaking-change guidance for component renames**; no `changelog` field in either schema.
- **No workflow row** in `features-overview.md`'s decision matrix and **no Workflow entry** in `glossary.md`.
- **The Anthropic engineering Agent Skills post says nothing about granularity or skill-to-skill composition** (verified by full-text extraction, not summarizer). Any granularity claim attributed to it is fabricated.

## Not researched — honest gaps

- Whether a widened description empirically **over-triggers on non-video `x.com` URLs**. Needs eval runs and the `/skills` description-tuning loop, not docs.
- **Actual tokenizer count** of the SKILL.md body. No tokenizer was available; the sidecar gives a method-named estimate range (~6,300–9,600) rather than a figure.
- Whether **any Claude Code version ever shipped and then removed** a skill alias mechanism. Only the current changelog was checked.
- **Independence limit, disclosed:** the `< 5,000 tokens` recommendation rests on a **single publishing pool** (agentskills.io). Anthropic's own docs state no token figure. The number is independently corroborated from a second Anthropic pool only as the compaction re-attachment cap, not as a body-length recommendation. See `RESEARCH-line-budget.md#independence-caveat-on-the-5000-token-figure--stated-not-buried`.

## Next-stage handoff

### Settled — safe for the plan to build on

1. **No authoritative source states a 200-line SKILL.md target.** It is community convention; locally it is an uncited tunable at `check-skill.sh:177` whose two neighbours both match upstream exactly.
2. **The official body constraint is `< 5,000 tokens`, with 500 lines as a coarse proxy.** The current body is ~2x the token recommendation while passing the line cap — the gate was measuring the wrong thing in **both** directions.
3. **A hub/spoke split pays only along a conditional axis.** Content the hub would read every time belongs in the hub; references stay one level deep.
4. **One-skill-with-adapters is not officially blessed but wins on merits** — the coherent-unit test, the `claude-api` dispatcher precedent, trigger-stealing, and listing-budget starvation. The four office skills look like counter-evidence and dissolve on inspection.
5. **The `description` is the only trigger mechanism for URL shapes**, bounded by 1,536 chars in Claude Code (1,024 only if portability is wanted), with the `xlsx` enumerate-then-negate shape as the working model.
6. **A command rename is a hard break with no compatibility mechanism**; four of its five consumer surfaces fail silently.
7. **Nothing in 2026 supersedes the incumbent shape.**

### Open decisions for the planning step

1. **Which content moves to spokes** — must be chosen by mutual exclusivity per invocation and by token weight, not by line count. The existing move table in `hub-split-budget.md` was built against the 200-line target and needs re-deriving against `< 5,000 tokens`.
2. **Whether to rename the command at all** (thread T2b). Research settles the *cost*, not the *choice*. Directory rename is free once `name:` is pinned; command rename is a deliberate breaking change needing out-of-band announcement.
3. **Whether to widen `description` toward 1,024 or 1,536** — i.e. whether claude.ai / routine portability is in scope. Not a research question; a product decision.

### Recommended regardless of any of the above

- **Pin `name: youtube-digest` in the plugin `SKILL.md` now.** It is the only documented decoupling of directory from command, costs nothing, and converts a future directory rename from breaking to free.
- **Retire the completion criterion that treats the 200-line WARN as a gate.** It is unbacked.
- **File a `skill-quality` follow-up:** re-anchor or remove `LINE_SOFT_CAP=200`, and add a token-based check for `< 5,000 tokens` — the constraint the current 500-line PASS fails to catch.

---

## Parent-side rows (written by the dispatching session)

Two rows the producer cannot supply: **project fit**, which needs the consuming project's
conventions, and the **independent verifier verdict**. Recorded here so this artifact is not read as
gate-passed on rows nobody graded.

### Project fit

| Finding | Fit verdict |
|---|---|
| 1,536-char listing cap binds; 1,024 only for portability | **Applies.** A plugin skill staying in Claude Code, so 1,536 binds today. But the plugin **is published to a marketplace**, so a consumer could carry it to claude.ai. Whether 1,024 is a real constraint is a product decision about who this ships to, not a research question |
| Retire the 200-line completion criterion | **Applies cleanly and cheaply.** It came from this work's own handoff, not from repo policy, so retiring it is a design-slice decision with no repo-wide blast radius |
| `skill-quality` follow-up: re-anchor `LINE_SOFT_CAP`, add a token check | **Applies, but is NOT free.** `plugins/skill-quality/` is in this repo, so it is ownable — but it is a cross-plugin change requiring a marketplace version bump that changes a gate for **every consumer of the plugin**. Its own work item, not part of an X-parity refactor |
| **Pin `name: youtube-digest`** | **Applies with a qualification the research could not see — below** |

### The `name:` recommendation diverges from a 205-file repo convention

Measured: **6 of 211 `SKILL.md` files pin `name:`, and all six are `vendor/` files** — upstream
copies this repo materializes rather than authors (`context7/…/vendor/cli`,
`context7/…/vendor/find-docs`, `dometrain/…/vendor`, `playbooks/…/boris/vendor`,
`playbooks/…/skill-authoring/vendor`, `playwright/…/vendor`).

**Not one of this repository's own 205 skills pins `name:`.**

So "pin `name:`, it costs nothing" is right about the *mechanism* and incomplete about the
*convention*: pinning it on one skill creates a second way of doing things in a repo that has one
way. Under reuse-or-replace the options are:

- **Adopt it fleet-wide** — every command name explicit, every directory rename free. Defensible,
  arguably right, and a 205-file change with its own work item.
- **Pin on this skill only, with the divergence recorded** — acceptable *if* stated as a deliberate
  exception with its reason (this is the skill facing a rename), not left as an unexplained outlier.
- **Do not pin** — accept directory-rename-is-command-rename, as everywhere else in this repo.

**Revised parent recommendation:** pin it here *and record the divergence explicitly*, filing the
fleet-wide question separately. The silent second way is the failure mode, not the divergence itself.

### Verifier verdict

**PENDING.** An independent verifier — independent of this artifact's producer — was dispatched
against the three absence claims, the single-pool caveat on `< 5,000 tokens`, the office-skills
counter-analogy dismissal, and scope-flattening in the guidance. Its verdict replaces this line when
it returns. **Until then, treat the rows above as parent-checked but not independently verified.**
