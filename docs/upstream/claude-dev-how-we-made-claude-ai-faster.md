# Upstream source: "How we made claude.ai 3x faster in two weeks"

## Contents

- [Status](#status)
- [Source and verification](#source-and-verification)
- [Row schema](#row-schema)
- [Decisions](#decisions)
- [Source conflicts](#source-conflicts)
- [Handed to other sessions](#handed-to-other-sessions)
- [Correlating later posts](#correlating-later-posts)

This is the provenance record for acting on the claude.dev post about the claude.ai performance
sprint. It follows the record shape of [claude-dev-sonnet-5-5-blog.md](claude-dev-sonnet-5-5-blog.md)
and the [upstream-drift](../conventions/upstream-drift/README.md#required-parts) convention. Each
row is our decision in our own words; no row restates the post or a docs page.

## Status

The post was first absorbed in #4426 (merged 2026-09-24), which added the `performance` plugin's
protect skill and technique catalog. This record covers a later delta pass over that absorption:
every departure from the post, and every rule behind one, was challenged and either kept or
dropped on evidence. The pass lands as one pull request with one commit per area and no new
plugin. Each row below names the file a decision landed in.

## Source and verification

- Correlate with `https://claude.dev/blog/how-we-made-claude-ai-faster/` (published 2026-09-23,
  digested and dual-verified 2026-09-29, its Steering section re-read 2026-10-02). It is never the
  pointer where a docs section covers the topic.
- Figures the post reports, each vendor-reported and none carried elsewhere in this repository:
  claude.ai and the desktop app about 3x faster after a two-week August sprint (vendor-reported:
  the title and intro); about 3,000 changes shipped (vendor-reported: the page's meta description).
- The digest tags every claim only this post makes as vendor-claimed; the Anthropic publisher
  profile now carries the rule for its outcome counts (row F21).

## Row schema

**Topic** names the item with an ID other files cite; **Ours** is what this repository now does
and where, or why it changed nothing; **Pointer** is the section to fetch live when re-deriving
the row. A post section appears only where no docs page covers the topic, as a correlate; `none`
marks an in-repo decision with no upstream section. Shared for every row:

- **As of**: 2026-10-02
- **Recheck trigger**: the pointed-to section is renamed or removed, or stops covering its topic;
  a docs page starts covering a topic whose pointer is the post (move the pointer there); or a
  later claude.dev post on claude.ai performance.

## Decisions

| Topic | Ours | Pointer |
|---|---|---|
| F1 Catalog is this plugin's own practice | `plugins/performance/reference/techniques.md` is cut to entries of a name in our terms plus When, Counter, Fails when and Used by, each with one context-glue record; the header presents the catalog as the plugin's practice. `reference/glossary.md` and `README.md` get the same treatment. No post text, figure or quote remains in the three files | Each entry's own record; the post's sections as correlates where no docs page covers the entry |
| F2 Outcome count as evidence | The catalog entry that read the post's change count as proof that guardrails make volume safe is deleted; the guardrail entries in `techniques.md` section G keep only our rules | Post, [Guardrails](https://claude.dev/blog/how-we-made-claude-ai-faster/#guardrails) (correlate) |
| F3 One pointer form | `docs/conventions/upstream-drift/README.md` Required parts names the context-glue Pointer (`when <situation>, fetch <link> live`) and the one-line layout; convention 2.1.0, additive. Every pointer this pass wrote uses it | none |
| F4 Catalog self-contradictions | `techniques.md` section B states the journey end-event rule once; section F marks the skeleton delay as a per-surface human ruling; the "Used by: `/performance:verify` Next" lines in sections G and H stay, now true (row F12) | none |
| F5 When a ratchet is earned | A counter ratchets at a lab MET; a change shipped behind a flag waits for the field read and turns the flag off if the read shows no gain. `plugins/performance/skills/protect/SKILL.md` Purpose; `techniques.md` "Ratchet mechanics" (G) and "Ratchet or revert" (H) | Post, [The loop, thread by thread](https://claude.dev/blog/how-we-made-claude-ai-faster/#the-loop-thread-by-thread) (correlate) |
| F6 Lowering a ceiling | Same-PR tightening is the default; protect proposes a scheduled draft-PR job only for a counter that can fall without a PR, and that workflow file is the setting (keep it or delete it). `protect/SKILL.md` section 4; `techniques.md` "Ratchet mechanics"; the ratchet step comment in `.github/workflows/ci.yml` says an image-driven drop is lowered by hand | Post, [Guardrails](https://claude.dev/blog/how-we-made-claude-ai-faster/#guardrails) (correlate) |
| F7 Estimated gain sets the Realistic target | Goal may propose the Realistic target as measured cost minus the summed estimated gain, labeled `estimate`, accepted or replaced at its human gate; never on a candidate with no measured cost. `plugins/performance/skills/goal/SKILL.md` section 3 and Output; `techniques.md` "Estimates in the target unit" (A); `skills/target/SKILL.md` Next names goal's real stop | [Define your success criteria](https://platform.claude.com/docs/en/test-and-evaluate/define-success#define-your-success-criteria); post, [The brief](https://claude.dev/blog/how-we-made-claude-ai-faster/#the-brief) (correlate) |
| F8 Percentiles | p50 and p95 over at least 20 samples stay the default; the goal records its list and passes it as `ab.sh --percentiles`, with the `1/(1-p)` floor on every entry. `plugins/performance/scripts/ab.sh`, `summarize.py`, `scripts/README.md`; `goal/SKILL.md`; `snapshot/SKILL.md` step 3 | [SRE Book, Aggregation](https://sre.google/sre-book/service-level-objectives/#aggregation-1Ls9hQin) |
| F9 Runs per deterministic counter | Two agreeing runs when a ceiling is set or lowered, tunable with `--runs N` on `ratchet.py add` and `propose-tighten`; CI `check` still runs once. `plugins/performance/scripts/ratchet.py`; `protect/SKILL.md` section 1; the instruction-count recipe in `techniques.md` section C | [Cachegrind command-line options](https://valgrind.org/docs/manual/cg-manual.html#cg-manual.cgopts); post, [Anything can be hill climbed](https://claude.dev/blog/how-we-made-claude-ai-faster/#anything-can-be-hill-climbed) (correlate) |
| F10 Counters of any kind | No new counter script: a counter is added with `ratchet.py add` as a `.performance/ratchets.json` entry whose command prints `<field>=<number>`. `techniques.md` "Deterministic counters by layer" (C), with its reopen trigger | Post, [Anything can be hill climbed](https://claude.dev/blog/how-we-made-claude-ai-faster/#anything-can-be-hill-climbed) (correlate) |
| F11 Correlation on every ratchet | A ratchet's goal text ends with the goal's Correlation value (a pointer, or `unproven: <reason>`); no schema key, policy key or script flag. `protect/SKILL.md` section 2 and Output; all 14 entries in `.performance/ratchets.json` backfilled | none |
| F12 Field read after a flagged release | Verify names the field-read source (`/harness-ops:observability latency` for Claude Code's own hook behavior, else the telemetry the project's instructions name), read before and after the release; Next bullets 1 and 3 fold the route in. `plugins/performance/skills/verify/SKILL.md` section 5 and Next; the read's limits in `techniques.md` section H | [Hook execution complete event](https://code.claude.com/docs/en/monitoring-usage#hook-execution-complete-event) |
| F13 The loop and the fix step | No router or chain skill: the loop over the five skills, the fix step included, runs under the user's own `/goal` or `/loop`, and the edit is delegated to `/implementation:implement`. `plugins/performance/README.md` Skills and "Own the fix"; `snapshot/SKILL.md` Next | Post, [The loop, thread by thread](https://claude.dev/blog/how-we-made-claude-ai-faster/#the-loop-thread-by-thread) (correlate) |
| F14 Staged rollout for plugins | No stable branch or release channel: main ships to everyone by version bump, ramped by evidence gates and dogfooding. `techniques.md` "Staged rollout" (H) maps the stages to this marketplace | [Run release channels](https://code.claude.com/docs/en/plugins/host-marketplace#run-release-channels) |
| F15 Skill bodies carry records | Each upstream specific the performance skill bodies restate carries a record in place, for example the pyperf thresholds in `snapshot/SKILL.md` step 1 and the latency-read limits in `verify/SKILL.md` section 5 | Each body's own record |
| F16 Merge lane autonomy goal | The merge lane prompt says the goal is to merge more classes autonomously as promotion evidence accrues, and today the lane merges only within the rung it resolves at run time. `prompts/loops/loop-lane-prompts.md` section 2; `prompts/loops/loop-lane-profile-claude-code-plugins.md` adds that here it is human-only. `.claude/source-control.md` keeps `c3-autonomous`; `techniques.md` "Standing role brief" (I) names both as users | none |
| F17 Approval count | No plugin sets an approval count: it comes from the repository ruleset's `required_approving_review_count`, which the merge gate reads. `plugins/source-control/reference/config-resolution.md` Loop-lane keys | none |
| F18 Before/after media on visual PRs | When a diff changes rendered output, PR create drafts before/after media into the verification section, attached with `gh pr create --attach` where listed; a project turns it off in its own CLAUDE.md or AGENTS.md. `plugins/source-control/skills/pull-request/reference/create.md` "Visual evidence"; `docs/conventions/pr-body-convention/README.md`; `techniques.md` section J names the step | [gh pr create, Options](https://cli.github.com/manual/gh_pr_create#options); post, [Steering](https://claude.dev/blog/how-we-made-claude-ai-faster/#steering) (correlate) |
| F19 Screenshots in bug reports | A screenshot or still frame backs Expected vs actual; video is never asked for; a repo that wants one every time says so in its `.claude/bugs.md`. `plugins/bugs/skills/write/SKILL.md` Step 3 | none |
| F20 Unrelated review fixes | A small unrelated fix lands in the PR only in a file it already touches, otherwise in its own small PR; the review thread resolves with a "fixed in a linked PR" disposition. `plugins/source-control/reference/review-discipline.md` clause `D4.6-unrelated-fix-placement` and D7.5; `babysit-prs/scripts/babysit_resolve_thread.py`; restatements in source-control, work-items and review point at the clause. `AGENTS.md` widens it to same-plugin fixes here | none |
| F21 Sprint outcome counts | A blog post's outcome counts for claude.ai are tagged consumer-surface and vendor-claimed; a team departs in its own CLAUDE.md or AGENTS.md. `plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md`; the queue notes for posts this pass fetched are corrected in `anthropic-docs-queue.md` | none |
| F22 Opus 5.5 scope and long runs | The scope section is deleted; Long runs keeps our rules, adds that a project changes its named stops in its own CLAUDE.md or AGENTS.md, and carries the post as a correlate. `plugins/playbooks/reference/model-adaptation/opus-5-5.md#long-runs` | [Unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs); post, [Steering](https://claude.dev/blog/how-we-made-claude-ai-faster/#steering) (correlate) |
| F23 Owned threads | The section keeps our rules: one thread per benchmark or journey, a named owner who sets goals and rules on tradeoffs and sequencing, each change merging under the repository's own merge policy, one shared brief. `plugins/playbooks/skills/fable-5/context/orchestration.md#narrow-threads-per-benchmark-or-journey` | The four docs sections in that section's record; post (correlate) |
| F24 Opus 5.5 guide read | The guide was re-read and three stamps refreshed with the outcome (moved; no verdict changed): `opus-5-5.md` Sources, `plugins/harness-config/skills/audit-prompting-postures/reference/postures.md`, `plugins/harness-config/skills/audit-instructions/reference/criteria.md`. harness-config took a patch release only because a changed file needs a new version | [Prompting Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5) |
| F25 Tunable defaults | Kept: every default above is tuned through a surface that already exists (a script flag, a tracked config file, the GitHub ruleset, or the project's own CLAUDE.md or AGENTS.md); this pass adds no setting key | none |
| F26 No new plugin | Kept: every change lands in existing plugins and docs; no capability gap the post exposed needed a new one | none |
| F27 Claude Tag and Slack | Declined: out of scope unless an organization on a Team or Enterprise plan connects a Slack workspace; no repository artifact depends on it | none |
| F28 Scope claim in other chapters | Declined: the post's scope claim is not copied into other model chapters, the postures catalog or a boris tip, because each model's own guide gives its scope steer (see [Source conflicts](#source-conflicts)) | [Task scope and over-verification](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#task-scope-and-over-verification) |
| F29 Automated "be bolder" nudges | Declined: the user sends a nudge when a met target should keep going, bounded by their own `/goal`; the catalog's quoted nudges went with F1 | Post, [Steering](https://claude.dev/blog/how-we-made-claude-ai-faster/#steering) (correlate) |
| F30 Concurrency defaults | Kept: the 3-5 worker wave and the work-loop cap stay, tuned by the existing implementation and work-items plugin settings | none |
| F31 Closing a thread at diminishing returns | Kept: the close call stays human, under the judgment criteria in F23's section; no detector | none |
| F32 Agent-proposed performance work | Declined: no performance routine, because `/improvement:find --unattended` already gives a findings-only pass a user can schedule; the scheduled ratchet PR stays with protect (F6) | none |
| F33 Usage-limit reset checker | Already fixed by #5676 before this pass; #5797 closed as completed. No session-flow change | Probe: #5676's regression tests |
| F34 Digest working files | Kept untracked: the digest, interview and plan files stay out of the repository; this record is the trail | none |

## Source conflicts

- The post's [Steering](https://claude.dev/blog/how-we-made-claude-ai-faster/#steering) section and
  Prompting Claude Opus 5's
  [Task scope and over-verification](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#task-scope-and-over-verification)
  section disagree on Claude's default task scope. The guide wins: rows F22 and F28 follow it.
  - **As of**: 2026-10-02
  - **Recheck trigger**: either section changes its scope statement, or the Opus 5.5 prompting
    guide starts covering task scope.

The delta pass found no other conflict between the post and an official page.

## Handed to other sessions

- #4588 tracks the promotion-evidence seam behind the merge rung. It was reopened on 2026-10-02 so
  its Phase 3 decision runs as its own security-reviewed effort. Until the seam returns a qualified
  read, the merge lane stays human-only (row F16).
- #5684 owns the tree-wide no-copy retrofit; this pass converted only the files it touched.
- The session acting on the Sonnet 5.5 prompting guide left the performance catalog, glossary and
  README to this pass; its own record is [claude-dev-sonnet-5-5-blog.md](claude-dev-sonnet-5-5-blog.md).

## Correlating later posts

A later claude.dev post on claude.ai performance is correlated here: add it as a correlate note
beside the row it touches, and move a row's pointer only to a docs section, never to a post.
