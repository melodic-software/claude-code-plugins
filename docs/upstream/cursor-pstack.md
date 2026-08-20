# Upstream source — cursor/plugins (pstack)

Single source of truth for everything in this marketplace derived from
[cursor/plugins](https://github.com/cursor/plugins) — "Official Cursor plugins for popular developer
tools, frameworks, and SaaS products", MIT — and specifically its `pstack/skills/` collection.
Provenance lives HERE and in plugin CHANGELOGs, never in skill bodies, where it is agent-facing
noise. Content citations an agent actually uses are not provenance records and stay in place.

**Last audited upstream state:** `main@60c641e4`. Git history of this file records *when*; this line
records only *what was audited*.

**Recheck trigger:** a change to any `pstack/skills/<name>/SKILL.md` named in the attribution table
below — re-audit the affected row. The upstream publishes no release notes for this collection, so
the trigger is a file change rather than a release, and the audit is a diff against the pinned SHA.

**Adaptation posture.** Every entry here is a **reauthor**, not a fork and not a vendored baseline.
The substance is preserved where it earns its place, the wrapper is adapted to this marketplace's
own conventions, and the prose is rewritten. This is deliberately unlike
[`playbooks`](../../plugins/playbooks/README.md)'s boris pack, which vendors a verbatim upstream copy
precisely so drift can be detected against it.

Upstream targets Cursor. Three classes of upstream machinery therefore do not survive a port and are
dropped without further note in each row: hardcoded model identifiers (upstream names specific
models for investigator and synthesizer roles), Cursor-specific MCP discovery ("inspect the `mcps/`
directory Cursor exposes"), and Cursor transcript paths under `~/.cursor/`.

## Attribution table

| Upstream skill | Ours | Relation | What was taken / rejected |
|---|---|---|---|
| `why` | [`discovery:trace-intent`](../../plugins/discovery/skills/trace-intent/SKILL.md) | Derived | **Taken:** the core insight that intent lives outside the code and must be recovered from records rather than inferred from implementation; the parallel per-category investigation model; null results as first-class findings; the Sources Consulted coverage map with its per-category line format; the two-and-only-two valid skip reasons with "probably irrelevant" explicitly rejected; the output split across direct evidence / reasonable inference / competing hypotheses / gaps; the five confidence tiers, whose *names* survive intact (see below); the Preserve/Change/Avoid/Risk constraint handoff. **Renamed:** the axis is the **intent-evidence tier**, never "intent-confidence" — the tier measures inferential distance from an explicit statement of intent, and labelling that "confidence" conflates it with certainty, which ICD 203 forbids by directive. **Added:** a per-citation source-reliability note that annotates without routing, because every comparable scheme (ICD 203, GRADE, Admiralty AJP-2.1) separates evidence directness from source reliability and forbids merging them — without it a review comment by the change's author and a four-year-old wiki page are both `Direct`. **Departed deliberately — see below.** **Rejected:** the seven-category investigator roster (four categories have no seam in this marketplace, so they would emit an identical gap on every run forever — replaced by three shipped categories plus a documented adapter seam); the six vendor-named source playbooks (`linear.md`, `notion.md`, `datadog.md`, `sentry.md`, `slack.md`, `databricks.md`) and the ~25 vendor names inline, inverted to category-named surfaces carrying vendors only as illustrations, per the two-lane convention posture; the parent-side seven-way generic fan-out, replaced by the one purpose-built agent this plugin's architecture already uses. |
| `arena` | No skill. Four ideas folded into [`architecture:improve` Design-It-Twice](../../plugins/architecture/skills/improve/research/deepening/interface-design.md), [`prototype`'s shared discipline](../../plugins/prototype/context/discipline.md), and [`naming:name-it-better tournament`](../../plugins/naming/skills/name-it-better/SKILL.md) | Absorbed (skill omitted — see [below](#why-arena-ships-no-skill)) | **Taken:** the rejected-alternatives return field, which becomes a sixth part of the Design-It-Twice result schema and reuses the `rejected-reason` field name the candidate artifact already carries; the graft ledger — a hybrid must name what came from which design *and* what was left behind with its reason — landing both in Design-It-Twice's recommendation step and in prototype's when-done capture, whose rule 6 previously read "the answer is the only thing worth keeping" and whose step 6 deletes losing variants; the read-the-spread discipline, adapted rather than copied, because that fan-out assigns *orthogonal* constraints so shape-divergence is the designed null result and only convergence-anyway or assumption-divergence carries signal; and criterion pre-commitment in naming's tournament, restricted to *when* the rubric is fixed since *which* criteria apply is already owned by the consuming project. **Rejected — the skill itself.** See below. **Rejected — the secret rubric.** Naming's rubric is deliberately the consuming project's own declared standards, which are public by construction; withholding them would fight that design rather than improve it, and pre-commitment gets the same anti-retrofit property without the secrecy. **Adaptation notes:** upstream spawns candidates under `isolation: worktree`, rejected three times here with recorded reasoning (`sweep-all:451`, `discovery/agents/explorer.md:103`, `researcher.md:99` — "isolation and a disk-graded handoff are incompatible by construction"); and its judge must come from a different model family unconditionally, where all ~15 cross-vendor sites here state it presence-gated with a named fallback. Neither drove the omission; both would have needed adapting had the skill shipped. |
| `technical-writing` | [`docs-hygiene:write-for-humans`](../../plugins/docs-hygiene/skills/write-for-humans/SKILL.md) | Derived, re-posture | **Taken:** the four-layer model and the question each layer answers (mode / address / load / ambiguity); the Diátaxis mode picker with all four modes, the compass, "use it on one sentence too", and the don't-mix-split-and-link rule; the three always-rules (cut every word that does no work, use the short everyday word, write the real name and don't invent jargon); the "vary the rhythm" section, which is the sharpest thing in the upstream file — a document can obey every layer and still read machine-written, and *be specific over sterile* names the failure exactly; the address, load and ambiguity rule sets; the STE fidelity caveat, kept because it is why this ships a paraphrase rather than a claim of conformance; and the review checklist, minus two items. **Re-postured — the whole point of the port.** Upstream ships the four standards as house rules. Here they are a **named, replaceable default set**, applied only after a search for the consuming project's own declared guide comes back empty, with the fallback stated out loud. `PLUGIN-PHILOSOPHY.md:198-202` admits a shipped default "only when it is a good-practice value that cannot conflict in *any* repo the plugin drops into", and names Conventional Commits as the archetype of what fails that test; Google style, ASD-STE100 and Global English are that class. The draft plan carried its own disproof — a decision existed solely to delete two Global English punctuation rules because they already conflicted with this repository's measured em-dash ruling. Those rules are therefore **kept**, where a consumer's own guide disables them, rather than deleted for every consumer because one repository disagreed; `ai-slop`'s own charter states the principle ("a deliberate house style is config in the consuming repo, never a shipped-default change"). **Rejected — the commit-message and PR-body scope.** Upstream applies every layer except Diátaxis to them. Here `ai-slop:audit` already excludes commit messages and PR bodies from the markdown-prose regime, shape is owned by `source-control:commit`'s subject-convention ladder and the PR-body-sections convention, and both `write-for-*` skills scope to markdown *files*, which a commit message is not. **Rejected — review-checklist items 1 and 8.** Item 1 is scoped "only to document sets" (a cross-document audit) and item 8 demands verifying counts and regeneration commands (a verification action); either would smuggle an audit into a write-time skill. The count rule survives in the body as a writing rule. **Rejected — "add new offenders to unslop's abstract-metaphor rule".** That rule lives in `ai-slop`'s `reference/catalog.md`, which is a private surface under the encapsulation contract *and* CC BY-SA 4.0 material derived from a pinned Wikipedia revision; instructing a consumer to edit another plugin's internals fails on both counts. For the same reason the audit's counter-proposal to absorb the three sentence layers into that catalog was declined: it would contaminate an attributed corpus and falsify its drift claim. **Rejected — "indent code snippets with tabs".** A hard formatting convention that collides with a consuming repo's own linter config, by the same test that re-postured the rest. **Rejected — the worked example.** Upstream's is about its own `budget.mjs`; a substitute path from this repository would be the identical defect with a different string, and a consumer reading a path that does not exist in their tree is what `audit-noise` classifies as a ghost ref. Rewritten fully generic, labelled as placeholders. **Renamed:** `write-for-humans`, not `technical-writing` — the latter is a noun phrase and the grammar takes an imperative verb phrase. Bare `write` both collides (the leaf-name registry records `write bug-report,testing`) and under-specifies the reader, which is exactly when `PLUGIN-PHILOSOPHY.md:67` prescribes a hyphenated qualifier, so this is grammar-conformant rather than a new exception. **Upgraded:** upstream's four source stamps carry a fetch date and no recheck trigger; the drift convention bars a bare date, so each now carries a full four-part stamp. |
| `blast-radius` | [`review:quality-gate downstream`](../../plugins/review/skills/quality-gate/context/downstream.md) | Partial (scope adopted, mechanics rejected) | **Taken:** the scope, which is the only part that was genuinely missing — the whole review lane is diff-scoped and nothing in it looks outward (verified by reading: `architecture-guardian` stops at mapping changed files to layers, `code-reviewer` and `doc-drift-detector` carry no caller item, `fanout` fans across surfaces all diffing one merge-base, `mutation-testing:audit` is `git diff`-scoped by construction). Also taken: "listing the callers is not the job"; the where-grep-stops surfaces (library source and pinned version, serialization boundaries, timing and lifecycle, flag reach, cross-language readers); the confirmed-vs-cleared split as two deliverables; "a search that finds nothing is still an answer"; and the cheapest-test handback, strengthened into a presence-gated handoff to `/testing:write` + `/mutation-testing:audit`. **Rejected — the five-rung proof ladder.** It would be this fleet's *ninth* evidence ladder (severity's confidence axis, `improvement:find`'s evidence ladder, research source tiers, `codebase-health`'s verified/likely/needs-review, `repo-fleet-hygiene`'s confidence model, `trace-intent`'s intent-evidence tiers, fable-5's calibration grades and inference-distance rungs, mutation-testing's productive/equivalent/arid/unclassified). `discipline:reuse-or-replace` names that exactly: "leaving the established way in place and quietly adding a divergent way alongside it". The unverified-claim floor it encodes is kept, citing fable-5's verification chapter as owner. And this port's own departure argument condemns its bottom rung specifically — a rung that is cheapest to fill when the evidence is worst is a rung that will be filled. **Rejected — "the one fact it's safe because of" as the report's spine**, demoted to a first probe. As an organizing structure it makes secondary risks structurally invisible on any change with several independent ones, and this marketplace models change risk as multi-dimensional (`autonomy`'s work-classes names four risk properties; `devils-advocate` Round 4 sweeps ten operational categories precisely because assumption-driven rounds miss traps). **Rejected — a third axis in `review/context/severity.md`**, which its own Vocabulary section closes at two and which `context/spec.md` had already declined to widen; it is also a cross-plugin convention surface with a CI gate. **Rejected — the `arena` routing**, no such skill existing here. **Renamed:** `downstream`, not `impact` (generic, and already prose-loaded in four always-listed descriptions) and not `blast-radius` (a three-way collision), while the "blast radius" trigger phrases are carried deliberately rather than suppressed. |

### The one deliberate departure

**Upstream permits labelled code-shape inference; this port forbids it outright.** Upstream's
`Inferred` tier admits a claim built from the code's own shape as long as it is labelled — its
failure-mode entry says "*or is labeled as inference*", and the tier's second worked example reasons
from a function name, a literal `3`, and a codebase convention.

`/discovery:trace-intent` excludes code shape from the scale entirely and records it as a gap. The
argument is **operational, not epistemic**: code is the only evidence source that is always present
and costs nothing to consult, so a weak-but-admissible rung for it gets filled exactly when the real
record is thin — which is precisely when a reader most needs to be told the record is thin. A rung
that is cheapest to fill when the evidence is worst is a rung that will be filled.

Version-control *behaviour* is explicitly not code shape and remains admissible at `Inferred`.
Change coupling, churn and hotspot data are evidence the code alone cannot supply, but they locate a
relationship without explaining the decision behind it, so they never reach `Direct`.

## Not adopted (decided, with reasons)

Recorded so a later reader can see what was considered and declined, rather than assuming it was
overlooked. Entries are added as each lane resolves.

### Why `arena` ships no skill

Upstream's `arena` runs N candidate solutions in parallel for an arbitrary task, judges them against
a rubric, and grafts the winner. Four of its ideas were absorbed (see its row above). The runner
itself was not, and the reason is the Rule of Three, not distaste for the pattern.

**There is no second consumer.** Extraction needs one, and this marketplace has at most two
arguable candidates — not three. Every candidate-competition site here was read before the verdict
was formed:

- `naming:name-it-better` — ~3 blind generators from distinct lenses, plus independent judges in
  `tournament` mode.
- `architecture:improve` Design-It-Twice — 3–4 subagents under deliberately *orthogonal* design
  constraints; the parent compares and there is no judge at all.
- `prototype:explore-directions` — **no fan-out whatsoever.** It builds variants and a switcher and
  the human clicks through them. Counting it as a consumer of a fan-out-and-judge runner was a
  mistake in the original brief, corrected on inspection.

So two consumers, and they disagree about nearly everything a shared runner would have to fix:
blind generation versus orthogonally-constrained generation, independent judges versus no judge,
elimination rounds versus a single parent-side comparison. A skill extracted across that gap would
have to make all of it configurable, which is the architecture plugin's own deletion test failing:
deleting the shared shell would not concentrate complexity, it would only move it, since each caller
would still supply its own generators, its own rubric, and its own convergence rule. That is the
definition of a shallow module, and `MIGRATION-PLAYBOOK.md:1630-1636` names extraction without a
second consumer speculative generality outright.

**Every trigger it would claim is already taken.** A user asking for competing names reaches
`naming`; competing interfaces, `architecture:improve`; competing UI layouts,
`prototype:explore-directions`. A skill splits on distinct trigger vocabulary
(`MIGRATION-PLAYBOOK.md:27-33`), and `arena` has none of its own — it would sit in the always-listed
description budget as a permanently-paid context line competing with the three skills that would
actually run.

**The fleet's precedent for this exact upstream shape is absorb.**
[`mattpocock-skills-v12-map.md:22`](mattpocock-skills-v12-map.md) records `design-an-interface`
being folded into Design-It-Twice rather than shipped standalone — the same call, on a skill of the
same shape, from the same kind of upstream.

#### What omitting costs

Stated because a provenance record that only justifies itself is worthless:

1. **No general runner.** A user whose task is not a name, an interface, or a UI layout — "write
   this migration three ways and pick" — has `session-flow:orchestrate`'s posture, `boris`'s
   pattern vocabulary, and the `Workflow` tool, but nothing that runs the loop for them.
2. **No comparative judgment anywhere in the fleet.** This is the sharper loss. Every judging site
   surveyed here verifies *one* artifact against a standard; not one picks among N. `naming`'s
   tournament is the sole exception and it is locked to names. Absorbing the graft ledger and the
   rejected-shapes field improves how the two existing competitions *record* their outcome, but it
   does not give the fleet a way to choose between rival solutions in general.

**Recheck trigger:** a second real consumer asks for arbitrary-task fan-out. If that happens, the
thing to evaluate is the native `workflows/` slot — deterministic control flow over subagents is
exactly what it is for — not a skill. Re-running this decision as "should we add an `arena` skill"
would be re-asking the question that already has an answer.

### Why `bro` ships nothing at all

Upstream's `bro` is seven lines, two of them body: "Restate your last message. Stop using jargon and
speak coherently. State it more simply and concisely, like one human talking to another." No
mechanism, no procedure, no output contract.

It is the only lane in this port where the honest answer is that the file contains nothing this
marketplace lacks. The capability ships **twice**, on two different axes:
`education:explain` is the altitude drop, and its **empty argument already resolves to the previous
assistant response** by anaphora, with 'rephrase that' and 'explain simply' already among its
triggers; `discipline:wait-what` is the interjection-fired re-pitch. The brevity pressure that is
`bro`'s only distinguishing note — "more simply *and* concisely", where `explain` adds an analogy and
a handoff line — ships a third time as `discipline:tighten-your-output`. The routing between them is
already stated by name in `adhd:clarify`'s own description.

`wait-what` is in substance this fleet's `bro`, down to the naming shape: a user-typed interjection
whose typed phrase IS the mechanism. That is why it holds an individually argued entry on the
naming grammar's **closed** exception list. Shipping `bro` would require a second entry on that list
carrying the same argument, against a rule that states "a name class is never blanket-sanctioned".

Recorded at this length only so a later reader can see the file was read rather than skipped for
being short. Nothing was absorbed, and nothing is lost.

### Why `show-me-your-work` ships neither a skill nor a convention

Upstream keeps a reviewable **decision trail** for long or unattended work: one append-only TSV,
`ts | phase | decision | why | evidence | result`, local by default and committed when a reviewer
needs it, plus a `log.sh` helper, a self-audit of the log against the transcript, a mandatory
cross-model review, and a standing "Attention" section on every reply.

The lane opened proposing to absorb this into `session-flow:running-retro`. An adversarial audit
destroyed that premise correctly: `running-retro`'s ledger is **defect-shaped**
(`| # | Category | Finding | Evidence | Suggested route | New / carried |`, over five categories
that are all session-process problems), written by a **transcript-parsing subagent** after the fact,
in a file whose cumulative-chain identity lives in YAML frontmatter a TSV cannot carry — and the
skill "does not run builds, tests, or a code review", so it cannot produce a `result` cell at all.
Upstream's is decision-shaped, written by the **acting agent at decision time**. Two artifacts, not
one. Two further blockers: `session-flow/reference/topic-docs.md` states "session-flow never writes
the contract tier", and `docs/conventions/topic-docs/README.md` records `history.md`
("append-only decision log") as **deliberately absent** already.

The audit then argued the opposite verdict — ship a capture format that the fleet's **eight**
existing audit-trail surfaces route into — on the grounds that this marketplace built the *recovery*
half (`discovery:trace-intent`, whose own entry above notes that the prior art is all about capture
and none about recovery) and left capture unbuilt. **That count was checked surface by surface and
does not hold.** Only one is a decision trail:

| Surface | Is it a decision trail? |
|---|---|
| `implementation:implement-dispatch` `DEVIATIONS.md` | **Yes.** What was planned, what was done instead, why, blast radius — written by the acting agent at deviation time, "the deviation log is the escalation, reviewed at PR time" |
| `session-flow:handoff` §8 "Decisions already settled" / §9 "Approaches tried and abandoned" | Related, different shape. Same content, but synthesized once at pause time for the next session, not appended at decision time |
| `code-tidying:tidy`'s PR follow-up comment | No. A change inventory — tidying type, file, line range, LOC delta. No decision, no why, no result |
| `work-items:work-loop` `loop-state@2` | No. Counters and durable loop state |
| `work-items:work-loop` escalation record | No. A notification artifact on the governed `loop-lane/escalation-record@1` schema, wired to a `PostToolUse` hook seam; reshaping it would break that contract |
| `work-items:attend-queue` lane telemetry | No. One sentinel status comment per lane instance, **edited in place** rather than appended |
| `autonomy` transition telemetry | No. OTel spans, and its own contract says "the runner adds **no parallel schema**" |
| `autonomy` return-accounting | No. Its first line reads "capturing RETURN — **not activity**", and it forbids the agent from estimating either of its two fields |

One genuine adopter — two if `handoff` counts, and those two disagree about the thing a shared
format would have to fix: append-at-decision-time versus synthesize-at-pause-time. That is the same
condition that killed `arena` above, and the playbook names the result: extraction without a second
consumer is speculative generality. A marketplace convention with one adopter would be a shallow
module wearing an owner doc's clothes.

**So the trail's substance was absorbed into its one real consumer.** `implement-dispatch`'s
`DEVIATIONS.md` gains the append-only-and-supersede rule, evidence-as-a-pointer with the
committed-script preference, an explicit outcome that says `unverified` rather than reading as
settled, and the one-entry-is-one-decision crispness rule. **Taken separately, and the highest-value
single item in the file: the formula-injection guard.** Upstream's `log.sh` prefixes any cell opening
with `=`, `+`, `-`, or `@` so a spreadsheet cannot execute it. That guard was absent fleet-wide, and
looking for somewhere to apply it found a live exposure rather than a hypothetical one —
`claude-ops:audit-install-state` wrote scanned `relpath` values raw through `csv.writer` into an
artifact the skill tells the reader to open file by file, and a plugin, project, or worktree
directory under `~/.claude` may be named anything. Fixed, with a discriminating test.

**Rejected:** the mandatory different-model-family review of the trail — the same unconditional
cross-vendor demand rejected for `arena`, against ~15 sites that all state it presence-gated with a
named fallback. **Rejected:** the standing "Attention section on every reply" — a session-wide
output posture is a declared species here with exactly one member (`adhd:shape`), and a second needs
its own argument plus the observed-stumble evidence the instruction-economy rule demands.
**Rejected as a duplicate:** the log-versus-transcript self-audit, whose discipline already ships
verbatim in two lanes ("Ground every claim in the cycle report against a tool result from this
cycle, and say which work is unverified rather than omitting the distinction" —
`work-items:work-loop` and `source-control:babysit-loop`); the absorb cites that rule rather than
restating it a third time.

**Recheck trigger:** a second surface starts appending decisions at decision time — not a status
comment, not counters, not telemetry. At two genuine consumers that agree on shape, re-evaluate an
owner doc under `docs/conventions/`; the classification table above is the baseline to diff against.

### What `code-tidying`'s docs-prose lane deliberately did not gain

`plugins/code-tidying/skills/tidy/lanes/docs-prose.md` already mutates `docs/**.md` and `README.md`
prose under six watch-for patterns, and already lists `diataxis.fr` among its preferred research
sources. Adding Diátaxis, Google-style, or Global-English watch-for patterns to it was considered
and declined: that lane *mutates*, and it has no mechanism for resolving the consuming project's
declared style guide — so style watch-fors there would enforce a guide the lane cannot know the
project rejected, which is the exact failure the `write-for-humans` port was re-postured to avoid.
The lane keeps its structural patterns; the style question stays with the write-time skill, where
the resolve step lives.

*(Lanes 5–10 of the pstack port have not yet been decided; this section fills as they land.)*

## Method provenance, for the record

Worth stating because it changes how much of `why` is genuinely upstream's invention: it is not. Five
of its six operating principles — evidence before narrative, cite everything, surface contradictions,
name the gaps, hedge on purpose — restate historiographical source criticism and intelligence-community
analytic tradecraft closely. Its genuine contribution is the *substrate*: applying that discipline to
software's own historical record, at a moment when all the adjacent prior art (ADRs, IBIS, QOC, DRL,
the design-rationale-capture literature) is about **capture** — writing rationale down at decision
time — and none is about **recovery** when nobody did.

That framing is what the port keeps. The tier vocabulary was compared against ICD 203's words of
estimative probability, GRADE's certainty levels, and the Admiralty code, and none is a substitute:
each measures a different axis (likelihood, certainty in an effect estimate, source quality), so
adopting one would have imported a scale that does not answer the question being asked.
