# web-writing-conciseness

Topic slug: `web-writing-conciseness`. Interview ledger and discovery artifacts:
`.work/web-writing-conciseness/` (memory tier, not committed). Status: Brief in progress
(round 1 of the interview locked 2026-09-05; round 2 open).

## Brief

### TLDR

- A new small plugin (working name `writing`, category `presentation`) with one reactive skill
  that rewrites a wall of text for scanning human readers, and one doctrine reference file.
- Doctrine derived from NN/g (concise, scannable, objective), GOV.UK, US plain language, Google,
  Microsoft, and BLUF, paraphrased with drift stamps; NN/g is never vendored.
- Reciprocal routing: ai-slop, docs-hygiene:write-for-humans, and discipline:tighten-your-output
  Boundaries point at the new skill for reader-facing prose; write-for-agents gets a pointer to
  the universal brevity rules.
- Proactive reach by presence-gated pointers at the composition sites (work-items templates,
  pull-request create 2.4.1, bugs:write, planning:prd); no hook.
- Judgment-only V1 with before/after word counts; thresholds shipped as a labelled fallback.

### Goal

Agents stop posting walls of text that product owners and executives cannot read. Any prose an
agent writes for a human reader in an external system (Jira, ADO, Linear, GitHub PR bodies and
comments, status updates) or in repo human docs (READMEs, changelogs) leads with the bottom line,
carries about half the words a first draft would, and is scannable, without dropping any
decision, number, ask, error, or warning. The same capability cleans up text that has already
been posted, on request.

### Constraints

- No new always-on hook: the marketplace hook budget is over ceiling and its rule 2 never relaxes.
- NN/g articles are copyrighted with terms that forbid reposting; only brief quotes with credit.
  Paraphrase with a four-part drift stamp per `docs/conventions/upstream-drift/README.md`.
- The ai-slop catalog is a closed CC BY-SA corpus; new material cannot be added to it.
- Cross-plugin references cite `/plugin:skill` by name with presence gating, never a sibling's
  `context/` or `reference/` file (encapsulation rule).
- Every touched plugin needs a version bump and CHANGELOG entry; every new or modified SKILL.md
  needs `evals/evals.json` (`--require-evals`).
- A rewrite must never break the pr-issue-linkage contract (closing keyword line plus the four
  required sections) when the target is a PR body.
- Draft PR #3766 (code-metrics) edits `.claude-plugin/marketplace.json`,
  `scripts/skill-leaf-name-registry.txt`, `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md`; rebase
  after it merges or expect list conflicts.

### Acceptance criteria

- A new plugin directory with `plugin.json`, README, CHANGELOG, one reactive SKILL.md, a
  `reference/` doctrine file, and `evals/evals.json`; `skill-quality:check` and
  `scripts/check-skill-leaf-names.sh --check` pass.
- The doctrine file separates universal brevity rules (about half the words, no filler,
  expletives, intensifiers, or redundancy, active voice, one idea per sentence) from human-only
  scannability rules (BLUF, front-loaded headings, lists for scannable facts, bounded bold), and
  names its thresholds as a labelled fallback: split sentences over 25 words, at most 5 sentences
  per paragraph, bottom line in the first sentence.
- The reactive skill outputs BLUF first, details after, reports before and after word counts, and
  never edits a posted record in place unless explicitly told.
- For inputs longer than a few paragraphs the skill runs the fresh-context semantic-diff guard
  (the compress and ai-slop fix contract) with an added "dropped decision, number, or ask" class;
  for short comments it shows the diff inline.
- The three excluding Boundaries (ai-slop audit, write-for-humans, tighten-your-output) and
  write-for-humans eval case 5 route reader-facing prose to the new skill; write-for-agents points
  at the brevity rules.
- Presence-gated pointers exist at: work-items `track add` body, `done` closing comment, triage
  `apply-outcome`, `decompose` step 4, `attend-queue` answer-back; pull-request `create` section
  2.4.1; `bugs:write`; `planning:prd`.
- Each NN/g-derived rule carries a drift stamp and a `reference/sources.md` entry; no article text
  is vendored.
- `scripts/affected-tests.sh --run` passes for the change set.

### Captured assumptions

- Jira and ADO have no bundled write path in this marketplace, so destination guidance for them
  lives in the skill body, not on a seam verb. Revisit if a Jira or ADO adapter gains a write path.
- The consuming repo's ai-slop config governs em dashes; this plugin adds no em-dash rule. Revisit
  if the em-dash purge campaign changes `.claude/ai-slop.json`.

### Out-of-scope

- A deterministic detector script (sentence length, intensifier density, passive heuristic) and
  Vale rules: deferred post-V1 with a recorded promotion path.
- A `.claude/writing.json` config file and its setup skill: deferred; thresholds are a labelled
  fallback overridable by CLAUDE.md prose.
- A PreToolUse hook on `gh pr create` or `gh issue comment`: deferred until demonstrated demand
  and a measured budget share.
- Requesting written permission from NN/g to vendor articles.

### Deferred questions

(none yet; round 2 in progress)

## Plan

(empty; populated by /planning:plan)
