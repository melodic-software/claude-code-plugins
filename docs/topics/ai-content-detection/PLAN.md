# ai-content-detection — PLAN

## Brief

### TLDR

- New marketplace plugin **`ai-slop`**: detect and remove AI-writing tells ("slop") from checked-in markdown prose.
- One skill: read-only **audit** as the default action, **fix** as an explicit follow-up action (chainable in one invocation on request).
- Two-layer detection: deterministic `detect.sh` for mechanical tells (em-dashes, emojis, banned vocabulary, "not X but Y" constructions, Unicode artifacts) + a judgment rubric for non-mechanical signs (puffery, editorializing, rule-of-three, sycophantic framing).
- Rule set seeded from Wikipedia's ["Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing), distilled into a bundled versioned catalog under upstream-drift tracking, plus our own additions layered explicitly on top.
- Findings conform to the detector-findings convention so `review:fanout fix` can consume them; the fix action is guarded by a semantic-diff subagent.

### Goal

Give the fleet a first-class capability to detect and clean AI-writing tells in written output — the text artifacts themselves. An audit pass surfaces every sign from the Wikipedia catalog plus mechanical tells across a repo's checked-in, agent-consumed markdown prose; an opt-in fix pass rewrites the findings without semantic loss. Default scope is the entire repo, prioritizing high-velocity files (frequently changed) and high-impact instruction surfaces (`CLAUDE.md`, `AGENTS.md`, and similar), unless the user names a narrower target.

### Constraints

- Findings files must conform to the shape owned by `plugins/review/skills/fanout/context/default-mode.md` and the producer rules in `docs/conventions/detector-findings/README.md` — including one argued severity-crosswalk row per deterministic rule (enforced by `scripts/check-detector-findings-crosswalk.sh`).
- The fix action never runs without an explicit user request, and every applied rewrite passes a semantic-diff subagent that reverts any change introducing semantic loss or ambiguity (the `docs-hygiene:compress` model).
- Wikipedia content is CC BY-SA — the bundled catalog must attribute the source page and revision, per the upstream-drift convention's citation shape.
- Mechanical rules are threshold- and context-based, never absolute bans: code blocks, fixtures, and deliberate stylistic conventions (this repo's own docs use em-dashes intentionally) must be exemptible via configuration.
- Marketplace conventions apply: plugin registered in `.claude-plugin/marketplace.json`, standard plugin layout (README, CHANGELOG, skills/), skill passes `skill-quality:check`.

### Acceptance criteria

- `plugins/ai-slop/` exists, registered in `.claude-plugin/marketplace.json` with category and tags.
- The skill's default action is read-only and reports findings; `fix` applies rewrites only on explicit request; "detect and rewrite" in one invocation chains both.
- A bundled reference catalog covers every tell on the Wikipedia "Signs of AI writing" page, each classified **mechanical** or **judgment**, with source URL + revision recorded per the upstream-drift convention (recheck trigger included).
- `detect.sh` deterministically detects the mechanical subset (~8–15 rules at V1); each rule has an argued severity-crosswalk row and the crosswalk check script passes.
- Detector output includes test fixtures (sample slop text with known expected findings) and a passing test script per the shell-test-helpers convention.
- Findings emitted by the audit are consumable by `review:fanout fix` (frontmatter `type: review-findings`, correct `branch:`).
- Empty-target invocation runs repo-wide over tracked markdown with high-velocity/high-impact prioritization; a path argument narrows scope to that target.
- Execution contract for repo-wide runs: per-file loop — detect, report; on fix: apply, semantic-diff verify, close. A file is closed when its findings are fixed, explicitly suppressed, or reverted-with-reason.

### Captured assumptions

- The Wikipedia page remains the single upstream source for V1 — revisit if it is restructured, deleted, or a materially better catalog emerges (upstream-drift recheck trigger).
- ~8–15 mechanical rules is the right V1 detector size — revisit if crosswalk authoring proves cheaper/costlier than expected during implementation.
- One skill (audit default + fix action) is sufficient surface — revisit if fix grows enough distinct behavior to warrant its own skill.

### Out-of-scope

- **Write-hooks** (flagging tells on every markdown write, format-plugin style) — post-V1, once the rule set has stabilized against real usage.
- **Non-repo / arbitrary text** (emails, posts, pasted drafts) — named future expansion.
- **Code comments** — owned by `code-tidying:audit-comment-residue`; boundary stays there.
- **Commit messages and PR bodies** — named future expansion.
- **Other content categories with their own actions/criteria/rubrics** — the user's expansion vision, post-V1.
- **Dogfood sweep of this repo's own skills and instructions** (removing em-dashes and other tells from our corpus) — explicit follow-up task after V1 ships; the plugin's first real-world target.

### Deferred questions

- Q12 — Exact V1 mechanical-rule roster and each rule's thresholds/exemptions — defer until planning; **arbiter: /planning:plan**
- Q13 — Primary skill name (`check` vs `audit`) and action-verb surface — defer until planning; **arbiter: /planning:plan**
- Q14 — High-velocity/high-impact prioritization mechanics (git-log frequency window, instruction-surface list) — defer until planning; **arbiter: /planning:plan**

## Plan

<!-- populated by /planning:plan -->
