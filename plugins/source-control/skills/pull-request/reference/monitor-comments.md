# 3.3 PR comment evaluation (WORKFLOW-GATED)

Part of [Phase 3: Monitor](monitor.md), which lists every section's file; a bare § number names a section listed there. Every push in this phase follows the push rule in [§3.0.6](monitor-multi-pr-scan.md) ("Monitor does the work").

**Fetch all comments deterministically** via the bundled script, never choosing API surfaces by agent judgment:

```bash
bash "<plugin-root>/scripts/fetch-all-pr-comments.sh" <pr-number>
```

Output: a JSON array sorted by `created_at`. Each object carries `type` (`general` | `review` | `inline`), `author`, `body`, `path`, `line`, `id`. The script hits all 3 GitHub API surfaces (issue-level comments, review-level comments, inline review comments), so none is skipped.

Every comment from an AI or human reviewer gets the **full workflow treatment**, not a glance and a thumbs-up: bot findings and "obvious" fixes are often wrong, so each finding is verified before anything changes.

## 3.3.1 Phase A: Evaluate ALL comments (batch)

Process every comment before fixing any, for a complete picture of what needs attention.

For **every substantive comment from every participant** (bot accounts with the `[bot]` suffix, human reviewers, AND the PR author's own comments, skipping only LGTM/empty/emoji-only):

**Finding extraction for multi-finding comments:** AI review summaries often pack multiple findings into a single comment: markdown tables, numbered severity items, multi-paragraph analyses. Extract each finding as a separate work item. One comment with N findings = N individual evaluate cycles below. Reply with a per-finding classification table and one `<!-- d5 finding=` label marker line per finding, not one blanket reply. See [review-discipline.md](../../../reference/review-discipline.md) §2 for extraction rules (including the mandatory ≥3-finding subagent dispatch).

**Repository triage rubric.** Before step 1, read the `## Review-bot triage rubric` section of `docs/conventions/source-control.md` at the PR's base branch, once per pass, as [config-resolution.md](../../../reference/config-resolution.md#review-bot-triage-rubric-docsconventionssource-controlmd) describes; no section means no rubric. For each bot finding a row matches, the row's disposition sets the expected classification and its confidence sets how much of step 2 the row replaces, within the rubric's limits (security and data findings are never dismissed; human comments are untouched). An `ask` row in an interactive session shows the user the finding and waits. With no one to answer (a CI lane, a `dontAsk` session), it never prompts: classify the finding UNCERTAIN, reply that the repository's rubric routes it to a person, leave the thread unresolved, and report it. Name the deciding row in the classification table's Evidence column.

1. **Explore:** read the referenced file/line, the surrounding code, and related files. Don't evaluate a comment about line 42 without understanding lines 1-100
2. **Research:** verify the specific technical claim against official docs (via a research skill when available); no assumptions. The sequence is explore → research → classify, never read → classify
3. **Classify** with evidence:
   - **VALID (fix now).** Research confirms the finding. Document: what's wrong, why, what the fix is
   - **VALID (defer).** Research confirms, and the finding is structural (needs its own planning pass), urgent and real but unable to land in this PR, or its fix is blocked on research this lane is not positioned to do (a claim that research cannot confirm stays UNCERTAIN). A small or medium finding is VALID (fix now); one fixed in this PR goes in the §3.3.2 review-fix commit rather than the original work's commits, and where an unrelated one lands is D4.6's scope test. **Provenance test first, before scope or fix size is weighed:** if the defect did not reproduce on the base branch, this change introduced it and it is VALID (fix now), never deferrable, whichever file it surfaced in, including a contract this change altered breaking an unchanged caller (D4.6, [review-discipline.md](../../../reference/review-discipline.md) §3). Only a defect that already reproduced on the base may defer: file it in your work-item tracker with evidence and the PR link, and cite that item's id in the D5 reply. A deferral the thread cannot resolve to an open item is a dropped finding. **No reachable tracker removes the deferral, never the reply:** the tracker is optional here ([SKILL.md](../SKILL.md) §Adapting to your environment) and its absence never blocks a phase. Without one, VALID (defer) is simply not available, so fix the finding now, or reply saying why the fix does not belong in this change, leave the thread unresolved, and report it for the user to place <!-- contract-restatement: D4.6-deferral-provenance --> <!-- contract-restatement: D4.6-deferral-grounding -->
   - **INCORRECT.** Research disproves the finding. Document: why the comment is wrong, with sources
   - **UNCERTAIN.** Research inconclusive. Escalate to the user

   **"Non-blocking" / "optional" / "nice-to-have" does NOT mean "ignore".** These modifiers describe merge-blocking status, not whether the finding is worth acting on. When research confirms a finding is valid: small or medium, related or not → VALID (fix now), placed by D4.6's scope test (this PR's §3.3.2 review-fix commit, or its own PR for an unrelated one outside the files this PR touches); structural, urgent-but-cannot-land, or fix-blocked-on-research → VALID (defer) + tracked work item, but only after the D4.6 provenance test passes: a defect this change introduced is VALID (fix now) at any size. **Never merge past a confirmed-valid finding with neither a fix nor a tracked issue.** The choice is always "fix now or ticket it". <!-- contract-restatement: D4.6-deferral-provenance -->
4. **React to the specific comment** via the comment's reactions endpoint ([GitHub](../../../reference/providers/github/README.md#review-surfaces)) (`+1` VALID, `-1` INCORRECT, `eyes` UNCERTAIN). For **bot accounts** (login ends in `[bot]`): react autonomously. Mixed-finding comments: `+1` if ANY VALID. For **human reviewers**: pause for user approval before reacting. **Verify the reaction posted** via a GET on the same endpoint filtered by your login; the POST can silently fail (rate limit, permission)
5. **Reply with evidence:** every comment gets a direct reply with research backing. Use the consuming project's bot-identity wrapper for these writes when it has one, else plain `gh`. **Route by comment source, REQUIRED and not interchangeable:** **inline review comments** (diff-anchored, `pulls/comments`) MUST reply THREADED → a reply to that comment ([GitHub](../../../reference/providers/github/pull-request/monitor.md#reply-on-an-inline-thread)) so the reply lands under the source thread, NEVER a detached issue comment. **General PR comments** (`issues/comments`, no thread) → post a new issue-level comment with thread context in the body. **Review-level comments** (`pulls/reviews`, no thread) → post a new issue-level comment addressing the review. A detached issue comment answering an inline finding orphans the reply from the thread the reviewer tracks: a routing error

**After evaluating ALL comments**, present a classification table:

```markdown
| # | Reviewer | Comment | Classification | Evidence |
|---|----------|---------|---------------|----------|
| 1 | claude[bot] | "Missing null check on line 42" | INCORRECT: parameter is non-nullable by type | [sources] |
| 2 | chatgpt-codex-connector[bot] | "Race condition in handler" | VALID (fix now): confirmed by research | [sources] |
| 3 | human-reviewer | "Consider extracting to helper" | VALID (fix now): small refactor, review-fix commit | [sources] |
| 4 | claude[bot] | "Split this module's persistence layer" | VALID (defer): structural, needs its own plan | Tracked work item |
```

## 3.3.2 Phase B: Fix ALL valid findings (batch, then single push)

After all comments are evaluated and responded to, implement all VALID (fix now) fixes in a single batch:

0. **Wait for every reviewer on the current head before pushing.** Every reviewer check run on the head SHA ([GitHub](../../../reference/providers/github/pull-request/monitor.md#read-the-heads-check-runs)) is completed, and every comment-only reviewer has landed its round or reached its Gate 5 bound in [readiness.md](readiness.md). A finding arriving after the push needs a second push, and each push starts a full CI run and cancels the one in flight. Fix while you wait; hold only the push. Any [§3.2](monitor-ci-failures.md) CI fix from this cycle goes in the same push
1. **For each VALID (fix now) finding**, follow the full workflow: explore the fix context, verify the *fix* approach (not just the finding), implement by changing only the lines the finding names (any other edit needs its own finding; `/review:quality-gate` owns this review-fix rule), re-run the project's build/test gate after each fix. When the finding is about behavior rather than wording or style, write the test first: it fails on the current head for the reason the finding gives, and the fix turns it green (D6 of the per-iteration checklist in [monitor.md](monitor.md#per-iteration-monitoring-checklist-on-every-ci-or-comment-event)). When nothing in the project's tests can reach that behavior, the D7 reply says so
2. **Stage all fixes together:** `git add <specific-files>` for each changed file
3. **Single commit.** One commit addressing all review comments: `fix: address PR review findings`
4. **Single push:** all fixes go up in one push, triggering one new monitoring cycle. Write any PR body or label change before this push, not after it: a body or label edit re-runs every workflow that triggers on `edited` or `labeled`, beside the push's own run

**Why batch?** Each push restarts the monitoring loop (3.1) and a full CI run, so one push per fix costs N cycles and N CI runs instead of 1.

## 3.3.3 Phase C: Re-monitor (loop restarts)

After the push:

1. The monitoring loop (3.1) restarts automatically: new push = new cycle
2. CI runs against the updated code
3. **Request re-review from comment-only actors:** if a bot's findings were fixed, request a fresh review so it can validate the fixes:
   - Trigger **"on every push"**: it re-reviews automatically; wait
   - Trigger **manual/smart**: post a comment with the trigger phrase its record in [reviewer-shapes.md](reviewer-shapes.md) states. Don't assume it re-fires on its own, and don't guess a phrase for a reviewer with no record
4. Security scans re-run
5. **Repeat from 3.3.1** if new substantive comments arrive
6. Continue until no new comments arrive and all readiness gates pass

**This is the convergence loop:** evaluate → respond → fix → push → re-monitor → repeat until clear. The monitoring report (3.4) comes only when no comments need attention and the full readiness checklist passes.

## 3.3.4 Comment evaluation gotchas

- **NEVER react or classify before researching.** No thumbs-up, thumbs-down, "VALID" or "INCORRECT" label until exploration and research complete, even if a prior cycle researched the same pattern; each finding gets its own verification. The sequence is always: explore → research → classify → react → reply
- **Zero false positives in classification.** A wrong INCORRECT is worse than a wrong VALID: the first dismisses a real issue, the second only does extra work. When in doubt, classify UNCERTAIN and escalate
- **Don't trust AI reviewer confidence.** A bot calling something a "critical bug" with high confidence doesn't make it critical. Research first, classify second
- **Don't fix what research says is wrong.** If research disproves a comment, reply with evidence and react with thumbs-down; never implement a "fix" for a non-issue because a bot said so
- **Verify empirically when possible.** For claims about CLI behavior, API responses, or tool output, run the command and check. Empirical evidence > documentation > prior research > intuition
- **Escalation guard.** After **3 evaluate-fix-push cycles** with the same reviewer posting new comments, STOP and escalate to the user: the reviewer may be generating noise, or there may be a fundamental disagreement
- **A reviewer's completion signal is a per-reviewer fact. Read its record, don't assume one.** Where a round lands (check run, review body, inline comments, an emoji reaction, or some mix), which push a comment belongs to, and how long a round takes differ per reviewer and are recorded in [reviewer-shapes.md](reviewer-shapes.md). A reviewer with no record there gets the flat Gate 5 cooldown: waiting on a signal no record promises stalls the loop as surely as declaring readiness too early ends it
- **A reviewer that did not fire needs its own trigger phrase, not a retry.** Silence from a discovered reviewer is as often a round that never started as a round with no findings; its record says which artifacts each state produces, so read the state off those before acting. When the round never started, re-fire it with the phrase its record names. With no record, report the silence rather than inventing a trigger
- **NEVER select API surfaces by judgment. Use the script.** The CLI's PR view of comments and reviews MISSES inline review comments ([GitHub](../../../reference/providers/github/pull-request/monitor.md#why-the-comment-script)). Always invoke the bundled `fetch-all-pr-comments.sh`, which deterministically hits all 3 surfaces
- **Never mark a comment addressed without verifiable evidence on GitHub.** Model memory of "I replied" or "I pushed the fix" is not evidence; compaction can lose it between iterations. Re-query GitHub to verify: reaction exists, reply exists, commit pushed, follow-up posted, bot-authored thread resolved (inline only; human/own excluded). "Done" = GitHub shows evidence. See [review-discipline.md](../../../reference/review-discipline.md) §3 verification gates
- **Resolve BOT-authored inline threads once dispositioned; never human or own.** Once EVERY finding in an inline review comment opened by a bot reviewer carries an eligible disposition, resolve that thread (D7.5, author- and classification-conditional). The eligible dispositions are a D6 fix pushed and cited by the D7 follow-up, a fix in a linked PR the reply cites (D4.6 scope test), a `VALID (defer)` grounded per D4.6 with the item id cited, or `INCORRECT` with counter-evidence posted. One dispositioned finding never makes a multi-finding thread eligible: resolving drops its remaining comments from the readiness count, so an unaddressed finding inside it would vanish. A single `UNCERTAIN` escalates and holds the whole thread open. **A `VALID (defer)` never clears the gate for a merge this same session performs:** route it to an independent adjudicating context, or leave the thread unresolved and do not merge (`review-discipline.md`, "Who authorizes a resolution that ships no fix"). Leave HUMAN-authored threads for the human to close; never resolve your own. Detect bot at resolution time via GraphQL `author.__typename == "Bot"` (GraphQL login omits the `[bot]` suffix REST shows). Open bot-thread count is a visible signal to reviewers. Leaving bot threads unresolved after fixing undermines the audit trail <!-- contract-restatement: D7.5-thread-eligibility --> <!-- contract-restatement: D7.5-merge-authorization -->
- **Filter your own prior replies during rescan.** Comments from your own posting identity carrying a D5 label marker line (`<!-- d5 finding=`) or, from before the marker, the classification-table pattern (`| # | Finding | Classification |`) are NOT findings. They are prior replies. Skip them during finding extraction. See [review-discipline.md](../../../reference/review-discipline.md) §1 step 1
