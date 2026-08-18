# skill-recommendation-system

## Brief

### TLDR

- New skill `/session-flow:what-next` — a human-facing option menu answering "what should I run next?"
- Reads the session's trajectory (where we've been, where we're heading) and buckets candidate skills as **Backfill / Now / Next / Standing**
- Presents options with a **no-gatekeeping presentation contract**: "we already did X" is a note on an option, never a reason to omit it — the human decides
- Recommends from the **full in-context skill listing** (any marketplace + built-ins), enriched with this repo's `workflow-stage` metadata when present; portable to any repo
- Usage-metrics-informed surfacing (`~/.claude.json` `skillUsage`) is **deferred to V2** behind a named seam

### Goal

Give the operator a skill they can invoke at any point that turns the installed skill catalog — roughly 150 skills across 65 plugins here, plus built-ins — from something they must remember into something they can consult. It reads the conversation's trajectory and the session's durable state, then lays out the candidate skills as options grouped by when they apply: ones that could still be run retroactively for decisions already made, ones that fit right now, ones two or three steps ahead, and standing hygiene that applies at any moment. Each option says what it would add *to this specific conversation* and when someone would skip it. The skill never withholds an option because it judges it unnecessary or already covered; the operator picks, and in picking, learns their own catalog.

### Constraints

- **No-gatekeeping is the defining constraint.** The skill must not filter candidates on the model's judgment that a step is done or unneeded. Such judgments appear as annotations on presented options. A design that ranks-then-truncates re-introduces gatekeeping through the cutoff and violates this.
- **Portable.** Must work in any repo where the marketplace is installed, degrading gracefully where this repo's `workflow-stage` / `summary` frontmatter and `docs/SKILL-CHEAT-SHEET.md` are absent.
- **No embedded inventory.** The skill body teaches the bucketing and grounding method and points at existing artifacts; it never restates a skill list, which would drift the day a skill is added (point-don't-copy / SSOT discipline; `docs/SKILL-CHEAT-SHEET.md` is generated from frontmatter by `scripts/generate-cheatsheet.mjs`).
- **Cheap enough to fire often.** It is model-invocable at phase boundaries, so the durable-state probe is capped — a fraction of `/session-flow:orient`'s depth, not a re-implementation of it.
- **Boundary carve against three near-neighbors must hold in the body's "What this skill does NOT do":** `/session-flow:workflow` routes to the one next *stage*; `/session-flow:orient` reports position and deliberately prescribes nothing; `/discipline:use-your-skills` corrects the *model's* skipped-skill drift. This skill shows the *human* their options.
- Repo convention: session-flow skills ship an `evals/` directory; frontmatter carries `metadata.workflow-stage` and `metadata.summary`, which feed the generated cheat sheet.

### Acceptance criteria

- `plugins/session-flow/skills/what-next/SKILL.md` exists with frontmatter setting `user-invocable: true`, `disable-model-invocation: false`, and `metadata.workflow-stage: anytime`, and the description names boundary triggers plus natural phrases ("what should I run next", "what are my options", "what am I forgetting").
- Invoking it produces the four buckets — Backfill, Now, Next, Standing — with each option carrying the skill's invocation name, one line of what it adds *to this conversation* (not its generic description), and a when-you-would-skip-it note stated as fact.
- An option whose stage already ran still appears, annotated — verifiable by an eval fixture where exploration is complete and `/discovery:explore` remains listed with a note rather than being dropped.
- Candidates are drawn from the live in-context listing at runtime; the SKILL.md contains no enumerated skill inventory (checkable by inspection and by the repo's existing cross-plugin drift checks).
- Running in a repo without this marketplace's frontmatter still yields buckets from names and descriptions alone.
- The body carries a "What this skill does NOT do" section naming the three near-neighbors and the boundary against each.
- An `evals/` suite exists alongside, matching sibling session-flow skills.
- `scripts/generate-cheatsheet.mjs` regenerated so the new skill appears in `docs/SKILL-CHEAT-SHEET.md`.

### Captured assumptions

- The in-context skill listing is a reliable runtime candidate source — revisit if listing-budget overflow is observed dropping descriptions the skill needs (official docs: descriptions drop least-invoked-first; `/doctor` estimates listing cost).
- Four buckets are the right cut — revisit if usage shows Backfill or Standing consistently empty or ignored.
- A capped durable probe is enough for Backfill accuracy — revisit if Backfill proves wrong after compactions or session resumes.

### Out-of-scope

- A deterministic `UserPromptSubmit` routing hook that injects skill mappings on every message — deliberately deferred, consistent with the same deferral already recorded in `/discipline:use-your-skills`; the seam is owned by a hooks-capable plugin.
- Changing `/session-flow:workflow`, `/session-flow:orient`, or `/discipline:use-your-skills`.
- A new plugin; this lands in `session-flow`.
- Agents, commands, and MCP tools as recommendation candidates (skills only in V1).

### Deferred questions

- Q4 — Usage-metrics-informed surfacing: should never-run and rarely-run skills be boosted, reading `~/.claude.json` `skillUsage` (`usageCount` / `lastUsedAt`, empirically verified but undocumented internal state) or OTEL telemetry (documented, opt-in, already read by `/claude-ops:observability`)? V1 ships a named seam only. Defer until V1 is in use and the bucketing proves itself; **arbiter: USER-RESERVED** (adds a data source and changes acceptance criteria).
- Q10 — Should a sibling decision-tree reference file (the `PHASE-BOUNDARIES.md` pattern from Matt Pocock's `ask-matt`) ship alongside, or does `/session-flow:workflow` already own phase-boundary routing? Defer until the body is drafted and the overlap is concrete; **arbiter: /planning:plan**.

## Plan

<empty — populated by /planning:plan>
