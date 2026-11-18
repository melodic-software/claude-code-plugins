# Upstream source: AI Hero Cohort 005, Workshop 7 "Software Factory Part One" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Software Factory Part One** workshop of Matt Pocock's AI Hero cohort (Cohort 005): nine lessons
on moving the steps from an issue to a merged pull request out of a person's hands, one CI workflow
per step. The workshop sandboxes the agents on hosted runners, sets up their credentials and
triggers, builds an implementer and a separate reviewer, runs a retrospective on their runs, adds
a triage step in front, and chains the steps together. Our counterparts are the
[loop-lane convention](../contracts/loop-lane/README.md), the [glossary](../glossary.md), the intake
lane ([`intake-triage.yml`](../../.github/workflows/intake-triage.yml)), the implement lane
([`work-resolve-issue.yml`](../../.github/workflows/work-resolve-issue.yml)), the review lanes,
[`/session-flow:retro`](../../plugins/session-flow/skills/retro/SKILL.md),
[`/autonomy:setup`](../../plugins/autonomy/skills/setup/SKILL.md), and the lane rules in
[ADR 0049](../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
[ADR 0058](../adr/0058-mint-lane-app-tokens-through-an-oidc-broker.md) and
[ADR 0085](../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md).
Rows hold our decisions and our own descriptions of each idea, under the upstream-drift
convention's [What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe).
The course is paid and account-gated, so no lesson text is recorded or linked here; the library
its workflows run on is public in [mattpocock/sandcastle](https://github.com/mattpocock/sandcastle),
whose record is [mattpocock-sandcastle.md](mattpocock-sandcastle.md). Earlier course units have
their own records: [aihero-course.md](aihero-course.md),
[aihero-shipping-course.md](aihero-shipping-course.md),
[aihero-domain-language.md](aihero-domain-language.md), [aihero-wayfinder.md](aihero-wayfinder.md),
[aihero-review.md](aihero-review.md), [aihero-codebase-design.md](aihero-codebase-design.md) and
[aihero-feedback-loops.md](aihero-feedback-loops.md).

- **Pointer**: when a row needs the upstream mechanism, read the library live at the pin its record
  audits:
  [mattpocock/sandcastle@0ed674e](https://github.com/mattpocock/sandcastle/tree/0ed674e5195b200d34bc4128eec33409f2952dcf).
- **As of**: 2026-11-17
- **Recheck trigger**: the next re-audit of [mattpocock-sandcastle.md](mattpocock-sandcastle.md),
  due at its v1 release. Course page updates are not observable events; the library's changes are
  the proxy, as the skills repository is in [aihero-shipping-course.md](aihero-shipping-course.md).

**Landed** names the merged pull request that carries the row; `pending` marks one not yet merged.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject` or `no change`, with the reason. The
upstream-problem cells are **Inference** throughout: the lesson pages that state them are paid and
not linked.

### Goal and vocabulary

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Brakes before accelerators | Sorts each mechanism into one that slows work to keep quality up and one that speeds work or starts it on a schedule | Inference: speeding agents up with nothing to slow them produces poor code at volume | We had no names for the two kinds, and the lane table did not say which each lane is | **adapt**: the glossary defines brake and accelerator, and the loop-lane lane table carries a column for them | [#16695](https://github.com/melodic-software/claude-code-plugins/pull/16695) |
| Trust sets how many agents run at once | Widens parallelism as output earns trust, bounded by token budget | Inference: more agents must not mean more prompts to write | Same | **already have**: the loop-lane convention keys its trust ladder to merge authority; the two limits get numbers with the next unit | none |
| Five steps from issue to merge, each with a person today | Names explore, approve, implement, review and merge as the steps to automate one at a time | Inference: a person at every step caps throughput | Our lanes cover each step under other names, and "approve" hid two separate jobs | **adapt**: the glossary maps the steps to our lanes, defines stage, lane and admission, and splits approve into a triage verdict plus admission | [#16695](https://github.com/melodic-software/claude-code-plugins/pull/16695) |
| "Software factory" as the name for the whole chain | Uses one term for every automated step together | Inference: the set of steps needs a name | Our course record had rejected the term | **adapt**: the glossary adopts it for every lane together, intake through post-merge; one local loop stays a loop lane | [#16695](https://github.com/melodic-software/claude-code-plugins/pull/16695) |
| Merge some pull requests with no person: reversible, small, no migration | Proposes three criteria for an unattended merge | Inference: the merge is the last step a person holds | Our merge lane already merges unattended on the verifier verdict, with no path or size cap by owner decision ([`pr-pipeline.yaml`](../conventions/pr-pipeline.yaml)) | **no change**: no new hold; adding his criteria would change what agents may merge unattended against that decision | none |

### Where agents run

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Local for attended work, one remote machine per unattended agent | Moves unattended runs off the workstation, one disposable machine each | Inference: many agents on one machine contend for it and endanger it | Same | **already have**: a fresh hosted runner per job (ADR 0049), with model and write steps in separate jobs (ADR 0085) | none |
| Hosted sandbox vendors | Offers managed sandboxes from several vendors | Inference: a firmer boundary than a CI runner | A vendor adds a billing account and a third party holding lane tokens | **reject**: stands as recorded in [mattpocock-sandcastle.md](mattpocock-sandcastle.md); reconsider when hardening returns | none |
| The agent runs on the runner with no sandbox | Treats the runner VM as the only boundary | Inference: the runner is disposable | Same choice; GitHub's egress firewall for hosted runners is now in preview | **already have**: ADR 0049 under its five conditions. Turning on the egress firewall tightens a control and waits for hardening | none |
| Help a user set up a factory of their own | n/a (raised while absorbing) | n/a | `/autonomy:setup` had no slots for runner, git host, tracker or observability, and no way to price them | **adapt**: setup slots for those four, with a live price-research step and no prices in the skill body | [#16702](https://github.com/melodic-software/claude-code-plugins/pull/16702) |
| Isolation of local runs on WSL | n/a (raised while absorbing) | n/a | The [isolation ladder](../../plugins/autonomy/reference/guardrails/isolation-ladder.md) said nothing about WSL | **adapt**: default WSL is no isolation level, WSL2 with the sandbox is `L1`, and the local-lane gap is recorded | [#16702](https://github.com/melodic-software/claude-code-plugins/pull/16702) |

### Credentials and triggers

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| One personal access token for every forge write | Lets a token that can start workflows chain the steps | Inference: events the built-in token causes start no workflow | A person-bound token makes that person the actor for every agent write | **reject**: lane writes run as one GitHub App ([loop-lane convention](../contracts/loop-lane/README.md)), with one-hour tokens minted through an OIDC broker (ADR 0058) | none |
| A label per step starts each workflow | Uses a label as both trigger and status | Inference: labels are the cheapest state GitHub offers | Same | **already have**: implement starts from a Work status field write counted only from a listed human or the lanes App ([`work-resolve-issue.yml`](../../.github/workflows/work-resolve-issue.yml)); prefixed labels: no change | none |
| The model credential as a job environment variable | Gives the remote agent its provider key | Inference: a remote agent has no login | Same | **already have**: [ADR 0062](../adr/0062-allow-api-keys-from-the-operator-s-own-linked-console-orgs.md) orders an API key, then the role's subscription token, then the fallback | none |
| Only collaborators may open issues and pull requests | Narrows who can start an agent | Inference: on a public repository anyone can file text an agent reads | Same | **already have**: on for the organization; the trusted-actor gate in ADR 0049 bounds what reaches a lane | none |
| Test a workflow change by pushing it to the default branch | Relies on issue and label events running only from the default branch | Inference: those events cannot run a branch's copy | Pushing to the default branch is on our stop list ([AGENTS.md](../../AGENTS.md)) | **reject** the push; **adapt**: the pipeline convention documents `gh workflow run <workflow> --ref <branch>` and what such a run does not exercise | [#16709](https://github.com/melodic-software/claude-code-plugins/pull/16709) |

### Choosing the agent harness

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Sandcastle as the runner for every workflow | One library call picks harness, sandbox and prompt file | Inference: each harness needs its own glue | We run one harness, and a dependency we do not need adds a release stream to track | **reject** as a dependency: our lanes stay on our own launcher; ideas from it are judged row by row in [mattpocock-sandcastle.md](mattpocock-sandcastle.md) | none |
| The list of harnesses Sandcastle supports | Names the agent CLIs the library can drive | Inference: a reader chooses a harness from the list | The lesson's list omits Cursor | **no change**: correction only. Cursor is a provider at the audited pin ([`src/AgentProvider.ts`](https://github.com/mattpocock/sandcastle/blob/0ed674e5195b200d34bc4128eec33409f2952dcf/src/AgentProvider.ts)); the dependency stays rejected | none |
| "Claude Code" as the provider's name | Names the harness, not the model vendor | Inference: providers are named for what they launch | Questioned whether "Claude" alone fits better | **no change**: "Claude Code" is correct for the harness. His helper keeps a Claude name whatever harness it returns, which we would not copy | none |
| Swapping the harness or moving to an API key | A four-step swap of env names, harness, install step and keys | Inference: users bill differently or prefer another CLI | The secret name repeats across his workflows, so a swap edits every file | **reject** the harness swap: our skills run on Claude Code only. The key-over-token precedence is already used on purpose (ADR 0062) | none |
| Permission checks skipped for every agent | Runs each harness with its bypass flag | Inference: an unattended run cannot answer prompts | Lanes never use bypass mode ([AGENTS.md](../../AGENTS.md)) | **reject**: CI lanes run `dontAsk` with fixed allowlists and no write token in the model job | none |
| Auto permission mode for CI agents | Lets a classifier approve tool calls instead of a fixed list | Inference: a fixed list is brittle | Our read lanes could not run in auto mode | **no change**: Claude Code 2.1.326 forces default mode when `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` is set, by a local probe; a [CI run at 2.1.304](https://github.com/melodic-software/claude-code-plugins/actions/runs/39723040443/job/119640730523) prints the same message; auto mode needs the scrub off, which keeps the Claude credential out of commands whose output reaches public logs. The scrub stays on with fixed allow-lists, by owner decision ([ADR 0049](../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md)) | none |

### The implement lane

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The model commits; scripted steps push and open the pull request | Keeps the push token out of the agent's step | Inference: the agent should not hold write power | Same, but his agent and push steps share one runner | **already have**, stronger: our model job holds no write token, leaves a patch, and a script with no model applies it in another job ([ADR 0053](../adr/0053-run-each-pipeline-activity-as-a-model-job-and-a-scripted-report-job.md)) | none |
| Protected paths held by prompt lines | Tells the agent not to touch workflows or hook files | Inference: an agent could rewrite its own checks | A prompt line is not enforcement | **reject** prompt-only guards: [`protected-paths.mjs`](../../.github/scripts/apply-patch/protected-paths.mjs) refuses those paths and the lane token cannot write workflows | none |
| Every agent pull request opens as a draft | Marks agent output as unread | Inference: the person left the build but not the merge | A draft here skips the test and review lanes | **reject**: this repository opens ready pull requests ([`source-control.yaml`](../conventions/source-control.yaml)); the review lanes and verifier carry the unread meaning | none |
| A fresh branch per run | Keeps retries from colliding | Inference: a retry must not reuse a branch | Same | **already have**: the implement lane's branch names carry the run id and attempt | none |
| The run log shows the agent's tool calls | Lets a person watch the agent work as in a local session | Inference: a person trusts what they can watch | Our lane logs showed none of the agent's activity | **adapt**: the shared launcher streams the agent's text and tool calls with truncated arguments, never tool results, behind the credential check, with a per-caller off switch; picked up here by the repin | [ci-workflows#1120](https://github.com/melodic-software/ci-workflows/pull/1120), [#16734](https://github.com/melodic-software/claude-code-plugins/pull/16734) |
| Keep each run's full agent transcript | n/a (raised while absorbing) | n/a | The implement lane's legs were not carried to the sealed transcript upload | **adapt**: the sealer copy is verified before use, the puller reaches the reuse-summary leg, and a clean job uploads the read runner's leg transcript | [#16705](https://github.com/melodic-software/claude-code-plugins/pull/16705), [#16698](https://github.com/melodic-software/claude-code-plugins/pull/16698), [#16805](https://github.com/melodic-software/claude-code-plugins/pull/16805), [#16894](https://github.com/melodic-software/claude-code-plugins/pull/16894) |
| The lane reports its outcome and claim | Comments on the issue with the run and the pull request | Inference: a person should see where the work went | The outcome script ignored the configured required body sections, and the claim comment had no run link | **adapt**: `report-outcome.mjs` reads `pr_body_required_sections`; the claim comment carries a run link | [#16709](https://github.com/melodic-software/claude-code-plugins/pull/16709) |

### The review lane

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A reviewer with no memory of the build | Gives the reviewer the diff, the standards and the issue only | Inference: a reviewer sharing the builder's context repeats its shortcuts | Same | **already have**: the implementer never reviews its own output, and review runs in a fresh context | none |
| The reviewer fixes what it finds | Commits fixes during review, leaving decisions to a person | Inference: the reviewer holds the context to fix at once | Mixing finding and fixing costs the reviewer its independence | **reject**: a reviewer reports, a different run fixes, a fresh reviewer re-checks (owner decision) | none |
| Findings as structured output | Returns unfixed findings as typed objects for inline comments | Inference: inline comments need a path and line | Same | **already have**: our review lanes return schema-typed output that a model-free job checks and publishes | none |
| Rules the review wanted and could not find | Lists rules no standard covers, for a later retrospective | Inference: gaps in the standards show up during review | No path carried such gaps to `/corrections:codify` | **adapt**: lanes write an uncovered-rules block in the summary, not a finding, and codify reads it; proof and approval unchanged | [#16771](https://github.com/melodic-software/claude-code-plugins/pull/16771) |
| Catch an agent loosening a check | The reviewer spotted an exemption the implementer added | Inference: an agent may weaken a check to pass it | The CI code-review lane did not load our loosened-check criterion | **adapt**: the criterion loads in the CI lane; the bounded fallback keeps a warning; advisory and manifest lines fold into one collapsed block | [#16709](https://github.com/melodic-software/claude-code-plugins/pull/16709) |
| A person answers on the pull request | n/a (raised while absorbing) | n/a | The fix lane answered review-thread replies only, so a trusted person's top-level comment went unanswered | **adapt**: the lane answers a trusted person's top-level comment that has a line starting `PR-fix lane:`, answer-only, within the same sweep and round cap; leftover and edited comments resend within the cap | [#16941](https://github.com/melodic-software/claude-code-plugins/pull/16941) |
| A fixed summary block atop each workflow | n/a (raised while absorbing) | n/a | Our workflow headers have no fixed order | **no change**: each candidate line restated the trigger block or the lane rules, and [ADR 0110](../adr/0110-remove-existing-comments-without-per-deletion-approval-and-block-new-ones.md) blocks such comments | none |

### Retrospectives on runs

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Retro on chosen CI runs | Points a retrospective at the implement and review runs of one change | Inference: the run holds the evidence of where the agent struggled | `/session-flow:retro` read only local sessions | **adapt**: a `ci-runs` target reads the sealed lane transcripts through a provider-neutral data contract | [#16712](https://github.com/melodic-software/claude-code-plugins/pull/16712) |
| A pull request's whole history in one audit | n/a (raised while absorbing) | n/a | [`/session-flow:audit-sessions`](../../plugins/session-flow/skills/audit-sessions/SKILL.md) `pr` read local sessions only | **adapt**: `pr` also reads the CI lane legs on the head branch when a transcript sink is set | [#16736](https://github.com/melodic-software/claude-code-plugins/pull/16736) |
| Decisions live in decision records, not comments | Deletes a comment recording a design choice and writes the record | Inference: decision comments drift and mislead agents | ADR 0108 asked approval for each deletion and kept old comments | **adapt**: [ADR 0110](../adr/0110-remove-existing-comments-without-per-deletion-approval-and-block-new-ones.md) removes existing comments without per-deletion approval and blocks new ones; a review criterion flags a deleted decision comment | [#16699](https://github.com/melodic-software/claude-code-plugins/pull/16699), [standards#1042](https://github.com/melodic-software/standards/pull/1042) |
| Remove existing comments across repositories | n/a (follows the row above) | n/a | Old comments stay until a sweep removes them | **adapt**, pending: one `/code-tidying:remove-comments aggressive` pull request per repository, each after its review criterion is on the default branch | pending |
| Batch feedback at commit time, not per edit | Keeps checks out of per-edit hooks | Inference: per-edit checks are noisy | Same; no organization standard said so | **adapt**: a check-placement standard in `melodic-software/standards`, pointing at our check-placement rules ([ADR 0072](../adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md)) | [standards#1046](https://github.com/melodic-software/standards/pull/1046) |
| Cache a tool the agent installs mid-run | Pins the install and caches it keyed by version and OS | Inference: each run rediscovers the same install | The Actions cache can let whoever writes an entry plant files a privileged job restores ([`setup-runner-isolation`](../../.github/actions/setup-runner-isolation/action.yml)) | **reject** the cache; a tool the agent needs is installed at a pinned version before it starts | none |
| A check-forced split counts as in scope | Treats a refactor a check forces as part of any ticket | Inference: a check and the reviewer disagreed | The CI issue lane adds no work beyond the issue's done-when ([`ci-mode.md`](../../plugins/work-items/skills/work/reference/ci-mode.md)) | **no change**: the done-when rule stays | none |
| Agents keep relearning how to sign in to the app | Gives the agent the recipe and seeded users | Inference: each run rediscovers the same steps | A ticket that adds a feature did not update the app's control skill | **adapt**: [`/app-control:map`](../../plugins/app-control/skills/map/SKILL.md) `refresh` on a ticket branch maps the features the diff adds | [#16768](https://github.com/melodic-software/claude-code-plugins/pull/16768) |

### Triage before building

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A triage step in front of the build | Checks each report's claims against the code before anyone builds | Inference: outside reports are vague, wrong or duplicated | Same | **already have**: the intake lane with a read-only model and a model-free apply, and [`/work-items:triage`](../../plugins/work-items/skills/triage/SKILL.md) | none |
| What a triage comment carries | Evidence, blast radius, reversibility and open questions for a person to read | Inference: the person deciding needs the facts in one place | Our intake prompt had three copies, a misspelled ready status, and a comment shape apart from the CI rubric | **adapt**: one prompt copy, the spelling fixed, the comment retargeted to the CI rubric, first-pass verdict eval cases and prompt examples kept apart from them | [#16701](https://github.com/melodic-software/claude-code-plugins/pull/16701) |
| Batch triage over every labeled issue | One run reads many issues to find duplicates and shared causes | Inference: duplicates show only when issues are read together | Same | **no change**: per-issue triage stays; batch triage runs by hand as a read-only one-off (owner decision, recorded in [mattpocock-sandcastle.md](mattpocock-sandcastle.md)) | none |
| Close a duplicate onto its survivor | Sets the duplicate reason and links the pair | Inference: GitHub should show the relation | We had not read what our adapter's close does | **already have**: the GitHub adapter closes with `--duplicate-of`, which sets the reason and the native relation ([adapter README](../../plugins/work-items/tools/work-item-tracker/adapters/github/README.md)) | none |
| Live data sources for exploration | n/a (raised while absorbing) | n/a | [`/discovery:explore`](../../plugins/discovery/skills/explore/SKILL.md) covers the codebase only, and no stage said who reads a live system's current state | **adapt**, by owner decision: no widening of explore and no new skill; the stage needing a live fact reads it directly and records it as a Brief assumption | [#16918](https://github.com/melodic-software/claude-code-plugins/pull/16918) |

### Chaining the steps

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Triage's verdict starts the build, the build starts review | Branches in code on one value from a closed set | Inference: each hand-off held a person | Same | **already have**: a model-free verdict writer, then [`admit.mjs`](../../.github/scripts/intake-triage/admit.mjs) admits under closed rules as the lanes App, and a ready pull request runs both review lanes | none |
| An outside channel files issues straight into the chain | An in-app form files an issue already labeled for triage | Inference: feedback should reach a pull request with no one in between | Text from someone not listed would reach an unattended build | **no change**: outside text stays human-gated; an issue the App files does not admit itself | none |
| A token that can do every write | Uses one personal token because the built-in token's labels start nothing | Inference: chaining needs another actor | An App installation token and dispatch events also start workflows | **reject**: see the personal-token row under "Credentials and triggers" | none |

### Found while absorbing

| Item | Disposition | Landed |
|---|---|---|
| The GitHub settings repository's docs were out of date on issue types for user repositories, the Work status field, the four hold states and a superseded work-class axis | **take**: corrected | [github-iac#914](https://github.com/melodic-software/github-iac/pull/914) |
| A shared resolve-main-tip action for the 98 inline copies | **no change**: each copy runs before checkout, so a local action cannot load, and [`callers.test.mjs`](../../.github/actions/resolve-config/callers.test.mjs) already holds every copy to one script | none |

### Deferred

These change the shape of the automation, so they wait for one pass after the next unit:

- a typed triage verdict through structured output;
- credential legs as reusable workflows;
- the model resolver and kill switch moved into the reusable review workflow;
- one gate job that computes agent-ready once;
- fleet review on the shared review workflow;
- polling schedules replaced by events.

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. Sandcastle's license is recorded in [mattpocock-sandcastle.md](mattpocock-sandcastle.md);
no text or code from it is copied either.

- **Pointer**: when a license question arises, read the library's
  [LICENSE](https://github.com/mattpocock/sandcastle/blob/0ed674e5195b200d34bc4128eec33409f2952dcf/LICENSE).
- **As of**: 2026-11-17
- **Recheck trigger**: the library's license file changes.
