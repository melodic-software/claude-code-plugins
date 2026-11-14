# Upstream source: AI Hero Cohort 005, Workshop 4 "Review" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Review** workshop of Matt Pocock's AI Hero cohort (Cohort 005): seven lessons on how a change gets
checked before it merges. The workshop layers deterministic checks, agent review and human review;
gives the person a pull request body that shows how much reading a change needs; runs a review agent
against standards and the spec; and turns repeated review comments into lasting fixes through a
retro. Our counterparts are [`/source-control:pull-request`](../../plugins/source-control/skills/pull-request/SKILL.md),
[`/review:merge-risk`](../../plugins/review/skills/merge-risk/SKILL.md), the
[`code-reviewer`](../../plugins/review/agents/code-reviewer.md) agent,
[`/corrections:codify`](../../plugins/corrections/skills/codify/SKILL.md) and
[`/session-flow:retro`](../../plugins/session-flow/skills/retro/SKILL.md). Rows hold our decisions
and our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no lesson text is recorded or linked here; the skills it
teaches are public and versioned in [mattpocock/skills](https://github.com/mattpocock/skills),
whose record is [mattpocock-skills.md](mattpocock-skills.md). Earlier course units have their own
records: [aihero-course.md](aihero-course.md), [aihero-shipping-course.md](aihero-shipping-course.md),
[aihero-domain-language.md](aihero-domain-language.md) and [aihero-wayfinder.md](aihero-wayfinder.md).

- **Pointer**: when a row needs the upstream mechanism, fetch the public skills it rests on live:
  [`pr`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/pr),
  [`code-review`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/code-review)
  and
  [`retro`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/retro).
- **As of**: 2026-11-13
- **Recheck trigger**: a mattpocock/skills changeset naming one of those units, checked as
  [mattpocock-skills.md](mattpocock-skills.md) describes. Course page updates are not observable
  events; the skills-repo changeset stream is the proxy, as in
  [aihero-shipping-course.md](aihero-shipping-course.md).

**Landed** means merged unless marked open. As of 2026-11-13,
[#16050](https://github.com/melodic-software/claude-code-plugins/pull/16050) (implement reads the
review-criteria index),
[#16056](https://github.com/melodic-software/claude-code-plugins/pull/16056) (one chosen pull
request's review comments) and
[#16064](https://github.com/melodic-software/claude-code-plugins/pull/16064) (body refresh in CI
address-feedback rounds) are open.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject` or `no change`, with the reason. The
upstream-problem cells are **Inference** throughout: the lesson pages that state them are paid and
not linked.

### Layers of review

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Quality controls before speed | Sets up the checks before raising how much agents produce | Inference: more agent output with no checks ships more defects and wears the reviewer out | Same | **already have**: new automation here gets its checks first, decided before this workshop | none |
| Three layers in order: deterministic checks, agent review, human review | Each change passes the cheap, certain checks first and a person last | Inference: a person should spend time only on what machines cannot settle | Same | **already have**: `ci-status` and hooks, the two CI review lanes ([`/review:code-review`](../../plugins/review/skills/code-review/SKILL.md), [`/review:security-review`](../../plugins/review/skills/security-review/SKILL.md)), and the owner stops in [When work stops for the owner](../contracts/loop-lane/README.md#when-work-stops-for-the-owner) | none |
| Add deterministic checks freely | Treats checks as nearly free because they spend compute, not model tokens | Inference: every check that catches a mistake saves review time | Checks still cost runner time, host load and flaky-test upkeep | **no change**: a check is added for an observed failure, not in bulk; `/corrections:codify` proposes one only with proof it fails on the old code and passes on the new | none |
| Agent review named as model-graded judging | Labels review by an agent with the evaluation term | n/a | Here that term names eval graders in the `evals` plugin | **no change**: review keeps its own name | none |

### The pull request body

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Two aims for human review: understand fast, spend time where it matters | Treats pull requests unequally by risk | Inference: equal attention for every change wastes the reviewer | Same | **already have**: a risk score routes merges, and low-risk diffs merge unattended ([`babysit_risk.py`](../../plugins/source-control/skills/babysit-prs/scripts/babysit_risk.py)) | none |
| Agent-written descriptions are weak | Gives the agent a body template to fill | Inference: a vague body puts reviewers off | Same | **already have**: the body contract's required sections, linkage line and `Left out:` line ([`create.md`](../../plugins/source-control/skills/pull-request/reference/create.md)) | none |
| Open the body with a drawing of the change | Puts a diagram, file tree or diff sketch above the prose | Inference: a picture conveys intent before any code is read | Our body is prose with a contract; drawings live in other skills | **reject** for the body: no study measures a drawing in a description helping review, and models make mistakes writing diagram syntax; [`/review:explain-change`](../../plugins/review/skills/explain-change/SKILL.md) draws the change outside the body | this record |
| Evidence that the change was broken before and works after | Shows the failing state, then the passing one, screenshots first for visual changes | Inference: proof in the body saves checking out the branch | Ours asks for verification and, for rendered changes, before and after media | **already have**, in part: `Verification` plus the visual evidence step ([`create.md`](../../plugins/source-control/skills/pull-request/reference/create.md), "Visual evidence"); **no change** for a failing-before line | none |
| A risk section the author writes: door type and reach | The body says whether the change can be undone cheaply and how far it reaches | Inference: one-way changes need the closest reading | Our body said nothing on undoing a change; the rating came only from a separate rater | **adapt**: the briefing preset's risk item says what the change reaches and how it is undone, written only when it has content; the author states no door or tier | [#16019](https://github.com/melodic-software/claude-code-plugins/pull/16019) |
| The author agent rates its own change | The same agent that wrote the change sets its risk | Inference: the author knows the change best | An author grading itself tends to grade itself well | **reject**: the rating stays with [`/review:merge-risk`](../../plugins/review/skills/merge-risk/SKILL.md), a second agent that rates blind | none |
| An additive schema change rated as a one-way door | Calls a migration that only adds structure hard to undo | Inference: migrations feel irreversible | Our shared door definition called every applied migration one-way, so an additive, backward-compatible one rated high | **adapt**: rewriting, deleting or narrowing is one-way; adding is two-way while the previous code still runs against the new schema, and removing the addition is its own change; turning a feature off after users wrote data through it is one-way; what a migration costs to run is rated under Impact ([`lib/one-way-doors.md`](../../lib/one-way-doors.md)) | [#16018](https://github.com/melodic-software/claude-code-plugins/pull/16018) |
| Low-risk, two-way changes skip human review and are read after merge | Lets solid checks and agent review carry small, undoable changes | Inference: a person cannot read every change | Low scores already merge unattended; nothing reads a merged diff afterwards | **no change** | none |
| Bring a borrowed skill in as a copy with a credit note | Copies another author's skill instead of depending on it | Inference: a copy cannot break when its source moves | Same | **already have**: records under `docs/upstream/` and the `attribution` plugin | none |

### Writing the body

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The body skill loads on its own when a body is asked for | No command to remember | Inference: users forget to call it | Same | **already have**: `/source-control:pull-request create` owns the body | none |
| The body uses the project's agreed terms | Reads the glossary while writing | Inference: a body in other words than the code misleads | Same | **already have**, in part: an unattended run reads the glossary and lists the terms it coined ([`create.md`](../../plugins/source-control/skills/pull-request/reference/create.md), "Glossary candidates on an unattended run") | none |
| Writing the body surfaces defects and weak evidence | The writer notices problems while describing the change | Inference: a cheap pass catches issues before a person reads | Same | **already have**: the `Left out:` line, and the review lanes that run once a pull request is ready | none |
| Show the body before posting | The person sees the drafted body and can stop it | Inference: a wrong body is posted unseen | Ours posted the body without showing it | **adapt**: `pr_body_preview` setting, posting directly by default; when on, the rendered body is printed and the run waits, in attended sessions only | [#16019](https://github.com/melodic-software/claude-code-plugins/pull/16019) |
| One skill writes the body, runs checks and reports code problems | Bundles evidence, risk and review into the body run | Inference: one run gives a complete picture | Ours splits these by job | **already have**, kept apart: verification, risk rating and change explanation are separate runs (`/verification:confirm`, `/review:merge-risk`, `/review:explain-change`) | none |

### The review agent

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Review is its own job, run in a fresh context | The reviewer starts at the diff, not the implementer's history | Inference: the implementer's context biases its own review | Same | **already have**: the review plugin's reviewers start fresh | none |
| A reviewer can carry far more instructions than an implementer | Loads the reviewer with a long standards list | Inference: review has room for detail | Long criteria dilute each one | **reject**: criteria stay short and split one concern per file in [`docs/review/`](../review/README.md) | none |
| Standards kept for review only; the implementer builds, the reviewer polishes | Hides the standards from the implementer on purpose | Inference: the implementer should focus on making it work | Our implementer reached the review criteria only through a pointer | **adapt**: plan and implement also read the review-criteria index when one exists, so the implementer meets the criteria before review; the two indexes stay | [#16020](https://github.com/melodic-software/claude-code-plugins/pull/16020) (standards contract), [#16050](https://github.com/melodic-software/claude-code-plugins/pull/16050) (open, implement) |
| Standards found at fixed file names | The skill expects named files | Inference: a fixed name is easy to find | A consumer arranges its standards its own way | **already have**: the [standards contract](../../plugins/review/reference/standards-contract.md) resolves where criteria live | none |
| Standards and the spec as separate review lenses | Two subagents check different things | Inference: one pass mixes the questions | Same | **already have**: the `quality-gate` spec lens and close-out ([aihero-shipping-course.md](aihero-shipping-course.md), lane D) | none |
| No security pass | His flow reviews quality only | n/a | Security needs its own lens | **already have**: the separate security lane, `/review:security-review` | none |

### Running the review

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The reviewer fixes what it finds and passes up only what it doubts | Merges review and fix in one run | Inference: comments left for a person slow review | A reviewer fixing its own findings loses the independent check | **already have**, kept: the reviewer reports, a different run fixes, and a fresh reviewer checks again | none |
| A finding that repeats is fixed everywhere | Treats one finding as a class | Inference: fixing one site leaves its siblings | Our findings named one site, and the fixer fixed that site | **adapt**: findings name the class when the site is one of several; the fixer's brief fixes every instance of that class | [#16020](https://github.com/melodic-software/claude-code-plugins/pull/16020), [#16019](https://github.com/melodic-software/claude-code-plugins/pull/16019) |
| Review against the spec: missing, unrequested, wrong | Quotes the requirement each finding fails | Inference: agents take shortcuts on requirements | Same | **already have**: [`quality-gate` spec lens](../../plugins/review/skills/quality-gate/context/spec.md) | none |
| A built-in smell list when a project has no standards | Ships the reviewer with a fixed set of design smells | Inference: a reviewer needs a floor | Our twelve smells lived inside the reviewer agent, an opinion the consumer could not change | **adapt**: the list moves to [`design-smells.md`](../../plugins/review/reference/design-smells.md) behind the `smell_baseline` setting (default list, off, or a repository path); `/review:setup` offers the wider catalog; the report names the list it used | [#16020](https://github.com/melodic-software/claude-code-plugins/pull/16020), [#16050](https://github.com/melodic-software/claude-code-plugins/pull/16050) (open, config-cascade row) |
| Judgment calls go to the person; the agent researches before recommending | Separates what needs a person from what the criteria settle | Inference: an agent should not decide taste | Same | **already have**: the owner stops, and findings labeled advisory unless a rule backs them | none |
| File follow-up issues during review | Turns out-of-scope findings into tracked work | Inference: findings are lost otherwise | Same | **already have**: `## Follow-ups` in the body while issue filing is paused (`AGENTS.md`) | none |
| Rewrite the body after fixes | The body tracks the latest commit | Inference: a stale body misleads the reviewer | Our body described the first push | **adapt**: the body always describes the current head; a run that pushes a change that makes a section stale rewrites it in place, the evidence comment likewise; `pr_body_refresh` turns it off; a deterministic check rejects new text holding a line a gate reads. CI address-feedback rounds do the same through the existing publish job; the fix-ci rounds are not covered | [#16019](https://github.com/melodic-software/claude-code-plugins/pull/16019), [#16064](https://github.com/melodic-software/claude-code-plugins/pull/16064) (open, CI) |
| Comments that no longer match the code | Treats stale comments as review findings | Inference: comments go stale and let agents excuse workarounds | Same | **adapt**: `comment_posture` defaults to `necessary` in every mode; `comment_keep_list` lets a repository replace the shipped keep list; this repository's [review criteria](../review/comments.md) require an added comment to be on that list | [#16014](https://github.com/melodic-software/claude-code-plugins/pull/16014) |

### Learning from review

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Never make the same review comment twice | Each human comment becomes a check, a rule or a review criterion | Inference: the system that wrote the code repeats its mistakes | `/corrections:codify` reads merged pull requests' review comments, but not one chosen pull request | **adapt**: a single-PR selector for review comments, open pull requests included | [#16056](https://github.com/melodic-software/claude-code-plugins/pull/16056) (open) |
| Retro reads past session transcripts and proposes environment fixes | Groups findings into categories such as standards, instruction pruning and checks | Inference: agents hit friction no one reports | Same | **already have**: `/session-flow:retro`, compared category by category in [mattpocock-skills.md](mattpocock-skills.md) (row `retro`) | none |
| Retro over one pull request | Takes the pull request's sessions, subagents and review comments as input, in batches | Inference: a pull request's lessons span several sessions | Our retro read one session; comments reached codify only across the last merged pull requests | **adapt**: a `pr` scope on `/session-flow:audit-sessions`, with subagents sized to the transcripts and comments handed to `codify reviews` | [#16015](https://github.com/melodic-software/claude-code-plugins/pull/16015), [#16056](https://github.com/melodic-software/claude-code-plugins/pull/16056) (open) |
| Retro proposes and a person picks | Changes are not applied on their own | Inference: self-applied changes loop and degrade | Same | **adapt**: retro and codify state the rule: a person approves now, and automatic application comes only where an eval set scores the change | [#16013](https://github.com/melodic-software/claude-code-plugins/pull/16013), [#16015](https://github.com/melodic-software/claude-code-plugins/pull/16015) |
| A new rule comes with fixing the code that breaks it | Clears existing violations when the rule lands | Inference: code that shows the opposite teaches agents the opposite | Our codify proposals said nothing about existing violations | **adapt**: a codify proposal states how many violations exist and offers the cleanup, with a ratchet for large counts | [#16013](https://github.com/melodic-software/claude-code-plugins/pull/16013) |
| Mechanical mistakes get a check; a type that rules a mistake out beats a rule | Puts each lesson on the strongest tool that catches it | Inference: prose rules are read inconsistently | Same | **already have**: codify's [enforcement ladder](../../plugins/corrections/skills/codify/reference/enforcement-ladder.md) | none |
| A comment that restates code drifts; a reason goes in a decision record | Moves the why out of comments | Inference: comments age faster than code | Same | **already have**: the `code-tidying` comment skills and the decision-rationale hand-off to `record-decision` | none |
| Leave review comments that state a pattern | Comments about one detail are deleted, pattern comments kept | Inference: only patterns become standards | Codify counts a pattern across distinct pull requests | **no change** | none |

### Found while absorbing

| Item | Disposition | Landed |
|---|---|---|
| The organization's managed `REVIEW.md` said includes are never expanded; current Claude Code docs say they are | **take**: the claim is removed and the file trimmed | [standards#998](https://github.com/melodic-software/standards/pull/998) |
| The drawing-in-the-body note in [mattpocock-skills.md](mattpocock-skills.md) (row `pr`) was left under evaluation | **reject** for the body, reason in the row above | this record |

### Handed elsewhere

- Interface and performance defects as verification evidence, with agents driving the app: the
  workshop on verification.
- Rule sources outside the repository (meetings, ticket comments) and nightly mining of sessions for
  corrections: the lanes workshops.
- A scan of the source authors' skills for names and paths a consumer cannot configure, and one map
  of which skill and action to use when: a cross-repository task.
- Agents logging their own friction during a session: under research.

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. The public skills repository reads MIT on the host and in
[mattpocock-skills.md](mattpocock-skills.md); no text or code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-13
- **Recheck trigger**: the skills repository's license file changes.
