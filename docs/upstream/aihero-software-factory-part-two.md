# Upstream source: AI Hero Cohort 005, Workshop 8 "Software Factory Part Two" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Software Factory Part Two** workshop of Matt Pocock's AI Hero cohort (Cohort 005): ten lessons on
choosing the services a software factory runs on and designing the tasks it performs, from scheduled
producers to a long unattended build of a whole spec. Our counterparts are the
[loop-lane convention](../contracts/loop-lane/README.md), the intake lane
([`intake-triage.yml`](../../.github/workflows/intake-triage.yml)), the implement lane
([`work-resolve-issue.yml`](../../.github/workflows/work-resolve-issue.yml)),
[`/improvement:find`](../../plugins/improvement/skills/find/SKILL.md),
[`/planning:interview`](../../plugins/planning/skills/interview/SKILL.md), and the lane rules in
[ADR 0049](../adr/0049-run-ci-lanes-on-github-hosted-runners-under-trigger-and-token-hardening.md),
[ADR 0062](../adr/0062-allow-api-keys-from-the-operator-s-own-linked-console-orgs.md),
[ADR 0085](../adr/0085-run-org-lanes-from-ci-workflows-under-one-lanes-app-with-central-grants.md),
[ADR 0096](../adr/0096-choose-the-pull-request-branch-update-method-from-shared-criteria.md) and
[ADR 0111](../adr/0111-admit-own-agent-filings-sized-small-or-medium-under-a-per-producer-cap.md).
Rows hold our decisions and our own descriptions of each idea, under the upstream-drift
convention's [What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe).
The course is paid and account-gated, so no lesson text is recorded or linked here; the author's
public skill on the topic is the `software-factory` row of
[mattpocock-skills.md](mattpocock-skills.md). The workshop before this one has its own record,
[aihero-software-factory-part-one.md](aihero-software-factory-part-one.md).

- **Pointer**: when a row needs the upstream mechanism, read the skill live at the pin its record
  audits:
  [mattpocock/skills@4ae2317](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/in-progress/software-factory).
- **As of**: 2026-11-18
- **Recheck trigger**: a row marked `pending` lands,
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) closes, or the
  `software-factory` row of [mattpocock-skills.md](mattpocock-skills.md) is re-audited. Course page
  updates are not observable events.

**Landed** names the merged pull request that carries the row. `pending` marks work not yet merged,
with its pull request where one is open. `none` means no change to this repository.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject`, `deferred` (decided to wait, listed under
[Deferred](#deferred)) or `no change` (nothing to decide, or decided to leave this repository as it is), with the reason; `deferred` and
`no change` are additions to the usual four. A row with two parts leads with the disposition of its
main idea. The upstream-problem cells are **Inference** throughout: the lesson pages that state them
are paid and not linked.

### Lesson 1: What Infrastructure Do I Need?

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Run the factory on separate products instead of GitHub Actions | Moves the runner, orchestrator and observability to bought services | Inference: Actions bills private repositories, has no factory-wide metrics and cannot hear tracker events | Our public repositories do not pay for Actions; only the missing metrics apply | **reject**: public repositories stay on Actions under ADR 0049 and ADR 0085; a private-repository runner is [deferred](#deferred) | none |
| Five infrastructure slots | Splits a factory into the tracker, the git host, the runner, the orchestrator and observability, each chosen separately | Inference: a builder needs a list of parts before buying any | We own every part but had no single map of them | **adapt**, names only: the slot names map onto our parts in our private course notes; our own names stay | none |
| The tracker is where people talk to agents | Sets the minimum a tracker must offer an agent | Inference: agents need a shared queue that people already read | Same | **already have**: the [`work-items`](../../plugins/work-items/skills/setup/SKILL.md) tracker providers, with the trusted-actor gate of ADR 0049 on what reaches a lane | none |
| The git host holds branches, reviews and merges | Lists self-hosted alternatives for code that cannot leave a network | Inference: some teams cannot use a public host | GitHub is fixed for us | **already have**: GitHub, plus a `gitea` tracker provider | none |
| A runner is a disposable sandbox | Keeps no state on the machine, so every result returns to the tracker or git host | Inference: a throwaway machine limits what a bad run can damage | Same | **adapt**, names only: a fresh runner per job is already ADR 0049; our course notes map his run to one GitHub job | none |
| The orchestrator starts runners on events and schedules | Compares CI, an own server and a hosted agent platform for that job | Inference: something must turn events into runs and handle their errors | Same | **already have**: Actions triggers lanes, with the org kill switch of ADR 0049. A hosted agent platform is rejected because public repositories stay on Actions, which already does this job at no charge; a private-repository runner is [deferred](#deferred) for its cost. Account rotation is not the reason: ADR 0062 already funds Managed Agents from linked Console orgs | none |
| Factory-wide observability | Collects cost and success rates across all runs | Inference: per-run logs cannot show how the whole factory is doing | Same: nothing joined our remote runs into one view | **adapt**: the [transcript sink](../../scripts/lane-transcripts/README.md) rows gain cost, cache tokens, failure class and trace id; no paid store; the CI artifact stays a 7-day transfer buffer. The launcher can join a leg's traces to its run and keep them through a sealed receiver that is off by default. This repository's lanes still pin the release before that change and none turns the receiver on, so no lane produces telemetry yet; the re-pin and a first lane's opt-in are tracked in [#17261](https://github.com/melodic-software/claude-code-plugins/issues/17261) | [#17046](https://github.com/melodic-software/claude-code-plugins/pull/17046), [#17075](https://github.com/melodic-software/claude-code-plugins/pull/17075), [provisioning#1052](https://github.com/melodic-software/provisioning/pull/1052), [ci-workflows#1136](https://github.com/melodic-software/ci-workflows/pull/1136) |
| Decide the slots in order | Fixes tracker and git host first, then prices the rest against real usage | Inference: the early choices constrain the later ones | Same | **already have**: numbered interview rounds, and skill bodies that point at live vendor pages | none |

### Lesson 2: Choosing Your Infrastructure

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A reference skill with one dated survey per slot | Holds shared vocabulary and tells the agent to research current details | Inference: vendor facts age quickly | Same | **already have**: [skill bodies state current rules](../../.claude/rules/skill-bodies-state-current-rules.md) by pointing at the source; `/discovery:research` reads it live | none |
| Design the services in an interview | Puts each question singly, settles services before tasks, and uses real pricing | Inference: an agent should not choose infrastructure alone | Same | **already have**: `/planning:interview` | none |
| Runner types differ by who owns the loop and the machine | Allows a different runner per task | Inference: cheap review and heavy implementation have different needs | One runner class serves every lane today | **already have**: hosted CI under ADR 0049; a runner per task is [deferred](#deferred) | none |
| Ask what a run can reach | Checks network, outbound allowlist and how secrets arrive | Inference: a run's reach sets the cost of a bad run | Same | **already have**: the [isolation ladder](../../plugins/autonomy/reference/guardrails/isolation-ladder.md) and the conditions in ADR 0049 | none |
| Act through a GitHub App from day one | Replaces a personal token with one App and a short permission list | Inference: the built-in token starts no workflows, and a personal token names a person | Same | **already have**, stronger: one lanes App, and no model job carries a token that can write (ADR 0085) | none |
| Start slow | Adds one throttled trigger at a time behind checks and review | Inference: each trigger speeds the factory up before its brakes are proven | Same | **already have**: brakes before accelerators, in [part one's record](aihero-software-factory-part-one.md) | none |
| A run never waits for a person, and each task answers fixed design questions | Ends the run, lets a later change start the next one, and checks each task against a question list | Inference: a design with an unanswered question fails in production | Lanes already end and restart on events, but no checklist existed for a new lane | **adapt**: the loop-lane contract's [Designing a new pipeline](../contracts/loop-lane/README.md#9-designing-a-new-pipeline) section asks seven questions | [#17032](https://github.com/melodic-software/claude-code-plugins/pull/17032) |
| Run the design session in auto mode | Has the agent add a label and post the finished design as an issue | Inference: a design session needs few interruptions | Same | **already have**: filing an issue needs no confirmation here ([AGENTS.md](../../AGENTS.md)) | none |
| What an orchestrator must get right | Lists triggers, duplicate webhooks, hung runs, caps, visible state and surviving a deploy | Inference: an own server has to supply what a CI product gives for free | Actions supplies these for us | **already have**: the list would be the acceptance test for any replacement | none |
| Limit how much power one vendor holds | Warns against one product both running the agent and keeping the credential that writes to the repository | Inference: one breach would expose both | Same | **already have**: job separation and the token broker keep them apart (ADR 0085) | none |
| Inngest as orchestrator, with a worker holding the secrets | Keeps run state in a service and long-lived secrets on a small worker host | Inference: durable waits and retries cost little code when bought | A billed service and a new host holding every secret, with no measured need | **reject**: stay on Actions | none |
| The runner pushes commits with a short-lived token | Accepts a write credential inside the run, backed by a ruleset and review | Inference: fewer moving parts survive a deploy | A write token beside untrusted text is what ADR 0085 rules out | **reject**: model jobs leave a patch and a scripted job writes it | none |
| Daytona as the runner vendor | Picks a sandbox vendor and starts each service on a free tier | Inference: compute is small beside model spend | A billing account and a third party holding lane tokens | **reject**: stands as recorded in [mattpocock-sandcastle.md](mattpocock-sandcastle.md) | none |
| The orchestrator owns each run's deadline | Waits with a timeout, then deletes the sandbox | Inference: a looping agent may never trip an inactivity stop | Same | **already have**: the launcher sets one timeout outside the agent | none |
| A per-run token for reporting completion | Stops an agent faking another run's completion | Inference: the agent can read the runner's event key | No model step holds a write or event credential | **already have**: ADR 0085 | none |
| Linear as the human interface | Delegates issues to an agent that acts as its own app identity | Inference: labels are a poor way to hand work to an agent | GitHub is our tracker | **reject**: GitHub stays the tracker | none |
| Keep transcripts in an observability platform | Sends telemetry to a bought store because runners delete their files | Inference: a retrospective needs the transcript after the runner is gone | Same need, without sending transcripts to a vendor | **adapt**: the sealed artifact and local sink carry it, with no paid store | [#17046](https://github.com/melodic-software/claude-code-plugins/pull/17046) |
| A feedback button files into the triage inbox | Lets a developer file with a personal key, starting no run | Inference: feedback should reach the tracker without a factory token on laptops | A new issue starts no run here | **already have** the gate; the button itself is recorded and not built | none |
| A subscription token first, then a capped API key | Moves to a spending-limited key at the first automated trigger | Inference: a spend limit acts as a brake | A paid key departs from our credential order | **reject**: keep [ADR 0062](../adr/0062-allow-api-keys-from-the-operator-s-own-linked-console-orgs.md) | none |
| Factory code in its own repository | Serves many repositories from one factory, with prompts shipped by its deploy | Inference: a company wants one factory across repositories | Same | **already have**: lanes run as `ci-workflows` reusables (ADR 0085) | none |
| Migrate task by task | Moves a task, runs both versions, deletes the old one, and revokes the personal token last | Inference: a staged move can be undone | Same | **already have**: ADR 0085 moves lanes one at a time | none |

### Lesson 3: Whiteboard Your Own Tasks

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Runner, run and task as working terms | Defines the machine, one execution and the work performed | Inference: a design needs shared words | We say lane and activity | **adapt**, names only: mapped in our private course notes; our names stay | none |
| Design on a whiteboard | Practises system design away from the agent, from a template | Inference: drawing exposes the shape before code exists | Same | **already have**: [`/visualization:visualize`](../../plugins/visualization/skills/visualize/SKILL.md) and the diagram tools it targets | none |
| Tag each step with the lane where it runs | Places a step where it happens, not where it was decided | Inference: a drawing should show who acts | No convention for drawing a new lane | **adapt**: the seventh design question draws one lane per place a step runs, with the token broker added | [#17032](https://github.com/melodic-software/claude-code-plugins/pull/17032) |
| A worked explore task | Groups tickets in one run and either comments or starts an implement run | Inference: a concrete example teaches the notation | Batch exploration stays a hand-run one-off | **already have**: per-issue intake and rule-based admission | none |
| A human lane on the board | Draws the person as a place a step happens | Inference: the handoff to a person is easy to leave out | Same | **adapt**: the design questions ask how a person does what the agent does, and the drawing shows that way in | [#17032](https://github.com/melodic-software/claude-code-plugins/pull/17032) |

### Lesson 4: Improve Codebase Architecture

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A daily producer of design improvements | Runs an architecture scan on a schedule and files what it finds | Inference: improvement work stops when nobody asks for it | No scheduled design filer exists | **deferred**: waits for counts from the new source label | none |
| List what speeds a loop up and slows it down | Treats each loop as bounded by design | Inference: an unbounded producer outruns its reviewers | Same | **already have**: brakes before accelerators | none |
| A finished run files a ticket | Replaces an interactive report with a tracker item | Inference: an unattended run has nobody to read its report | [`/architecture:improve`](../../plugins/architecture/skills/improve/SKILL.md) ends in an interactive pick | **adapt**: an unattended deepening scan writes a candidate file and `/improvement:find` files only its verified `Strong` candidates; the caps and thresholds are settings, and no schedule runs the scan yet | [#17091](https://github.com/melodic-software/claude-code-plugins/pull/17091) |
| A person's label starts the build | Reviews the filed ticket, then labels it | Inference: a person should approve work before it is built | Same | **already have**: admission under closed rules | none |
| A source label on each filing | Names the flow that filed a ticket so its runs can find their own | Inference: a loop needs to count its own output | `/improvement:find` filings carried no such label | **adapt**: every filing carries one source label, `source: architecture-improve` for an architecture candidate and `source: improvement-find` for the rest | [#16995](https://github.com/melodic-software/claude-code-plugins/pull/16995), [#17091](https://github.com/melodic-software/claude-code-plugins/pull/17091) |
| Stop when too many filings are open | Pauses the producer when reviewers fall behind | Inference: a queue limit makes review pace set production pace | The filing cap was soft and per run | **adapt**: a hard stop at 5 open filings per source label, as the `find_open_item_cap` setting | [#16995](https://github.com/melodic-software/claude-code-plugins/pull/16995), [#17091](https://github.com/melodic-software/claude-code-plugins/pull/17091) |
| File every candidate | Keeps each candidate as a ticket so nothing is lost | Inference: unfiled findings disappear | Filing everything defeats the cap | **reject**: each run's report and candidate file keep the rest | none |
| A variant with no person before the build | Lets the producer judge its own candidates ready and build them | Inference: a person between proposal and build slows the loop | Own-agent filings waited for a person to file them again | **adapt**: own-agent filings sized small or medium admit themselves under a per-producer cap of 5; large ones wait for a person, and outside text never counts ([ADR 0111](../adr/0111-admit-own-agent-filings-sized-small-or-medium-under-a-per-producer-cap.md)). The merge gate trusts a filing that meets the same rule, so its pull request can merge with no person; a filing that stops meeting the rule goes to a person | [#16999](https://github.com/melodic-software/claude-code-plugins/pull/16999), [#17093](https://github.com/melodic-software/claude-code-plugins/pull/17093) |

### Lesson 5: The Ratchet

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Rules checked only on staged files | Shows that old violations surface only where an agent happens to edit | Inference: a repository-wide fix is one large, risky change | CI already checks the whole tree | **already have**: CI is the hard stop | none |
| A daily run that fixes one violation | Opens one small fix per run so the codebase tightens over time | Inference: a backlog of violations never shrinks without a steady worker | The main branch is mostly clean, so a fixing lane has little to do | **adapt**: no lint-fix pipeline; a [linter bump carries its own whole-tree fix](../review/linters.md), and [`/toolchain:ratchet`](../../plugins/toolchain/skills/ratchet/SKILL.md) stays our name for the count ceiling | [#17044](https://github.com/melodic-software/claude-code-plugins/pull/17044) |
| Design checks for the fixing run | Avoids two fixes for one failure and stops above an open limit | Inference: parallel fixers collide | Same | **already have**: [tidy upkeep](../../.github/workflows/maintenance-tidy-code-upkeep.yml) selects areas under an open cap | none |
| A merge starts the next run | Lets merge speed set the pace | Inference: the factory should run as fast as work is accepted | Merges here are already unattended, so the loop would close with no person | **deferred**: a strong accelerator that adapts the pace to how fast the developer wants to move that day, so it stays open until the map of factory tasks in [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) settles its brakes | none |
| Two lint grades, with graduation | Moves a rule from a full set to a strict set once it reaches zero | Inference: a rule needs a path from advisory to enforced | A baseline does this with one rule set | **reject**: `/toolchain:ratchet` holds one rule set at error with a baseline | none |
| Automatic review on ratchet pull requests | Adds a review step to the merge | Inference: small fixes should not wait for a person | Same | **already have**: the verifier verdict and both AI review lanes | none |
| Failure text written for an agent | Words a check's failure as instructions | Inference: the agent reads the failure first | No rule sets how failure text is worded | **no change**: no wording rule is adopted. [ADR 0072](../adr/0072-place-each-check-by-coverage-cost-and-model-facing-output.md) decides where checks run and what output reaches the model, not how failure text reads; its only related rule is that an agent commit with a missing tool fails with the install command | none |

### Lesson 6: The Morning Rebase

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Update every open pull request nightly | Brings each branch up to date before the working day | Inference: stale branches conflict when someone returns to them | Each update costs a CI run | **reject**: each push to main [dispatches an update](../../.github/workflows/pr-unblock-dispatch.yml) only for conflicting pull requests | none |
| A script first, an agent only on conflict | Spends no tokens when a scripted update works | Inference: most updates need no judgment | Same | **already have**: ADR 0096, and the behind-only update pins the expected head | none |
| A force push to finish the update | Rewrites the branch, protected by a lease | Inference: a rebase needs a rewrite | Unattended runs must not rewrite a pushed head | **reject**: ADR 0096 keeps unattended runs off rewrites | none |
| Filter to out-of-date, unblocked pull requests | Skips anything labeled blocked | Inference: a blocked item should not consume runs | Same | **already have**: the [dispatcher](../../.github/scripts/pr-unblock/dispatch.mjs) re-queries an unknown merge state, then skips it for a later run | none |
| One runner per pull request | Isolates each update | Inference: one failure should not stop the rest | Same | **already have**: pr-unblock is dispatched per pull request | none |
| A label as a second trigger | Starts an update between scheduled runs | Inference: a nightly run is sometimes too slow | The push-to-main event reaches these sooner | **already have** in effect | none |
| The unhappy path, superseded work included | Sends a hard conflict or an obsolete pull request to a person | Inference: an agent should not force a resolution it cannot judge | Nothing tested whether main already held a pull request's change | **adapt**: [`superseded-by-main.mjs`](../../.github/scripts/pr-unblock/superseded-by-main.mjs) runs before the conflict agent and hands a match to a person | [#17001](https://github.com/melodic-software/claude-code-plugins/pull/17001) |
| Matching ticket state to pull request state | Scripts the sync when the two are separate products | Inference: split tools drift apart | Both are GitHub for us | **already have** | none |

### Lesson 7: The Slow-Query Monitor

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Outside monitors as an input | Reads application metrics to find work | Inference: production data shows problems no reviewer sees | We have no product database to monitor | **already have** for factory signals: [`maintenance-monitor-signals.yml`](../../.github/workflows/maintenance-monitor-signals.yml) | none |
| An input of unknown rate must not flood the factory | Avoids starting one run per alert | Inference: alert volume is outside the factory's control | No push-started agent run exists | **already have**: spending limits and lane kill switches | none |
| Queue alerts and pull them on a schedule | Sets the pace from the consumer's side | Inference: a pull cannot be overrun | Same | **already have**: the monitor lane pulls on a schedule | none |
| Group alerts and remove duplicates | Files one ticket per group, checked against existing tickets | Inference: repeated alerts become repeated tickets | Two places judged duplicates | **adapt**: intake triage alone decides a duplicate; a producer's search only skips an obvious repeat | [#16995](https://github.com/melodic-software/claude-code-plugins/pull/16995) |
| A monitor's ticket starts a fix run | Opens a fix from an alert with no person involved before the pull request | Inference: small fixes should not wait | Alert text is outside text | **deferred**: the design is recorded and nothing is built now; when built, an alert starts the agent alongside the page, never instead of it, and a person reviews an alert-started fix before it merges | none |
| Rate each group's severity | Sends only severe groups to a fix run | Inference: fix capacity should go to what matters | We have no alert intake | **adapt**: adopt severity rating for monitor alerts only when an incident lane is built; severity then orders the queue and never drops an alert | none |
| Pull from the vendor's API | Gives the orchestrator a production read credential and puts alert text in a run's context | Inference: a pull needs access to the source | Production query text could carry data into agent context | **reject**: no production data in a pipeline for our repositories | none |

### Lesson 8: Prototyping

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| "Prototype needed" as a third exploration verdict | Starts a prototype run from triage | Inference: some questions need something to look at | Prototypes run when a person starts them | **reject** for now: prototypes stay attended | none |
| Iterate through the factory | Creates or updates a prototype, rebuilding history from tracker comments | Inference: iteration is where prototypes earn their value | Same, attended | **already have**: the `vary` and `combine` actions of [`/prototype:explore-directions`](../../plugins/prototype/skills/explore-directions/SKILL.md) | none |
| Deploy the prototype for a non-technical reviewer | Gives a person a link with no local setup | Inference: reviewers should not need a development environment | Same goal | **already have**: the self-contained HTML demo of [`/prototype:pressure-test`](../../plugins/prototype/skills/pressure-test/SKILL.md); a hosted preview deploy is rejected | none |
| Comment only after the prototype exists | Posts the tracker comment with its link | Inference: a comment should point at something real | Same | **already have**: the verdict goes in the resolution comment, with evidence on the dossier branch | none |
| Store the prototype as a labeled draft pull request | Keeps the code where nobody merges it | Inference: throwaway code needs a home | A branch has no merge button to guard | **already have**: one dossier branch per map; the draft pull request is rejected | none |
| Bring the person back through the tracker | Asks for a reaction to the running prototype | Inference: people react better to something they can use | Same, attended | **already have**: the skill hands over and waits for a reply | none |
| A tagged comment starts the next iteration | Lets a tracker comment start a run with write access | Inference: the conversation should drive the loop | Comment permission would become permission to start a run | **reject** for now: prototypes stay attended | none |
| A human route beside each agent route | Adds a tag a person applies to start the same run | Inference: a person must be able to do what the agent does | The rule holds; the unattended run does not exist | **already have** the rule; a tag that starts an unattended prototype run is rejected | none |
| Prototypes as a spec from non-technical people | Treats the output as a detailed spec, not production code | Inference: people outside engineering can show what they want | Same | **already have**: our prototypes end as acceptance criteria and decisions | none |
| The tracker as the human-to-agent channel | Keeps the conversation with agents on tickets | Inference: people already work there | Same | **already have**: one tracker seam over providers | none |
| The prototype loop has no exit on the board | Leaves nothing moving a finished prototype on | Inference: not stated; seen on the board | Ours closes with a resolution | **already have**: `/prototype:explore-directions` removes its variants after capture | none |

### Lesson 9: Implement Spec

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Build the spec overnight | Runs a long unattended build that ends in a reviewed pull request | Inference: people plan by day and agents build by night | Per-item unattended runs exist; whole-spec runs are attended | **already have** per item: no new pipeline for a whole spec | none |
| Turn skill steps into deterministic orchestration | Splits each step into agent work and plain scripting | Inference: scripted steps are cheaper and repeatable | Same | **already have**: ADR 0085 | none |
| The frontier needs no agent | Computes unblocked tickets from dependency edges | Inference: graph traversal does not need judgment | Same | **already have**: native blocked-by edges and [`/work-items:ship`](../../plugins/work-items/skills/ship/SKILL.md) | none |
| Split a spec into tickets unattended | Runs the ticket split with no approval step | Inference: the split is busywork once the spec is fixed | [`/work-items:decompose`](../../plugins/work-items/skills/decompose/SKILL.md) waits for approval | **reject**: the approval stays | none |
| Shared notes on a remote branch | Keeps exploration notes every later run reads | Inference: runs share no memory | Same | **already have**: one dossier branch per map, deleted when its spec container closes ([#16907](https://github.com/melodic-software/claude-code-plugins/pull/16907)) | none |
| Build the whole frontier in parallel | Merges one runner per ticket into an integration branch | Inference: parallel tickets shorten a long build | Same, attended | **already have**: both shapes in `/work-items:ship` | none |
| One review at the end | Reviews the integration branch once | Inference: a single review costs less | Per-item review keeps change control per ticket | **already have**: both review lanes on every ready pull request; end-only review is rejected | none |
| A label starts the spec run | Alerts the orchestrator from a labeled or assigned spec | Inference: starting a run should be one action | Same, per item | **already have**: an issue-field write from a listed sender | none |
| A self-restarting chain with order in issue bodies | Runs one ticket per run and starts itself again with no limit | Inference: a chain needs no separate scheduler | Editable body lines and an uncapped chain are unsafe | **reject**: native edges and work-in-progress caps stand | none |
| One personal token for every call | Uses a personal token because the built-in token cannot chain | Inference: chaining needs another actor | A person-bound token names a person for every write | **reject**: the lanes App, as in [part one's record](aihero-software-factory-part-one.md) | none |
| Filter comments by author association | Passes only trusted authors' comments to the agent | Inference: comments are an injection path | Same | **already have**: intake filters by listed identity and covers the issue body | none |
| Fences held by prompt lines | Tells agents not to touch hooks or workflows | Inference: an agent could weaken its own checks | A prompt line is not enforcement | **already have**, stronger: token scope and [`protected-paths.mjs`](../../.github/scripts/apply-patch/protected-paths.mjs) | none |
| A failed ticket stays open and blocked | Skips it, moves on, and retries when a person clears the label | Inference: failures must stay visible | Same | **already have**: capped re-fires in the implement lane | none |
| Decomposition rules, with a ticket-count bound | Sets one ticket per module, checkable completion and a maximum count | Inference: a very long ticket list signals a spec that should split | Same shape; approval already catches a bad count | **already have** the shape; the count warning is rejected while approval stays | none |
| Prompts leave columns unindexed for a later lesson | Plants a defect for the monitor to find | Inference: a demonstration needs something to detect | None | **reject**: a teaching device | none |
| Fresh context per subagent | Starts each implementer with a clean context | Inference: long contexts degrade | Same | **already have**: [`/implementation:implement-dispatch`](../../plugins/implementation/skills/implement-dispatch/SKILL.md) | none |

### Lesson 10: Wrapping Up

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The course's through-line | Connects each earlier workshop to trust in the factory | Inference: the parts depend on one another | Each part was decided in its own record | **no change**: nothing new to decide | none |
| Wayfinder as an accelerator | Reclassifies the planning method | Inference: better planning pushes more work through | [`/planning:wayfind`](../../plugins/planning/skills/wayfind/SKILL.md) is unchanged | **no change**: noted in our private course notes | none |
| A factory that interrupts people only when stuck | Sets the goal of leaving the factory alone | Inference: attention is the scarce resource | Same goal | **already have**: [when work stops for the owner](../contracts/loop-lane/README.md#when-work-stops-for-the-owner) | none |
| What comes after the course | Closes the course and points at office hours | Inference: learners need a next step | Office hours have [their own record](aihero-office-hours.md) | **no change** | none |

### Raised while absorbing

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Choose question pacing by topic breadth | n/a (raised while absorbing) | n/a | `/planning:interview` had a fixed pacing | **take**: an `auto` value for `question_pacing`; rounds stay the default | [#17000](https://github.com/melodic-software/claude-code-plugins/pull/17000) |
| Hand a confirmed interview on to a spec | n/a (raised while absorbing) | n/a | The interview did not name the next step for a confirmed design | **take**: `## Next` offers `/planning:prd` or `/planning:design` | [#17000](https://github.com/melodic-software/claude-code-plugins/pull/17000) |
| Skill reference layout and examples | n/a (raised while absorbing) | n/a | Whether skills should move their references | **already have**: no layout change | none |
| System design support | n/a (raised while absorbing) | n/a | No file-backed diagram target, no system-design steps, and event storming depended on Miro | **adapt** inside existing plugins, with no new plugin: an Excalidraw file target, then quality-scenario, capacity and risk steps in `/planning:design`, then event storming backends with Miro as one of them | [#17052](https://github.com/melodic-software/claude-code-plugins/pull/17052), [#17062](https://github.com/melodic-software/claude-code-plugins/pull/17062), [#17087](https://github.com/melodic-software/claude-code-plugins/pull/17087) |
| Improvement skills as factory tasks | n/a (raised while absorbing) | n/a | Simplify and similar passes run only by hand | **adapt**: a map of factory tasks from ideation to merge ([#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133)) decides where each runs, including a simplify pass on every pull request that never slows it | pending |
| A parent issue for agent-filed work | n/a (raised while absorbing) | n/a | Agent filings of one kind have no grouping | **no change**: the source label comes first, and a parent only if needed | none |
| Lesson 1: a factory spec handed to an agent to build | n/a (raised while absorbing) | n/a | The note needs a place in the factory's design | **deferred**: carried into the map of factory tasks in [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133), since the spec describes what the map settles | none |
| Lesson 2: a plugin that builds and maintains a factory | n/a (raised while absorbing) | n/a | The note needs a place in the factory's design | **deferred**: carried into the map of factory tasks in [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133), since the skills it ships follow from the tasks on the map | none |
| Lesson 2: research every runner, storage and hosting vendor raised, with modern alternatives | n/a (raised while absorbing) | n/a | Nothing is being bought, and public repositories stay on Actions | **deferred**: to the infrastructure design run as a [`/planning:wayfind`](../../plugins/planning/skills/wayfind/SKILL.md) effort, carried in [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) | none |
| Lesson 2: compare and take from the author's newest `software-factory` skill | n/a (raised while absorbing) | n/a | Whether the newest copy holds anything to take | **no change**: the newest copy differs from the audited pin by two one-line edits, and the `software-factory` row of [mattpocock-skills.md](mattpocock-skills.md) takes nothing | none |
| Lesson 2: vendor-agnostic providers | n/a (raised while absorbing) | n/a | The owner's direction needs a design | **deferred**: carried into the map of factory tasks in [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) as direction to design there | none |
| Lesson 3: agent-built templates and palette | n/a (raised while absorbing) | n/a | Diagram templates and a palette an agent could build with a person have no home | **deferred**: a separate item after the Excalidraw file target, tracked in [#17128](https://github.com/melodic-software/claude-code-plugins/issues/17128) | none |

### Deferred

These were decided to wait, each for the condition or in the issue named:

- a daily design filer, until the source label gives counts of open filings;
- a production-incident pipeline, until a production source exists; an alert starts the agent
  alongside the page, never instead of it, and a person reviews any alert-started fix before it
  merges;
- a private-repository runner, until that work starts, because of its cost;
- a different runner per task, carried into the map of factory tasks in
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133), which decides
  where each task runs first;
- a factory spec handed to an agent, and a plugin that builds and maintains a factory, both carried
  into the map of factory tasks in
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133);
- research of the runner, storage and hosting vendors raised, with modern alternatives, until the
  infrastructure design runs as a `/planning:wayfind` effort, carried in
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133);
- a merge that starts the next run, a strong accelerator that adapts the pace to how fast the
  developer wants to move that day, until the map of factory tasks in
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) settles its brakes;
- vendor-agnostic providers, carried into the map of factory tasks in
  [#17133](https://github.com/melodic-software/claude-code-plugins/issues/17133) as direction to
  design there;
- agent-built templates and palette, a separate item after the Excalidraw file target, tracked in
  [#17128](https://github.com/melodic-software/claude-code-plugins/issues/17128).

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. [mattpocock-skills.md](mattpocock-skills.md) records the author's skills repository as
MIT licensed; no text or code from it is copied either.

- **Pointer**: when a license question arises, read the opening of
  [mattpocock-skills.md](mattpocock-skills.md).
- **As of**: 2026-11-18
- **Recheck trigger**: that record's license statement changes.
