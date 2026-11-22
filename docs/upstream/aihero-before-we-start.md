# Upstream source: AI Hero Cohort 005, Workshop 1 "Before We Start" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Before We Start** workshop of Matt Pocock's AI Hero cohort (Cohort 005): seven lessons that set
up the cohort before any building starts. The workshop names where the course ends up (agent
sessions started by events rather than by a person), orders checks ahead of throughput, covers
model and plan choice, isolates the learner's agent from personal configuration, explains the
community and live sessions, and sets up a practice repository that tracks the instructor's
checkpoints. Our counterparts are [`/work-items:ship`](../../plugins/work-items/skills/ship/SKILL.md),
the [loop-lane contract](../contracts/loop-lane/README.md),
[`/planning:interview`](../../plugins/planning/skills/interview/SKILL.md),
[`/harness-ops:inventory`](../../plugins/harness-ops/skills/inventory/SKILL.md) and
[`/knowledge:video-digest`](../../plugins/knowledge/skills/video-digest/SKILL.md). Rows hold our
decisions and our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no lesson text is recorded or linked here; the skills it
teaches are public and versioned in [mattpocock/skills](https://github.com/mattpocock/skills),
whose record is [mattpocock-skills.md](mattpocock-skills.md). Later workshops have their own
records: [aihero-domain-language.md](aihero-domain-language.md),
[aihero-wayfinder.md](aihero-wayfinder.md), [aihero-review.md](aihero-review.md),
[aihero-codebase-design.md](aihero-codebase-design.md) and
[aihero-feedback-loops.md](aihero-feedback-loops.md); the earlier crash course is in
[aihero-course.md](aihero-course.md).

- **Pointer**: when a row needs the upstream mechanism, fetch the public skills the practice
  repository vendors live:
  [`grill-me`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/grill-me),
  [`grilling`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/grilling)
  and
  [`handoff`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/productivity/handoff).
- **As of**: 2026-11-18
- **Recheck trigger**: a mattpocock/skills changeset naming one of those units, checked as
  [mattpocock-skills.md](mattpocock-skills.md) describes. Course page updates are not observable
  events; the skills-repo changeset stream is the proxy, as in
  [aihero-shipping-course.md](aihero-shipping-course.md).

**Landed** names the merged pull request that carries the row.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject`, `no change` or `hold`, with the reason; a
`hold` names what it waits on. The upstream-problem cells are **Inference** throughout: the lesson
pages that state them are paid and not linked. Rows about the follow-along practice repository
record decisions kept outside this repository.

### Where the course is going

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The term "software factory" | Names agent sessions that events start, with no person launching them | Inference: the target state needs one name | We had rejected the term as a second name for our loop lane | **adapt**: adopted with a wider meaning, every lane together; see the term row in [aihero-course.md](aihero-course.md#terms-from-the-v13-video-pass-decided-2026-10-10) and the [glossary](../glossary.md) | [#16695](https://github.com/melodic-software/claude-code-plugins/pull/16695) |
| A spec-implementation flow: exploration step, one runner per ready ticket, merge, agent review last | Runs a whole spec through parallel runners in waves until every ticket closes | Inference: one ticket at a time is too slow for a full spec | `/work-items:ship` runs per-item pull requests or one integration branch | **already have** per item, compared in the [workshop 8 record](aihero-software-factory-part-two.md#lesson-9-implement-spec): `/work-items:ship` runs per-item pull requests, so no new pipeline is added; **reject** agent review last, since both review lanes run on every ready pull request | none |
| Trust grows with the number of agents running | Measures progress by how many agents run at once | Inference: more agents is the visible sign of a working setup | Our autonomy ladder is keyed to merge authority, not agent count | **adapt**: two limits, agents running and changes waiting on the owner; the numbers wait for workshop 08 and the automation-shape pass, since they depend on infrastructure and on what counts as an agent; the ladder stays keyed to merge authority | none |
| Brakes before accelerators | Puts review, design, shared terms, planning and checks in place before more automation | Inference: speed without checks multiplies defects | Our gates and throughput loops had no map under this split | **take**: the ordering governs new or widened automation, and verification keeping pace is the per-loop audit question; the brake and accelerator terms and the topology table's column landed, the ordering rule and the checks-to-loops map wait for the automation-shape pass | [#16695](https://github.com/melodic-software/claude-code-plugins/pull/16695) (terms only) |
| Prerequisites: context window, a context budget, steering, grilling | Assumes the crash-course basics | Inference: later workshops build on them | Same | **already have**: recorded in [aihero-course.md](aihero-course.md) | none |
| Any terminal agent that runs skills | Keeps the course harness-neutral | Inference: learners use different agents | Ours ship as Claude Code plugins | **reject** for now: Claude Code plugins only, configurable, with valid defaults | none |
| How fast quality drops as the context fills | Gives a rough point where the window starts to hurt | Inference: long sessions degrade unnoticed | Our context bands were described as resting on a shared practitioner figure | **adapt**: band values stay declared judgment, user-configurable from one source, until our own runs measure them; the reader contract drops the consensus wording | [#15294](https://github.com/melodic-software/claude-code-plugins/pull/15294) |
| Deterministic checks make the loop trustworthy | Prefers checks with fixed outcomes as the agent's self-correction signal | Inference: a model judging a model drifts | Our merge path is a model judgment per head, behind layered tamper guards | **take**, decided at the feedback-loops workshop, on the condition that a check covers the edge cases or it needs upkeep; see [aihero-feedback-loops.md](aihero-feedback-loops.md) | see that record |
| One decision per question when grilling | Asks the person a single question at a time | Inference: batched questions get shallow answers | `/planning:interview` asks in numbered rounds | **no change** after measuring: a paired eval compared rounds against single questions and rounds held up, with both arms at the quality ceiling, so `round` stays the default ([`interview-pacing.md`](../../plugins/planning/evals/interview-pacing.md)) | [#16514](https://github.com/melodic-software/claude-code-plugins/pull/16514), [#16625](https://github.com/melodic-software/claude-code-plugins/pull/16625) |

### Choosing a model and plan

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Model choice matters more for long, parallel, autonomous runs | Raises the bar for the model behind each agent | Inference: weaker models fail on long tasks | Our model and effort per role ([`defaults.yaml`](../../plugins/multi-agent/reference/defaults.yaml)) rest on judgment | **hold**: the model-choice decision, which tests our routing on long tasks | none |
| The lowest plans are not enough for this course | Steers learners away from entry plans | Inference: learners hit limits mid-lesson | The owner's plan is settled | **reject**: no plan advice ships here; plan limits are the vendor's to state | none |
| A mid plan is the minimum for the top model class | Ties model access to plan level | Inference: learners need the strongest models | Not our case | **reject**: plan access and limits are the vendor's to state, and cost claims link the vendor's pages ([cost-claims rule](../../.claude/rules/cost-claims.md)) | none |
| The instructor's own plan, used daily | Shows the plan that sustains his workload | Inference: learners copy a working setup | Same | **already have** | none |
| A subscription, not the API, for this work | Prefers subscription billing for heavy agent use | Inference: metered use costs more for long sessions | CI's credential order no longer matched its decision record | **already have** for interactive work; **adapt**: ADR 0062 records CI's credential order and the fallback token's account ([ADR 0062](../adr/0062-allow-api-keys-from-the-operator-s-own-linked-console-orgs.md)) | [#15287](https://github.com/melodic-software/claude-code-plugins/pull/15287) |
| Any top-class model on any subscription serves equally | Treats model and plan as interchangeable above a bar | Inference: learners overthink the choice | We route models per role | **reject** as stated: we pick the model per role | none |
| A public long-task benchmark picks the model | Reads a leaderboard to choose | Inference: vendor claims are hard to compare | No benchmark drives our routing | **hold**: the benchmark is one input to the model-choice decision, beside our own evals | none |
| His model is missing from the benchmark | Notes the gap | Inference: the board lags releases | Same | **no change** | none |
| Start on a low plan and upgrade when it runs out | Grows spend with use | Inference: learners should not overpay | Not our case | **reject**: not applicable | none |

### Setting up the agent

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Any agent that runs skills; switching agents loses nothing | Treats a skill folder as portable across harnesses | Inference: learners want freedom of tool | Harnesses differ in how they load skills | **reject** for now: Claude Code plugins only | none |
| The course skills ship inside the practice repository | Needs nothing installed globally | Inference: global installs drift between learners | ADR 0018's premise of no repository-local skills no longer held | **already have** repository delivery through plugins; **adapt**: ADR 0018 says a repository-local control skill is not a distribution unit ([ADR 0018](../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)) | [#15287](https://github.com/melodic-software/claude-code-plugins/pull/15287) |
| The skills folder is a symbolic link to another folder | Serves one skill set to several harnesses | Inference: harnesses look in different folders | Whether Claude Code reads a skills folder that is itself a link | **already have**: confirmed 2026-11-16 in the follow-along experiment, where a project skill loads through a linked `.claude/skills` folder | none |
| Any top-class model, chosen with the benchmark | Repeats the model advice for setup | Inference: as above | As above | **hold**: the model-choice decision | none |
| A personal skill with the same name can win over the repository's | Warns that a global skill silently replaces a project one | Inference: learners get results unlike his | Plugin skills are namespaced and cannot be shadowed; a project skill can replace a bundled skill of the same name | **already have** for plugins; **adapt** in the experiment: record that it runs his versions of skills that share a bundled name | none |
| Home-folder instruction files load in every project | Warns that personal instructions fight the repository's | Inference: hidden instructions skew results | The experiment sat under a repository with its own instruction files | **adapt**: the experiment clone moved outside any repository | none |
| Clear personal configuration by moving it to a backup | Resets to defaults by renaming folders | Inference: a clean start makes results comparable | A move misses some configuration and is easy to get wrong | **reject** the move: Claude Code's documented switches isolate a session without moving files ([Run a session clean](../../plugins/harness-ops/README.md#run-a-session-clean)) | none |
| A prompt that finds shadowing skills and instructions, then backs them up | Has the agent audit its own configuration | Inference: learners do not know where configuration hides | No guidance for running one interactive session clean | **adapt**: [Run a session clean](../../plugins/harness-ops/README.md#run-a-session-clean) | [#16510](https://github.com/melodic-software/claude-code-plugins/pull/16510) |
| Ask the agent which skills it sees and where each comes from | Checks the reset worked | Inference: a reset can fail silently | Same | **already have**: `/harness-ops:inventory` and the source tags Claude Code shows | none |

### Community and live sessions

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Search past questions before asking | Avoids repeat questions | Inference: repeats waste the answerer's time | The interview's self-answer step sent tradeoffs to the owner even when already decided | **adapt**: self-answer reads prior owner decisions, and a quoted ruling answers ([`self-answer.md`](../../plugins/planning/context/self-answer.md)) | [#15289](https://github.com/melodic-software/claude-code-plugins/pull/15289) |
| A channel for specific problems, another for general talk | Sorts questions by kind | Inference: mixed channels bury questions | Our questions reach the owner through interview rounds and parked items | **reject**: no peer community here | none |
| Cohort roles and access steps | Gets learners into the right channels | Inference: hidden channels confuse newcomers | Not our case | **no change** | none |
| Moderators and a role for helpful members | Rewards members who answer | Inference: a large cohort needs helpers | No community to moderate | **reject** | none |
| Peer discussion is worth the time | Encourages learners to talk to each other | Inference: peers unblock each other | Unattended sessions read no community channel | **no change**: the owner keeps community channels unread outside attended sessions | none |
| His other open-source tools have their own channels | Points to support for each tool | Inference: tool questions belong with the tool | Same | **already have**: [mattpocock-sandcastle.md](mattpocock-sandcastle.md) | none |
| Scheduled live sessions, recorded at a stable link | Lets learners join or watch later | Inference: time zones keep people from attending | Same | **already have**: each session is digested once its recording exists | none |
| Questions posted ahead and ordered by votes | Puts the most wanted questions first | Inference: live time is short | Only one person asks the owner questions | **no change**: no second voter, so no vote signal | none |
| Urgent questions go to the always-watched channel, not the live queue | Splits urgent from batched questions | Inference: a batched queue is too slow for blockers | Our severity sets notification depth, not when a question is asked | **no change**: no class of questions is held for a scheduled owner session | none |
| Take part asynchronously when you cannot attend | Treats the recording as the session | Inference: learners miss live sessions | A recording's captions appear only after processing, and video-digest stopped without them | **adapt**: video-digest waits for captions after a live stream ends | [#15316](https://github.com/melodic-software/claude-code-plugins/pull/15316) |

### The practice repository

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A fresh practice repository, separate from the crash course one | Starts the cohort on a clean copy | Inference: leftover work confuses later lessons | Same | **already have**: the follow-along experiment | none |
| Clone over HTTPS or SSH | Picks a clone protocol | Inference: learners stall on setup | Either works | **no change** | none |
| A command-line fork: a new public repository holding the course's `main` with its history (one fresh commit before ai-hero-cli 0.13.0), scripts that still reach the course repository | Copies the course without a platform fork | Inference: learners need their own remote for issues and pull requests | Same | **already have** in the experiment, forked before 0.13.0 with one commit ([ai-hero-cli changelog](https://github.com/mattpocock/ai-hero-cli/blob/main/CHANGELOG.md)) | none |
| Your own issues and pull requests are the ticket tracker | Keeps tickets beside the code | Inference: one place for work | A fork checkout with an `upstream` remote could send our tracker and pull-request writes to the course's public repository | **adapt**: write paths pin the target repository in fork checkouts, and the work-item tracker resolves it with the pull-request skill's resolver, so a fork checkout targets the fork | [#15375](https://github.com/melodic-software/claude-code-plugins/pull/15375) |
| Public, so hosted CI runs free | Avoids CI charges | Inference: private repositories run out of included minutes | Larger runners bill even on public repositories | **already have**: the pull-request pipeline's cost hold covers larger runners ([pr-pipeline](../conventions/pr-pipeline/README.md)) | none |
| The same sample app as the crash course | Builds new skills on a known codebase | Inference: a new app adds noise | Same | **already have** | none |
| Install, seed, then start the app; ignore install warnings | Gets the app running | Inference: warnings scare learners | Same | **already have** in the experiment; ignoring audit warnings fits a throwaway repository only | none |
| Third-party accounts for later lessons | Prepares notification and whiteboard services | Inference: sign-ups stall a lesson | Nothing here uses them yet | **no change**: those lessons arrived and none needs either account, so no sign-up is made | none |
| A troubleshooting section built from member reports | Collects common setup failures | Inference: the same failures recur | Not our case | **no change** | none |
| A lock file pins vendored skills by path and content hash | Fixes the skill versions the course uses | Inference: skill changes would break lessons | Our rule: installs track the latest marketplace version, never a per-repository pin | **already have**: no repository here vendors skills; plugins install from the marketplace, and borrowed upstream content is pinned by commit with a weekly drift check ([mattpocock-skills.md](mattpocock-skills.md)), so a lock file has no consumer | none |

### Keeping in step with the instructor

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Keep your code at his checkpoint so your agent's results match his | Aligns starting states | Inference: different code gives different results | One run from the same commit does not show a difference is ours | **adapt** in the experiment: the same commit is necessary, not sufficient; compare several runs from one checkpoint | none |
| A reset command replaces your work with a checkpoint | Jumps to a lesson's start | Inference: learners fall behind | Same | **already have**: commit first, as the crash course rows decided | none |
| A cherry-pick command keeps your commits and adds the lesson's on top | Keeps local work, at the cost of conflicts | Inference: learners want to keep their changes | Our pull-request `ready` updates a branch by merging the base, or by a lease-pinned rebase only on an attended run that allows a rewrite; an unattended run never rewrites | **already have** | none |
| Cherry-picking keeps your own model choice while taking his changes | Protects local settings from checkpoint updates | Inference: learners customize the model | His runner hard-codes the model in a tracked file his checkpoints also edit, so a changed model conflicts | **no change**: rechecked 2026-11-18 at the course branch tip that workshops 07 and 08 use: the runner still hard-codes the model in a tracked file, so the conflict stands and there is nothing to take | none |
| A pull command merges announced fixes and keeps your work | Delivers course fixes | Inference: course code has bugs | Not our case | **already have** | none |
| Install, migrate and seed again after a reset | Brings dependencies and schema in line with the code | Inference: a reset changes source only | Nothing re-runs these after a checkout | **already have**: the open check, whether `/app-control:drive ready` spots pending migrations, stays with the crash-course absorption | none |

### Handed elsewhere

- The two limits' numbers and the checks-to-loops map behind brakes before accelerators: the
  automation-shape pass after workshop 08.
- Model choice, the long-task benchmark as one input, and top-class model advice: the model-choice
  decision.
- How much of the host a Claude Code session in WSL can reach, and what isolates it: decided in
  workshop 07. The [isolation ladder](../../plugins/autonomy/reference/guardrails/isolation-ladder.md#wsl-on-a-windows-host)
  counts default WSL as no isolation level and WSL2 with the per-command sandbox as `L1`
  ([#16702](https://github.com/melodic-software/claude-code-plugins/pull/16702)); the stack for a
  Windows-only machine is still to be decided.

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. The public skills repository reads MIT on the host and in
[mattpocock-skills.md](mattpocock-skills.md); no text or code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-17
- **Recheck trigger**: the skills repository's license file changes.
