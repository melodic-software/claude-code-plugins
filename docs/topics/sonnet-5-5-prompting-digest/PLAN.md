# Sonnet 5.5 prompting guide: repo changes

## Brief

### TLDR

- A new Sonnet 5.5 model-adaptation chapter, current-model cleanup (Fable 5.1, Opus 5.5 and Sonnet 5.5 are current; Opus 5, Opus 4.8 and Sonnet 5 are fallback-only), and tier tables updated.
- Verification by runnable checks instead of "please verify" prose; toolchain and confirm stop counting fake checks and report skips by name.
- An effort guardrail: one effort table with a medium floor for code-changing or verifying work on every model, a skill self-check, a warn-only hook, and one drift check over every table that names models.
- The whole links-only retrofit: no copied or paraphrased upstream content anywhere in the repo; the verification-record rule becomes pointer + as-of + recheck trigger.
- docpage-digest pipeline fixes, including the blog extractor from the blog-digest branch. It all ships as one draft PR with one commit per area, and five follow-on issues are filed.

### Goal

The repo reflects what Anthropic's [Sonnet 5.5 prompting guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5) means for how this marketplace's skills, agents, catalogs and conventions steer current Claude models. Every such decision is stated in our own words and points at the live upstream section instead of copying it. The repo keeps itself honest when models change: a new model with no guidance fails a check, not a reviewer's memory. It ships as one draft PR from `feat/sonnet-5-5-prompting-digest` under one parent issue whose sub-issues the PR closes, including the reopened [#4347](https://github.com/melodic-software/claude-code-plugins/issues/4347) with its own `Closes #4347` line.

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

- No file calls a retiring model current, except the playbooks host skill's name until its rename issue lands; a Sonnet 5.5 session is routed to the Sonnet 5.5 chapter.
- Every file this PR changes, which is the whole retrofit per Q45, contains no copied or paraphrased upstream text, and the attribution audit reports zero copies.
- Every volatile specific carries a topic pointer to the exact section, an as-of date and a recheck trigger.
- The audit and posture catalogs fire on a sonnet-5-5 target for the widened rows and the new rows.
- No code-changing or verifying agent or skill pins an effort below medium on any current model, and every agent pins its effort.
- IF the effort table has no row for the running model or the hook errors, THEN the hook never blocks; at most one non-blocking notice.
- WHILE a model on Claude Code's model page has no row in the effort table, the plugin-philosophy tier table, the loop-lane tier table or the model-adaptation chapter index, or a row names an unlisted model not marked fallback-only, the drift check fails.
- IF a check can't run only because declared dependencies are missing, THEN the workflow installs them with the project's own package manager, never sudo, within the permission mode, before reporting a skip.
- IF a check is syntax-only or failed to start, THEN toolchain:check and verification:confirm don't count it, and a skipped check is named with its reason and never reported as done.
- The blog extractor's fixture test passes, and its output has table separator rows, no widget or video label text, and no blank line opening a code block.
- The PR passes the required check and the repo's existing lint and tests.
- The five follow-on issues exist and are linked from the parent issue.

### Captured assumptions

- The ledger's answer text is authoritative where a page commitment list predates a revised answer (Q24, Q29, Q30, Q34, Q36, Q37, Q43, Q45): revisit if a reviewer finds a commitment the ledger dropped. Ledger: `.work/sonnet-5-5-prompting-digest/interview-checklist.md`.
- "Current" means the model list on Claude Code's model page, read live (Q35): revisit if Claude Code stops publishing that list.
- The `haiku` alias follows the current Haiku (loop-lane README, "Runtime resolution is by model alias only"): revisit if Haiku 5.5 ships under a different alias.
- The blog extractor source is staged at `.work/sonnet-5-5-prompting-digest/staged/extract_blog_body.py` (moved with the blog-digest session's user's confirmation): revisit if that branch still commits it.
- Source conflicts already found and to be recorded as disagreements: advisor-model compatibility, Priority Tier availability, `between_tools` reachability from Claude Code, models overview vs the Sonnet 5.5 blog on where to start (`.work/sonnet-5-5-prompting-digest/peer-inputs.md`): revisit if any listed page changes.

### Decisions

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

- Q38: Drift check: CI or schedule, whether it gates PRs, how it reads Claude Code's model page; defer until planning; **arbiter: /planning:plan**
- Q39: Guard hook: host plugin, consumer off-switch default, how "code-changing" is classified; defer until planning; **arbiter: /planning:plan**
- Q40: How the hook and the skill self-check detect unattended runs (ask vs warn; must never hard-stop a lane); defer until planning; **arbiter: /planning:plan**
- Q41: Commit areas for the one PR, and who may split out a stalled part; defer until planning; **arbiter: /planning:plan**

## Plan
