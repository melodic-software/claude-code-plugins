# Upstream source: AI Hero Cohort 005, Workshop 5 "Codebase Design" (Matt Pocock)

This page records what this repository takes from, adapts, already has, or rejects in the
**Codebase Design** workshop of Matt Pocock's AI Hero cohort (Cohort 005): eight lessons on shaping
a codebase so agents can change it safely. The workshop fixes one module-design vocabulary, hunts
for shallow modules, puts seams around legacy code so it can be tested, enforces module boundaries
with a deterministic check, and runs a refactor from a scan report through a spec and tickets. Our
counterparts are [`/architecture:improve`](../../plugins/architecture/skills/improve/SKILL.md),
[`/architecture:principles`](../../plugins/architecture/skills/principles/SKILL.md),
[`/architecture:enforce-boundaries`](../../plugins/architecture/skills/enforce-boundaries/SKILL.md),
[`/architecture:adr`](../../plugins/architecture/skills/adr/SKILL.md),
[`/planning:design`](../../plugins/planning/skills/design/SKILL.md),
[`/tdd:principles`](../../plugins/tdd/skills/principles/SKILL.md) and
[`/work-items:ship`](../../plugins/work-items/skills/ship/SKILL.md). Rows hold our decisions and
our own descriptions of each idea, under the upstream-drift convention's
[What a row may describe](../contracts/upstream-drift/README.md#what-a-row-may-describe). The
course is paid and account-gated, so no lesson text is recorded or linked here; the skills it
teaches are public and versioned in [mattpocock/skills](https://github.com/mattpocock/skills),
whose record is [mattpocock-skills.md](mattpocock-skills.md). Earlier course units have their own
records: [aihero-course.md](aihero-course.md), [aihero-shipping-course.md](aihero-shipping-course.md),
[aihero-domain-language.md](aihero-domain-language.md), [aihero-wayfinder.md](aihero-wayfinder.md)
and [aihero-review.md](aihero-review.md).

- **Pointer**: when a row needs the upstream mechanism, fetch the public skills it rests on live:
  [`codebase-design`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/codebase-design),
  [`improve-codebase-architecture`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/improve-codebase-architecture),
  [`implement-spec`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/engineering/implement-spec)
  and
  [`setup-ts-deep-modules`](https://github.com/mattpocock/skills/tree/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/skills/in-progress/setup-ts-deep-modules).
- **As of**: 2026-11-18
- **Recheck trigger**: a mattpocock/skills changeset naming one of those units, checked as
  [mattpocock-skills.md](mattpocock-skills.md) describes. Course page updates are not observable
  events; the skills-repo changeset stream is the proxy, as in
  [aihero-shipping-course.md](aihero-shipping-course.md).

**Landed** names the merged pull request that carries the row.

## Attribution table

Disposition is `take`, `adapt`, `already have`, `reject` or `no change`, with the reason. The
upstream-problem cells are **Inference** throughout: the lesson pages that state them are paid and
not linked.

### The codebase as the agent's environment

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The codebase, its tests and its checks are the agent's working environment | Treats a careless codebase as the cause of an agent's poor work | Inference: an agent in a tangled codebase produces tangled changes | Same; ours also counts the harness files tracked in the repository | **already have**: the environment framing from the crash course ([aihero-course.md](aihero-course.md)) | none |
| Agents work tactically, so a person carries the strategic design work | Keeps design decisions with the human | Inference: an agent sees the task, not the system | Same; how much of that work agents can take on is open | **no change**: the owner plans and decides design; the evidence found favors a deterministic check on structure plus an outside verifier over prose guidance | none |
| Benchmarks score task completion, not codebase health | Warns against reading a leaderboard as a quality measure | Inference: a board that asks "done?" hides decay | True of test-graded boards, not of every benchmark | **no change** | none |

### One module-design vocabulary

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| One fixed set of terms: module, interface, implementation, depth, seam, adapter, leverage, locality | Stops an agent mixing design schools | Inference: mixed terms give mixed designs | The terms lived inside one skill, so no other skill could load them | **adapt**: a knowledge skill, `/architecture:principles`, holds the terms; `/architecture:improve` and the planning skills load it by name; no setting replaces the vocabulary | [#16089](https://github.com/melodic-software/claude-code-plugins/pull/16089), [#16422](https://github.com/melodic-software/claude-code-plugins/pull/16422) |
| Each term credited to one author | Gives the vocabulary a single source | n/a | Our basis line credited one author for terms that come from three, and for terms that are the skill author's own | **take** (correction): the basis line says which terms are Ousterhout's, Feathers's and Cockburn's, and credits leverage, locality, the deletion test and the two-adapter check to mattpocock/skills `codebase-design` | [#16089](https://github.com/melodic-software/claude-code-plugins/pull/16089), [#17186](https://github.com/melodic-software/claude-code-plugins/pull/17186) |
| Hidden internals make tautological tests impossible | Blames the codebase for bad tests | Inference: a test cannot assert on what it cannot reach | A tautological test can go through a public method | **no change**: hiding internals removes one class of structure-coupled test; the test audit stays | none |
| A deep module forces tests of whole flows | Prefers flow tests over per-function tests | Inference: per-function tests miss integration faults | No study found links module depth to test granularity | **no change** | none |
| Design defaults beyond the eight terms | n/a (raised by the owner while watching) | n/a | Our design defaults lacked an errors line and "make illegal states unrepresentable", and three entries cited the wrong source | **adapt**: both added, the sources corrected; Law of Demeter, least astonishment, command-query separation and a pattern section are left out | [#16044](https://github.com/melodic-software/claude-code-plugins/pull/16044), [#16418](https://github.com/melodic-software/claude-code-plugins/pull/16418) |
| One logical change that needs edits in many places | n/a (raised by the owner while watching) | n/a | Review raised it only as a suggestion, and only when the diff added to the set | **adapt**: review raises it as important whenever one change needed coordinated edits in many places, code or Markdown, with the sites as evidence; planning flags it at plan time | [#16051](https://github.com/melodic-software/claude-code-plugins/pull/16051), [#16181](https://github.com/melodic-software/claude-code-plugins/pull/16181) |

### Finding shallow modules

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The deletion test chooses between removing and deepening a shallow module | Asks what happens to the complexity if the module goes | Inference: a wrapper that adds nothing costs every reader | Our vocabulary named two fixes for a module that only forwards calls; Ousterhout names a third | **adapt**: the deletion test stays; a module that only forwards calls has three fixes: delete it, move work between it and the module it wraps so each has a distinct job, or merge the two into one deeper module (Ousterhout, *A Philosophy of Software Design*, §7.1) | [#17169](https://github.com/melodic-software/claude-code-plugins/pull/17169) |
| The agent hunts, the person judges, and the hunt is scoped | Limits the scan to an area worth changing | Inference: a whole-repository scan returns noise | Our hot-spot step listed commits without paths and counted bot commits | **adapt**: the step reads changed paths and leaves out bot-authored commits | [#16089](https://github.com/melodic-software/claude-code-plugins/pull/16089) |
| A design scan also turns up live defects | Folds each defect into the refactor that would remove it | Inference: the refactor fixes it anyway | The refactor may never be picked, and a security defect must not be written up in public | **adapt**: a reproduced live defect gets its own bug report at once; a security defect is named first and reported privately | [#16194](https://github.com/melodic-software/claude-code-plugins/pull/16194) |
| A design scan also sees review-class problems, such as types that opt out of checking | Reads them as part of the design finding | Inference: they show the same carelessness | A design scan that grows review criteria duplicates the review skills | **adapt**: the scan keeps them as evidence and names the skill that owns them | [#16194](https://github.com/melodic-software/claude-code-plugins/pull/16194) |

### Seams, adapters and legacy code

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A seam is where behavior can change without an edit at that place, and where a module's interface sits | Gives tests a place to substitute a dependency | Inference: code without seams cannot be tested apart | "Seam" has five senses in this repository | **adapt**: the vocabulary entry states the module-design sense and Feathers's enabling point; this repository's other senses are listed in [`docs/glossary.md`](../glossary.md), not in the shipped vocabulary | [#16418](https://github.com/melodic-software/claude-code-plugins/pull/16418) |
| An adapter is the concrete thing plugged in at a seam | Names the role, from ports and adapters | n/a | A reader could take it for the Gang of Four pattern | **adapt**: one clause says it is not that pattern; modular monolith and vertical slice are named beside it | [#16418](https://github.com/melodic-software/claude-code-plugins/pull/16418) |
| Legacy code is code without seams; put seams around what must change | Makes legacy code testable before it is changed | Inference: an agent cannot safely change what it cannot test | Our characterization reference had no path for code that cannot be put in a test harness | **adapt**: characterize first stays the rule, with Feathers's exception (make only the dependency-breaking change first), the seam types, and the Strangler Fig for migrations | [#16420](https://github.com/melodic-software/claude-code-plugins/pull/16420) |
| Extract a module from a request handler, then test it | Skips a characterization step | Inference: the handler cannot be tested as it stands | Refactoring untested code first risks changing behavior unseen | **reject** the ordering as a default; covered by the exception in the row above | none |
| Pass the current time in instead of faking timers | Makes the clock a parameter | Inference: fake timers are slow and global | Same | **already have**: the clock rule in [`/testing:write`](../../plugins/testing/skills/write/SKILL.md) | none |
| A real in-memory database in place of a fake repository | Tests reach the real queries | Inference: a fake repository drifts from the real one | Same; a different engine standing in for the production one is still a test double | **already have** | none |
| Seed deliberate bugs to test fresh tests | Checks that the new tests can fail | Inference: an agent's tests can pass on broken code | Same | Handed to the feedback-loops workshop | [#16614](https://github.com/melodic-software/claude-code-plugins/pull/16614) (an advisory mutation run on the diff when `/implementation:implement` completes), [#16632](https://github.com/melodic-software/claude-code-plugins/pull/16632) (`/mutation-testing:seed-faults`) |

### Enforcing module boundaries

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| A deterministic check enforces module boundaries | An import that crosses a boundary fails the check | Inference: review misses boundary crossings, and an agent takes the shortest import that compiles | Our boundaries lens proposed a check and wrote none | **adapt**: a new skill, `/architecture:enforce-boundaries`, sets up the strongest mechanism the repository supports for each recorded rule; the check and its config belong to the consumer repository | [#16498](https://github.com/melodic-software/claude-code-plugins/pull/16498) |
| A setup skill for one language and one tool | Installs and configures a named import-rule tool | Inference: one stack keeps the skill simple | A plugin here ships no language- or tool-specific logic | **reject** the shipped tool config and template; the skill discovers the repository's own mechanism or researches one at run time | [#16498](https://github.com/melodic-software/claude-code-plugins/pull/16498) |
| Rule kinds: entry points only, tests through entry points, no cycles, a consumer barred from a module's job | Says what a boundary rule can forbid | n/a | Our recorded rule forms had no entry-points-only or no-cycles form | **take**: both added to the one list of rule forms | [#16498](https://github.com/melodic-software/claude-code-plugins/pull/16498) |
| Prove the check by breaking it on purpose | Shows the check fails on a real violation | Inference: a check that never fails proves nothing | One proof for a set of rules can leave a rule unchecked | **adapt**: every rule is proven on its own injected violation, and only the injected lines are removed | [#16498](https://github.com/melodic-software/claude-code-plugins/pull/16498) |
| A written standard beside the check | Repeats the boundary rule in prose for agents | Inference: prose is a second line of defense | A prose copy of a checked rule drifts from the check | **reject**: a rule a deterministic check enforces is not also written in prose; the skill writes nothing to agent instructions | [#16498](https://github.com/melodic-software/claude-code-plugins/pull/16498) |
| A change that loosens a check | n/a (raised while absorbing) | n/a | Nothing flagged a diff that weakened a check | **already have**, through a lane change that is stricter than the answer given here | [#16372](https://github.com/melodic-software/claude-code-plugins/pull/16372) |
| A committed example module as a template | Gives agents a module to copy | Inference: agents copy what they see | A template per ecosystem is a file per tool to keep current | **no change** | none |

### The architecture scan and its report

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| The scan skill: scope, explore in a fresh context, deletion test, report, then an interview | Runs a design review end to end | Inference: design review is skipped when it is manual | Same | **already have**: the deepening lens, with a reproduction gate and a durable candidate file upstream lacks | none |
| The scan is invoked by the user only | Keeps the scan's cost a human choice | Inference: an unrequested scan wastes a run | A planning step cannot reach a user-only skill | **no change**: ours stays invocable by the model and names the agent count before it dispatches | none |
| The scan calls other skills for the interview and the design alternatives | Composes smaller skills | n/a | Ours held three lenses and a layout lens in one skill | **adapt**: the steps every lens shares moved to one file and the layout lens to its own skill, `/architecture:improve-layout`; the interview loop and the design hand-off stay in the lens, because they write fields (`agreed-shape`, `graft-record`) the `/planning:interview` Brief has no place for | [#16496](https://github.com/melodic-software/claude-code-plugins/pull/16496), [#17809](https://github.com/melodic-software/claude-code-plugins/pull/17809) |
| The report loads a layout library and a diagram library from a CDN | Draws graph-shaped diagrams with a diagram library and the rest by hand | Inference: a hand-drawn graph is slow to write and easy to get wrong | Our rendered views allowed no external request, so every diagram was hand-built | **adapt** (reverses the earlier rejection): a rendered view may load a popular library from a CDN at an exact version, with an integrity hash and a fallback; the deepening report takes that route on the shared page chrome, with strict diagram settings | [#16490](https://github.com/melodic-software/claude-code-plugins/pull/16490), [#16508](https://github.com/melodic-software/claude-code-plugins/pull/16508), [#17844](https://github.com/melodic-software/claude-code-plugins/pull/17844) |
| Evidence counts in the report header | The recorded run added count tiles its own spec does not ask for | n/a | Our header had no counts | **adapt**: one header line of counts, each a number the verification gate reproduced | [#16508](https://github.com/melodic-software/claude-code-plugins/pull/16508) |
| Several picked candidates treated as one design | The recorded run interviewed related candidates together | Inference: dependent refactors share decisions | Ours interviewed each on its own | **adapt**: one interview each, except candidates that depend on each other, which are interviewed as one tree | [#16508](https://github.com/melodic-software/claude-code-plugins/pull/16508) |
| When one skill layers on another | Upstream skills call each other by name | n/a | Our authoring guidance said how to word a call, not when to layer | **adapt**: one rule in [`/playbooks:skill-authoring`](../../plugins/playbooks/skills/skill-authoring/SKILL.md): call the skill that owns a behavior and add only your own steps | [#16449](https://github.com/melodic-software/claude-code-plugins/pull/16449) |

### Running the refactor

| Idea | What it does | Upstream problem | Our problem | Disposition | Landed |
|---|---|---|---|---|---|
| Design the interface twice with parallel agents and take a hybrid | Compares alternative interfaces before choosing | Inference: the first workable design is rarely the deepest | Same | **already have**: the Design-It-Twice branch, which also records what a hybrid left behind | none |
| A spec, then a ticket graph, then one integration branch | Runs the refactor as tracked work | Inference: a large refactor needs slices that land in order | Same | **already have**: `/work-items:ship run` | none |
| The spec and its tickets are closed before the code is pushed | The recorded run closed them on a local branch | n/a | Ours closes work on a merged pull request | **already have**, stricter | none |
| Security gaps found by the scan become public tickets | The recorded run filed them with the rest | n/a | A public item must not carry a vulnerability's details | **already have**, stricter | none |
| One module returns every permission decision, called from each route | Centralizes authorization | Inference: scattered checks drift | A call per route is opt-in; a missed route is open | **adapt**: the security reviewer flags per-route opt-in authorization that has no central decision or default deny | [#16423](https://github.com/melodic-software/claude-code-plugins/pull/16423) |
| A decision record only for a hard-to-reverse, surprising choice with a real trade-off | Gates decision records on all three conditions | Inference: too many records bury the important ones | Ours admits a record when a real alternative was weighed and one of five conditions holds | **no change**: our gate stays; the difference is stated in [mattpocock-skills.md](mattpocock-skills.md) (Map, `domain-modeling`) | this record |
| Commit glossary and decision changes straight to the default branch | Skips a pull request for documentation | Inference: a pull request slows small edits | This repository's rule forbids pushing to the default branch | **reject** | none |

### Found while absorbing

| Item | Disposition | Landed |
|---|---|---|
| The interview had no place for topics of rounds not yet ready | **adapt**: a `Later:` header line in [`/planning:interview`](../../plugins/planning/skills/interview/SKILL.md) | [#16456](https://github.com/melodic-software/claude-code-plugins/pull/16456) |
| Closed bug issues were not a source for recurring-mistake checks | **adapt**: an `issues` action in [`/corrections:codify`](../../plugins/corrections/skills/codify/SKILL.md) | [#16452](https://github.com/melodic-software/claude-code-plugins/pull/16452) |
| The file-size measure had one fixed reference and no rule for acting on it | **adapt**: one configurable reference, the repository's own linter limit preferred; an over-reference file is acted on only when it also changes often. The size report is the signal's one home: an opt-in check mode, off by default, fails a changed file that crosses the reference | [#16444](https://github.com/melodic-software/claude-code-plugins/pull/16444), [#17251](https://github.com/melodic-software/claude-code-plugins/pull/17251) |
| The enforcement ladder gave no source for its rung order | **take**: a source line | [#16440](https://github.com/melodic-software/claude-code-plugins/pull/16440) |
| The landscape map recorded credentials from a remote URL | **take**: fixed | [#16468](https://github.com/melodic-software/claude-code-plugins/pull/16468) |
| Two verdicts in [mattpocock-skills.md](mattpocock-skills.md) were stale and one citation did not show its claim | **take**: corrected | this record |

### Handed elsewhere

- A mutation check of freshly written tests, and a test-isolation rule (no write outside a
  temporary directory; a destructive-command test never runs against the real machine): handed to
  the feedback-loops workshop, and landed in
  [`/testing:write`](../../plugins/testing/skills/write/SKILL.md)'s determinism controls.
  [#16610](https://github.com/melodic-software/claude-code-plugins/pull/16610) added isolation for
  tests that run concurrently;
  [#16955](https://github.com/melodic-software/claude-code-plugins/pull/16955) added the
  temporary-directory write rule and the destructive-command sandbox. The mutation check is the
  "Seed deliberate bugs" row above.
- One shared, brandable HTML default for every plugin:
  [#16412](https://github.com/melodic-software/claude-code-plugins/issues/16412).

## License notice

The course is paid content under its provider's terms; no lesson text, caption, image or code is
copied here. The public skills repository reads MIT on the host and in
[mattpocock-skills.md](mattpocock-skills.md); no text or code from it is copied either.

- **Pointer**: when a license question arises, read the skills repository's
  [LICENSE](https://github.com/mattpocock/skills/blob/4ae2317ddb22b046e26455e4f9c9b3aaaf62212d/LICENSE).
- **As of**: 2026-11-16
- **Recheck trigger**: the skills repository's license file changes.
