# Vendor routing audit: skill steps that delegate a whole task

Each row is one skill step that hands a whole task (a review, an investigation, a generated asset,
a long unattended change) to another agent, with the work type and whether the step could take its
vendor from `/multi-agent:route vendors` instead of being fixed to Claude.

Routing source: [`vendors.md`](vendors.md) (the rule, task classes and per-vendor facts) and
[`/multi-agent:route vendors`](../skills/route/SKILL.md) (the skill that applies it). A `route`
verdict marks a candidate only: this audit moves no Claude step to another vendor, and routing
stays behind the user's switches. Rows whose reason says "already runs on another vendor" run there
by the skill's own design.

## Columns

- **Work type**: `coding` (code review, code change, tests, debugging, code analysis), `web UI`
  (evaluating or driving a rendered web interface), `knowledge work` (research, docs, prose,
  classification, planning, config and markdown audits) or `image generation` (producing or
  judging images, video, animation, visual assets).
- **Verdict**: `route` when the step hands a self-contained brief (files, a diff, URLs, a question)
  to a fresh agent and takes back a report or a change, so another vendor given the same brief
  could do it. `keep` when it needs session context (a fork that inherits the conversation, which
  a skill's `context: fork` does not, or input such as the transcript or the live session that a
  brief cannot carry), or when Claude must do it (it probes or grades Claude Code or a Claude
  skill, its delegated task is running a named skill through the Skill tool, or it runs behind a
  Claude Code enforcement such as a PreToolUse gate). A worker that calls a skill only when its
  plugin is enabled, with an inline fallback, stays `route`.
- **Step**: the `file:line` that shows the delegating step, then what it delegates. Line numbers
  are as of 2026-11-23. Recheck when: a cited line no longer shows its step, or a skill adds or
  drops a delegating step.

## Audit

| Skill | Step | Work type | Verdict | Reason |
|---|---|---|---|---|
| ai-slop:audit | `plugins/ai-slop/skills/audit/SKILL.md:142`: full audit or fix run per repository | knowledge work | route | brief carries the repository root and the single-repository procedure |
| ai-slop:audit | `plugins/ai-slop/skills/audit/SKILL.md:332`: semantic-diff check of a de-slop rewrite | knowledge work | route | brief carries the before and after pair and the risky classes |
| ai-slop:audit | `plugins/ai-slop/skills/audit/context/rubric-fanout.md:63`: rubric pass over one batch of markdown | knowledge work | route | brief carries the batch file list, rubric path, cues and digest |
| animation:produce | `plugins/animation/skills/produce/SKILL.md:82`: pre-delivery review of the rendered film's frames | image generation | route | brief carries frames, brief, boards, style guide, shot list and pack-check output |
| app-control:map | `plugins/app-control/skills/map/reference/refresh.md:175`: source-wave drift questions per feature file | coding | route | brief carries the feature file, source globs, changed files and fixed questions |
| app-control:map | `plugins/app-control/skills/map/reference/refresh.md:243`: reading a new ticket-branch surface into a recipe | coding | route | brief carries the hub, the surface, its source path and the questions |
| architecture:enforce-boundaries | `plugins/architecture/skills/enforce-boundaries/SKILL.md:27`: rules, mechanism and plan phases per repository | coding | route | brief carries the repository root and the single-repository procedure |
| architecture:improve | `plugins/architecture/skills/improve/actions/boundaries.md:18`: collecting and matching boundary rules per repository | coding | route | brief carries the repository root, home and memory root |
| architecture:improve | `plugins/architecture/skills/improve/actions/conventions.md:40`: code walk for building blocks, owners and blueprints | coding | route | brief carries the scoped area and the evidence each kind needs |
| architecture:improve | `plugins/architecture/skills/improve/actions/deepening.md:21`: friction scan for deepening candidates | coding | route | brief carries the scoped area, scan-briefing template and return schema |
| architecture:improve | `plugins/architecture/skills/improve/actions/deepening.md:48`: reproducing strong-confidence and runtime claims | coding | route | brief carries each candidate's claim with the cited code |
| architecture:improve | `plugins/architecture/skills/improve/research/deepening/interface-design.md:30`: alternative interface designs under one constraint each | coding | route | brief carries files, coupling, seam, names and one design constraint |
| architecture:improve-layout | `plugins/architecture/skills/improve-layout/SKILL.md:48`: co-change layout analysis per repository | coding | route | brief carries the repository root, home and co-change script invocation |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:66`: nominating possibly copied passages in a corpus chunk | knowledge work | route | brief carries a chunk of corpus files and the breadcrumb inventory |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:111`: three blind judges per candidate passage | knowledge work | route | brief carries the passage, its file, the fetched source and one rubric |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:135`: review veto pass over copy findings | knowledge work | route | brief carries the finding, its file, the source and the judges' grades |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:140`: refutation pass on restated-fact findings | knowledge work | route | brief carries the passage, the source and the panel's quoted evidence |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:195`: semantic-loss check of a fix rewrite | knowledge work | route | brief carries the before and after text only |
| attribution:audit | `plugins/attribution/skills/audit/SKILL.md:249`: audit, fix or sweep per repository | knowledge work | route | brief carries the repository root, target path and procedure |
| bugs:scan | `plugins/bugs/skills/scan/SKILL.md:121`: whole hunt-and-gate pipeline per repository | coding | route | brief carries the repository root, lanes and that repository's config |
| bugs:scan | `plugins/bugs/skills/scan/SKILL.md:279`: read-only bug hunting, one lens each | coding | route | brief carries the file list, the lens rules and the source framing |
| bugs:scan | `plugins/bugs/skills/scan/SKILL.md:310`: refute-by-default gate per bug candidate | coding | route | brief carries one candidate, its evidence quote and the gate prompt |
| code-tidying:audit-dead-code | `plugins/code-tidying/skills/audit-dead-code/SKILL.md:93`: dead-code scan per repository | coding | route | brief carries the repository root, limits, lane and target |
| code-tidying:audit-dead-code | `plugins/code-tidying/skills/audit-dead-code/SKILL.md:142`: adjudicating batches of dead-code candidates | coding | route | brief carries the candidate list and dynamic-usage patterns |
| code-tidying:batch-simplify | `plugins/code-tidying/skills/batch-simplify/SKILL.md:126`: repo-mode sweep per repository | coding | route | brief carries the repository root and the repo-mode procedure |
| code-tidying:batch-simplify | `plugins/code-tidying/skills/batch-simplify/SKILL.md:267`: simplifying one ecosystem group of files | coding | route | brief carries the file list, conventions, verify commands and deferral rules |
| code-tidying:batch-simplify | `plugins/code-tidying/skills/batch-simplify/SKILL.md:294`: fixing consolidated deferred items | coding | route | brief carries the item's cross-group file set and recorded ground |
| code-tidying:batch-simplify | `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md:74`: refining the repo-mode file grouping | coding | route | brief carries the base grouping and the split rules |
| code-tidying:batch-simplify | `plugins/code-tidying/skills/batch-simplify/context/repo-mode.md:168`: refutation verifier on behavior preservation | coding | route | brief carries the group's diff and one refutation question |
| code-tidying:remove-comments | `plugins/code-tidying/skills/remove-comments/SKILL.md:107`: remove-comments run per repository | coding | route | brief carries the repository root and the resolved scope |
| code-tidying:remove-comments | `plugins/code-tidying/skills/remove-comments/SKILL.md:139`: comment triage and comment-only edits in a scope | coding | route | brief carries scope files, posture, settings and keep list; the parent checks the diff |
| code-tidying:tidy | `plugins/code-tidying/skills/tidy/SKILL.md:74`: whole tidy workflow per repository | coding | route | brief carries the repository root and lane |
| codebase-health:audit | `plugins/codebase-health/skills/audit/SKILL.md:176`: discovery and validation per repository | knowledge work | route | brief carries the repository, scope, dimensions and config |
| codebase-health:audit | `plugins/codebase-health/skills/audit/SKILL.md:247`: extracting and checking every claim in one file | knowledge work | route | brief carries one file, the claim-extraction method and a scope fence |
| codebase-health:audit | `plugins/codebase-health/skills/audit/SKILL.md:274`: false-positive gate over drift findings | knowledge work | route | brief carries the findings, their files and verification sources |
| coupling:reduce | `plugins/coupling/skills/reduce/SKILL.md:91`: every coupling phase per repository | coding | route | brief carries the repository root, scope and procedure |
| coupling:reduce | `plugins/coupling/skills/reduce/SKILL.md:106`: coupling scan returning ledger findings | coding | route | brief carries the scope slice and the coupling model |
| debugging:analyze-profile | `plugins/debugging/skills/analyze-profile/SKILL.md:46`: querying a large heap snapshot or profile | coding | route | brief carries the artifact path, format queries and data framing |
| debugging:debug | `plugins/debugging/skills/debug/SKILL.md:339`: outcome verification of a bug fix | coding | route | brief carries the symptom, the fix diff and pass or fail criteria |
| developer-experience:build-cli | `plugins/developer-experience/skills/build-cli/SKILL.md:100`: review of a CLI against the CLI rules | coding | route | brief carries the tool's files and the rule table |
| discipline:do-your-research | `plugins/discipline/skills/do-your-research/SKILL.md:89`: audit of the session's claims | knowledge work | route | brief carries the discipline source and the claims under audit |
| discipline:do-your-research | `plugins/discipline/skills/do-your-research/SKILL.md:106`: blind re-derivation of a suspect claim | knowledge work | route | brief carries the claim and question only |
| discipline:do-your-research | `plugins/discipline/skills/do-your-research/reference/fan-out-tier.md:36`: checking claim inventory items against primary sources | knowledge work | route | brief carries one inventory item |
| discipline:follow-operating-procedures | `plugins/discipline/skills/follow-operating-procedures/SKILL.md:66`: the method doc's step 2 and 3 audit subagents | knowledge work | route | brief carries the discipline source and the work under audit |
| discipline:follow-our-standards | `plugins/discipline/skills/follow-our-standards/SKILL.md:90`: the method doc's step 2 and 3 audit subagents | coding | route | brief carries the discipline source and the work under audit |
| discipline:follow-our-standards | `plugins/discipline/skills/follow-our-standards/SKILL.md:96`: standards audit per repository | coding | route | brief carries the repository root |
| discipline:mind-your-maxims | `plugins/discipline/skills/mind-your-maxims/SKILL.md:86`: the method doc's step 2 and 3 audit subagents | knowledge work | route | brief carries the discipline source and the work under audit |
| discipline:pick-for-the-problem | `plugins/discipline/skills/pick-for-the-problem/SKILL.md:80`: audit of tool and approach choices | knowledge work | route | brief carries the discipline source and the choices made |
| discipline:point-dont-copy | `plugins/discipline/skills/point-dont-copy/SKILL.md:73`: audit for copied content | knowledge work | route | brief carries the discipline source and the files under audit |
| discipline:point-dont-copy | `plugins/discipline/skills/point-dont-copy/SKILL.md:106`: copy audit per repository | knowledge work | route | brief carries the repository root and the discipline |
| discipline:reason-dont-recite | `plugins/discipline/skills/reason-dont-recite/SKILL.md:50`: audit of choices justified by precedent | knowledge work | route | brief carries the discipline source and the decisions |
| discipline:recheck-against-upstream | `plugins/discipline/skills/recheck-against-upstream/SKILL.md:80`: re-check of a suspect doc reading | knowledge work | route | brief carries the surface and the upstream URL |
| discipline:recheck-against-upstream | `plugins/discipline/skills/recheck-against-upstream/SKILL.md:122`: upstream recheck per repository | knowledge work | route | brief carries the repository root, pinned version and ledger path |
| discipline:recheck-against-upstream | `plugins/discipline/skills/recheck-against-upstream/reference/fan-out-tier.md:14`: per-surface comparison against upstream docs | knowledge work | route | brief carries the surface, fetch script paths and divergence categories |
| discipline:reuse-or-replace | `plugins/discipline/skills/reuse-or-replace/SKILL.md:145`: audit for second ways beside a pattern | coding | route | brief carries the discipline source and the code |
| discipline:reuse-or-replace | `plugins/discipline/skills/reuse-or-replace/SKILL.md:175`: two-ways audit per repository | coding | route | brief carries the repository root |
| discipline:script-the-deterministic-work | `plugins/discipline/skills/script-the-deterministic-work/SKILL.md:76`: audit of hand-done work to script | coding | route | brief carries the discipline source and the change |
| discipline:scrutinize-dont-coast | `plugins/discipline/skills/scrutinize-dont-coast/SKILL.md:68`: adversarial review of produced output | knowledge work | route | brief carries the artifact and the requirement |
| discipline:sweep-all | `plugins/discipline/skills/sweep-all/reference/batched-pass.md:25`: audit pass per corrector over the conversation | knowledge work | keep | needs session context: a fork audits this conversation's transcript |
| discipline:sweep-all | `plugins/discipline/skills/sweep-all/reference/batched-pass.md:120`: confirming clean ledgers per corrector | knowledge work | route | brief carries the discipline source and the work under audit |
| discipline:sweep-all | `plugins/discipline/skills/sweep-all/reference/batched-pass.md:158`: blind re-derivation of a drifting finding | knowledge work | route | brief carries the finding and question only |
| discipline:sweep-all | `plugins/discipline/skills/sweep-all/reference/inheritance-preflight.md:51`: canary proving forks inherit the conversation | knowledge work | keep | Claude must do it: probes Claude Code fork inheritance |
| discipline:tighten-your-output | `plugins/discipline/skills/tighten-your-output/SKILL.md:58`: audit for padding | knowledge work | route | brief carries the discipline source and the text |
| discipline:use-your-skills | `plugins/discipline/skills/use-your-skills/SKILL.md:58`: audit of skill use | knowledge work | route | brief carries the discipline source and the work under audit |
| discovery:explore | `plugins/discovery/skills/explore/SKILL.md:72`: six-dimension exploration by `discovery:explorer` | coding | route | brief carries the scope, reason, slice path, budget and output shape |
| discovery:explore | `plugins/discovery/skills/explore/SKILL.md:72`: sibling verifier grading `EXPLORE.md` | coding | route | brief carries the index path and the criterion |
| discovery:explore | `plugins/discovery/skills/explore/SKILL.md:142`: Explore scouts per disjoint area | coding | route | brief carries the area and thoroughness level |
| discovery:research | `plugins/discovery/skills/research/SKILL.md:16`: multi-source research by `discovery:researcher` | knowledge work | route | brief carries the topic, reason, slice path, budget and breadth |
| discovery:research | `plugins/discovery/skills/research/SKILL.md:54`: research verifier grading outcome rows | knowledge work | route | brief carries the index path, row numbers and cited claim ids |
| discovery:research | `plugins/discovery/skills/research/context/deep-tier.md:27`: one researcher per separable topic | knowledge work | route | each brief carries its own topic and sub-slice |
| discovery:research | `plugins/discovery/skills/research/context/deep-tier.md:119`: research-sweep workflow with skeptics | knowledge work | route | args carry the question, angles, seed sources and roles |
| discovery:research | `plugins/discovery/skills/research/context/discipline.md:155`: gathering sources for research gaps | knowledge work | route | brief carries the gap, hypothesis, version and fetch recipe |
| discovery:research | `plugins/discovery/skills/research/context/dispatch.md:245`: verifying the synthesized root index | knowledge work | route | brief carries the index path and verifier-owned rows |
| discovery:trace-intent | `plugins/discovery/skills/trace-intent/SKILL.md:24`: design-rationale archaeology by `discovery:intent-tracer` | knowledge work | route | brief carries the target, reason, slice path and budget |
| discovery:trace-intent | `plugins/discovery/skills/trace-intent/context/dispatch.md:159`: verifier grading evidence tiers | knowledge work | route | brief carries the index path and the tier criterion |
| disk-hygiene:audit | `plugins/disk-hygiene/skills/audit/SKILL.md:74`: evidence-only scan of one subtree | knowledge work | keep | Claude must do it: the worker's engine calls run behind the plugin's PreToolUse gate |
| disk-hygiene:clean | `plugins/disk-hygiene/skills/clean/SKILL.md:194`: deeper scans per approved subtree | knowledge work | keep | Claude must do it: the worker's engine calls run behind the plugin's PreToolUse gate |
| disk-hygiene:clean | `plugins/disk-hygiene/skills/clean/reference/scan-flags.md:125`: searching issues, PRs and handoffs for a path | knowledge work | route | brief carries the target path, repository and handoff directory |
| docs-hygiene:audit-derivability | `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:64`: blind re-derivation of a doc's conclusions | knowledge work | route | brief carries the doc's questions only |
| docs-hygiene:audit-derivability | `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:78`: derivability verdicts over doc batches | knowledge work | route | brief carries the batch doc list and the rubric |
| docs-hygiene:audit-derivability | `plugins/docs-hygiene/skills/audit-derivability/SKILL.md:79`: derivability sweep per repository | knowledge work | route | brief carries the repository root and the sweep procedure |
| docs-hygiene:audit-encapsulation | `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md:42`: encapsulation sweep per repository | knowledge work | route | brief carries the repository root and the detect procedure |
| docs-hygiene:audit-encapsulation | `plugins/docs-hygiene/skills/audit-encapsulation/SKILL.md:63`: sorting or fixing encapsulation hits | knowledge work | route | brief carries the detect hits |
| docs-hygiene:audit-noise | `plugins/docs-hygiene/skills/audit-noise/SKILL.md:120`: noise verdicts over chunks of a corpus | knowledge work | route | brief carries the file chunk and the shape table |
| docs-hygiene:audit-noise | `plugins/docs-hygiene/skills/audit-noise/SKILL.md:121`: verifying merged noise verdicts | knowledge work | route | brief carries the merged verdicts and cited files |
| docs-hygiene:compress | `plugins/docs-hygiene/skills/compress/SKILL.md:112`: labeling differences between two skill directories | knowledge work | route | brief carries both directory paths and the compare prompt |
| docs-hygiene:compress | `plugins/docs-hygiene/skills/compress/context/fan-out-orchestration.md:15`: compressing one markdown file | knowledge work | route | brief names one allowed file and the latitude |
| docs-hygiene:compress | `plugins/docs-hygiene/skills/compress/context/semantic-diff-prompt.md:7`: semantic diff of original against compressed | knowledge work | route | brief carries two file paths and a fixed prompt |
| docs-hygiene:extract-ssot | `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:54`: duplication survey per repository | knowledge work | route | brief carries the repository root and the survey |
| docs-hygiene:extract-ssot | `plugins/docs-hygiene/skills/extract-ssot/SKILL.md:207`: adversarial review of an extraction diff | knowledge work | route | brief carries the cluster's diff |
| docs-hygiene:extract-ssot | `plugins/docs-hygiene/skills/extract-ssot/actions/batch.md:22`: verify gate per candidate cluster | knowledge work | route | brief carries the cluster and lesson snapshot |
| docs-hygiene:extract-ssot | `plugins/docs-hygiene/skills/extract-ssot/actions/identify.md:105`: repo-wide duplicated-markdown survey | knowledge work | route | brief is a self-contained survey prompt |
| docs-hygiene:extract-ssot | `plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md:37`: executing an extraction across call sites | knowledge work | route | brief carries the cluster, wave plan and lessons |
| docs-hygiene:rename-references | `plugins/docs-hygiene/skills/rename-references/SKILL.md:70`: stale-reference sweep per repository | knowledge work | route | brief carries the old and new names and the repository root |
| docs-naming:audit-file-names | `plugins/docs-naming/skills/audit-file-names/SKILL.md:51`: file-name facts per repository | knowledge work | route | brief carries the repository root and worktree path |
| education:quiz-me | `plugins/education/skills/quiz-me/SKILL.md:86`: writing or checking the answer key | knowledge work | route | brief carries the report and the diff |
| evals:plugin-eval | `plugins/evals/skills/plugin-eval/SKILL.md:246`: headless runs of a plugin's eval suite | coding | keep | Claude must do it: grades a Claude plugin's skills in Claude Code sessions |
| evals:plugin-eval | `plugins/evals/skills/plugin-eval/SKILL.md:401`: labeling must-pass and must-fail samples | knowledge work | route | brief carries the grader rubric and the samples |
| evals:plugin-eval | `plugins/evals/skills/plugin-eval/SKILL.md:406`: judge calibration runs | knowledge work | keep | Claude must do it: calibrates the Claude judge the suite uses |
| event-storming:simulation | `plugins/event-storming/skills/simulation/reference/agentic-simulation.md:537`: persona agents writing stickies per round | knowledge work | route | brief carries the persona, board, domain context and round rules |
| event-storming:simulation | `plugins/event-storming/skills/simulation/reference/agentic-simulation.md:1032`: aggregate role-play agents | knowledge work | route | brief carries the aggregate's state, commands and events |
| event-storming:simulation | `plugins/event-storming/skills/simulation/reference/simulation-evaluation.md:358`: scoring boards against the rubric | knowledge work | route | brief carries the board export, round transcripts and rubric |
| explainer-video:produce | `plugins/explainer-video/skills/produce/SKILL.md:95`: judging rendered delivery frames | image generation | route | brief carries the report, frames, beats and script paths |
| explainer-video:produce | `plugins/explainer-video/skills/produce/SKILL.md:179`: judging storyboard contact sheets | image generation | route | brief carries the contact sheet paths and the script |
| external-agents:antigravity | `plugins/external-agents/skills/antigravity/SKILL.md:33`: a task or investigation on the agy CLI | coding | route | already runs on another vendor; the prompt file names the paths |
| external-agents:antigravity | `plugins/external-agents/skills/antigravity/SKILL.md:34`: read-only branch review on agy | coding | route | already runs on another vendor; brief carries the base ref |
| external-agents:codex | `plugins/external-agents/skills/codex/SKILL.md:32`: a task or investigation on the Codex CLI | coding | route | already runs on another vendor; the prompt file names the paths |
| external-agents:codex | `plugins/external-agents/skills/codex/SKILL.md:33`: read-only branch review on Codex | coding | route | already runs on another vendor; brief carries the base ref |
| firecrawl:firecrawl | `plugins/firecrawl/skills/firecrawl/context/commands.md:118`: web research through Firecrawl's hosted agent | knowledge work | route | runs on Firecrawl's hosted agent, not a vendor `vendors.md` covers; the brief is the prompt |
| fleet:reach | `plugins/fleet/skills/reach/SKILL.md:106`: headless turn in another fleet lane | coding | route | prompt carries the task, done condition and stop condition |
| fleet:reach | `plugins/fleet/skills/reach/SKILL.md:112`: long-running background session in another lane | coding | route | prompt carries the task and its standing instructions |
| harness-config:audit-automation-gaps | `plugins/harness-config/skills/audit-automation-gaps/SKILL.md:181`: docs and web research per candidate | knowledge work | route | brief carries the candidate list and research questions |
| harness-config:audit-automation-gaps | `plugins/harness-config/skills/audit-automation-gaps/SKILL.md:206`: refusal gate over candidates | knowledge work | route | brief carries the candidates, evidence and gate table |
| harness-config:audit-automation-gaps | `plugins/harness-config/skills/audit-automation-gaps/SKILL.md:451`: review of an implemented automation | coding | route | brief carries the change and existing patterns |
| harness-config:audit-instructions | `plugins/harness-config/skills/audit-instructions/SKILL.md:199`: instruction audit per repository | knowledge work | route | brief carries the clone root and procedure |
| harness-config:audit-instructions | `plugins/harness-config/skills/audit-instructions/SKILL.md:210`: per-lane audit against the criteria catalog | knowledge work | route | brief carries the lane files, criteria and pre-scan rows |
| harness-config:audit-instructions | `plugins/harness-config/skills/audit-instructions/SKILL.md:356`: refuting removal and rewrite proposals | knowledge work | route | brief carries the proposals, surfaces and refute prompt |
| harness-config:audit-pass | `plugins/harness-config/skills/audit-pass/SKILL.md:329`: verifying an applied fix | knowledge work | route | brief carries the applied diff and its finding |
| harness-config:audit-pass | `plugins/harness-config/skills/audit-pass/SKILL.md:364`: verifying the assembled findings | knowledge work | route | brief carries the findings and suppressions |
| harness-config:audit-pass | `plugins/harness-config/skills/audit-pass/reference/multi-repository.md:10`: whole audit pass per repository | knowledge work | keep | Claude must do it: each pass invokes its lane skills through the Skill tool |
| harness-config:audit-permission-state | `plugins/harness-config/skills/audit-permission-state/SKILL.md:210`: oracle session capturing auto-mode narration | knowledge work | keep | Claude must do it: probes Claude Code's own harness behavior |
| harness-config:audit-prompting-postures | `plugins/harness-config/skills/audit-prompting-postures/SKILL.md:141`: refuting posture verdicts per batch | knowledge work | route | brief carries the components, verdicts and refute prompt |
| harness-config:unhobble | `plugins/harness-config/skills/unhobble/SKILL.md:433`: blind decisions on experiment questions | knowledge work | route | brief carries one research memo per decision |
| harness-memory:audit | `plugins/harness-memory/skills/audit/SKILL.md:93`: memory audit per repository | knowledge work | route | brief carries the clone root and procedure |
| harness-ops:audit-install-state | `plugins/harness-ops/skills/audit-install-state/reference/evidence-discipline.md:84`: cross-review of install-state findings | knowledge work | route | brief carries the findings and engine report |
| harness-ops:behavior-probes | `plugins/harness-ops/skills/behavior-probes/SKILL.md:61`: live sessions probing platform behavior | coding | keep | Claude must do it: the cases test Claude Code itself |
| harness-ops:changelog | `plugins/harness-ops/skills/changelog/SKILL.md:134`: docs research per feature cluster | knowledge work | route | brief carries the explorers' questions and the fetch route |
| harness-ops:changelog | `plugins/harness-ops/skills/changelog/context/decisions.md:61`: classifying changelog items against surfaces | knowledge work | route | brief carries the item files and the discovery script |
| harness-ops:changelog | `plugins/harness-ops/skills/changelog/context/decisions.md:63`: verifying decision rows' repository facts | knowledge work | route | brief carries the rows with cited paths |
| harness-ops:control-claude-code | `plugins/harness-ops/skills/control-claude-code/SKILL.md:40`: launched Claude Code session driving plugin features | coding | keep | Claude must do it: drives Claude Code's own terminal UI |
| harness-ops:lanes | `plugins/harness-ops/skills/lanes/SKILL.md:29`: long-running unattended loop lanes | coding | keep | Claude must do it: lanes are Claude Code background sessions running plugin skills |
| implementation:implement | `plugins/implementation/skills/implement/SKILL.md:216`: phase-boundary review fallback | coding | route | brief carries the phase diff, base, tag and severity scale |
| implementation:implement | `plugins/implementation/skills/implement/SKILL.md:229`: phase acceptance verdict | coding | route | brief carries binary criteria and the diff |
| implementation:implement | `plugins/implementation/skills/implement/SKILL.md:269`: advisor critique of the change | coding | keep | needs session context: the advisor reads the live conversation |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:115`: plan phase implementation in a worktree | coding | route | brief carries the scope fence, plan, design excerpt, criteria and worktree |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:191`: competing implementation attempts | coding | route | brief carries a full phase brief and one constraint |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:214`: holdout acceptance tests | coding | route | brief carries the criteria and design excerpt only |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:231`: trail review of the deviations log | coding | route | brief carries the log path, refs and criteria |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:248`: phase-boundary review fallback | coding | route | brief carries the phase diff, base, tag and severity scale |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:250`: phase acceptance by `phase-verifier` | coding | route | brief carries binary criteria, diff and a throwaway worktree |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:254`: verifying an orchestrator source commit | coding | route | brief carries the commit diff and its purpose |
| implementation:implement-dispatch | `plugins/implementation/skills/implement-dispatch/SKILL.md:297`: one fix worker per open PR head | coding | route | brief carries the failing checks, unresolved threads and failed criteria |
| improvement:find | `plugins/improvement/skills/find/SKILL.md:51`: improvement scan per repository | coding | route | brief carries the repository root |
| improvement:improve | `plugins/improvement/skills/improve/SKILL.md:50`: one gap and one PR per repository | coding | route | brief carries the repository root, focus and target |
| instruction-placement:audit | `plugins/instruction-placement/skills/audit/SKILL.md:66`: placement audit per repository | knowledge work | route | brief carries the worktree root and the audit workflow |
| instruction-placement:delta | `plugins/instruction-placement/skills/delta/SKILL.md:83`: delta comparison per repository | knowledge work | route | brief carries the worktree path and the delta workflow |
| instruction-placement:migrate | `plugins/instruction-placement/skills/migrate/SKILL.md:256`: cutover canary on instruction loading | knowledge work | keep | Claude must do it: tests whether Claude Code loads the file |
| instruction-placement:migrate | `plugins/instruction-placement/skills/migrate/SKILL.md:350`: verifying each migrated surface loads | knowledge work | keep | Claude must do it: probes Claude Code's loading through its hook event |
| instruction-placement:migrate | `plugins/instruction-placement/skills/migrate/reference/verification.md:105`: Codex canary quoting loaded lines | knowledge work | route | already runs on another vendor; brief carries the repository and prompt |
| knowledge:course-digest | `plugins/knowledge/skills/course-digest/context/workflow.md:205`: transcript concept extraction per module | knowledge work | route | brief carries the module transcripts |
| knowledge:course-digest | `plugins/knowledge/skills/course-digest/context/workflow.md:207`: on-screen visual analysis per module | knowledge work | route | brief carries the frame and contact-sheet paths |
| knowledge:course-digest | `plugins/knowledge/skills/course-digest/context/workflow.md:210`: exploring the course's companion code | coding | route | brief carries the code section paths |
| knowledge:course-digest | `plugins/knowledge/skills/course-digest/context/workflow.md:213`: module summary from the three outputs | knowledge work | route | brief carries the agents' outputs and existing summary |
| knowledge:docpage-digest | `plugins/knowledge/skills/docpage-digest/SKILL.md:168`: digesting one doc section | knowledge work | route | brief carries the source section, context and output path |
| knowledge:docpage-digest | `plugins/knowledge/skills/docpage-digest/context/batch-path.md:23`: multi-page digest workflow | knowledge work | route | args carry the page URLs, work root, skill dir and date |
| knowledge:docpage-digest | `plugins/knowledge/skills/docpage-digest/context/dual-verification.md:10`: verifier A on the digest set | knowledge work | route | brief carries the pinned slice files and verdict rules |
| knowledge:docpage-digest | `plugins/knowledge/skills/docpage-digest/context/dual-verification.md:25`: cross-vendor verifier B | knowledge work | route | already runs on another vendor; brief carries the slice files |
| knowledge:docpage-digest | `plugins/knowledge/skills/docpage-digest/context/dual-verification.md:84`: applying verifier findings per unit | knowledge work | route | brief carries the findings and the unit file |
| knowledge:map-corpus | `plugins/knowledge/skills/map-corpus/SKILL.md:205`: digesting the approved queue | knowledge work | route | args carry the queue URLs and work root |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/companion-primary-sources.md:27`: research per companion-page section | knowledge work | route | brief carries the section topic and one output path |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/quality-gates.md:88`: vision-fidelity spot-check | knowledge work | route | brief carries only the slice path |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/watch-pipeline.md:137`: transcript claims into a research agenda | knowledge work | route | brief carries the transcript |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/watch-pipeline.md:139`: link previews and linked repositories | knowledge work | route | brief carries the harvested links and slice path |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/watch-pipeline.md:141`: recommendations menu and takeaways | knowledge work | route | brief carries the slice artifacts and target |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/watch-pipeline.md:269`: sorting one contact sheet | knowledge work | route | brief carries the sheet, its frame index and the JSON template |
| knowledge:video-digest | `plugins/knowledge/skills/video-digest/context/watch-pipeline.md:284`: quality audit of promoted frames | knowledge work | route | brief carries the frames directory and audit template |
| machine-health:setup | `plugins/machine-health/skills/setup/SKILL.md:379`: scheduled unattended audit run | knowledge work | keep | Claude must do it: the run invokes a plugin slash command inside Claude Code |
| mcp-tools:audit | `plugins/mcp-tools/skills/audit/SKILL.md:27`: whole tool-definition audit in a fork | coding | route | the input is the optional path and the working tree |
| mcp-tools:audit | `plugins/mcp-tools/skills/audit/SKILL.md:50`: per-tool checklist evaluation | coding | route | brief carries the tool sources and checklist |
| multi-agent:audit-defaults | `plugins/multi-agent/skills/audit-defaults/SKILL.md:74`: drift audit with finders and skeptics | knowledge work | keep | Claude must do it: the stages run a named agent behind a PreToolUse gate |
| mutation-testing:audit | `plugins/mutation-testing/skills/audit/SKILL.md:292`: triage of surviving mutants | coding | route | brief carries the mutated line, nearby code and covering tests |
| mutation-testing:audit | `plugins/mutation-testing/skills/audit/context/several-repositories.md:67`: scope and estimate per repository | coding | route | brief carries the clone root and procedure |
| mutation-testing:audit | `plugins/mutation-testing/skills/audit/context/several-repositories.md:76`: mutant run per repository | coding | route | brief carries the worktree, config, baseline and mutant set |
| mutation-testing:seed-faults | `plugins/mutation-testing/skills/seed-faults/SKILL.md:134`: reviewing seeded files for defects | coding | route | brief carries the seeded files and a neutral prompt |
| naming:name-it-better | `plugins/naming/skills/name-it-better/SKILL.md:137`: name candidates per lens | knowledge work | route | brief carries the naming brief only |
| naming:name-it-better | `plugins/naming/skills/name-it-better/SKILL.md:209`: scoring judges in elimination rounds | knowledge work | route | brief carries the candidate pool and criteria |
| overengineering:audit | `plugins/overengineering/skills/audit/SKILL.md:101`: enforcement audit per repository | knowledge work | route | brief carries the repository root and procedure |
| overengineering:delta | `plugins/overengineering/skills/delta/SKILL.md:109`: delta cycle per repository | knowledge work | keep | Claude must do it: each subagent invokes the audit through the Skill tool |
| performance:go-faster | `plugins/performance/skills/go-faster/SKILL.md:91`: whole-process speed sweep | knowledge work | keep | needs session context: sweeps this session's transcript and work |
| performance:verify | `plugins/performance/skills/verify/SKILL.md:25`: adversarial re-derivation of a performance claim | coding | route | brief carries the trees and the claim |
| planning:audit-answers | `plugins/planning/skills/audit-answers/SKILL.md:94`: adversarial check of the answer set | knowledge work | route | brief carries the answers, the Brief and each answer's evidence |
| planning:devils-advocate | `plugins/planning/skills/devils-advocate/SKILL.md:32`: stress-test of a plan or incumbent | knowledge work | route | prompt carries the plan or the incumbent's location |
| planning:interview | `plugins/planning/skills/interview/SKILL.md:318`: each round's recommendations | knowledge work | route | brief carries each question, its options and context |
| planning:interview | `plugins/planning/skills/interview/SKILL.md:334`: assumption sweep over the ledger | knowledge work | route | brief carries the ledger, recommendations and Brief draft |
| planning:interview | `plugins/planning/skills/interview/context/assumption-sweep.md:105`: re-reading quoted sources | knowledge work | route | brief carries each fact, quote and location |
| planning:interview | `plugins/planning/skills/interview/context/lane-shared.md:412`: reading an untrusted upload | knowledge work | route | brief carries the stored path and the question |
| planning:plan | `plugins/planning/skills/plan/SKILL.md:243`: plan draft review by `plan-reviewer` | knowledge work | route | brief carries the draft, design artifacts and Brief |
| planning:plan | `plugins/planning/skills/plan/SKILL.md:269`: formal devils-advocate stress-test | knowledge work | keep | Claude must do it: the subagent runs a skill through the Skill tool |
| planning:plan | `plugins/planning/skills/plan/SKILL.md:348`: built-in Plan agent sketch or context | knowledge work | route | brief carries the planning question |
| planning:plan | `plugins/planning/skills/plan/context/plan-panel.md:34`: competing planners, judges and synthesis | knowledge work | route | args carry the task, context, angles and rubric |
| playbooks:fable-5 | `plugins/playbooks/skills/fable-5/context/orchestration.md:64`: verifying a multi-file change | coding | route | brief carries the artifact and binary criteria |
| playbooks:repo-sweep | `plugins/playbooks/skills/repo-sweep/reference/review.md:11`: reviewing the last sweep step | knowledge work | keep | Claude must do it: grades a Claude skill run's own behavior |
| playbooks:skill-authoring | `plugins/playbooks/skills/skill-authoring/reference/rewrite-a-plugin.md:42`: classifying eval failures | knowledge work | keep | Claude must do it: grades a Claude skill's eval behavior |
| playwright:demo-video | `plugins/playwright/skills/demo-video/SKILL.md:99`: frame review of a web app demo video | web UI | route | brief carries the video, QC sheets, steps and acceptance rules |
| plugin-quality:audit | `plugins/plugin-quality/skills/audit/SKILL.md:211`: findings per plugin component by `auditor` | knowledge work | route | brief carries the evidence packet, target and lens files |
| plugin-quality:audit | `plugins/plugin-quality/skills/audit/SKILL.md:363`: checklist review of the findings write-up | knowledge work | route | brief carries the write-up and a fixed checklist |
| plugin-quality:audit | `plugins/plugin-quality/skills/audit/SKILL.md:392`: blind re-check of each finding | knowledge work | route | brief carries each finding and its artifact |
| plugin-quality:audit | `plugins/plugin-quality/skills/audit/reference/component-types/agent.md:35`: running the audited agent definition | knowledge work | keep | Claude must do it: probes a Claude Code agent definition |
| prototype:build-generator | `plugins/prototype/skills/build-generator/reference/visual-research.md:43`: research into a visual style | knowledge work | route | each brief carries one research thread |
| review:code-review | `plugins/review/skills/code-review/SKILL.md:306`: hunting and verifying PR findings | coding | route | brief carries the diff, PR context and prior findings |
| review:council | `plugins/review/skills/council/SKILL.md:150`: council member review by `brief-reviewer` | coding | route | prompt carries the intent, change set and member brief |
| review:council | `plugins/review/skills/council/SKILL.md:160`: external-vendor council review | coding | route | already runs on another vendor; the command carries the base and brief |
| review:fanout | `plugins/review/skills/fanout/context/default-mode.md:3`: tiered leaf reviewers over the diff | coding | route | brief carries the diff base, intent and findings path |
| review:fanout | `plugins/review/skills/fanout/SKILL.md:229`: plain and red-team Codex reviews | coding | route | already runs on another vendor; carries the base and brief |
| review:fanout | `plugins/review/skills/fanout/context/leaf-roster.md:21`: review against one criteria document | coding | route | brief carries the criteria document and diff base |
| review:fanout | `plugins/review/skills/fanout/context/run-everything-mode.md:16`: full-roster review sweep workflow | coding | route | args carry the diff base, slices, roles and findings paths |
| review:merge-risk | `plugins/review/skills/merge-risk/SKILL.md:53`: blind second merge-risk rating | coding | route | brief carries the PR, rubric and saved facts |
| review:quality-gate | `plugins/review/skills/quality-gate/context/architecture.md:16`: architecture compliance review | coding | route | brief carries the scope, concerns and diff base |
| review:quality-gate | `plugins/review/skills/quality-gate/context/close-out.md:319`: fidelity review of a shipped container | coding | route | brief carries the commit range, container body and finding table |
| review:quality-gate | `plugins/review/skills/quality-gate/context/code-design.md:82`: code-design review | coding | route | brief carries the change set, bar and criteria |
| review:quality-gate | `plugins/review/skills/quality-gate/context/code.md:60`: convention-grounded code review | coding | route | brief carries the diff base and findings path |
| review:quality-gate | `plugins/review/skills/quality-gate/context/criteria.md:19`: project criteria at a phase boundary | coding | route | brief carries the criteria and the phase inputs |
| review:quality-gate | `plugins/review/skills/quality-gate/context/downstream.md:21`: what the change breaks outside the diff | coding | route | brief carries the diff base and changed symbols |
| review:quality-gate | `plugins/review/skills/quality-gate/context/per-slice.md:10`: review against one criteria document | coding | route | brief carries the criteria path and diff base |
| review:quality-gate | `plugins/review/skills/quality-gate/context/pr.md:65`: read-only review of an open PR | coding | route | brief carries the merge-base diff and criteria |
| review:quality-gate | `plugins/review/skills/quality-gate/context/restatement.md:20`: restatement review of changed markdown | knowledge work | route | brief carries a file batch and the three lenses |
| review:quality-gate | `plugins/review/skills/quality-gate/context/security.md:19`: security audit of the change | coding | route | brief carries the scope, focus and diff base |
| review:quality-gate | `plugins/review/skills/quality-gate/context/self.md:11`: design and completeness review | coding | route | brief carries the diff base, plan and criteria |
| review:quality-gate | `plugins/review/skills/quality-gate/context/spec.md:128`: spec-fidelity comparison | coding | route | brief carries the spec text and diff base |
| review:security-review | `plugins/review/skills/security-review/SKILL.md:417`: security hunters and verifiers | coding | route | brief carries the diff, PR context and prior findings |
| review:security-review | `plugins/review/skills/security-review/SKILL.md:426`: refuting each critical rating | coding | route | brief carries the candidate and the severity bar |
| session-flow:audit-sessions | `plugins/session-flow/skills/audit-sessions/actions/pr.md:24`: reading a PR's past transcripts | knowledge work | route | brief names the transcript files and ranges |
| session-flow:continue-in-background | `plugins/session-flow/skills/continue-in-background/SKILL.md:205`: continuing the task in a background session | coding | route | the save-point payload is self-contained |
| session-flow:find-handoff | `plugins/session-flow/skills/find-handoff/SKILL.md:151`: handoff timeline in one transcript | knowledge work | route | brief carries one transcript path and the fields |
| session-flow:orchestrate | `plugins/session-flow/skills/orchestrate/SKILL.md:293`: probing nested subagent spawn | knowledge work | keep | Claude must do it: probes Claude Code's nested-spawn gate |
| session-flow:recall | `plugins/session-flow/skills/recall/SKILL.md:104`: condensing each matching past session | knowledge work | route | brief carries the topic, terms and redacted scan lines |
| session-flow:retro | `plugins/session-flow/skills/retro/context/ci-runs.md:72`: lens review of CI lane legs | knowledge work | keep | Claude must do it: grades how Claude CI legs followed their skill |
| session-flow:retro | `plugins/session-flow/skills/retro/context/session.md:126`: single-pass session analysis | knowledge work | keep | needs session context: judges this session's transcript |
| session-flow:retro | `plugins/session-flow/skills/retro/context/session.md:134`: three lens reviews of the session | knowledge work | keep | needs session context: each lens reads this session's transcript |
| session-flow:running-retro | `plugins/session-flow/skills/running-retro/SKILL.md:108`: mid-session checkpoint findings | knowledge work | keep | needs session context: reads the live transcript and state note |
| session-flow:running-retro | `plugins/session-flow/skills/running-retro/SKILL.md:198`: detached post-session observer | knowledge work | keep | needs session context: tails this session's transcript |
| session-flow:workflow | `plugins/session-flow/skills/workflow/context/pre-pr.md:15`: pre-PR review of the diff | coding | route | brief carries the diff and conventions |
| session-flow:workflow | `plugins/session-flow/skills/workflow/context/steps.md:210`: outcome verification against intent | coding | route | brief carries the Brief and the diff |
| songwriting:co-write | `plugins/songwriting/skills/co-write/SKILL.md:99`: refuting candidate lyric lines | knowledge work | route | brief carries the candidates, map, rubric and filter |
| songwriting:diagnose | `plugins/songwriting/skills/diagnose/SKILL.md:63`: refuting rewrite candidates | knowledge work | route | brief carries the candidates, map, rubric and filter |
| songwriting:object-writing | `plugins/songwriting/skills/object-writing/SKILL.md:54`: timed object-writing dives | knowledge work | route | brief carries the seed, timer, category and output path |
| source-control:babysit-loop | `plugins/source-control/skills/babysit-loop/reference/pre-escalation-dispatch.md:14`: resolving a blocker before escalation | coding | route | brief carries the blocker and the PR |
| source-control:babysit-prs | `plugins/source-control/skills/babysit-prs/SKILL.md:242`: per-PR fix and triage worker | coding | route | prompt carries the PR, reasons, worktree and fenced fields |
| source-control:babysit-prs | `plugins/source-control/skills/babysit-prs/reference/independent-resolution.md:52`: adjudicating an unresolvable bot thread | coding | route | brief names the thread and claimed disposition |
| source-control:babysit-prs | `plugins/source-control/skills/babysit-prs/reference/loop.md:123`: findings ledger from a multi-finding comment | coding | route | prompt carries the comment |
| source-control:babysit-prs | `plugins/source-control/skills/babysit-prs/reference/orchestration.md:508`: resolving a merge conflict | coding | route | brief carries the PR, worktree and both sides' diffs |
| source-control:pull-request | `plugins/source-control/skills/pull-request/reference/monitor.md:53`: findings ledger from review comments | coding | route | prompt carries the review comment |
| source-control:pull-request | `plugins/source-control/skills/pull-request/reference/monitor.md:373`: CI log audit | coding | route | brief carries the run ids and log output |
| source-control:pull-request | `plugins/source-control/skills/pull-request/reference/prep.md:72`: checking findings against official docs | coding | route | brief carries each claim and the versions |
| source-control:pull-request | `plugins/source-control/skills/pull-request/reference/ready-for-review.md:338`: code review at the ready step | coding | route | brief carries the diff and criteria |
| source-control:pull-request | `plugins/source-control/skills/pull-request/reference/ready-for-review.md:392`: security review of the diff | coding | route | brief carries the diff and security scope |
| testing:audit | `plugins/testing/skills/audit/SKILL.md:114`: cannot-fail scan per repository | coding | route | brief carries the repository root and detector command |
| testing:audit | `plugins/testing/skills/audit/SKILL.md:230`: judging expected-value sources by `test-judge` | coding | route | prompt carries the rubric, the file and its blocks |
| testing:cleanup | `plugins/testing/skills/cleanup/SKILL.md:96`: cleanup scan per repository | coding | route | brief carries the repository root and scanner command |
| testing:cleanup | `plugins/testing/skills/cleanup/SKILL.md:213`: classifying deletion candidates | coding | route | brief file carries the tests and candidates |
| testing:cleanup | `plugins/testing/skills/cleanup/SKILL.md:319`: skeptic per test file | coding | route | brief file carries the test file and candidates |
| testing:fix-failing | `plugins/testing/skills/fix-failing/context/fix-until-green.md:30`: fix-until-green workflow | coding | route | args carry the command, scope and rounds |
| testing:run-e2e | `plugins/testing/skills/run-e2e/SKILL.md:178`: launching and driving the app | web UI | keep | Claude must do it: the subagent drives through a skill on the Skill tool |
| testing:run-e2e | `plugins/testing/skills/run-e2e/context/map.md:72`: driving each feature-map entry | web UI | keep | Claude must do it: each subagent drives through a skill on the Skill tool |
| testing:write | `plugins/testing/skills/write/context/blind-author.md:21`: acceptance tests from the spec | coding | route | brief carries the criteria, interface and conventions |
| user-experience:evaluate | `plugins/user-experience/skills/evaluate/SKILL.md:39`: heuristic evaluation by `evaluator` | knowledge work | route | brief carries the artifact path and method |
| user-interface:audit | `plugins/user-interface/skills/audit/reference/launch-scope.md:98`: static UI audit sweeps per lane group | coding | route | prompt carries the lane files and recon facts |
| verification:confirm | `plugins/verification/skills/confirm/SKILL.md:146`: build, test and lint pass | coding | route | brief carries the changed files and command tables |
| verification:confirm | `plugins/verification/skills/confirm/SKILL.md:178`: live drive split across workers | web UI | keep | Claude must do it: each worker invokes a skill through the Skill tool |
| verification:confirm | `plugins/verification/skills/confirm/SKILL.md:199`: outcome verdict | coding | route | brief carries the criteria, diff and evidence path |
| wizard:generate | `plugins/wizard/skills/generate/SKILL.md:190`: review of the generated wizard script | coding | route | brief carries the script and values table |
| work-items:scan-todos | `plugins/work-items/skills/scan-todos/SKILL.md:39`: marker scan per repository | coding | route | brief carries the repository root and path |
| work-items:track | `plugins/work-items/skills/track/actions/due.md:84`: doc audit by the consumer's tooling | knowledge work | route | brief carries the docs and rules scope |
| work-items:work | `plugins/work-items/skills/work/SKILL.md:219`: scope-fenced implementation in its own worktree | coding | route | brief carries the item quoted as data, branch, scope and push command |
| work-items:work | `plugins/work-items/skills/work/SKILL.md:242`: PR owner driving CI and the review pass | coding | keep | Claude must do it: the owner runs the PR skills through the Skill tool |
| work-items:work | `plugins/work-items/skills/work/SKILL.md:242`: fix worker for failing checks and findings | coding | route | brief carries the worktree, checks, findings and push command |
| work-items:work | `plugins/work-items/skills/work/SKILL.md:270`: confirming bug reproduction captures | coding | route | brief carries the runs' commands, revisions and outputs |
| work-items:work | `plugins/work-items/skills/work/reference/ci-mode.md:122`: local review standing in for the CI lane | coding | route | brief carries the whole diff |
| writing:be-concise | `plugins/writing/skills/be-concise/SKILL.md:85`: semantic diff of a concise rewrite | knowledge work | route | brief carries the before and after text |

## Coverage

The search covered every `SKILL.md` and markdown file under `plugins/*/skills/`, matching `subagent`,
`sub-agent`, `Agent tool`, `subagent_type`, `fresh-context`, `dispatch`, `spawn`, `fork`,
`Workflow`, `agent(`, `run_in_background`, fan-out, reviewer, verifier and skeptic wording, and
named agent types. It leaves out:

- evals, fixtures, probe case prompts and probe records;
- vendored upstream copies and upstream source lists;
- playbook chapters that describe a practice without a step the skill runs;
- lines that state a rule about subagents without dispatching one;
- a step that only invokes another skill, which is listed where that skill spawns;
- a repeat of a listed delegation in a second file.
