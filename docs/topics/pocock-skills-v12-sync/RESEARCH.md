# RESEARCH — mattpocock/skills v1.2 sync

Digest of Matt Pocock's v1.2 release (video `gaDdrDdczO4` + changelog article + v1.2.0 GitHub
release notes + full repo inventory at HEAD v1.2.3 `84fdeff`), run 2026-08-08 via
`/knowledge:youtube-digest`. Working slice (transcript, frames, claim inventory, verification
reports) is memory-tier and uncommitted; this file carries what later lanes need.

## What v1.2 shipped (all verified against release notes + repo tree)

- **Claude Code plugin in the official marketplace** (#536): `claude plugins install
  mattpocock-skills`; sha-pinned listing; skills.sh remains the editable-copy installer; native
  Codex plugin deferred (upstream ADR 0002: Codex manifest takes a single skills path and drops
  symlinks).
- **Codex sidecars** (#551): `agents/openai.yaml` beside every SKILL.md;
  `policy.allow_implicit_invocation: false` = Codex analog of `disable-model-invocation: true`;
  `AGENTS.md` symlink → `CLAUDE.md` (materializes as a plain file on Windows checkouts).
- **New:** `wait-what` (#751) — one-sentence user-invoked verbosity corrective (re-pitch with
  context, ASD-STE100 Simplified Technical English, ubiquitous language from CONTEXT.md);
  `wizard` (#680) — model-invoked generator of interactive bash wizards for human-only steps
  (fixed `template.sh` library above a STAGES marker; deterministic, secrets never reach the
  agent); `to-questionnaire` graduated to Productivity (#593).
- **Changed:** `grilling` family runs frontier rounds (#593/#532); **breaking rename**
  `writing-great-skills` → `writing-for-agents` (#763; GLOSSARY merged in, SKILL-MECHANICS.md
  split out, new "cache" pruning term); `prototype` → single shareable HTML file + capture on
  `prototype/<name>` branch (#763); `wayfinder` → decision-ticket term + parallel `/research`
  subagent burn-down (#763); `ask-matt` → phase-boundaries decision tree (continue → /clear →
  /handoff → subagent → /compact; smart zone ~120k→~150k) (#763);
  `improve-codebase-architecture` → YAGNI scoping filter (#533); friendlier setup +
  `.scratch/<feature>/issues/<NN>-<slug>.md` ticket layout (#502).
- **Removed six skills** (#752): `ubiquitous-language`→`domain-modeling`,
  `design-an-interface`→`codebase-design` (+`DESIGN-IT-TWICE.md`), `qa`→`triage`+`to-tickets`,
  `request-refactor-plan`→`to-spec`+`improve-codebase-architecture`; `edit-article` +
  `obsidian-vault` deleted with the `personal/` bucket.
- **Post-video patches:** v1.2.2 — `writing-for-agents` sidecar dropped the policy line (it had
  hidden the skill from Codex); v1.2.3 — `diagnosing-bugs` gains a Redact-secrets section,
  subagent-dispatch language made harness-neutral, `wizard` drops time estimates.

## Corrections to secondary sources

- Video caption "24K stars" is an auto-caption garble: `gh api` 2026-08-08 → **209,779 stars**
  (docs-site frame shows 204,298 at recording).
- ASD-STE100 is real: international standard since Issue 9 (2025-01-15); 53 writing rules +
  ~900-word dictionary ([asd-ste100.org](https://www.asd-ste100.org/)).

## Outputs

- Verified 35-skill map: [`his-ours-map.md`](his-ours-map.md) (fresh-context adversarial
  verification found and fixed 3 errors before commit).
- Provenance SSOT: [`docs/upstream/mattpocock-skills.md`](../../upstream/mattpocock-skills.md).
- Lane plan: [`PLAN.md`](PLAN.md).
