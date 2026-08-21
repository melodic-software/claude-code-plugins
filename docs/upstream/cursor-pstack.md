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
| `recall` | No skill, no absorb — see [below](#recall--omitted-and-it-absorbed-nothing) | Omitted | **Taken:** nothing. **Rejected — the skill:** `session-flow` ships four incumbents on this axis (`orient`, `find-handoff`, `reanchor`, `reconcile`) and `orient` owns the trigger vocabulary. **Rejected — the closed status-tag set:** duplicates the explicitly-closed two-axis vocabulary in `source-control/skills/worktree/context/status.md`, which `reanchor` already routes to. **Rejected — "cut detail before you cut threads":** stated twice already by `session-flow:show-options`, in the same plugin. **Rejected — the scope-restatement rule:** genuinely novel, declined on the instruction-economy gate for want of observed stumble evidence. **Rejected — the cross-workspace privacy rule:** `find-handoff` scans across repos deliberately, on request. |
| `teach` | Two rules in [`education:teach`'s lesson contract](../../plugins/education/skills/teach/context/lessons.md) — see [below](#teach--absorbed-into-the-lesson-contract) | Absorbed (skill omitted) | **Taken:** the build-up diagram series (for three or more moving parts, a short series where each picture redraws the last and adds one part, never one all-at-once diagram); and "a list of names is reference, not teaching". Both verified absent fleet-wide before landing. **Re-homed on audit:** the plan put the first in `visualization:visualize` (which declares itself a form-and-medium router that "is not a craft teacher") and the second in `education:explain` (an ELI5 drop that never lists functions); both moved to the lesson contract, which is what actually degenerates into a reference dump. **Rejected — the `how` + `why` composition:** this marketplace has no `how`, and extracting one without a second consumer is speculative generality. **Rejected — the anti-pacing-theater list:** nothing bans it, but `explain` has no register section and there is no stumble evidence. **Rejected — the spatial-idea / image-generation branch:** a real gap in `visualize`'s decision matrix, but this harness ships no image-generation tool. **Rejected — the voice paragraph:** ~80% owned by `docs-hygiene:write-for-humans`, and it carries the same "No em dashes" rule that lane declined. |
| `tdd` | Two rules: [`testing:write`'s decline list](../../plugins/testing/skills/write/context/write.md) and [`debugging:debug` phase 5](../../plugins/debugging/skills/debug/SKILL.md) — see [below](#tdd--absorbed-as-two-rules-in-two-different-plugins) | Absorbed (skill omitted) | **Taken:** the cost branch — six impracticality triggers (broad harness setup, brittle mocks, slow end-to-end infrastructure, production-only state, an unstatable reproduction, large fixture churn) plus "prefer no new test to a bad one" and the requirement to name the substitute check; and "confirm it fails for the intended reason", the one part of the seven-step workflow with no counterpart. **Re-homed on audit:** the plan put both in `debug`; `testing:write`'s "When NOT to write tests" is the incumbent for the cost concern and a second decline list there would split it. **Rejected — the skill:** its own description says to "use only when the user explicitly asks", which cannot earn an always-listed line. **Rejected — the five-item bad-test definition:** `tdd:principles` sources this from Khorikov and `testing:audit` enforces it deterministically. **Rejected — the anti-test-gaming guardrails:** already verbatim in `implementation:implement`. **Rejected — "do not silently skip the regression step":** `debug` phases 5 and 6 already say it. **Rejected — the evidence-shaped report:** marginal; phase 6 already requires the hypothesis and an independent verdict. |
| `reflect` | One routing fix in [`running-retro`](../../plugins/session-flow/skills/running-retro/SKILL.md) and [`retro`](../../plugins/session-flow/skills/retro/context/session.md) — see [below](#reflect--omitted-one-routing-gap-closed) | Absorbed (skill omitted) | **Taken:** routing an accepted learning by edit size, narrowed to the one part that was missing — an accepted new-skill candidate now goes to `/playbooks:skill-authoring` gated on `/skill-quality:check`, presence-gated with a stated fallback, in BOTH retro skills. **Widened on audit:** the plan scoped it to `running-retro` because "`retro`'s five dimensions are closed", a non-sequitur — `retro` closes its scoring dimensions, not the analysis that produces candidates. **Rejected — the skill:** `retro` and `running-retro` own the axis and `reflect` claims no unclaimed trigger. **Rejected — the structural-enforcement check:** `claude-config:audit-automation-gaps` owns it with a default-REJECT posture. **Rejected — the Accepted/Rejected/Backlog gate:** stated twice already, and upstream's version auto-files backlog items where `running-retro` forbids it. **Rejected — "the skill didn't trigger" as a finding class:** owned by `discipline:use-your-skills`. **Rejected — the three orthogonal lenses:** the strongest dissent in this port, recorded below rather than smoothed over. |
| `arena` | No skill. Four ideas folded into [`architecture:improve` Design-It-Twice](../../plugins/architecture/skills/improve/research/deepening/interface-design.md), [`prototype`'s shared discipline](../../plugins/prototype/context/discipline.md), and [`naming:name-it-better tournament`](../../plugins/naming/skills/name-it-better/SKILL.md) | Absorbed (skill omitted — see [below](#why-arena-ships-no-skill)) | **Taken:** the rejected-alternatives return field, which becomes a sixth part of the Design-It-Twice result schema and reuses the `rejected-reason` field name the candidate artifact already carries; the graft ledger — a hybrid must name what came from which design *and* what was left behind with its reason — landing both in Design-It-Twice's recommendation step and in prototype's when-done capture, whose rule 6 previously read "the answer is the only thing worth keeping" and whose step 6 deletes losing variants; the read-the-spread discipline, adapted rather than copied, because that fan-out assigns *orthogonal* constraints so shape-divergence is the designed null result and only convergence-anyway or assumption-divergence carries signal; and criterion pre-commitment in naming's tournament, restricted to *when* the rubric is fixed since *which* criteria apply is already owned by the consuming project. **Rejected — the skill itself.** See below. **Rejected — the secret rubric.** Naming's rubric is deliberately the consuming project's own declared standards, which are public by construction; withholding them would fight that design rather than improve it, and pre-commitment gets the same anti-retrofit property without the secrecy. **Adaptation notes, corrected on verification.** An earlier draft of this row overstated both, and the corrections are recorded rather than quietly swapped. (1) Upstream does **not** set a subagent `isolation:` — the word never appears in its file. It assigns each candidate an output path, "a git worktree where possible, otherwise `/tmp/arena-<slug>/candidate-<n>/`", to avoid N candidates writing to one path. That is a different mechanism from the `isolation: worktree` frontmatter this fleet has declined three times (`sweep-all:451`, `discovery/agents/explorer.md:103`, `researcher.md:99` — "isolation and a disk-graded handoff are incompatible by construction"), so those rejections are not actually in conflict with it. (2) Its judge instruction is "**Prefer** a different model family from the parent's" — a preference, not the unconditional demand the earlier draft claimed; `must` appears zero times in the upstream file. That is compatible with this fleet's presence-gated-with-a-named-fallback posture rather than opposed to it. The unconditional version belongs to `show-me-your-work`, below, and the two lanes should not be conflated. Neither note bears on the omission, which rests on the Rule of Three alone. |
| `technical-writing` | [`docs-hygiene:write-for-humans`](../../plugins/docs-hygiene/skills/write-for-humans/SKILL.md) | Derived, re-posture | **Taken:** the four-layer model and the question each layer answers (mode / address / load / ambiguity); the Diátaxis mode picker with all four modes, the compass, "use it on one sentence too", and the don't-mix-split-and-link rule; upstream's three above-the-layers rules (cut every word that does no work; use the short everyday word; when a rule makes a sentence worse, fix the sentence another way or leave it alone) — our third always-rule, write the real name and do not invent jargon, is drawn from upstream's separate word-list and anti-jargon paragraphs rather than from that trio; the "vary the rhythm" section, which is the sharpest thing in the upstream file — a document can obey every layer and still read machine-written, and *be specific over sterile* names the failure exactly; the address, load and ambiguity rule sets; the STE fidelity caveat, kept because it is why this ships a paraphrase rather than a claim of conformance; and the review checklist, minus two items. **Re-postured — the whole point of the port.** Upstream ships the four standards as house rules. Here they are a **named, replaceable default set**, applied only after a search for the consuming project's own declared guide comes back empty, with the fallback stated out loud. `PLUGIN-PHILOSOPHY.md:198-202` admits a shipped default "only when it is a good-practice value that cannot conflict in *any* repo the plugin drops into", and names Conventional Commits as the archetype of what fails that test; Google style, ASD-STE100 and Global English are that class. The draft plan carried its own disproof — a decision existed solely to delete two Global English punctuation rules because they already conflicted with this repository's measured em-dash ruling. Those rules are therefore **kept**, where a consumer's own guide disables them, rather than deleted for every consumer because one repository disagreed; `ai-slop`'s own charter states the principle ("a deliberate house style is config in the consuming repo, never a shipped-default change"). **Rejected — the commit-message and PR-body scope.** Upstream applies every layer except Diátaxis to them. Here `ai-slop:audit` already excludes commit messages and PR bodies from the markdown-prose regime, shape is owned by `source-control:commit`'s subject-convention ladder and the PR-body-sections convention, and both `write-for-*` skills scope to markdown *files*, which a commit message is not. **Rejected — review-checklist items 1 and 8.** Item 1 is scoped "only to document sets" (a cross-document audit) and item 8 demands verifying counts and regeneration commands (a verification action); either would smuggle an audit into a write-time skill. The count rule survives in the body as a writing rule. **Rejected — "add new offenders to unslop's abstract-metaphor rule".** That rule lives in `ai-slop`'s `skills/audit/reference/catalog.md`, which is a private surface under the encapsulation contract *and* CC BY-SA 4.0 material derived from a pinned Wikipedia revision; instructing a consumer to edit another plugin's internals fails on both counts. For the same reason the audit's counter-proposal to absorb the three sentence layers into that catalog was declined: it would contaminate an attributed corpus and falsify its drift claim. **Rejected — "indent code snippets with tabs".** A hard formatting convention that collides with a consuming repo's own linter config, by the same test that re-postured the rest. **Rejected — the worked example.** Upstream's is about its own `budget.mjs`; a substitute path from this repository would be the identical defect with a different string, and a consumer reading a path that does not exist in their tree is what `audit-noise` classifies as a ghost ref. Rewritten fully generic, labelled as placeholders. **Renamed:** `write-for-humans`, not `technical-writing` — the latter is a noun phrase and the grammar takes an imperative verb phrase. Bare `write` both collides (the leaf-name registry records `write bug-report,testing`) and under-specifies the reader, which is exactly when `PLUGIN-PHILOSOPHY.md:67` prescribes a hyphenated qualifier, so this is grammar-conformant rather than a new exception. **Upgraded:** upstream's four source stamps carry a fetch date and no recheck trigger; the drift convention bars a bare date, so each now carries a full four-part stamp. |
| `blast-radius` | [`review:quality-gate downstream`](../../plugins/review/skills/quality-gate/context/downstream.md) | Partial (scope adopted, mechanics rejected) | **Taken:** the scope, which is the only part that was genuinely missing — the whole review lane is diff-scoped and nothing in it looks outward (verified by reading: `architecture-guardian` stops at mapping changed files to layers, `code-reviewer` and `doc-drift-detector` carry no caller item, `fanout` fans across surfaces all diffing one merge-base, `mutation-testing:audit` is `git diff`-scoped by construction). Also taken: "listing the callers is not the job"; the where-grep-stops surfaces (library source and pinned version, serialization boundaries, timing and lifecycle, flag reach, cross-language readers); the confirmed-vs-cleared split as two deliverables; "a search that finds nothing is still an answer"; and the cheapest-test handback, strengthened into a presence-gated handoff to `/testing:write` + `/mutation-testing:audit`. **Rejected — the five-rung proof ladder.** It would be this fleet's *ninth* evidence ladder (severity's confidence axis, `improvement:find`'s evidence ladder, research source tiers, `codebase-health`'s verified/likely/needs-review, `repo-fleet-hygiene`'s confidence model, `trace-intent`'s intent-evidence tiers, fable-5's calibration grades and inference-distance rungs, mutation-testing's productive/equivalent/arid/unclassified). `discipline:reuse-or-replace` names that exactly: "leaving the established way in place and quietly adding a divergent way alongside it". The unverified-claim floor it encodes is kept, citing fable-5's verification chapter as owner. And this port's own departure argument condemns its bottom rung specifically — a rung that is cheapest to fill when the evidence is worst is a rung that will be filled. **Rejected — "the one fact it's safe because of" as the report's spine**, demoted to a first probe. As an organizing structure it makes secondary risks structurally invisible on any change with several independent ones, and this marketplace models change risk as multi-dimensional (`autonomy`'s work-classes names four risk properties; `devils-advocate` Round 4 sweeps ten operational categories precisely because assumption-driven rounds miss traps). **Rejected — a third axis in `review/context/severity.md`**, which its own Vocabulary section closes at two and which `review/skills/quality-gate/context/spec.md` had already declined to widen; it is also a cross-plugin convention surface with a CI gate. **Rejected — the `arena` routing**, no such skill existing here. **Renamed:** `downstream`, not `impact` (generic, and already prose-loaded in six always-listed descriptions (`ai-slop:audit`, `architecture:improve`, `claude-ops:changelog`, `docs-hygiene:rename-references`, `improvement:find`, `work-items:work`)) and not `blast-radius` (a three-way collision), while the "blast radius" trigger phrases are carried deliberately rather than suppressed. |
| `unslop` | [`ai-slop:audit`'s tell catalog, "Cursor unslop additions"](../../plugins/ai-slop/skills/audit/reference/catalog.md) and [`reference/rewrite-guide.md`](../../plugins/ai-slop/skills/audit/reference/rewrite-guide.md), in [`ai-slop` 0.2.0](../../plugins/ai-slop/CHANGELOG.md) | Absorbed (skill omitted) | **Landed before this record** — derived at `ai-slop` 0.2.0 on 2026-08-19 (`reference/catalog.md`, "Second pass"), so this file's git history dates the *row*, not the derivation — and so it is not one of the ten lanes decided below; the row exists because the collection's attribution is incomplete without it, and because the recheck trigger above reaches only the rows this table names. **No skill:** `ai-slop:audit` already owned the axis over a Wikipedia-derived tell inventory and already shipped the detect-then-guarded-fix flow upstream's four-step process describes, so the port lands as entries in an existing catalog rather than as a skill; the `unslop this` trigger phrase is carried in that skill's description rather than suppressed. **Taken:** the seven patterns the Wikipedia inventory did not already carry — three script rules (`rule-chatbot-artifacts`, which merges upstream's separate chatbot-phrase and sycophantic-tone patterns and argues IMPORTANT in the [detector-findings crosswalk](../conventions/detector-findings/README.md); `rule-filler-phrases` and `rule-stacked-hedging`, both SUGGESTION) and four rubric tells (`rule-false-ranges`, `rule-colon-crutch`, `rule-abstract-metaphor-jargon`, `rule-mechanism-free-claims`); the plain-word trio `utilize` / `leverage` / `facilitate` into the shipped AI-vocabulary default, density-gated and measured quiet on the calibration corpus, so the shipped default stays neutral while saturated files still flag; and the upstream file's fix-time half, which a catalog that only decides *what flags* had nowhere to put — it becomes `reference/rewrite-guide.md`, carrying the plain-speech rewrites, the substitution guardrail (an em dash becomes a period or a comma, never a parenthesis, an en dash, or a spaced hyphen, because swapping one tell for another is not a fix), and the closing self-audit pass. **Deduplicated rather than absorbed:** every remaining upstream pattern already had a Wikipedia-derived entry, and the catalog records that in an overlap map accounting for all of them. The map says **catalogued by**, deliberately weaker than "covered by": a row pointing at a `recorded-only` entry says so, and `rule-bold-overuse`, `rule-inline-header-lists` and `rule-title-case` are each catalogued and dormant, so nothing runs them in either layer — and upstream's own carve-out for a bold lead-in that ends in a period and introduces genuinely new detail is recorded on `rule-inline-header-lists` as calibration pre-work, not as a live boundary. **Rejected — Name-dropping**, deliberately out of scope for general prose: the Wikipedia-specific form is `rule-canned-notability`, whose entry says there is no general-prose analogue worth a rule. **Rejected — the general half of Generic conclusions.** Only the formulaic closer that `rule-challenges-conclusion`'s pattern actually matches is detected; a bare optimism line matches no shipped rule, and the overlap map records that rather than papering over it. **Rejected as a script rule — abstract metaphor nouns.** Upstream ships a word list; calibrated against this marketplace's corpus, "substrate" alone measured 114 legitimate technical uses, so the tell stays rubric, where the literal-versus-metaphor call has a reader. **Rejected — "let some mess in".** Five of the six adding-soul bullets survive as the rewrite guide's Adding voice section; that one does not, and the section is bounded twice over — by document register (never API reference tables) and by the fix flow's meaning-preservation guard, so voice changes how a kept claim is phrased and never invents one. **Adaptation note:** upstream's description ends "Must always apply"; the additions inherited the incumbent's posture instead — triggered, read-only by default, rewriting only when `fix` is passed as an explicit argument. **Not audited at the pin above.** This verdict was formed at integration time against upstream `main` with no revision recorded — the catalog and the rewrite guide both cite an unpinned blob URL, and the catalog's own four-part drift record covers the Wikipedia source page only — so `main@60c641e4` is this row's baseline for the next diff, not the state it was audited at. |

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

### `recall` — omitted, and it absorbed nothing

Upstream rebuilds a user's recent working context: fan out over chat transcripts, sweep the shared
record, verify against live `git`/`gh` state, and return a four-part brief (Capsule, Threads with a
closed status tag each, Problems, Next move).

`session-flow` ships four skills on this axis — `orient` (which owns 'catch me up' and
'where do we stand'), `find-handoff`, `reanchor` (upstream's verify-against-live-state step), and
`reconcile` — so no new skill was ever warranted. What makes this lane worth recording is that all
three of its proposed **absorbs** also failed, each to a different rule:

- **The closed status-tag set** duplicates one that already ships.
  `source-control/skills/worktree/context/status.md` defines a two-axis closed vocabulary,
  explicitly closed, and four of upstream's six tags map straight onto it (`[merged #N]`→`merged`,
  `[open PR #N]`→`in-review`, `[in flight <branch>]`→`active`,
  `[verified, uncommitted]`→`dirty`). `session-flow:reanchor` already routes this inventory there. A
  second, differently-worded closed vocabulary is exactly the silent second way
  `discipline:reuse-or-replace` names.
- **"Cut detail before you cut threads"** is already stated twice in the same plugin, by
  `session-flow:show-options` ("a design that ranks-then-truncates reintroduces the same gatekeeping
  through the cutoff"), which routes to `orient`.
- **"Never quietly turn 'all' into 'recent N'"** is genuinely novel — `orient` has no scope-lock
  step — and was still declined. `PLUGIN-PHILOSOPHY.md:574-578` admits a new standing instruction
  only on observed, repeated stumble evidence against the current model, named where the instruction
  is added. The only evidence available was that upstream says so.

Upstream's cross-workspace privacy rule ("never read another project's transcripts without being
asked") was considered separately and also declined: `find-handoff` scans `~/.claude/projects/*/`
across repos *deliberately*, because a lost session may have run in a different repo, and the user
invoking it has asked for exactly that.

**What omitting costs.** `orient` reads durable state, not chat history. A user whose context lives
only in past conversations — no handoff, no ledger, no branch — gets less than upstream's `recall`
would give them, and `find-handoff` covers only the narrower case of a save-point written and lost.

**Recheck trigger:** a repeated, observed failure where a session's context could not be rebuilt
because nothing durable was written. That is the stumble evidence the scope-lock rule and any
transcript-mining step both currently lack.

### `teach` — absorbed into the lesson contract

Upstream explains a body of work plainly by composing its `how` and `why` skills. That composition
does not port — this marketplace has no `how` (`discovery:explore` covers "how does this work", and
extracting one without a second consumer is speculative generality), and its `why` is
`discovery:trace-intent`, above. `education:teach` and `education:explain` already claim the trigger
vocabulary between them, so no third skill.

Two mechanics were genuinely absent and are now in `education:teach`'s lesson contract:

- **Build the diagram up; never open with the finished one.** For three or more moving parts, draw a
  short series where each picture redraws the last and adds one part. Verified absent across all of
  `plugins/` before landing.
- **A list of names is reference, not teaching.** Enumerating functions and constants produces
  something shaped like a lesson that teaches nothing.

**Both were re-homed on audit.** The plan put the diagram rule in `visualization:visualize` on the
theory that "one diagram or a series" is a form decision. It is not: `visualize` declares itself a
form-and-medium router that "is not a craft teacher" and does not do comprehension work, and the
rule is comprehension-driven by upstream's own words ("a single all-at-once diagram is a reference,
not teaching"). The plan put the second rule in `education:explain`, which is an ELI5 altitude drop
that never lists functions; the Teach/Practice/Go-deeper lesson unit is what actually degenerates
into a reference dump.

**Rejected — the anti-pacing-theater list** (don't print "Pause", don't ask the learner to say it
back, don't print framing labels like "the key insight" or "TL;DR"). Nothing bans these, but
`education:explain` has no register section to host them, and a new standing instruction with no
stumble evidence fails the instruction-economy gate. Worth recording that the plan's supporting grep
was broken — it used `\|` without `-E`, so it searched for a literal string and found nothing, where
the real corpus has 14+ hits.

**Rejected — the spatial-idea branch**, which routes an idea like layout or scroll position to an
image-generation tool. `visualization`'s decision matrix has no generated-image row at all, so this
is a real gap; but this harness ships no image-generation tool, and a medium row pointing at one
would be non-portable. Verified by reading the matrix.

**Rejected — the voice paragraph.** Roughly 80% is already owned by `docs-hygiene:write-for-humans`'
sentence rules, and it carries the same "No em dashes" rule that lane declined against this
repository's measured ruling.

**Note for the record:** our `education:teach` and upstream's `teach` are in direct opposition, not
merely different. Ours coaches — "ask ONE question at a time", "questions before answers", quizzes —
and upstream forbids exactly that ("No quizzes… don't ask them to say it back"). The absorbs are the
two mechanics that survive that opposition.

### `tdd` — absorbed as two rules, in two different plugins

Upstream is not a TDD skill; it is a bugfix gate, and its own description says to use it "only when
the user explicitly asks". That cannot earn an always-listed description line, and `tdd` is a
noun/acronym that is not on the naming grammar's closed exception list. `debugging:debug` phase 5 is
literally "fix + regression test" — the same moment.

Most of the file is owned twice over. The five-item bad-test definition is a weaker restatement of
what `tdd:principles` sources from Khorikov's four pillars and anti-patterns, and what
`testing:audit` enforces deterministically behind a fail-closed gate. The anti-test-gaming
guardrails are already stated verbatim in `implementation:implement` ("never hardcode the test's
expected values, special-case its inputs, or weaken an assertion"). And "do not silently skip the
regression step" is already `debug`'s own rule: phase 5 says of an absent seam that "that
itself is the finding", and phase 6 requires "regression test passes (or absence of correct
seam is documented as an architectural finding)".

Two things survived that:

- **The cost branch → `testing:write`'s "When NOT to write tests".** That list covered code needing
  no test; upstream's covers a test not worth writing — broad harness setup, brittle mocks, slow
  end-to-end infrastructure, production-only state, an unstatable reproduction, large fixture churn.
  Different axis, verified by reading both. Declining now requires naming the trigger and the
  substitute check, which matches the no-silent-skip doctrine this repo already enforces in CI.
- **"Red for the right reason" → `debug` phase 5.** Step 2 said "Watch it fail (Red)" and stopped. A
  test that errors on a typo or an unrelated defect is also red, and the fix that turns it green has
  not touched the bug.

**Re-homed on audit.** The plan put both in `debug`; `testing:write`'s decline list is the incumbent
for the cost concern, and a second decline list in `debug` would have split it. The evidence-shaped
final report was dropped as marginal — `debug` phase 6 already requires the correct hypothesis in
the commit message and an independent outcome verdict.

### `reflect` — omitted; one routing gap closed

Upstream mines the transcript through three orthogonal review lenses, synthesizes into
Accepted/Rejected/Backlog, demotes anything a lint rule would enforce better, gates on human
approval, then routes each accepted edit by size. `session-flow:retro` and
`session-flow:running-retro` own this axis, and `reflect` claims no unclaimed trigger — the same
argument that omitted `arena`.

Three of its four mechanics were declined. The **structural-enforcement check** is already a whole
skill here, and a stronger one: `claude-config:audit-automation-gaps` audits against the enforcement
hierarchy with a default-REJECT posture, where upstream has one sanity-check bullet. The
**capture-don't-apply gate** is stated twice already — and upstream's version actually conflicts
with ours, since it files backlog items to a tracker automatically where `running-retro` says "never
file automatically". **"The skill exists but didn't trigger"** as a finding class is owned by
`discipline:use-your-skills`, which audits for "a skill that should have fired and did not" and
already routes description-surfaceability to `/skill-quality:check` — an incumbent this lane's
survey missed entirely.

**One real gap closed: an accepted skill candidate had nowhere to go.** Both retro skills are
required to produce candidates and neither named a destination. Both now hand one to
`/playbooks:skill-authoring` gated on `/skill-quality:check`, presence-gated with a stated fallback.
The plan scoped this to `running-retro` alone on the reasoning that `retro`'s five dimensions are
closed; that is a non-sequitur — `retro` closes its *scoring* dimensions, not the improvement
analysis that produces the candidates — so both were fixed.

**The strongest dissent in this port is recorded rather than smoothed over.** The audit argued for
absorbing the three orthogonal lenses, on the grounds that `review:fanout` is a third consumer of
the fan-out-and-normalize shape and would therefore satisfy the recheck trigger `arena` left behind.
It also correctly caught that the plan had miscited `arena`'s own reasoning. The lenses are still
declined, for a reason the plan did not give: a three-lens fan-out over a transcript is a new
standing mechanism with no observed-stumble evidence, which the instruction-economy rule makes
disqualifying on its own. A later reader who disagrees should start here.

### Why `bro` ships nothing at all

Upstream's `bro` is seven lines, one of them body: "Restate your last message. Stop using jargon and
speak coherently. State it more simply and concisely, like one human talking to another." No
mechanism, no procedure, no output contract.

It is the only lane in this port where the honest answer is that the file contains nothing this
marketplace lacks. The capability ships **twice**, on two different axes: `education:explain` is the
altitude drop, and its **empty argument already resolves to the previous assistant response** by
anaphora, with 'rephrase that' and 'explain simply' already among its triggers;
`discipline:wait-what` is the interjection-fired re-pitch. The brevity pressure that is `bro`'s only
distinguishing note — "more simply *and* concisely", where `explain` adds an analogy and a handoff
line — ships a third time as `discipline:tighten-your-output`. `adhd:clarify`'s description already
routes the lossy plain-language drop to `education:explain` by name, which settles the axis `bro`
sits closest to; the other two are reached by their own triggers rather than by a stated three-way
routing, and an earlier draft of this paragraph overstated that.

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

All ten lanes are decided.

## Method provenance, for the record

Worth stating because it changes how much of `why` is genuinely upstream's invention: it is not.
Upstream states its discipline as two separate six-item lists — a "Concretely" list (evidence before
narrative, precision over polish, consider what you haven't seen, name the gaps, hedge on purpose,
no shortcut by code-reading) and a "Principles" list (cite everything, prefer "appears to" over
"because", surface contradictions, acknowledge gaps, multiple hypotheses are valid, beware
rationalization). Across both, every item but one restates historiographical source criticism and
intelligence-community analytic tradecraft closely. The exception is "no shortcut by code-reading",
which is specific to this substrate — and is the very rule this port then hardened past upstream's
own position, as the deliberate departure above records. Its genuine contribution is the
*substrate*: applying that discipline to software's own historical record, at a moment when all the
adjacent prior art (ADRs, IBIS, QOC, DRL, the design-rationale-capture literature) is about
**capture** — writing rationale down at decision time — and none is about **recovery** when nobody
did.

That framing is what the port keeps. The tier vocabulary was compared against ICD 203's words of
estimative probability, GRADE's certainty levels, and the Admiralty code, and none is a substitute:
each measures a different axis (likelihood, certainty in an effect estimate, source quality), so
adopting one would have imported a scale that does not answer the question being asked.
