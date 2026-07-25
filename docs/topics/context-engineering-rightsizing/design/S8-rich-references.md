# S8 — "Then: Simple specs / Now: Rich references"

Source span: `source-article.md:81-90`. Corroborating span used only in Conflicts: `source-article.md:111-114`.

## Claims

1. **Plan mode has relied on markdown plan files.**
   > "In plan mode, Claude Code has heavily relied on markdown files with plans. Storing these files as
   > plans helped Claude refer to them when needed." (`source-article.md:84`)

2. **Storing specs in the codebase is a (past) best practice for long projects.**
   > "Another similar best practice was to store specs in the codebase for Claude to refer to while
   > working across longer projects." (`source-article.md:84`)

3. **Claude now handles more complicated references than it used to.**
   > "But we've found that Claude can handle increasingly more complicated references."
   > (`source-article.md:86`)

4. **HTML artifacts replace simple markdown files as the reference medium.**
   > "Instead of simple markdown files, Claude can reference HTML artifacts created by our new
   > artifacts feature." (`source-article.md:86`)

5. **Code is a valid reference form; a detailed test suite can be a spec.**
   > "You may also give Claude references in the form of code. A spec may also be a detailed test
   > suite..." (`source-article.md:88`)

6. **A function in a different codebase can be a reference, for porting.**
   > "...or a function in a different codebase that Claude might port." (`source-article.md:88`)

7. **Rubrics are a form of reference.**
   > "Rubrics are another form of references." (`source-article.md:90`)

8. **Rubrics let Claude verify the operator's taste in a domain.**
   > "Rubrics allow Claude to try and verify your taste in a particular field (e.g. what does a good
   > API design look like)..." (`source-article.md:90`)

9. **The delivery mechanism for rubrics is dynamic workflows spinning up verifier agents.**
   > "...by using dynamic workflows and spinning up verifier agents with those rubrics."
   > (`source-article.md:90`)

## Evidence status

**1 — PARTIAL, and closer to refuted than the article implies.**
`https://code.claude.com/docs/en/permission-modes.md` describes plan mode as: "Claude reads files, runs
shell commands to explore, and writes a plan, but does not edit your source" and "Edits stay blocked
either way until you approve the plan." The plan is an in-session proposal — presented at an approval
dialog, openable in `$EDITOR` with `Ctrl+G`, discarded on `Shift+Tab` out. No current page describes plan
mode persisting a markdown plan file, and plan mode's own write block means it structurally *cannot*
write one before approval. The one documented persistence path is an ultraplan escape hatch:
"**Cancel**: save the plan to a file without executing it; Claude prints the file path so you can return
to it later" (`https://code.claude.com/docs/en/ultraplan.md`) — file format and location are not
documented, so "markdown file" is unverified even there. Verdict: the *practice* of markdown plan files
is real operator behavior (this repo has 12 of them), but the article attributes it to plan mode, and
current docs do not.

**2 — UNBACKED.** No page under `https://code.claude.com/docs/llms.txt` documents "store specs in the
codebase" as a Claude Code practice. `https://code.claude.com/docs/en/memory.md` and
`https://code.claude.com/docs/en/claude-directory.md` are the persistence surfaces the docs name, and
neither describes a spec-file convention. Legitimate author practice with no documented mechanism.

**3 — UNBACKED.** A model-capability claim. I checked the index at
`https://code.claude.com/docs/llms.txt` and the four pages closest to the subject
(`artifacts.md`, `workflows.md`, `memory.md` via the index, `permission-modes.md`); none makes a
comparative statement about reference-handling capability across model generations. Not checkable.

**4 — PARTIAL, and the framing is wrong (see Conflicts).**
`https://code.claude.com/docs/en/artifacts.md` confirms artifacts exist, are HTML pages published to a
private claude.ai URL, and are cross-session addressable: "To update an artifact from a different
session, give Claude the artifact's URL and ask it to revise." That is a documented **write-back** path,
not a documented read-as-reference path. The only *read* evidence available to me is harness
tool-description text, a lower evidence tier than a docs page: the `Artifact` tool's own description says
"To read an existing artifact's content: call WebFetch with its URL," and `WebFetch`'s description says
"claude.ai/code/artifact/{uuid} URLs ARE fetchable via your claude.ai login." Artifact-as-*input-spec* is
therefore mechanically possible but has no documentation behind it, and the docs explicitly frame an
artifact the other way: "An artifact is a capture of work, not an application."

**5 — UNBACKED as stated, ADJACENT-CONFIRMED in the article itself.** No official page says "a spec may
be a test suite." The nearest official support is indirect: `https://code.claude.com/docs/en/memory.md`
positions CLAUDE.md for project instructions, not specs. The article's own line 114 ("Generally you
should prefer files that are in code as it provides clear, high-fidelity instructions to Claude in a
language it knows very well") is the strongest support, and it is the same author, not an independent
source. Sound engineering advice; no documented mechanism required, because "point Claude at the test
file" needs none.

**6 — UNBACKED.** Same status as 5. I looked in `https://code.claude.com/docs/en/memory.md` and
`https://code.claude.com/docs/en/claude-directory.md` (the persistence and reference surfaces) and found
no cross-codebase reference convention. Nothing is needed: reading a function in another repo is ordinary
file reading, gated only by working-directory scope. **Not criteria-bearing** — it prescribes an operator
gesture at prompt time, leaves no artifact behind, and so has no repo surface to check. No criterion is
issued for it, deliberately.

**7 / 8 — UNBACKED.** I fetched `https://code.claude.com/docs/en/workflows.md` and
`https://code.claude.com/docs/en/sub-agents.md` (via the index) and grepped the workflows page: the words
"rubric", "grade", "score", and "criteria" do not appear. There is no rubric primitive, no rubric file
format, no rubric-binding parameter, and no documented convention for where a rubric lives. "Rubric" in
this article is a *technique name for a prompt payload*, not a Claude Code feature.

**9 — CONFIRMED for the mechanism, UNBACKED for the rubric binding.** `workflows.md` confirms every
structural piece: a dynamic workflow is "a JavaScript script that orchestrates subagents at scale";
`agent()` spawns one subagent and `pipeline()` runs one per item; the doc names the exact pattern —
"it can have independent agents adversarially review each other's findings before they're reported" —
and gives the prompt shape "adversarially verify each finding before reporting it." Verifier agents are
documented by name in the bundled `/deep-research` workflow: "when the verifier agents can't check a
claim... the report lists that claim as unverified instead of counting it as refuted." What is *not*
documented is any mechanism for handing those verifiers a rubric — that is just text in the prompt the
script writes.

**Plugin-form constraint (asked in the task, answered here).**
**A hosted artifact can be an operator-local planning reference only. It can never be a reference a
shipped plugin depends on.** The binding constraint is *not* the plugin cache rule — an artifact URL is
not a filesystem path, so `plugins-reference.md`'s "Installed plugins cannot reference files outside
their directory" does not decide it; a `SKILL.md` could legally embed a URL and WebFetch it. The chain
that actually kills it is entirely in `artifacts.md`:

- **Reachability.** Content "is visible only to authenticated members of the publishing organization,
  unless the artifact is shared publicly," and public sharing "is off by default on Team and Enterprise
  plans" pending an Owner toggle. A plugin installed by a third party is, by definition, outside the
  publishing org.
- **Auth.** Reading requires a claude.ai-backed session. "Sessions using an API key, gateway token, or
  cloud-provider credential cannot publish," and the surface is unavailable on Bedrock, Google Cloud's
  Agent Platform, and Microsoft Foundry, and "Off by default in Agent SDK, GitHub Action, and MCP-server
  contexts."
- **Mutability and expiry.** "Each publish becomes a version, and from the **Share** control in the page
  header you can choose which version viewers see" — there is no content-addressed pin, so a consumer
  cannot depend on a fixed revision. Owners can also "set how long artifacts are kept before automatic
  deletion."
- **Per-user disablement.** `disableArtifact`, `CLAUDE_CODE_DISABLE_ARTIFACT=1`, or `Artifact` in
  `permissions.deny`.

Even the operator-local use is auth-bound and expirable. Note the asymmetry with dynamic workflows: a
*workflow* **is** plugin-shippable — "Place the script in a `workflows/` directory at the plugin root...
Plugin workflows are namespaced by the plugin name" — so the mechanism side of claim 9 ships fine; only
the artifact side of claim 4 does not.

## Criteria

**C8.1 — A plan or spec artifact that is only ever read must not be treated as a plan-mode output.**
Surface: `docs/topics/*/PLAN.md` and any prose spec. Observable: the file is a durable repo artifact
authored by an operator workflow, not a plan-mode side effect; any doc, skill, or CLAUDE.md line that
claims plan mode writes or reads such a file fails. Must NOT flag: a skill that *instructs* Claude to
write a plan file itself (e.g. `planning:plan` persisting `PLAN.md`) — that is the skill writing it, and
is exactly what the docs leave to the operator.

**C8.2 — A prose document whose content is a set of executable behavioral assertions should be an
executable check, not prose.** Surface: `docs/*.md`, plugin `reference/*.md`. Observable: the document
records commands run and results observed, and carries a re-verify warning, but ships no runnable form —
i.e. its truth decays silently and nothing in CI detects the decay. Must NOT flag: an ADR
(`docs/adr/0001-*.md`, `0002-*.md`), whose content is a decision record with no executable form; or
`docs/OFFICIAL-DOCS.md`-style deliberate upstream URL pointers, which the user-global convention
explicitly keeps as URLs "so it never drifts."

**C8.3 — A rubric that no verifier ever runs against is dead weight and must be reported as such.**
Surface: `plugins/*/skills/*/evals/evals.json`, `plugins/*/skills/*/context/*rubric*.md`,
`plugins/*/skills/*/references/*rubric*.md`. Observable: the file states graded expectations, and no
script, workflow, CI job, or documented procedure consumes it as grading input. Pass requires a named
consumer. Must NOT flag: a rubric a *skill body* instructs Claude to apply inline during its own run
(e.g. `plugins/claude-ops/skills/changelog/context/classification-rubric.md`) — the skill is the
consumer, and progressive disclosure of a rubric into a skill run is a legitimate consumption path.

**C8.4 — A repeated fan-out with per-item verification should be a dynamic workflow, not a subagent
fan-out held in a context window.** Surface: agent definitions and orchestrating skills that spawn
N verifiers per run. Observable: the orchestration is (a) repeated across runs, (b) fans out per item
rather than per task, and (c) keeps intermediate per-item results in the orchestrator's context.
`workflows.md`'s comparison table makes this decidable: workflows keep intermediate results in "script
variables" and are "Resumable in the same session" at "Dozens to hundreds of agents per run," where
subagents put results in "Claude's context window," "Restart the turn" on interruption, and scale to
"A few delegated tasks per turn." Must NOT flag: a one-shot single-lens dispatch —
`plugins/review/skills/quality-gate/SKILL.md`, which by its own contrast "picks ONE lens per invocation"
(`plugins/review/skills/fanout/SKILL.md:20`) — where nothing is repeated and no per-item loop exists.

**C8.5 — An artifact may be a rendering surface, never a dependency.** Surface: any `SKILL.md`, agent
definition, hook, or plugin README. Observable: the component *publishes* an artifact and degrades when
the surface is absent → pass; the component *reads* an artifact URL, or requires one to exist, as an
input its behavior depends on → fail. Must NOT flag: `plugins/visualization/skills/visualize/SKILL.md:84`
("Artifact is heavily gated (plan, sign-in, provider, and version constraints; off ...)"),
`plugins/adhd/skills/clarify/SKILL.md:122-135`, or `plugins/planning/skills/interview/SKILL.md:56` —
all three already publish-and-degrade correctly.

**C8.6 — A criterion mentioning "artifact" must resolve the term before firing.** Surface: this repo's
own docs. Observable: `docs/PLUGIN-ARTIFACT-PROTOCOL.md` uses "artifact" to mean *lifecycle artifact*
(topic docs), and `plugins/playwright/skills/*/SKILL.md` uses it for a trace/screenshot output directory.
Neither is a claude.ai Artifact. Any S8 criterion that string-matches "artifact" and flags these is
wrong.

## Targets in this repo

All counts from commands run in `D:/repos/.worktrees/context-engineering-rightsizing`.

**Prose plans (claim 1/2).** 12 files, 4,353 lines.

```
find . -name "PLAN.md" -not -path "./.git/*"      # 12
wc -l docs/topics/*/PLAN.md                       # 4353 total
find docs/topics -name "*.md" \
  -not -path "*context-engineering-claude-5*" \
  -not -path "*fable-field-guide-audit*" | wc -l  # 36
```

**Prose design docs at `docs/` root (claim 5).** 10 files, 2,574 lines (`wc -l docs/*.md`). The sharpest
single target is `docs/extensibility-contract-smoke-tests.md` (163 lines): it is a transcript of manually
executed harness probes, and states at `docs/extensibility-contract-smoke-tests.md:8` "Run 2026-07-12
against Claude Code 2.1.207 on Windows. Re-verify fresh before relying on a result." That is a spec whose
correct form is a test suite — exactly claim 5 — and the repo already has the machinery: `ls scripts`
shows 12 `*.test.sh` files paired with their checkers, plus `scripts/run-plugin-tests.sh`. The tooling
layer already honors claim 5; the docs layer does not.

**Rubrics that exist but are never graded against (claims 7-9).** This is the load-bearing population.

```
find plugins -name "evals.json" | wc -l           # 155
find plugins -name SKILL.md | wc -l               # 187
# skills with no evals/evals.json                 # 32
# total eval cases across all files               # 843
# files where >=1 case carries expectations/assertions  # 150
# files with only the minimal (prompt-only) form        # 5
grep -ril rubric --include=*.md --include=*.json --include=*.js . \
  --exclude-dir=.git --exclude-dir=context-engineering-claude-5 \
  --exclude-dir=fable-field-guide-audit | wc -l   # 33
```

The `evals.json` format **is already a rubric**. `plugins/skill-quality/reference/evals.schema.json:57`
defines `expectations` as "objectively-verifiable expectations," and a real case
(`plugins/re-anchor/skills/tighten-your-output/evals/evals.json`) carries a prose `expected_output` plus
three graded `expectations` — that is a model-graded rubric in everything but name. 843 such cases exist.
And nothing runs them: `plugins/skill-quality/skills/check/SKILL.md:3` states the skill is "Not for:
writing new skills, or **running model-graded evals**," and `plugins/skill-quality/scripts/check-skill.sh:459-460`
only checks *presence* ("action-router-shaped skill with no evals/evals.json"). The repo validates rubric
*shape* and never grades against rubric *content*.

**Zero dynamic workflows (claim 9).**

```
find plugins -type d -name workflows | wc -l      # 0
grep -rl '"workflows"' --include=plugin.json .    # (no output)
ls .claude/                                       # settings.json  source-control.md — no workflows/
```

The only `workflows` directory in the tree is `.github/workflows` (GitHub Actions). Across 60 plugins
(`ls plugins | wc -l` → 60) and 187 skills, this marketplace ships **not one** dynamic workflow, despite
`workflows.md` documenting plugin distribution explicitly. Its fan-out runs through subagents instead:
`plugins/review/skills/fanout/SKILL.md` dispatches six leaf reviewer agents
(`ls plugins/review/agents` → `architecture-guardian.md`, `ci-log-auditor.md`, `code-reviewer.md`,
`doc-drift-detector.md`, `ecosystem-specialist.md`, `security-reviewer.md`) plus main-thread
orchestrators, then normalizes "their incomparable outputs into one severity-ranked report persisted to
disk" (`plugins/review/skills/fanout/SKILL.md:20`). That is the repo's clearest C8.4 candidate: a
repeated, per-surface fan-out with a normalization step, held entirely in a context window.

**Zero HTML in the tree (claim 4).** `find . -name "*.html" -not -path "./.git/*" -not -path "*/node_modules/*" | wc -l` → 0.
Artifacts appear only as an *output* medium, correctly gated, in three skills:
`plugins/visualization/skills/visualize/SKILL.md:70,84-90`, `plugins/adhd/skills/clarify/SKILL.md:118-135`,
`plugins/planning/skills/interview/SKILL.md:56`.

**Named gap.** `plugins/knowledge/skills/youtube-digest/extraction/evals/` is the one `evals` directory
with no `evals.json` (156 dirs, 155 files). It is not a defect: it holds executable JS checkers with
fixtures (`check-transcript-goldens.js`, `check-watch-outcomes.js`, and `.test.js` peers). It is the
repo's single existing instance of claim 5 applied to *skill output* rather than tooling — a spec that is
a test suite. It should be the model, not an anomaly.

### User-global scope (read-only; routed recommendations only)

I checked the three surfaces S8's criteria could reach. **S8 produces one routed recommendation and two
clean absences.**

```
ls ~/.claude/docs/          # 5 files
wc -l ~/.claude/docs/*.md   # 128 lines total
ls ~/.claude/workflows/     # No such file or directory
ls ~/.claude/skills/        # consult-fable/  (SKILL.md only, no evals/)
```

- **C8.2 (prose that should be executable) — no finding.** All five `~/.claude/docs/*.md` are reference
  prose about topology, layout, and paid-feature policy; three are 3-4 line pointer stubs. None records
  executed commands with observed results, so none has an executable form to convert to. Distinct from
  `docs/extensibility-contract-smoke-tests.md`, which does.
- **C8.3 (ungraded rubric) — no finding.** No rubric-shaped file exists at user-global scope.
- **C8.4 / claim 9 (workflows) — routed recommendation.** `~/.claude/workflows/` does not exist, so the
  operator has no personal workflow either. `workflows.md` names it as one of the two save locations
  ("`~/.claude/workflows/` in your home directory: available in every project, visible only to you"). If
  the grader from Open Question 3 is prototyped before it ships as a plugin workflow, this is where it
  lands — but note the user directory is chezmoi-managed, so a workflow saved there by `/workflows` → `s`
  becomes an untracked durable user-scope config and is a tracking candidate for the dotfiles
  `add-dotfile` flow. **Route: propose, do not create.**
- **Adjacent absence, out of S8's scope but worth naming:** `~/.claude/skills/consult-fable/` ships no
  `evals/`, mirroring the repo's 32-of-187 gap. Whatever grader gets built should be able to run against
  user-scope skills too, not just `plugins/**`.

## Conflicts and ambiguity

**1. Claim 4 is factually wrong against the docs it invokes.** "Instead of simple markdown files, Claude
can reference HTML artifacts" opposes markdown to artifacts. `artifacts.md` lists the publishable source
types as "`.html`, `.htm`, or `.md`" and adds "Markdown files render as styled HTML." Markdown is not
what artifacts replace; it is one of the two artifact formats. The real axis is *hosted and versioned*
vs *local file*, not *HTML* vs *markdown*, and the article names the wrong axis.

**2. Claim 4 contradicts claim 5, and the article's own line 114 sides with claim 5.** Line 86 elevates
hosted HTML artifacts; line 114 says "Generally you should prefer files that are in code as it provides
clear, high-fidelity instructions to Claude in a language it knows very well." A hosted artifact is the
least in-code reference available: not in the repo, not version-controlled with the code, not diffable,
not reviewable in a PR, auth-gated, and silently mutable. Where the two conflict the article gives no
tiebreak. For this repo the tiebreak is forced anyway by the plugin-form constraint above.

**3. The rubric/verifier pattern is *weaker* than what this repo's governing convention already
mandates.** `~/.claude/CLAUDE.md:30` (user-global, read-only to me) states the independence hierarchy:
"self-review (floor) < fresh same-vendor context < different-vendor model; use the strongest the
situation warrants," and requires "producer ≠ critic ≠ tester." A verifier subagent handed a rubric is
*fresh same-vendor context* — the middle rung. So adopting the article's pattern as written would be a
downgrade from the top of the ladder the operator already requires, and the repo already reaches that top
rung: `plugins/review/skills/fanout/SKILL.md:90` routes to "the OpenAI Codex plugin (`codex@openai-codex`)
as a different-model surface," reasoning that "its blind spots are uncorrelated with the same-vendor leaf
agents and Claude orchestrators, so a finding only Codex raises is signal the rest structurally cannot
see." The rubric is still a real gain, but for a different reason than the article gives: it makes the
*criteria* explicit and reusable, independent of who grades. Recommending it as an *independence* upgrade
would be wrong.

**4. The article conflates two primitives that `workflows.md` separates.** Claim 9 says "dynamic
workflows and spinning up verifier agents" as one thing. The doc's own comparison table makes them
distinct primitives with different tradeoffs, and this repo has already chosen subagents deliberately —
`plugins/review/skills/fanout/SKILL.md:86` requires its orchestrator surfaces to run "on the MAIN THREAD
(they fan out their own agents; a subagent cannot dependably do that)," a constraint that exists only
because the orchestration is held in a context window rather than in a script. A finding that says "adopt
dynamic workflows" without a per-case argument from the table's axes — repeatability, where intermediate
results live, resumability, scale — is not actionable.

**5. Claim 1 mis-attributes an operator practice to a harness feature.** Plan mode blocks edits until the
plan is approved; it cannot write a plan file. Every `PLAN.md` in this repo was written by a skill
(`planning:plan`) or by hand, after plan mode ended. This matters for remediation routing: nothing about
plan-file practice can be fixed by changing how plan mode is used, only by changing the skills that
write them.

**6. Claim 5 does not generalize to this repo's dominant artifact class.** "A spec may be a detailed test
suite" assumes the spec describes deterministic behavior. Most of this repo's 187 skills specify
*judgment* — when to fire, what to weigh, what to refuse. A test suite cannot express "does not fabricate
a standard that does not exist" (a real expectation at
`plugins/re-anchor/skills/tighten-your-output/evals/evals.json`). That is precisely the boundary where a
rubric beats a test suite, and the article never draws it. Applied naively, claim 5 would push judgment
skills toward brittle string assertions.

**7. "Verify your taste" (claim 8) has no failure semantics.** A test suite fails deterministically; a
rubric graded by a model produces a judgment that can itself be wrong. The article offers no
disagreement-handling story. `workflows.md` shows Anthropic hit this in `/deep-research` and resolved it
conservatively: "when the verifier agents can't check a claim... the report lists that claim as
unverified instead of counting it as refuted." Any rubric harness this repo builds needs that third
state — pass / fail / **could not verify** — and the article does not tell you so.

**8. Scope ambiguity in claim 7.** "Rubrics are another form of references" leaves open whether a rubric
is context loaded into the main session or a payload handed to an isolated grader. The two have opposite
context-cost profiles and opposite independence properties (loading a rubric into the producer's own
context destroys producer ≠ critic). The article's phrasing — a *reference* — implies the first; its
mechanism — verifier agents — implies the second. This repo's existing rubrics do both:
`plugins/claude-ops/skills/changelog/context/classification-rubric.md` is loaded into the producing run,
while `evals.json` is written for an external grader that does not exist.

## Open questions for the operator

1. **Should the rubric this effort builds be a new artifact, or should it grade the 843 eval cases that
   already exist?** RECOMMENDED: grade the existing ones. The rubric asset is already built and
   schema-validated; only the grader is missing. Building a parallel rubric would duplicate 155 files.

2. **Should the grader be a dynamic workflow or a subagent fan-out?** RECOMMENDED: a dynamic workflow, on
   the doc's own axes — 843 cases is a per-item loop far past the "a few delegated tasks per turn"
   subagent scale, results should stay in script variables rather than a context window, and the run must
   be resumable. It is also the only form that ships in a plugin (`workflows/` at plugin root).

3. **Does the grader ship as a plugin workflow, or stay operator-local?** RECOMMENDED: ship it. Unlike an
   artifact, a workflow is plugin-distributable and namespaced (`/plugin:name`), and grading skill quality
   is exactly this marketplace's subject matter.

4. **Does `docs/extensibility-contract-smoke-tests.md` become an executable suite?** RECOMMENDED: yes for
   the assertions that can run headlessly, no for the ones requiring an interactive install. Split it,
   rather than converting or keeping it whole. Flag: some probes require a throwaway marketplace and a
   real install, which CI may not tolerate.

5. **Do we adopt "could not verify" as a first-class grader outcome?** RECOMMENDED: yes — the bundled
   `/deep-research` workflow already does exactly this, and two-state grading will silently convert
   rate-limit failures into false negatives.

6. **Is a hosted artifact acceptable as an operator-local planning reference despite expiry and version
   mutability?** RECOMMENDED: yes for review surfaces and decision tables that die with the session
   (which is how `planning:interview` and `adhd:clarify` already use it), no for anything a later session
   must re-read. Nothing shipped may depend on one.

## Evidence-status tally

| Verdict | Claims | Count |
| :--- | :--- | :--- |
| CONFIRMED | — | 0 |
| PARTIAL | 1, 4 | 2 |
| SPLIT (mechanism CONFIRMED / rubric binding UNBACKED) | 9 | 1 |
| UNBACKED | 2, 3, 5, 6, 7, 8 | 6 |
| **Total** | | **9** |

No claim in this section is fully CONFIRMED. Claim 9 is counted separately rather than rounded up: the
orchestration machinery it names is documented in full, the rubric binding it depends on is not.

## Fence events

None. I did not read, list, grep, or reference `docs/topics/context-engineering-claude-5/**`,
`docs/topics/fable-field-guide-audit/**`, `.work/fable-field-guide-audit/**`, any other worktree, or any
other agent's file under `sections/`. Two deliberate avoidances: I never ran `ls docs/topics` (I used
`find` with explicit `-not -path` exclusions for the two fenced slugs), and I never listed `sections/`
(I used `mkdir -p sections` and wrote directly).
