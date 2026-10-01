# Sonnet 5.5 prompting guide: repo changes

## Brief

### TLDR

- A new Sonnet 5.5 model-adaptation chapter, current-model cleanup (Fable 5.1, Opus 5.5 and Sonnet 5.5 are current; Opus 5, Opus 4.8 and Sonnet 5 are fallback-only), and tier tables updated.
- Verification by runnable checks instead of "please verify" prose; toolchain and confirm stop counting fake checks and report skips by name.
- An effort floor: medium for code-changing or verifying work on every model that supports effort, stated once in `docs/plugin-philosophy.md`, and enforced where the repo sets effort (agent and skill pins) by an audit row. Tier tables name aliases, so they need no drift check (amended at planning).
- The links-only retrofit: no copied or paraphrased upstream content in any file this PR touches. That covers the confirmed record and blog-pointer files, the model chapters, and the misses the plan review found. The verification-record rule becomes pointer + as-of + recheck trigger, and the rest of the repo is a follow-on (amended at planning).
- docpage-digest pipeline fixes, including the blog extractor from the blog-digest branch. It all ships as one draft PR with one commit per area, and six follow-on issues are filed.

### Goal

The repo reflects what Anthropic's [Sonnet 5.5 prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5) means for how this marketplace's skills, agents, catalogs and conventions steer current Claude models. Every such decision is stated in our own words and points at the live upstream section instead of copying it. The repo stays honest when models change because nothing hardcodes a model version where an alias works, and each per-version chapter carries a recheck trigger (amended at planning: no drift check). It ships as one draft PR from `feat/sonnet-5-5-prompting-digest` under one parent issue whose sub-issues the PR closes, including the reopened [#4347](https://github.com/melodic-software/claude-code-plugins/issues/4347) with its own `Closes #4347` line.

### Constraints

- **No copied upstream content, strict (Q22, Q30, Q42, Q43, Q44).** Repo files hold our decisions in our own words, a link to the exact upstream section, an as-of date and a recheck trigger. Upstream facts are read live and never stored, not even one line. Pointer shape: "for XYZ, see <link>". A source conflict is recorded only as "pages X and Y disagree on topic T", with both links, a date and a trigger.
- **Main doc pages over blog posts (C10).** A blog post gets at most a note to correlate. Never file issues on Anthropic's repos; record conflicts in our own files instead.
- **Tie-break (Q5).** On model behavior the model's prompting guide wins; on Claude Code delivery the Claude Code docs win.
- **Mechanisms are the plan's (Q1).** See Deferred questions.
- **Delivery (Q24, C6).** One draft PR, Conventional Commits title, PR body contract. Split out only a part that stalls CI.
- **Cross-branch (Q27, Q37, Q50).** This PR merges first; the blog-digest branch rebases after it. This branch is the single editor of docpage-digest `SKILL.md`, `context/anthropic-docs-profile.md`, `dual-verification.md` and audit-instructions criteria row I17-b. Findings from other branches for those files fold in once their own user accepts them, links-only; one that would change a decision here comes back to the user as a question. Intake closes when the PR is marked ready. `docs/upstream/**` and the digest queue: each branch adds only its own entry.
- **Out of this rule:** vendored copies of licensed third-party skills are decided by the Poteto session's Q54 (see `.claude/rules/vendor-docs-are-not-style.md`).
- Digest findings reach instruction surfaces only through this interview and the user's approval (C5). Digest working data stays in ignored `.work/`.

### Acceptance criteria

Amended at planning, 2026-09-30 to 2026-10-01, with the user's approval in session. The effort guard hook, the effort table and the drift check are dropped, two follow-ons are added, and criterion 2 is made measurable. Struck lines show what changed.

- No file calls a retiring model current, except the playbooks host skill's name until its rename issue lands and the boris playbook's third-party tip content; a Sonnet 5.5 session is routed to the Sonnet 5.5 chapter.
- ~~Every file this PR changes, which is the whole retrofit per Q45, contains no copied or paraphrased upstream text, and the attribution audit reports zero copies.~~ Every file this PR changes contains no copied or paraphrased upstream text. Over those files, the attribution audit reports zero fingerprint-confirmed and zero source-fetched-similar findings, and a fresh-context agent reviews every llm-suspected finding. Each converted catalog row keeps a firing rule in our own words that works without a live fetch.
- Every volatile specific carries a topic pointer to the exact section, an as-of date and a recheck trigger.
- The audit and posture catalogs fire on a sonnet-5-5 target for the widened rows and the new rows.
- No code-changing or verifying agent or skill pins an effort below medium on any current model, every agent pins its effort, and the claude-config audit flags a code-changing component pinned below medium.
- ~~IF the effort table has no row for the running model or the hook errors, THEN the hook never blocks; at most one non-blocking notice.~~ Dropped with the hook.
- ~~WHILE a model on Claude Code's model page has no row in the effort table, the plugin-philosophy tier table, the loop-lane tier table or the model-adaptation chapter index, or a row names an unlisted model not marked fallback-only, the drift check fails.~~ No tier table names a model version: each names a Claude Code alias and points at Claude Code's model page.
- IF a check can't run only because declared dependencies are missing, THEN the workflow installs them with the project's own package manager, never sudo, within the permission mode, before reporting a skip.
- IF a check is syntax-only or failed to start, THEN toolchain:check and verification:confirm don't count it, and a skipped check is named with its reason and never reported as done.
- The blog extractor's fixture test passes, and its output has table separator rows, no widget or video label text, and no blank line opening a code block.
- The PR passes the required check and the repo's existing lint and tests.
- The ~~five~~ seven follow-on issues exist and are linked from the parent issue.
- IF installing declared dependencies would run install scripts, change a tracked file, or install a tool itself, THEN toolchain:check and verification:confirm don't do it. Only a missing tool or missing dependencies blocks a "done" claim; a consumer opt-out or a not-applicable skip never does.

### Captured assumptions

- The ledger's answer text is authoritative where a page commitment list predates a revised answer (Q24, Q29, Q30, Q34, Q36, Q37, Q43, Q45): revisit if a reviewer finds a commitment the ledger dropped. Ledger: `.work/sonnet-5-5-prompting-digest/interview-checklist.md`.
- "Current" means the model list on Claude Code's model page, read live (Q35): revisit if Claude Code stops publishing that list.
- The `haiku` alias follows the current Haiku (loop-lane README, "Runtime resolution is by model alias only"): revisit if Haiku 5.5 ships under a different alias.
- The blog extractor source is staged at `.work/sonnet-5-5-prompting-digest/staged/extract_blog_body.py` (moved with the blog-digest session's user's confirmation): revisit if that branch still commits it.
- Source conflicts already found and to be recorded as disagreements: advisor-model compatibility, Priority Tier availability, `between_tools` reachability from Claude Code, models overview vs the Sonnet 5.5 blog on where to start (`.work/sonnet-5-5-prompting-digest/peer-inputs.md`): revisit if any listed page changes.

### Decisions

Amended at planning, 2026-09-30, with the user's approval in session. Each change, and the answer it replaces, is under "Plan changes after the Brief" in the Plan below.

- **Model coverage.** New `plugins/playbooks/reference/model-adaptation/sonnet-5-5.md`, structured from the Sonnet 5.5 page and the Sonnet 5 lineage, with the Opus 5.5 chapter at most a loose reference (Q2). Retire Opus 4.8, Sonnet 5, Opus 5 and Fable 5 from "current" everywhere. Keep slim fallback-only chapters for Opus 5, Opus 4.8 and Sonnet 5 while Claude Code still names them (Q19). Effort-table rows cover Fable 5.1, Opus 5.5, Sonnet 5.5 and Haiku 4.5; fallback models are marked fallback-only (Q31).
- **Tiers and routing.** Tier tables name Sonnet 5.5 (Q9). Repo defaults follow Anthropic's recommendations, and the override points are documented; the user's routing stays user-scope (Q11). The Sonnet 5.5 tier row points at the models overview and Claude Code model config, with a blog-correlate note; the "consequential verdict at session tier or above" rule is unchanged (Q36). The mechanical tier names the `haiku` alias, and nothing moves to Haiku in this PR (Q48). The tier-table and loop-lane recheck triggers read "any new model on Claude Code's model page" (Q35).
- **Verification (Q3, Q4, Q21, Q26, Q29).** Remove instructed-verification prose. A code-changing component has a runnable check or says why not, and its done report shows the command and its result. toolchain and confirm: install declared dependencies before reporting a skip; don't count syntax-only or failed-to-start checks; name a skipped check with its reason. The Sonnet 5.5 verification paragraph is not shipped; the chapter names its trigger and links the page section. At xhigh/max, a model-conditional posture: run real checks, then stop, with no self-started review rounds or reviewer subagents; gates this repo requires count as review the user asked for. The chapter carries the reviewer note and a pointer to Claude Code's subagent caps.
- **Effort (Q10, Q17, Q18, Q32, Q47).** Every agent pins its effort: code-reviewer and ci-log-auditor high; ecosystem-specialist, doc-drift-detector and explorer medium; Opus agents unchanged pending the sweep. The effort table is the single source of truth; every model row carries the medium floor for code-changing or verifying work and links that model's effort docs. A `${CLAUDE_EFFORT}` self-check goes in code-changing skills; a data-driven, fail-open, warn-only guard hook with an off switch; and an audit rule for low-effort pins. The drift check passes before the hook ships.
- **Drift (Q35).** One check covers the effort table, the plugin-philosophy tier table, the loop-lane tier table and the chapter index; see the acceptance criterion. A model with no chapter gets an explicit "no chapter" row.
- **Catalogs.** All seven instruction-audit parts (Q6), the three posture parts (Q7), and the three safeguard parts (Q12), all in pointer form (Q44).
- **Chapter content.** Hook-text convention and a trust-chapter line, document-only (Q8). Chapter notes on JSON output and tolerant tool calls; image findings; a cross-model "reading dense images" playbook note (Q14). Each snippet's page section is linked with our own trigger note. Authoring guidance says which vehicles are system prompt. Medium-effort Sonnet 5.5 workers get our own-wording finish-then-stop instruction (Q23). Four handed-over pointers: prompt caching, fast mode being Opus-only in Claude Code (and unrelated to the loop-lane "fast" tier), the docs-index row, and the loop-lane fast-tier bullet with its classifier-fallback gap (Q42).
- **Retrofit (Q43, Q45).** Rewrite `.claude/rules/skill-bodies-state-current-rules.md` and `docs/conventions/upstream-drift/` to pointer + as-of + trigger. Convert the 22 files carrying the old record and the 29 files pointing at blog posts. Rewrite the Opus 5.5 and Fable 5.1 chapters and the three fallback chapters links-only. Re-justify the retiring-model audit rows and repoint the Fable 5 posture citations (Q33). Rewrite the model-adaptation contributor rule (Q30).
- **Knowledge pipeline (Q13, Q15, Q34, Q46, Q49).** The pin-manifest script, the Codex no-network note, per-unit corrections files, and the model-alias spawning gap (Q15 parts 1-4). The platform docs corpus searched first, the work root resolved to the session's worktree, one standard absence corpus, and a split-applicability quote rule (Q34). The blog extractor lands in docpage-digest `scripts/` with a fixture test and its three output flaws fixed. A decisions-only record under `docs/upstream/`, a `docs/official-docs.md` row and a queue entry. Graduating the slice to knowledge-corpus stays deferred.

### Out-of-scope

- Q20 (where the page's snippets live, first draft): withdrawn; superseded by Q23 after the no-copy decision.
- Follow-on efforts, each its own issue linked from the parent:
  1. Gate-based verification across Sonnet 5.5, Opus 5.5 and Fable 5.1, including must-not-break gate definitions (Q3, Q26), the reviewer-weaker-than-implementer gap (Q32), and review-on-Sonnet vs the tier rule (Q36).
  2. Renaming the Fable 5 playbooks host skill (Q19).
  3. A linked-page research phase for docpage-digest (Q15 part 5).
  4. A shared crop/zoom capability (Q14).
  5. The effort eval sweep, testing Haiku 5.5 once it ships for the three mechanical agents and the loop-lane fast tier (Q10, Q48).
- claude.com/blog extractor support: routed with the Spending Your Effort session's blog-host finding (Q49).
- Interview-page bugs: [#5569](https://github.com/melodic-software/claude-code-plugins/issues/5569).
- Moving any agent or lane to Haiku (Q48).

### Deferred questions

All four were resolved at planning. See "Plan changes after the Brief" (Q38-Q41 row) and the Handoff commit areas.

- Q38: Drift check: CI or schedule, whether it gates PRs, how it reads Claude Code's model page; defer until planning; **arbiter: /planning:plan**
- Q39: Guard hook: host plugin, consumer off-switch default, how "code-changing" is classified; defer until planning; **arbiter: /planning:plan**
- Q40: How the hook and the skill self-check detect unattended runs (ask vs warn; must never hard-stop a lane); defer until planning; **arbiter: /planning:plan**
- Q41: Commit areas for the one PR, and who may split out a stalled part; defer until planning; **arbiter: /planning:plan**

## Plan

### Goal

**What:** land every Brief decision as amended below in one draft PR from `feat/sonnet-5-5-prompting-digest`. That covers the Sonnet 5.5 chapter, current-model cleanup, alias-based tier tables, the medium effort floor, the verification counting rules, the catalog rows, the whole links-only retrofit and the docpage-digest fixes.
**Why:** current Claude models get guidance that matches what Anthropic publishes, and no repo file stores upstream text that can go stale.
**Done when:** the PR meets every acceptance criterion in the Brief, the required `ci-status` check is green, and the parent issue links all seven follow-ons.

### Plan changes after the Brief

The user approved each change below explicitly in this session (2026-09-30), after a challenge to over-engineering. The ledger rows are set to `answered` with the reconfirmed text.

| Q | What the user said | What the plan does now | New external effect | Source |
|---|---|---|---|---|
| Q18, Q47 | Effort table as single source of truth, `${CLAUDE_EFFORT}` self-check, warn-only guard hook, audit rule | Hook, self-check and effort table dropped: the model cannot change its own effort, so their output had no one to act on it. The medium floor is one sentence in `docs/plugin-philosophy.md` with a pointer to each model's defaults on Claude Code's model page, plus a claude-config audit row for a code-changing component pinned below medium | none | plan (user-approved challenge) |
| Q31, Q35 | Effort-table rows per model; one drift check over four model tables | No drift check. The cause is removed instead: the tier tables name aliases (`sonnet`, `opus`, `haiku`) and point at the model page, and the loop-lane alias-to-version binding table is deleted. The chapter index keeps per-version chapters; a model with no chapter gets the playbook's existing no-chapter rule | none | plan (user-approved challenge) |
| Q19 | Keep slim fallback-only chapters for Opus 5, Opus 4.8, Sonnet 5 | Unchanged. A deletion was proposed and approved, then withdrawn: Claude Code's model page says the session continues on the fallback model, so these chapters are read | none | stress-test finding |
| Q4, Q29 | Install declared deps before skipping, bounded by permission mode; a skipped check never counts as done | Narrowed: install only from the lockfile with scripts disabled, never install a tool, fail if a tracked file changed. Only missing-tool or missing-dependency skips block "done" | none | stress-test finding (user-approved) |
| Q45, criterion 2 | Whole retrofit; attribution audit reports zero copies | This PR converts the confirmed record and blog-pointer files, every whole file the PR touches, and the misses the plan review named. The remaining files that quote linked upstream pages (about 230) become follow-on 7. Criterion 2 counts the audit's fingerprint-confirmed and source-fetched-similar tiers, with a fresh-context review of llm-suspected findings | one more issue filed (Phase 0) | reviewer fix + stress-test finding (user-approved) |
| Q13, Q46 | `docs/upstream/` decisions record and a docpage-digest queue entry | Both dropped. The chapter carries each decision with its pointer, as-of date and trigger, and the queue lists only undigested pages. The `docs/official-docs.md` row stays | none | plan (user-approved challenge) |
| Q45 | Whole retrofit, "EVERYTHING" | Three groups stay untouched: released CHANGELOG entries (CI forbids edits), `.claude/unhobble/**/evidence/` records, and the boris playbook's third-party tip content. Criterion 1 names the boris exception | none | plan (user-approved) |
| Q24 | Five follow-on issues | Seven: adds a post-merge `/overengineering:audit` of CI and hooks (including the audit catalog's per-model version tokens), and the tree-wide no-copy retrofit of the remaining files | two more issues filed (Phase 0) | plan (user-approved) |
| Q38-Q41 | Deferred to planning | Q38 and Q39 dissolve with the hook and the drift check. Q40: nothing needs to detect unattended runs, since nothing asks or blocks. Q41: see Execution shape | none | plan |

### Standards grounding

No `docs/standards/` index exists, so these were inferred from `docs/conventions/` (resolution ladder rung 4).

| Surface | Sections cited | Layer provenance |
|---|---|---|
| Verification records | `docs/conventions/upstream-drift/README.md` (required parts, firing, adopters); `.claude/rules/skill-bodies-state-current-rules.md` | team |
| Commits and PRs | `docs/conventions/commit-convention/`; `.claude/rules/pr-body-contract.md`; `AGENTS.md` (draft PRs) | team |
| Plugin release | `docs/migration-playbook.md:494-496` (a version bump is the only delivery vehicle); `scripts/check-changelog-parity.sh` | team |
| Hook text | `docs/conventions/hook-observability/README.md` (Phase 5 convention addition) | team |
| Python | `.claude/rules/ruff-pin.md` (`scripts/run-ruff.sh`, never a bare ruff) | team |
| Mechanisms | "Build only what someone acts on" (global instructions, melodic-software/dotfiles#965) | user-global |

### Target record shape (used by every phase)

```markdown
<our decision, in our words>
- **Pointer**: for <topic>, see <link to the exact upstream section>.
- **As of**: YYYY-MM-DD
- **Recheck trigger**: <an observable event, never a bare date>
```

A blog link appears only as a "correlate with <blog link>" note beside a main-docs pointer. A conflict is recorded only as "pages X and Y disagree on topic T", with both links, a date and a trigger.

### Phase 0: Tracker setup [TODO]

Runs after plan approval. Every write is the user's approved action.

- [ ] **Phase-entry check:** `gh issue list --state all --search 'Sonnet 5.5 prompting guide in:title' --json number,title,state`, and the same for each follow-on title below.
- [ ] If a match exists, pivot: comment on that issue instead of creating a duplicate, and record its number.
- [ ] If none exists: create the parent issue, "Apply the Sonnet 5.5 prompting guide to the marketplace", with a body that states the Goal and links this PLAN.md on the branch.
- [ ] Reopen #4347 and add it as a sub-issue of the parent.
- [ ] File seven follow-ons, each linked from the parent's body (not as sub-issues, so the PR does not close them):
  1. gate-based verification across Sonnet 5.5, Opus 5.5 and Fable 5.1 (Q3, Q26, Q32, Q36);
  2. renaming the Fable 5 playbooks host skill (Q19);
  3. a linked-page research phase for docpage-digest (Q15 part 5);
  4. a shared crop/zoom capability (Q14);
  5. the effort eval sweep, including Haiku 5.5 when it ships (Q10, Q48);
  6. an `/overengineering:audit` of CI and hooks, including the audit catalog's per-model version tokens;
  7. the tree-wide no-copy retrofit: inventory every remaining file that quotes a linked upstream page with `/attribution:audit`, then convert plugin by plugin, running each catalog skill's evals before and after.
- **Sanity Check:** `gh issue view <parent> --json body --jq .body` contains all seven follow-on numbers, and `gh issue view 4347 --json state --jq .state` prints `OPEN`.

### Phase 1: Links-only rule and retrofit [TODO]

Review: code-design

Phase 1a runs in the main session and fixes the target shape. Phase 1b converts files.

**1a. Rule, convention and consumers**

- [ ] **Pre-flight (first item):** classify every hit of `git grep -lE 'Recheck trigger|\*\*Basis|four-part' -- scripts .github 'plugins/*/scripts' 'plugins/*/skills/*/scripts' 'plugins/*/hooks'` as a parser of the record shape (update it), a comment carrying a record (convert it in 1b), or unrelated. Known hits include `plugins/attribution/skills/audit/scripts/check-stamps.sh`, `scripts/gen-hook-event-registry.sh` (writes records into a committed registry) and `plugins/skill-quality/scripts/check-skill.sh`. Record the classification in the phase notes.
- [ ] `.claude/rules/skill-bodies-state-current-rules.md` (body and frontmatter `description` at :2): replace the four-part record with the target shape. The `## Next` requirement stays.
- [ ] `AGENTS.md:42`: the "Conventions that load on demand" row describing the rule becomes the new shape.
- [ ] `plugins/skill-quality/scripts/check-skill.sh:450-455,685-687`: the comments naming the four-part record as the conforming shape name the new shape.
- [ ] Main session only: any `plugin.json` description or keyword naming the four-part record or upstream-drift (for example `plugins/attribution/.claude-plugin/plugin.json`).
- [ ] Keep `docs/conventions/recommendation-basis/` and its `Basis:` labels out of scope: they label recommendations, not upstream records.
- [ ] `docs/conventions/upstream-drift/README.md`: replace "Required parts" and the "No verbatim quote, no claim" rule with the target shape, and update the adopters list.
- [ ] `plugins/playbooks/reference/model-adaptation/AGENTS.md`: replace the verbatim-quote rules with links-only (Q30).
- [ ] `plugins/attribution/skills/audit/SKILL.md` (description at :2 and the dispositions at :36) and its scripts: "four-part stamped record" becomes the target shape. Then run `node plugins/attribution/skills/audit/scripts/fingerprint.test.mjs` and the `check-stamps.test.sh` suite.
- [ ] Update each parser that the pre-flight classified as reading the record shape, together with its test.

**1b. Retrofit inventory**

Convert each file to the target shape. Remove every quoted or paraphrased upstream sentence, move pointers to the main docs page section, and keep a blog link only as a correlate note. In a catalog (audit criteria, postures, checklists, official guidance), each row keeps a firing rule in our own words that works without a live fetch.

Phases 2-6 follow the same rule: every file a phase edits is converted whole by that phase's worker (criterion 2 covers every file the PR changes).

| File | Action | Why |
|---|---|---|
| [ ] `docs/conventions/liveness-assertion/README.md` | MODIFY | record |
| [ ] `docs/conventions/native-references/README.md` | MODIFY | record |
| [ ] `docs/conventions/topic-docs/README.md` | MODIFY | record |
| [ ] `docs/conventions/loop-lane/README.md` | MODIFY | declared adopter (:937); tier-table edits are Phase 3 |
| [ ] `docs/conventions/hook-config-delivery/README.md` | MODIFY | declared adopter |
| [ ] `docs/official-docs.md` | MODIFY | declared adopter (link plus verified-date rows) |
| [ ] `docs/upstream/opus-5-5-usage-guide.md` | MODIFY | adopter + blog pointer |
| [ ] `docs/upstream/claude-code-mods/sources.md` | MODIFY | blog pointer |
| [ ] `docs/upstream/claudedevs-cost-performance.md` | MODIFY | blog pointer |
| [ ] `docs/adr/0038-restore-the-claude-review-lanes-on-every-push.md` | MODIFY | blog pointer |
| [ ] `docs/finding-your-unknowns.md` | MODIFY | blog pointer |
| [ ] `docs/plugin-philosophy.md` | MODIFY | blog pointer; tier and floor edits are Phase 3 |
| [ ] `docs/specs/context-engineering-corpus-knowledge.md` | MODIFY | blog pointer |
| [ ] `docs/specs/context-engineering-linked-sources.md` | MODIFY | blog pointer |
| [ ] `plugins/ai-slop/skills/audit/reference/catalog.md` | MODIFY | record |
| [ ] `plugins/architecture/skills/record-decision/SKILL.md` | MODIFY | record |
| [ ] `plugins/claude-config/reference/agents-md-liveness.md` | MODIFY | record |
| [ ] `plugins/claude-config/skills/audit-permission-state/reference/criteria.md` | MODIFY | record + blog |
| [ ] `plugins/claude-config/skills/audit-instructions/reference/criteria.md` | MODIFY | blog; catalog rows are Phase 4 |
| [ ] `plugins/claude-config/skills/audit-prompting-postures/reference/postures.md` | MODIFY | blog; posture rows are Phase 4 |
| [ ] `plugins/claude-memory/skills/audit/reference/official-guidance.md` | MODIFY | record + blog |
| [ ] `plugins/claude-ops/skills/observability/SKILL.md` | MODIFY | record |
| [ ] `plugins/claude-ops/skills/plugins/context/scope-semantics.md` | MODIFY | record |
| [ ] `plugins/claude-ops/skills/known-issues/context/action-quality.md` | MODIFY | blog; safeguard trigger is Phase 3 |
| [ ] `plugins/computer-use/skills/diagnose/reference/screenshots-and-zoom.md` | MODIFY | blog |
| [ ] `plugins/docs-hygiene/skills/audit-progressive-disclosure/SKILL.md` | MODIFY | blog |
| [ ] `plugins/docs-hygiene/skills/write-for-humans/reference/sources.md` | MODIFY | record (period-form labels) |
| [ ] `plugins/guardrails/README.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/README.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/context/verified-mechanics.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/skills/check/SKILL.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/skills/migrate/SKILL.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/skills/migrate/reference/sources.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/skills/migrate/reference/verification.md` | MODIFY | record |
| [ ] `plugins/instruction-placement/skills/setup/SKILL.md` | MODIFY | record |
| [ ] `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md` | MODIFY | blog; pipeline fixes are Phase 6 |
| [ ] `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-queue.md` | MODIFY | blog |
| [ ] `plugins/mcp-tools/README.md` | MODIFY | blog |
| [ ] `plugins/mcp-tools/skills/audit/SKILL.md` | MODIFY | blog |
| [ ] `plugins/mcp-tools/skills/audit/reference/checklist.md` | MODIFY | blog |
| [ ] `plugins/mcp-tools/skills/audit-posture/reference/checklist.md` | MODIFY | record |
| [ ] `plugins/performance/README.md` | MODIFY | blog |
| [ ] `plugins/performance/reference/glossary.md` | MODIFY | blog |
| [ ] `plugins/performance/reference/techniques.md` | MODIFY | blog |
| [ ] `plugins/planning/skills/interview/context/session-config.md` | MODIFY | blog |
| [ ] `plugins/playbooks/reference/model-adaptation/opus-5-5.md` | MODIFY | whole chapter links-only (Q30) |
| [ ] `plugins/playbooks/reference/model-adaptation/fable-5-1.md` | MODIFY | whole chapter links-only (Q30) |
| [ ] `plugins/playbooks/reference/model-adaptation/opus-5.md` | MODIFY | slim fallback-only chapter, links-only (Q19, Q30) |
| [ ] `plugins/playbooks/reference/model-adaptation/opus-4-8.md` | MODIFY | slim fallback-only chapter, links-only (Q19, Q30) |
| [ ] `plugins/playbooks/reference/model-adaptation/sonnet-5.md` | MODIFY | slim fallback-only chapter, links-only (Q19, Q30) |
| [ ] `plugins/playbooks/reference/prompt-caching.md` | MODIFY | review miss: restated model availability (:41, :50) |
| [ ] `plugins/playbooks/skills/fable-5/context/calibration.md` | MODIFY | review miss: block quotes beside upstream links |
| [ ] `plugins/playbooks/skills/fable-5/context/context-economy.md` | MODIFY | review miss: block quotes beside upstream links |
| [ ] `plugins/review/context/severity.md` | MODIFY | review miss: verbatim Sonnet 5 guide quote (:15) |
| [ ] `plugins/claude-memory/skills/stateless/reference/official-guidance.md` | MODIFY | review miss: block quotes |
| [ ] `plugins/context-guard/reference/reader-contract.md` | MODIFY | review miss: the record at :389 only; the compaction paragraph (~:296-323) belongs to the blog-digest branch |
| [ ] `plugins/playbooks/skills/fable-5/context/orchestration.md` | MODIFY | blog |
| [ ] `plugins/playbooks/skills/skill-authoring/reference/verification-loops-in-skills.md` | MODIFY | blog |
| [ ] `plugins/session-flow/skills/orchestrate/SKILL.md` | MODIFY | blog |
| [ ] `plugins/session-flow/skills/orchestrate/context/sources.md` | MODIFY | blog |
| [ ] `plugins/session-flow/skills/keep-going/SKILL.md` | MODIFY | the record row at ~:189 only (the reset bullet belongs to the blog-digest branch) |
| [ ] `plugins/typos-format/README.md` | MODIFY | record |
| [ ] each script comment record that 1a classified | MODIFY | record |
| [ ] `plugins/playbooks/skills/boris/**` | KEEP | third-party tip content (user decision) |
| [ ] `**/CHANGELOG.md` released entries | KEEP | `check-changelog-parity.sh --check-preserved` |
| [ ] `.claude/unhobble/**/evidence/*` | KEEP | experiment evidence |

- **Sanity Check:** with the 1b file list saved one path per line in `.work/sonnet-5-5-prompting-digest/retrofit-files.txt`, `xargs grep -lE '^\s*- \*\*Basis(\*\*|\.\*\*)' < .work/sonnet-5-5-prompting-digest/retrofit-files.txt` prints nothing. The `**Basis` label stays legal elsewhere under the recommendation-basis convention.
- **Sanity Check:** `git grep -nE 'claude\.com/blog|claude\.dev/blog|anthropic\.com/(engineering|news|research)' -- docs plugins ':!plugins/playbooks/skills/boris/*' ':!*CHANGELOG.md' ':!docs/topics/*' | grep -vi correlate` prints nothing.
- **Sanity Check:** `/attribution:audit` over the 1b file list reports zero fingerprint-confirmed and zero source-fetched-similar findings. Each llm-suspected finding carries a fresh-context agent's verdict. The findings file is the evidence.
- **Sanity Check:** each converted catalog skill's evals run before and after 1b with the same results (`/skill-quality:check validate-evals <skill>` for the static gate; `/evals:plugin-eval` where a suite exists). A changed result is a regression to fix, not to accept.
- **Sanity Check:** `node plugins/attribution/skills/audit/scripts/fingerprint.test.mjs` exits 0, and `bash scripts/affected-tests.sh --run --base origin/main` exits 0.

### Phase 2: Sonnet 5.5 chapter and model coverage [TODO]

- [ ] Create `plugins/playbooks/reference/model-adaptation/sonnet-5-5.md`, links-only and structured from the Sonnet 5.5 page and the Sonnet 5 lineage (Q2). Contents:
  - pointers with our trigger notes for each page section (Q23);
  - the effort-floor pointer to `docs/plugin-philosophy.md`;
  - the trigger for the verification paragraph, which is not shipped (Q29);
  - the reviewer note and a pointer to Claude Code's subagent caps (Q3);
  - a pointer to the xhigh/max posture, whose text Phase 4 owns in `postures.md` (Q21);
  - JSON-output and tolerant-tool-call notes, image findings, and a pointer to the cross-model dense-images note (Q14);
  - which vehicles are system prompt: only a subagent body and `--system-prompt`/`--append-system-prompt`;
  - the flagged-request fallback pointer (D10.2);
  - caching and fast-mode pointers: fast mode is Opus-only in Claude Code and unrelated to the loop-lane fast tier (Q42);
  - disagreements, each recorded as "pages X and Y disagree on T" only after a live re-check on the day it is written: Priority Tier availability, `between_tools` reachability from Claude Code, and models overview vs the Sonnet 5.5 blog on where to start. The advisor-model conflict was resolved upstream (Claude Code's advisor page now has its own Sonnet 5.5 row, per the blog-digest session, 2026-10-01), so it is not recorded.
- [ ] `plugins/playbooks/skills/fable-5/SKILL.md`, converted whole:
  - :2: the description lists Fable 5.1, Opus 5.5 and Sonnet 5.5 as current, and Opus 5, Opus 4.8 and Sonnet 5 as fallback-only;
  - :19: meta-rule 3 routes Sonnet 5.5 to `sonnet-5-5.md`; Opus 5, Opus 4.8 and Sonnet 5 sessions, including those that arrive by fallback, keep their chapters; the safeguard classifier list becomes a pointer (D10.1 part 1); the system-card paraphrase becomes a pointer;
  - :154: the routing row.
- [ ] `plugins/playbooks/skills/fable-5/evals/evals.json`: add a Sonnet 5.5 routing eval.
- [ ] `plugins/playbooks/skills/fable-5/context/` (new short note): a cross-model "reading dense images" note (Q14).
- **Sanity Check:** `test -f plugins/playbooks/reference/model-adaptation/sonnet-5-5.md`, and `grep -c 'sonnet-5-5.md' plugins/playbooks/skills/fable-5/SKILL.md` prints at least 1.
- **Sanity Check:** `grep -c 'sonnet-5-5' plugins/playbooks/skills/fable-5/evals/evals.json` prints at least 1, and `/skill-quality:check validate-evals fable-5` passes.

### Phase 3: Tiers, effort floor, agent pins and safeguards [TODO]

- [ ] `docs/plugin-philosophy.md`:
  - :1098-1105: the tier table names aliases (`sonnet`, `haiku`; session model for consequential verdicts), points at Claude Code's model page, and documents the override points (Q11).
  - The Sonnet row points at the models overview and Claude Code model config, with a blog-correlate note (Q36).
  - The recheck trigger becomes "any new model on Claude Code's model page".
  - :1118-1119: drop the "current Sonnet and Haiku" sentence.
- [ ] `docs/plugin-philosophy.md:1311-1340` (pin rationale):
  - add the medium-floor sentence for code-changing or verifying work on every model that supports effort, under a heading named "Effort floor", which the Phase 2 chapter links by that heading;
  - note that aliases resolve to different models on Bedrock, Agent Platform and Foundry, with a pointer to the model page's provider section;
  - point at the model page's effort section;
  - correct the claim at :1313 ("Fourteen named agents pin `effort: high`") and its agent list to the new split (eleven `high`, four `medium` counting plan-reviewer);
  - restate the fired recheck trigger with a model-change event.
- [ ] `plugins/discovery/reference/parent-contract.md:133` ("every producing worker … at `effort: high`"): correct it for explorer's `medium` pin.
- [ ] `docs/upstream/claudedevs-cost-performance.md:157` ("13 agents pinned `effort: high`"): correct the count during its 1b conversion.
- [ ] `docs/conventions/loop-lane/README.md`:
  - :379-391: delete the alias binding table and point at the model page's alias table;
  - :393-400: the known-gap note covers the fast tier and the classifier-fallback gap (Q42, D10.1 part 2).
- [ ] `plugins/claude-ops/skills/known-issues/context/action-quality.md:58-73`: the fired recheck trigger is re-read and restated (D10.1 part 3).
- [ ] `docs/official-docs.md:131-139`: add a Sonnet 5.5 prompting-guide row (Q13).
- [ ] Agent pins (Q10):
  - `plugins/review/agents/ecosystem-specialist.md`, `plugins/review/agents/doc-drift-detector.md` and `plugins/discovery/agents/explorer.md` change from `effort: high` to `effort: medium`;
  - `code-reviewer` and `ci-log-auditor` stay `high`;
  - the three medium agents gain our own-wording finish-then-stop instruction (Q23).
- **Sanity Check:** the tier table rows in `docs/plugin-philosophy.md` (the table under the tier heading near :1098) and the loop-lane alias section in `docs/conventions/loop-lane/README.md` (formerly :379-391; the known-gap note below it may name models by version) contain no `(Sonnet|Opus|Haiku|Fable) [0-9]` match. The worker reports the exact line ranges it checked, and the main session reruns the grep on them.
- **Sanity Check:** `grep -h '^effort:' plugins/review/agents/ecosystem-specialist.md plugins/review/agents/doc-drift-detector.md plugins/discovery/agents/explorer.md | sort -u` prints only `effort: medium`, and `git grep -nE '^effort: *low' -- 'plugins/*/agents/*.md' 'plugins/*/skills/*/SKILL.md'` prints nothing.

### Phase 4: Audit and posture catalogs [TODO]

- [ ] `plugins/claude-config/skills/audit-instructions/reference/criteria.md`:
  - D2.1: add the page to Sources (:171-181) as a pointer.
  - D2.2: widen I10 to `sonnet-5-5`, with a dated "Widened to" bullet.
  - D2.3: I8-c is not widened; record it as considered and declined.
  - D2.4: extend I17 and I17-b to the `between_tools` 400s, API-code scope only.
  - Fix I17-b's stale confirm-before-apply carve-out (:1134-1137, :1158-1159; recheck fired, Q37).
  - D2.5: I8-f gets a cross-reference note.
  - D2.6: add rows A21 (tool-discouraging language) and A22 (own countdown after a tool result).
  - D2.7: I28's trigger fired; re-read and restate it.
  - Q33: re-justify rows I8-a, I8-c, I8-d, I10, I17-d, I23 and I27 against current models and drop retired-model tokens that no longer carry meaning.
- [ ] `plugins/claude-config/skills/audit-prompting-postures/reference/postures.md`:
  - D3.1: Sonnet 5.5 pointer block; fix the stale ":11 two model subpages".
  - D3.2, as revised by Q29: a code-changing component has a runnable check or says why not, and its done report shows the command and its result.
  - D3.3: ideas-first on open-ended requests.
  - D3.4, from Q21: no self-started review rounds at xhigh/max, model-conditional.
  - Repoint P2, P5, P6 and P8's Fable 5 citations.
- [ ] `plugins/claude-config/skills/audit/reference/audit-checklist.md:214-215`: new row flagging a code-changing or verifying component pinned below `medium`.
- **Sanity Check:** `grep -c 'sonnet-5-5' plugins/claude-config/skills/audit-instructions/reference/criteria.md` prints at least 3, and the claude-config tests pass under `bash scripts/affected-tests.sh --run --base origin/main`.
- **Sanity Check:** `grep -n 'pinned below' plugins/claude-config/skills/audit/reference/audit-checklist.md` prints the new row.

### Phase 5: Verification doctrine [TODO]

- [ ] `plugins/toolchain/skills/check/SKILL.md` (:117, :127-146, :169, :195) and `plugins/verification/skills/confirm/SKILL.md` (:96-98, :126-128). Changes (Q4, Q29, narrowed at planning):
  - when declared dependencies are missing, install them from the lockfile with install scripts disabled and the project's own package manager (for example `npm ci --ignore-scripts`, `uv sync --frozen`, `dotnet restore --locked-mode`), within the permission mode and never with sudo;
  - never install a tool itself (a runner missing from PATH stays a named skip);
  - if the install changed any tracked file (`git status --porcelain` differs), stop and report it instead of checking;
  - a syntax-only check, or a check that failed to start, does not count;
  - every skipped check is named with its reason. Only an environment skip (missing tool or missing dependencies) blocks a "done" claim; an opt-in-unmet skip and a not-applicable row never do. confirm no longer proceeds on an all-environment-skip run.
- [ ] `plugins/playbooks/skills/fable-5/context/verification.md:96`: the same install rule, then downgrade (Q4).
- [ ] Remove instructed self-verification prose (Q26). Replace each with a runnable check, or delete it:
  - `plugins/docs-hygiene/skills/write-for-humans/SKILL.md:155`
  - `plugins/docs-hygiene/skills/rename-references/context/audit-modes.md:104`
  - `plugins/testing/skills/write/context/write.md:33`
  - `plugins/songwriting/skills/co-write/SKILL.md:112`
  - `plugins/songwriting/skills/diagnose/SKILL.md:67`
  - `plugins/session-flow/skills/orchestrate/SKILL.md:75`
- [ ] Authoring guidance on which vehicles are system prompt: `plugins/docs-hygiene/skills/write-for-agents/SKILL.md` and `plugins/playbooks/skills/skill-authoring/SKILL.md` (Q23).
- [ ] `docs/conventions/hook-observability/README.md`: a hook-text frequency and phrasing convention (D6.1). `plugins/playbooks/skills/fable-5/context/trust-and-authority.md`: one line on mid-turn user messages arriving beside tool results (D6.3). Document only (Q8).
- **Sanity Check:** `grep -n 'skip' plugins/verification/skills/confirm/SKILL.md` shows no line letting an all-environment-skip run proceed to Stage 2, and `grep -nE 'ignore-scripts|frozen|locked-mode' plugins/toolchain/skills/check/SKILL.md plugins/verification/skills/confirm/SKILL.md` prints a line in each.
- **Sanity Check:** `bash scripts/affected-tests.sh --run --base origin/main` exits 0, and `/skill-quality:check check` passes for each SKILL.md changed in this phase.

### Phase 6: docpage-digest [TODO]

All of it is in `plugins/knowledge/skills/docpage-digest/`.

- [ ] `scripts/extract_blog_body.py`, from the staged extractor (sha256 `13dcc3be…`):
  - add a `main()` guard;
  - emit `|---|` table separator rows;
  - drop code-widget and video-control label text;
  - no blank line opening a code fence (Q49).
- [ ] Create `scripts/test_extract_blog_body.py` with a small HTML fixture under `scripts/fixtures/`, plus `scripts/extract_blog_body.test.sh` calling `gate_test::run_suite`. Write the test first and watch it fail on the three flaws.
- [ ] `scripts/pin-manifest.py` writes `verification/pin-manifest.json` (`docpage-pin/v1`), with a test (D13.1).
- [ ] `SKILL.md` and `context/anthropic-docs-profile.md` changes:
  - platform docs corpus searched before certifying vendor-claimed or blog-only (Q34a);
  - work root resolved to the session's worktree, not the main checkout (Q34b; `plugins/knowledge/.claude-plugin/plugin.json:38-43` default);
  - one standard absence corpus, the full code.claude.com llms.txt set (Q34d);
  - a split-applicability quote rule (Q34e);
  - the claude.dev blog extractor line;
  - the Codex no-network note (D13.2);
  - the model-alias spawning gap (D13.5);
  - the stale "effort is session-inherited" gotcha (:257-259), a peer finding.
- [ ] `context/dual-verification.md`: per-unit corrections files (D13.3).
- [ ] Fold in accepted peer findings for these files (Q50), links-only.
- **Sanity Check:** `python3 plugins/knowledge/skills/docpage-digest/scripts/test_extract_blog_body.py` exits 0. Its assertions cover a `|---|` row, no widget label text, and no fence opened by a blank line.
- **Sanity Check:** `bash scripts/run-ruff.sh check plugins/knowledge/skills/docpage-digest/scripts` exits 0, and `bash scripts/affected-tests.sh --run --base origin/main` exits 0.

### Phase 7: Verify and open the PR [TODO]

- [ ] Each touched plugin gets one version bump and one CHANGELOG entry for the PR. The first commit touching a plugin bumps it and opens the entry; each later commit touching that plugin appends its own bullet to the same entry, in the same commit as its source change.
- [ ] Before the gates: `git fetch origin`, then `git diff --stat HEAD...origin/feat/sonnet-5-5-blog-digest -- docs/official-docs.md plugins/session-flow/skills/keep-going/SKILL.md plugins/knowledge` to see overlap with the peer branch. Shared files take separate entries (Q27); report any overlap in the PR body.
- [ ] Run the repo gates locally, one mode per call: `scripts/check-changelog-parity.sh --check`, `--check-bump origin/main`, `--check-preserved origin/main`, `--check-order`; markdownlint on changed markdown; and `bash scripts/affected-tests.sh --run --base origin/main`.
- [ ] Criterion 1 triage: run the broad grep `git grep -nliE '(opus 4\.8|sonnet 5([^.0-9]|$)|opus 5([^.0-9]|$)|fable 5([^.0-9]|$))' -- docs plugins ':!*CHANGELOG.md' ':!plugins/playbooks/skills/boris/*' ':!docs/topics/*' ':!docs/adr/*' ':!docs/specs/*'`, then classify each hit as historical, fallback, test fixture or "calls current". Every "calls current" hit is fixed in this PR. The playbooks host skill name `fable-5` is exempt.
- [ ] Run `/attribution:audit` over every file the PR changes. It reports zero fingerprint-confirmed and zero source-fetched-similar findings, and a fresh-context agent reviews each llm-suspected finding (criterion 2).
- [ ] Open the draft PR. Title: `feat(playbooks): apply the Sonnet 5.5 prompting guide across the marketplace`. Body follows the contract: `Closes #<parent>`, `Closes #4347`, Summary, Fix, Verification, Related.
- **Sanity Check:** `gh pr view --json isDraft,title --jq '.isDraft,.title'` prints `true` and the title, and `gh pr checks` shows `ci-status` passing.

## Blast radius

Blast radius: HIGH
Stress-test needed: Yes. The plan invokes /planning:devils-advocate.
Reason: About 80 files across about 20 plugins change doctrine that every consumer session loads, including how toolchain:check and verification:confirm count checks and install dependencies, and how the playbook routes models. Everything is reversible by revert, and nothing is deleted.

## Stress-test summary

A fresh-context plan reviewer (2 critical, 7 important, 2 suggestions) and a `/planning:devils-advocate` run (1 critical, 6 high, 3 medium, 1 low) reviewed the draft. Every finding was checked against the files or live docs before it was applied.

- **Withdrawn:** deleting the fallback chapters. Claude Code's model page says a session continues on the fallback model (`model-config.md:521`, fetched 2026-10-01), so those chapters are read.
- **Retrofit scope:** greps for the old record and for blog links missed files that quote upstream pages without either marker. 429 files link Anthropic pages, and 284 carry a quoted span of 8+ words. This PR takes the confirmed set, every file it touches, and the named misses; the rest is follow-on 7 (user decision).
- **Criterion 2 made measurable:** the attribution audit cannot fingerprint-confirm a paraphrase (`plugins/attribution/skills/audit/SKILL.md:125`), so the criterion counts two tiers and adds a fresh-context review of the third.
- **Install-before-skip narrowed:** lanes read untrusted PR text while holding push credentials (`AGENTS.md`), so installs run from the lockfile with scripts disabled. Opt-outs never block "done" (`plugins/toolchain/skills/check/SKILL.md:131,196`).
- **Catalog meaning:** converted rows keep a firing rule in our words, and catalog evals run before and after.
- **Mechanics:**
  - `check-changelog-parity.sh` runs once per mode (`scripts/check-changelog-parity.sh:111-117`);
  - the stale "fourteen agents pin high" claims are corrected;
  - the record-rule consumers are added to the pre-flight;
  - the criterion 1 grep became a triage step;
  - area 1 is committed before Wave B;
  - a peer-branch overlap check runs before the PR.
- **Upstream change:** the advisor-model conflict no longer exists upstream (reported by the blog-digest session and applied).

## Execution shape

- **Dependency graph:** Phase 0 runs first (issues). Phase 1a sets the record shape, then 1b converts files. Phases 2-6 each edit files that 1b converts, so they follow 1b. Phases 2-6 touch disjoint files and can run in parallel. Phase 7 follows all of them.
- **Recommended shape:** [EXEC-SHAPE]
  - Wave A: Phase 1b as worker batches, one pilot first, then four in parallel.
  - Wave B: Phases 2-6 as five parallel workers.
  - Area 1 is committed before Wave B starts, so later areas can be staged by path without mixing in retrofit edits. The main session then commits areas 2-6 in order and runs Phase 7.
  - Each Wave B worker runs only its own phase's checks; the main session runs `affected-tests.sh` after all of Wave B returns, since a worker would see other workers' half-done edits.
  - Cost note: about ten worker runs in total versus one long serial session.

| Phase | Surface | Basis |
|---|---|---|
| 0 | main session | tracker writes need the user's approval |
| 1a | main session | sets the shape every worker follows; consumer judgment |
| 1b | opus worker batches by plugin group (pilot `docs/` first) | file-disjoint volume rewrite, judgment per paragraph |
| 2 | opus worker | chapter authoring |
| 3 | opus worker | doctrine tables and pins |
| 4 | opus worker | catalog rows with firing rules |
| 5 | opus worker | cross-plugin skill text |
| 6 | opus worker | script, test and pipeline text |
| 7 | main session | verification, PR |

**Worker scope fence:** each worker is ALLOWED only its phase's file list. Each is FORBIDDEN to touch PLAN.md, any `plugin.json`, any `CHANGELOG.md`, another phase's files, and to stage, commit or push. Each brief carries the divergence-escalation clause from the plan template, word for word. Fallback: a worker that reports it cannot complete, or that edits outside its fence, is stopped, and that phase runs sequentially in the main session.

### Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Retrofit runs first, before the content phases | Phase 1 converts every in-scope file before Phases 2-6 add content, so later phases write in the new shape and never re-convert | Tidy First: structural commits land before behavioral ones (plan template, "Tidy First discipline"); Phases 2-6 edit files in the 1b list | plan |
| [EXEC-SHAPE] Wave A: pilot plus four retrofit workers. Wave B: five content workers | Phases 1b-6 run as opus workers with scope fences; the main session commits | Phases 2-6 file lists are disjoint (checked against each phase's paths); global rule: pilot before a fan-out wider than four | plan |
| [EXEC-SHAPE] Commit areas and order (Q41) | Six Conventional Commits, listed under Handoff | Q41 deferred to planning with `/planning:plan` as arbiter; one commit per area (Q24) | plan |
| [EXEC-SHAPE] No unattended-run detection (Q40) | No phase builds detection | With the hook and self-check dropped, nothing asks or blocks, so no lane can stall | plan |
| [EXEC-SHAPE] One version bump and one CHANGELOG entry per plugin for the whole PR | The first commit touching a plugin bumps it; later commits add lines to the same entry | `scripts/check-changelog-parity.sh --check-bump` compares against the base; recent commits 3184ee418 and 32d7ac5df bump per plugin | plan |
| [EXEC-SHAPE] Record labels: Pointer, As of, Recheck trigger | Phase 1a writes this shape into the rule and the convention | Q43 answer: topic pointer + as-of + recheck trigger; "Recheck trigger" keeps the label existing parsers already know | plan |
| [EXEC-SHAPE] Phase 4 owns the xhigh/max posture text; the chapter points at it | One copy of the wording, in `postures.md` | Two workers writing the same posture would drift (stress-test finding) | stress-test finding |
| [EXEC-SHAPE] The Phase 3 "Effort floor" heading is the link anchor for the Phase 2 chapter | Both briefs name the heading | Phases 2 and 3 run in parallel, so the anchor is fixed in advance (reviewer finding 8) | reviewer fix |

## Open questions

None at plan time. Peer findings for files this branch owns fold in until the PR is marked ready (Q50).

## Handoff to implementation

Approval: attended: approved by the user in session on 2026-10-01

### User-approval gates

- Phase 0 issue filing, and every push and PR action.
- Splitting a stalled part out of the one PR into its own PR (Q41).
- A peer finding that would change a decided answer (Q50).

### Execution shape ([EXEC-SHAPE] tagged)

See Execution shape above. Commit areas (Q41), one Conventional Commit each:

1. `docs: adopt links-only verification records and convert existing records`
2. `feat(playbooks): add the Sonnet 5.5 adaptation chapter and route Sonnet 5.5 sessions to it`
3. `docs: name model aliases in tier tables and set a medium effort floor`
4. `feat(claude-config): extend audit and posture catalogs for Sonnet 5.5`
5. `fix(verification): count only real checks and install declared dependencies before skipping`
6. `fix(knowledge): repair docpage-digest pipeline defects and add the blog extractor`

### Mechanical work

- Before Phase 1, run `git fetch origin main` and merge it if the branch is behind.
- The main session stages each area's files by path (never `git add -A`). Version bumps and CHANGELOG entries ride the first commit that touches each plugin.
- Advance the phase tags as each phase lands.
- Message the blog-digest session (feat/sonnet-5-5-blog-digest, draft PR #5676) with this PR's number when it opens, and with the merge commit SHA when it merges. That branch rebases on this one (Q27).
