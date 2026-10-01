# sonnet-5-5-adoption

## Brief

### TLDR

Act on the verified digest of the claude.dev post "Building with Claude Sonnet 5.5" (2026-09-28),
limited to what only that post drives. Everything the Sonnet 5.5 prompting guide drives belongs to
the `feat/sonnet-5-5-prompting-digest` branch; this branch turns three stale restated facts into
doc pointers and fixes the usage-limit reset checker now, closes out the digest slice, and adds
the post's own records after that branch merges. The blog extractor ships in that branch's PR.

### Goal

Remove the repo's stale Sonnet 5.5 facts that only this post surfaced, fix the one tooling defect
with a known fix, and record the post as a source, without colliding with the peer branches that
own the guide-driven changes.

### Constraints

- Files are owned by source article. This branch edits only blog-only paths; the Prompting Sonnet
  5.5 branch owns the Sonnet 5.5 chapter, fable-5 routing and evals, audit-instructions and
  prompting-postures rows, the plugin-philosophy tier table, the loop-lane README tier row, agent
  effort pins, verification skills, and docpage-digest `SKILL.md`, profile and
  `dual-verification.md` (pending its Q37). Its PR merges first; this branch rebases once. (Q17)
- The ten relayed standing rules apply (Q19): self-contained interview questions; no copied
  upstream content in repo files (own words, a link to the exact section, a date and a recheck
  trigger; look sources up live); official Anthropic defaults with configurable overrides; source precedence on
  conflicts (prompting guide for model behavior, Claude Code docs for Claude Code handling), every
  conflict written down; verification by gates, not prose; medium effort floor for code-changing
  work; current-model list; fix known issues now, else file; one PR with a parent issue closing
  sub-issues; coordinate across sessions by message.
- Pointers go to the latest main doc pages, never a single blog release post; a note records
  where later blog posts should be correlated. (Q12) Exception: this post's own provenance record
  and queue entry link the post, since it is their subject. (Q22)
- Links only: where a repo file needs an upstream fact, it keeps a one-line topic pointer to the
  exact doc section with a check date and a recheck trigger, and no values, lists or quotes; any
  exception needs the user's explicit yes. (Q29) This includes this post's own provenance record
  and queue entry: what was decided and changed, phrased without upstream values, plus links,
  dates and recheck triggers. (Q31)
- Outward actions (push, PR creation, issue creation) wait for one explicit go from the user at
  execution time, after one combined review of the branch, the PR title and body, and the issue
  texts. (Q32) After the post-merge rebase, one more combined review covers the force-push (with
  lease), the record diffs, the updated PR body and the ready flip, acting on one go. (Q33, Q36)
  Any other outward action (an interim push, a PR title edit, issue linking after creation)
  stops and asks, per the repo's standing stop-before-push rule. Merging and commenting are never
  covered. (AGENTS.md)
- No issues are filed on Anthropic repositories. (Q12)
- Every issue or PR mention on an interview page is a link. (Q2)
- PRs open as drafts with Conventional Commits titles and the repo's PR body contract; stop
  before push, merge, or commenting. (AGENTS.md)

### Acceptance criteria

- `prompts/loops/loop-lane-prompts.md`: the effort paragraph keeps its instruction (leave effort
  at its default) but no longer states or quotes any default; its reason is a one-line pointer to
  Claude Code model-config's effort section, with a check date and recheck trigger. (Q7, Q29)
- The boris reference's default-effort statement and always-thinking list
  (`plugins/playbooks/skills/boris/reference/advanced.md`, `autonomy.md`) become one-line
  pointers to the Claude Code model-config sections, with check date and recheck trigger; no
  model names or effort values remain there. (Q7, Q29)
- The context-guard native-1M model list (`plugins/context-guard/reference/reader-contract.md`)
  becomes a one-line pointer to model-config's context-window section, with check date and
  recheck trigger. (Q7, Q29)
- Each pointer's target section is fetched live at edit time and shown to still cover the topic;
  the PR body's verification section lists each pointer's URL, fetch date and a one-line
  still-covers note. (Q19 rule 2, Q35)
- The session-flow keep-going usage-limit reset checker resolves a reset clock time that is
  already past on the message's own day to the next day; a regression test covers "resets 3am
  (America/New_York)" received at about 14:35 the same day; the existing test suite passes.
- One parent issue in this repo tracks the effort; the reset-checker fix is its sub-issue and the
  PR body closes both. Guard-hook friction on compound and `github`-path commands is a standalone
  issue linked from the parent, not a sub-issue. (Q13, Q21)
- One PR for the effort: opened as a draft at the first go (not waiting on the other branch), kept draft until the Prompting Sonnet 5.5 PR
  merges, then rebased, completed with the post-merge items, and marked ready. (Q18, Q21)
- The 10 minor round-3 verifier findings are fixed in the slice; correct-and-reverify repeats
  until no finding with a known fix remains, and any without a known fix is recorded in the
  slice. (Q14, Q23)
- No repo file carries passages from the post, verbatim or paraphrased; the slice stays
  untracked and is copied outside the worktree before the worktree is removed. (Q14, Q22, Q29)
- After the Prompting Sonnet 5.5 PR merges and this branch rebases: the post's own
  docpage-digest queue entry and `docs/upstream/` provenance record exist, linking the post
  (their subject) and the main doc pages, holding only our decisions phrased without upstream
  values, and carrying a note to correlate later blog posts. (Q18, Q22, Q31)
- The blog extractor's source is handed to the Prompting Sonnet 5.5 session, which ships it in
  its PR; this branch commits no extractor. At rebase time this branch checks that it landed; if
  not, it messages that session and brings the gap to the user before the PR goes ready.
  (Q30, Q34)
- Every finding handed to another session is sent and acknowledged, and the PR body lists them:
  counting rules, recheck trigger, workload table, digest-pipeline defects, advisor conflict and
  re-check, four unclaimed doc items, Priority Tier and between-tools conflicts, and the blog
  extractor source (credited to this branch's finding). (Q26, Q30)
- The two Model routing lines in the user's `~/.claude/CLAUDE.md` are revised in the chezmoi
  source on its own branch; the user sees the diff and approves commit, push and apply. This
  does not gate the PR. (Q11, Q27)

### Captured assumptions

- The peer branches' candidate file lists are as they reported by message on 2026-09-30; a later
  change arrives by message before any edit.
- The facts this work rests on (Sonnet 5.5's Claude Code defaults and `sonnet` alias resolution)
  are as [Claude Code model-config](https://code.claude.com/docs/en/model-config) stated on
  2026-09-29; recheck at edit time.

- Acceptance-criteria coverage (unwanted-behavior "if … then" and state-driven "while …" cases)
  was asked once at confirmation and got no reply; the user confirmed the restatement, so those
  cases are unexamined.

### Out-of-scope

- Every guide-driven change listed under Constraints (owned by the Prompting Sonnet 5.5 branch).
- Changing any agent's or lane's model or effort binding.
- Filing upstream issues on Anthropic repositories.
- Graduating the digest slice into the repo.

### Deferred questions

- Q15 (arbiter: /planning:plan): mechanism-level choices, such as the parent issue's title, the
  exact pointer wording, the reset checker's code change and test shape.

## Plan

Standards grounding: repo `AGENTS.md` (draft PRs, Conventional Commits titles, stop before outward
actions), `.claude/rules/pr-body-contract.md` (PR body), `.claude/rules/ruff-pin.md` (Python lint),
`.claude/rules/skill-bodies-state-current-rules.md` (the keep-going `SKILL.md` edit; the peer
branch is rewriting this rule to pointer + as-of + trigger), `docs/migration-playbook.md`
(one version bump per branch, `scripts/check-changelog-parity.sh`). Design gate:
[design/design-resolution.md](design/design-resolution.md) (Tier B, early exit).

Pointer shape for Phases 2 and 5, matching the peer branch's links-only shape so one convention
lands after the rebase (confirmed by that session 2026-09-30): our instruction in our own words,
then `For <topic>, see [Claude Code model config, "<section>"](<url>#<anchor>).`, an "As of"
date and a "Recheck trigger" naming an observable event. No values, lists or quotes. Candidate anchors read off the live page on 2026-09-30, confirmed again at edit time:
`#choose-an-effort-level` (effort levels and per-model defaults), `#extended-thinking` (models
whose thinking cannot be turned off), `#default-auto-compact-thresholds` (native-1M compaction).

### Phase 0: Commit the plan and confirm file ownership [DONE]

1. Commit `docs/topics/sonnet-5-5-adoption/PLAN.md` and `design/design-resolution.md`, staging
   those two paths only (`.playwright-cli/` stays out of every commit).
2. Message "Prompting Sonnet 5.5": list this branch's edit set (the Phase 1 and Phase 2 files)
   and ask whether its links-only retrofit (its PLAN Decisions, "Retrofit (Q43, Q45)") touches any
   of them. Its `peer-inputs.md` "Peer keeps (not ours)" already leaves these four sites to this
   branch; this message confirms the retrofit does not also rewrite them. A file it claims is
   dropped from this plan and the drop is shown to the user.

**Sanity Check:**
- `git log -1 --name-only` lists exactly the two topic files.
- `.work/sonnet-5-5-adoption/handoffs.md` records the ownership message and the peer's reply.

### Phase 1: Usage-limit reset checker fix [DONE]

Files: `plugins/session-flow/skills/keep-going/scripts/check-usage-limit-reset.py`,
`check-usage-limit-reset.test.py`, `plugins/session-flow/skills/keep-going/SKILL.md`.

1. Identify consumers: `grep -rn "check-usage-limit-reset" plugins/ scripts/ .github/ docs/`.
   The only known caller is keep-going `SKILL.md:159`. The new flag is optional, so any other
   caller keeps working.
2. Red. Add tests to `check-usage-limit-reset.test.py`:
   - regression: `resets 3am (America/New_York)`, `--received 2026-09-29T14:35:00-04:00`,
     `--now 2026-09-29T14:40:00-04:00` → exit 1, reset `2026-09-30T03:00:00-04:00`;
   - same message and received, `--now 2026-09-30T03:05:00-04:00` → exit 0;
   - `resets 12am (America/New_York)`, received 23:59 → next day 00:00;
   - fall-back: `resets 1:30am (America/New_York)`, received `2026-10-31T22:00:00-04:00` →
     resolves on 2026-11-01;
   - spring-forward: `resets 2:30am (America/New_York)`, received `2027-03-13T22:00:00-05:00` →
     resolves on 2027-03-14 to a real instant (no nonexistent wall time);
   - zone-less message `resets 3:45pm` with `--received …Z` and `--now` at `-04:00` → the reset
     is 15:45 at `-04:00`, never 15:45 UTC;
   - malformed `--received` and offset-less `--received` → exit 2;
   - direct `parse_reset(..., received=...)` call.
   Run; the new tests fail.
3. Green. Add `--received` and the `received` parameter. The zone is the message's zone when it
   states one, else `--now`'s zone, else the local zone; `received` never supplies the zone.
   Build the candidate wall time on `received`'s calendar date in that zone; compare instants in
   UTC; while the candidate is earlier than `received`, rebuild it on the next calendar date
   (not a 24h `timedelta`), normalizing through UTC so a gap or fold time resolves to a real
   instant. Parse `--received` (and `--now`) inside the error boundary so a bad or naive value
   exits 2, never 1.
4. `SKILL.md` reset bullet (bullet text only; the Claim/Basis/As of/Recheck row is left as-is
   for the peer's retrofit): the invocation shown passes `--received "<ISO time the limit
   message was shown>"`, sourced from the transcript entry's `timestamp` (confirm the field by
   reading one worker transcript at implementation time; if it is absent, say so in the
   bullet) or else the time the message was captured. When no time is available, an exit `0`
   is provisional, like exit `1`: re-check live or ask the operator before resuming.

**Sanity Check:**
- `bash plugins/session-flow/skills/keep-going/scripts/check-usage-limit-reset.test.sh` exits 0
  (existing tests unchanged and passing, new tests passing).
- `python3 plugins/session-flow/skills/keep-going/scripts/check-usage-limit-reset.py "resets 3am (America/New_York)" --received 2026-09-29T14:35:00-04:00 --now 2026-09-29T14:40:00-04:00`
  exits 1 and prints `2026-09-30T03:00:00-04:00`.
- `grep -n 'check-usage-limit-reset.py" .*--received' plugins/session-flow/skills/keep-going/SKILL.md` returns the invocation line.
- `git diff --name-only -- plugins/session-flow` lists exactly the three Phase 1 files; ruff via
  the pinned wrapper is clean on the two `.py` files.

### Phase 2: Doc pointers, each live-checked [TODO]

Files: `prompts/loops/loop-lane-prompts.md`, `plugins/playbooks/skills/boris/reference/advanced.md`,
`plugins/playbooks/skills/boris/reference/autonomy.md`,
`plugins/context-guard/reference/reader-contract.md`.

1. Fetch https://code.claude.com/docs/en/model-config live; confirm each target section still
   covers its topic; record URL, date and a one-line still-covers note per pointer in
   `.work/sonnet-5-5-adoption/pointer-checks.md` (feeds the PR body, Phase 4).
2. `loop-lane-prompts.md` (~:445): keep "Leave effort at its default"; replace the stated
   default, the quote and the "verified 2026-08-08" record with the effort pointer.
3. boris `advanced.md` (:15-21): keep the `/effort` command example and the advice on when to
   use the top level, in our words; remove the level list and the default clause from line 15
   and replace the Amended block with the effort pointer.
4. boris `autonomy.md`: replace the effort-precedence Amended block (~:250-265, the medium-default
   statement Q7 names) with the effort pointer; rewrite the always-thinking Amended block
   (~:270-282) as our instruction in our own words (on models that always think, change effort
   rather than adding "think carefully" lines) plus the extended-thinking pointer, with no
   model names and no quoted lines.
5. context-guard `reader-contract.md` (~:296-323): replace the native-1M model list with the
   auto-compact-thresholds pointer and keep the sentence's logic about native-1M windows. The
   rest of that paragraph follows Open decision D1 below.

**Sanity Check:**
- `sed -n '/Leave effort at its default/,/^$/p' prompts/loops/loop-lane-prompts.md | grep -cE "Opus|Sonnet|Fable|xhigh|\`high\`"` prints 0.
- `grep -nE "Five levels|default is|xhigh|Opus 4\.7|Opus 5\.5" plugins/playbooks/skills/boris/reference/advanced.md` returns nothing.
- `grep -nE "Opus 5\.5 starts at|Answer directly without deliberating|Opus 5\.5 and the Fable models" plugins/playbooks/skills/boris/reference/autonomy.md` returns nothing.
- `grep -n "Sonnet 5, the Fable" plugins/context-guard/reference/reader-contract.md` returns nothing (plus the D1 grep below).
- Each new pointer carries `As of 2026-` and `Recheck trigger`; `pointer-checks.md` has one row per pointer.
- `git diff --name-only -- prompts plugins/playbooks plugins/context-guard` lists only the Phase 2 files.

### Phase 3: Slice correct-and-reverify [TODO]

Untracked work under `.work/claude-dev-blog-building-with-c-09e1fe5d/`; nothing is committed.

1. Fix A3-1..A3-5 and B3-1..B3-5 (`verification/verifier-A-opus-r3.md` "Other",
   `verifier-B-codex-r3.md` "Other"); record each in
   `verification/corrections-applied-<date>-r3.md`.
2. Re-verify with the docpage-digest dual-verification procedure (round 4, both arms).
3. Repeat until no finding with a known fix remains; record any without one in the slice.

**Sanity Check:**
- `verification/corrections-applied-*-r3.md` lists all ten ids, each with a disposition.
- The latest round's two verifier files each state a verdict, and every finding in them is
  either fixed in a later corrections file or listed as no-known-fix.
- `git ls-files .work` prints nothing.

### Phase 4: First go: draft PR and issues [TODO]

1. Handoff table in `.work/sonnet-5-5-adoption/handoffs.md`: one row per Brief-listed handoff
   (counting rules, recheck trigger, workload table, digest-pipeline defects, advisor conflict
   and re-check, four unclaimed doc items, Priority Tier and between-tools conflicts, blog
   extractor source), each with sent and acknowledged evidence (the 2026-10-01 handoff records
   all as sent and acknowledged; confirm each against the prior session transcript or the
   peer's reply). A row without acknowledgement is re-asked by message; it blocks the go.
2. Search before create: `gh issue list --search "<terms> in:title" --state all` for the
   effort parent, the reset-checker defect and the guard-hook friction. A hit counts as a match
   only when it is the same defect or this effort's own parent; every hit is shown at the go
   and the user picks reuse or new. Nothing is reused automatically.
3. Draft, without sending: guard-hook friction issue (compound and `github`-path commands,
   from the ledger), parent issue (links the guard-hook issue in its body), reset-checker
   sub-issue, PR title `fix: adopt Building with Claude Sonnet 5.5 findings` (scope picked at
   drafting), PR body per the PR body contract with the Q35 pointer evidence and the handoff
   table.
4. Stop. Show the branch diff summary, the search hits, the PR title and body, the three issue
   texts and the creation order together; act only on the user's one go.
5. On go, in order: push the branch; `gh issue create` the guard-hook issue; create the parent
   with its number in the body; `gh issue create --parent <parent>` the reset-checker issue;
   `gh pr create --draft` with `Closes #<parent>` and `Closes #<sub>`. No comments.

**Sanity Check:**
- `gh pr view --json isDraft,title` reports `isDraft: true` and a Conventional Commits title.
- `gh pr view --json body` body starts with the two `Closes` lines and has non-empty
  `## Summary`, `## Fix`, `## Verification`, `## Related` sections.
- `gh issue view <parent> --json body` contains the guard-hook issue's number, and the
  reset-checker issue's parent is `<parent>` (`gh api repos/{owner}/{repo}/issues/<sub>/parent`).
- `handoffs.md` has 8 handoff rows, each with acknowledged evidence.

### Phase 5: After the Prompting Sonnet 5.5 PR merges [TODO]

Blocked on that PR merging.

1. `git fetch origin`, then `git rebase origin/main`, as two commands.
2. Check the blog extractor landed on main; if not, message "Prompting Sonnet 5.5" and tell the
   user before going further.
3. Add the post's entry to `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-queue.md`
   and a provenance record `docs/upstream/claude-dev-sonnet-5-5-blog.md` following the existing
   records' pattern: decisions phrased without upstream values, links to the post and the main
   doc pages, dates, recheck triggers, and the note on correlating later blog posts.
4. One version commit, made after the rebase: patch bumps and CHANGELOG entries for
   session-flow, playbooks, context-guard and knowledge, on top of main's current versions.
5. Stop for the second go: show the force-push (with lease), the record diffs, the version
   commit, the updated PR body, and the ready flip, including that
   `/source-control:pull-request ready` may merge the base and push again. On go:
   `git push --force-with-lease`, update the PR body, run the ready flip.
6. Copy `.work/` out of the worktree to a durable location before any worktree removal.

**Sanity Check:**
- `git log origin/main..HEAD --oneline` shows only this branch's commits after rebase.
- `grep -n "building-with-claude-sonnet-5-5" plugins/knowledge/skills/docpage-digest/context/anthropic-docs-queue.md docs/upstream/claude-dev-sonnet-5-5-blog.md` hits both files.
- `/attribution:audit` on the two new records reports zero copies.
- `bash scripts/check-changelog-parity.sh` exits 0.
- `gh pr view --json isDraft` reports `isDraft: false` only after the go.

### Phase 6: User CLAUDE.md routing lines (separate, not gating) [TODO]

In the chezmoi source (`~/.local/share/chezmoi`), on its own branch in a chezmoi worktree, revise
the two Model routing lines named in Q11/Q27. Show the diff; the user approves commit, push and
`chezmoi apply`.

**Sanity Check:**
- `git -C <chezmoi worktree> diff --name-only` lists only the CLAUDE.md source file, and no
  commit exists on that branch before the user's approval.

## Open decisions

- **D1. The rest of the context-guard paragraph** (`reader-contract.md` ~:296-323). Besides the
  native-1M list the Brief names, the same paragraph quotes the auto-compact figure, lists the
  200K-boundary models, and repeats a second model list near :321. Its margin argument (the
  trigger sits above the `dumb` band) uses the figure. Options: (A) convert all of it to the
  pointer and restate the margin argument without the number, then recheck it against
  `zones.json`; (B) keep those values as a recorded exception, which Q29 requires your explicit
  yes for. Resolved: A (2026-09-30, at plan approval). Basis: `reader-contract.md:304-323`; Brief Constraints, links only (Q29).
  Under A, the Phase 2 sanity check adds
  `grep -nE "967K|Opus and Fable|Sonnet 4\.6" plugins/context-guard/reference/reader-contract.md` returns nothing.

## Blast radius

Blast radius: MEDIUM. About 12 files across four plugins plus one prompt file; one script gains
an optional flag (backward compatible, existing tests unchanged); two edited files are agent
instructions (loop-lane prompts, keep-going `SKILL.md`). Everything is git-revertable; outward
actions sit behind two explicit user gates.

## Stress-test summary

Plan reviewer (fresh context): 0 critical, 6 important, 4 suggestions. Devil's advocate (fresh
context): 4 high, 7 medium, 4 low. All were checked against the files. Adopted: reset-checker
zone rule, `SKILL.md` always passes `--received` with exit 0 provisional when it cannot, UTC
comparison and the DST, midnight and CLI-boundary tests; the autonomy.md effort block (the
medium default Q7 names) and the full always-thinking block; advanced.md level list; the
compaction anchor `#default-auto-compact-thresholds`; the peer's pointer shape and an ownership
check (Phase 0); version bumps in one post-rebase commit; issue-creation order with no comments;
user-chosen reuse of search hits; the ready-flip push listed at the second go; handoff table;
attribution audit and changelog-parity checks; path-scoped diff checks; separate git commands.
Open for the user: D1.

## Execution shape

Phase 0 gates everything. Phases 1, 2 and 3 then touch disjoint files and can run in parallel;
Phase 4 gates on all three; Phase 5 gates on Phase 4 and the peer merge; Phase 6 is
independent.

| Phase | Surface | Basis |
|---|---|---|
| 0, 1, 2 | main session | one script + test and short doc edits; small |
| 3 | sub-agents per docpage-digest dual verification | verification is fresh-context by design |
| 4, 5 | main session | outward actions need the user's go |
| 6 | main session, chezmoi worktree | user-scope config |

## Decisions made (gate-passed)

| Decision | What it changes in the plan | Basis (evidence) | Source |
|---|---|---|---|
| [EXEC-SHAPE] Reset fix via an optional `--received` flag; old behavior when absent; `SKILL.md` always passes it, and treats exit 0 as provisional when it cannot | Phase 1 adds a flag and a `SKILL.md` instruction instead of always rolling a past time forward | `test_lifted_after_reset_same_day` (`check-usage-limit-reset.test.py:43`) expects "lifted" for a 2:30am reset checked at 10:25 the same day, the bug's exact shape; the Brief requires the existing suite to pass and anchors on "the message's own day" | Q15 |
| [EXEC-SHAPE] The message's zone, else `--now`'s, else local; never `received`'s | Phase 1 zone rule and test | `check-usage-limit-reset.py:180-185`; transcript timestamps are UTC | Q15 |
| [EXEC-SHAPE] Pointer anchors and the peer's "For <topic>, see <link>" shape | Phase 2 targets and wording | live model-config headings fetched 2026-09-30; peer `PLAN.md` Constraints line 19 | Q7, Q29 |
| [EXEC-SHAPE] autonomy.md effort block and advanced.md level list included | Phase 2 steps 3-4 | ledger Q7 "boris medium-default" is `autonomy.md` ~:259; Brief "no model names or effort values remain there" | Q7 |
| [EXEC-SHAPE] Version bumps in one commit after the rebase | Phase 5 step 4; Phases 1-2 carry no bumps | `docs/migration-playbook.md:533-567` one bump per branch; peer edits playbooks | judgment on conflict risk |
| [EXEC-SHAPE] Issue order: guard-hook, parent, sub-issue via `--parent`; no comments | Phase 4 step 5 | `gh issue create --help` shows `--parent` (gh 2.98.0, probed by the reviewer); Brief forbids comments | Q21, Q32 |

## Handoff to implementation

Approval: approved by the user on 2026-09-30, with the direction that implementation stays
driven by the interview ledger, the source article slice, and live research. D1 resolves to its
recommendation (A); option B was the only one needing an explicit Q29 yes.

### User-approval gates

- Open decision D1 before Phase 2 step 5.
- Phase 4 step 4 (first go) and Phase 5 step 5 (second go).
- Phase 6 commit, push, apply.
- Any interim push, PR title edit, or issue link outside those gates stops and asks.
