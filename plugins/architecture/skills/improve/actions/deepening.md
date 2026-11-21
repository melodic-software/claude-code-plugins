# Deepening lens (Ousterhout)

The `deepening` action applies Ousterhout's idea of deep modules. It looks for shallow modules, whose interface is almost as complicated as the code behind it, and proposes how to make each one deep: a small interface over a lot of behavior.

Three phases, with a verification gate (Phase 1.5) between the scan and the report. Each has a hard gate before the next.

## Phase 1: Explore for friction

The steps every lens shares are in [../../../reference/improvement-steps.md](../../../reference/improvement-steps.md); this playbook cites each by its section name.

**Check the branch is current with its base before scanning** ("Base freshness").

**Scope before scanning: YAGNI.** The return on deepening is cheaper change later, so it only
arrives where code is still being changed; deepening a file no one edits buys nothing. Choose the
scope and size the scan fan-out from it ("Scope and fan-out").

Read the project's domain glossary, if it keeps one: invoke `/domain-driven-design:ubiquitous-language lookup` via the Skill tool for the directory being examined when that skill is available; otherwise Glob the repository for `**/*{glossary,Glossary,GLOSSARY,ubiquitous,UBIQUITOUS}*.md` (the root, any `docs/` folder and the module's own folder) and Read the match that covers the area; a path the project's instructions declare, or a `glossary_file` set in `docs/conventions/domain-driven-design.yaml`, wins, and a tool's own reference glossary under a plugin or package `reference/` or `context/` folder is skipped, plus its glossary index in a multi-context repository.

Also read the architecture decision records in the area being examined ("Recorded decisions").

Walk the codebase through the Agent tool (`subagent_type=Explore`, or any read-only exploration subagent available). Brief each scan subagent with the canonical template in [../research/deepening/scan-briefing.md](../research/deepening/scan-briefing.md): vocabulary primer, friction checklist, dependency categories, the two badge-acceptance heuristics, and the per-candidate return schema. Briefing from it keeps scan quality from varying run-to-run and calibrates confidence against the heuristics at scan time, not leaving it to Phase 2. The scan follows what it finds rather than a fixed route, and records friction wherever it shows up:

- Code with no tests, or code whose current **interface** makes it hard to test.
- Modules that are **shallow**: the interface asks almost as much of a caller as the implementation does.
- A single idea whose logic is split over so many small modules that a reader has to open each of them to follow it.
- Pure functions pulled out to make testing easy, while the defects sit in the code that calls them (no **locality**).
- Defects that keep appearing *where* several owned subsystems meet (a web client, its API, a worker, its store) and not inside any of them. That points to putting them behind one **deep** interface, so a single integration test covers the whole path instead of each junction being debugged on its own.
- Modules so tightly coupled that they leak across their **seams**.

Four further hazards mislead an agent that edits the code, and each is judged by the **open-file test**: with only the file being edited open, can an agent see every other place it must change? A "no" confirms the hazard.

- **Split ownership:** more than one module writes the same state or keeps its own copy, so an agent that edits one writer cannot see the others. Remedy: one owner per piece of state; the others read it or ask the owner.
- **Two ways to do one task:** an agent copies whichever way it finds first, so every way keeps gaining callers. Remedy: keep one way; move callers off the others and delete them in the same change.
- **Importable internals:** an agent takes the shortest path that compiles and imports internals directly, which makes them part of the interface. Remedy: make internals unreachable from outside, so such an import fails the build.
- **Hand-synced list:** two or more places list the same items and adding one means editing every list; an agent updates only the list it sees. Remedy: keep one list and derive the others, or fail the build when they disagree.

Put each suspect through the **deletion test** and record one of two results: "concentrates", when removing it would pull logic now spread over its callers into one module (the candidate signal), or "moves", when the same logic would only relocate. The terms are defined in [../../../reference/vocabulary.md](../../../reference/vocabulary.md).

Classify each candidate's dependencies per [../research/deepening/dependencies.md](../research/deepening/dependencies.md). The category determines testing strategy.

## Phase 1.5: Verify before publishing

Hard gate between the scan and the report. Scan-agent accuracy is mixed, and the HTML report is a user-facing artifact that lends every claim its authority. An overstated claim there is cheap to make and expensive to reputation. The scan output carries a `confidence` field (`strong` / `worth-exploring` / `speculative`) but no badge yet. The `recommendation` badge is assigned in Phase 2. Gate on the scan field that exists here. Before rendering Phase 2, adversarially verify:

- **Every candidate the scan returned with `confidence: strong`** (the ones headed for a `Strong` badge): reproduce its `shallow-signal` (the concrete observation from the scan-briefing return schema). If the signal does not reproduce, drop the candidate's confidence below `strong`.
- **Every `runtime-claim`**: any candidate asserting a live bug or dead code. These are grep-cheap to check and the most damaging to get wrong: a service can look unregistered from the file that should compose it and still be consumed elsewhere, with tests. Reproduce the claim against the actual code before it reaches the report; correct or drop it if it does not hold.

Verification can be a second cheap read-only subagent pass or inline reproduction. The bar is that no `confidence: strong` candidate and no runtime-bug/dead-code claim reaches Phase 2 unreproduced. Record what changed (downgraded, dropped, corrected) so the candidate artifact reflects the verified state, not the raw scan, and count it: the artifact's `phase-1.5` line carries the three counts, including when all three are zero, so a reader sees the gate ran and what it caught.

**The verification level governs this gate.** Copy the level line SKILL.md's Variables section resolved into the candidate artifact. `standard` and `strict` run the gate as written. Under `light`, and `off`, which acts as `light` here, reproduce nothing and do not check inline in the gate's place: the artifact's last-but-one line is `phase-1.5: verification: skipped (<level>)`, and every `confidence: strong` candidate, every promotion to `Strong` and every `runtime-claim` reaches the report labeled `unverified`.

## Phase 2: Present candidates as HTML report

**A candidate proposes a change.** A finding whose conclusion is to leave the code as it is, such as keeping deliberate copies under an existing drift check, is not a candidate: before re-badging, move it to the record's `kept` list and the artifact's `## Looked at, no change` section, each with its title, one sentence of reason and its files. It carries no badge, is never a card and is never the top recommendation; the page reaches it from the end of the candidate list, so a reader, and a later scan reading the artifact, sees the code was already looked at.

**Re-badge first.** Before rendering, map each surviving candidate's scan `confidence` to its `recommendation` badge (`strong` → `Strong`, `worth-exploring` → `Worth exploring`, `speculative` → `Speculative`), then re-badge against the two acceptance heuristics below (deletion-test acceptance form, two-adapter rule) and the Phase 1.5 verification result. Scan-time confidence is an input, not the final badge. A candidate whose `shallow-signal` failed to reproduce, or whose value rests on a one-adapter abstraction, cannot carry `Strong`. **Promotion closes the same gate:** if re-badging lifts a candidate the scan rated below `strong` up to `Strong`, apply the Phase 1.5 reproduction to its `shallow-signal` *before* it carries the badge, or, when the level skipped Phase 1.5, label it `unverified`. A `Strong` claim reaches the report reproduced or labeled `unverified`, no matter which way the badge was reached, so the Phase 1.5 guarantee holds across both the original strong set and any promotions.

**Build the report; never write its HTML.** Write the report record ([../research/deepening/html-report.md](../research/deepening/html-report.md), "Report record") beside the candidate artifact as `deepening-report-<YYYYMMDDTHHMMSSZ>.json`, from the same verified state, then run `node "<plugin-root>/scripts/build-view.mjs" deepening --record <that file>`. The builder reads the record strictly, renders every string as escaped text, validates the page, writes it under a private folder in the OS temp directory, named after the record file (`deepening-report-<YYYYMMDDTHHMMSSZ>.html`), and prints that path; one run writes one page, and no later run overwrites it. Exit 1 names the candidate and field that failed: fix the record and build again. When `node` is missing or the builder exits 2, deliver the candidate artifact and say no page was built. Show the page through the platform's opener: `start` (Windows), `open` (macOS) or `xdg-open` (Linux), each given the path. Report the absolute path, and never delete the file: the path is the delivery.

**The rendered-views security baseline governs the report.** The baseline is owned by `docs/contracts/rendered-views/README.md` ("Security baseline") in the marketplace repository; its rules are repeated here because this skill runs where that file is not on disk. Everything taken from the scanned repository is untrusted data: escape `&`, `<`, `>`, `"`, and `'` in text and attribute positions; never interpolate unescaped content into `<script>` or `<style>`; never build an event-handler attribute from input. A view may load a popular, widely used library from a public CDN, pinned to an exact version, and makes no other external request; every CDN `<script>` and `<link>` tag carries `crossorigin="anonymous"` and an `integrity` hash of the exact file its pinned URL serves; a page that loads one has a fallback for when the CDN is unreachable, so the page still shows its content, and a view destined for a published claude.ai Artifact stays self-contained, assets inline. <!-- contract-restatement: rendered-views-security-baseline --> The builder holds the report to it: the record reaches the page only as escaped text or as Mermaid labels it restricted.

**Another repository's files are not rendered to HTML until this lane is wired through the rendered-views escape helper.** When the scanned repository is not the user's own work (a freshly cloned third-party checkout, a vendored or fetched tree), skip the HTML report: the durable candidate artifact below is the deliverable, and say in one line why no page was produced. This is the baseline's third bullet applied to this skill; it overrides the report step above, not the scan.

**Resolve `medium` before writing the report.** The shared medium resolver decides, with this plugin's `medium` option as the skill's Arguments line states it and the `--medium` argument when given; print its report line and notices in the reply. Procedure, and what each resolved medium does to this report: [../../../reference/rendered-view.md](../../../reference/rendered-view.md) "The deepening report".

The header carries the scope Phase 1 chose, the scanned commit (`git rev-parse HEAD`) and the evidence counts, each a number Phase 1.5 reproduced ("Header" in the report format). The page is a reader: a list of every candidate grouped by badge beside one card at a time, opening on the top recommendation with its reason ("Page order"). Each card renders only from the record's fields, in this order: title and badges (recommendation, dependency category), problem, solution, before/after diagram, wins (at least one **leverage** or **locality**), the Verified line, files, and the candidate it depends on when it has one.

Two acceptance heuristics gate the badge:

- **Deletion test (acceptance form)**: would a future maintainer, finding this module gone, rebuild it substantially the same way? If not, the module is cut in an arbitrary place and the candidate is weak.
- **Two-adapter rule**: an abstraction or port earns its existence only with two real consumers/adapters (typically production + test). A candidate whose value hinges on a one-adapter abstraction is speculative indirection. Badge it `Speculative` at best.

The record's `top` names the **Top recommendation**, which the page shows first. The record, the card parts and the diagram patterns are in [../research/deepening/html-report.md](../research/deepening/html-report.md).

Domain nouns come from the project's glossary; architecture nouns come from [../../../reference/vocabulary.md](../../../reference/vocabulary.md).

**Durable candidate artifact.** Alongside the report record and page (or standing alone, per the carve-out above, under `terminal`, or when no page could be built), write a machine-readable candidate list that survives the session. The HTML, when produced, is the human-readable companion, ephemeral in the temp dir. Write it to the **memory tier** ("Memory-tier writes"): `<memory_dir>/<topic-slug>/deepening-candidates-<YYYYMMDDTHHMMSSZ>.md`, default `.work/<topic-slug>/…`. This file, not the HTML, is the durable handoff a planning step consumes. One entry per candidate:

```markdown
## <candidate title>

- status: proposed | selected | agreed-shape | rejected
- files: <comma-separated paths>
- dependency-category: in-process | local-substitutable | ports-and-adapters | mock
- recommendation: Strong | Worth exploring | Speculative
- problem: <one sentence>
- solution: <one sentence: what the deepened module would own and hide; names no entry point, since Phase 2 proposes no interfaces>
- wins: <one or more `; `-separated gains, each `<vocabulary term>: <at most six words>`, at least one `leverage:` or `locality:`>
- verified: reproduced | corrected: <one clause, with no semicolon> | unverified
- deepening: <one sentence of narrative naming the shallow-module friction, not an interface proposal; e.g. "three modules wrap a single call each, adding no behavior">
- shallow-signal: <the concrete observation, evidence rather than narrative; e.g. "InvoiceController/InvoiceChecker/InvoiceStore each forward their one argument unmodified (confirmed by reading all three)". Reproduced in Phase 1.5 for every `Strong` candidate; a runtime-claim candidate has its *claim* reproduced, not this signal, so unless it is also `Strong` the signal here is the scan's as-reported observation, not yet reproduced>
- verification-notes: <the full Phase 1.5 notes for this candidate: what was reproduced, corrected or dropped, and how. The card shows only the `verified` line>
- signal-verified: <true only once Phase 1.5 reproduced *this signal*, i.e. every `Strong` candidate. A runtime-claim reproduction verifies the claim, not the shallow-signal, so a runtime-claim candidate left below `Strong` keeps `signal-verified: false`. This keeps the planning handoff from ever reading an unverified shallowness observation as verified>
- agreed-shape: <optional; omitted until Phase 3. Filled when the user picks and the shape is grilled: interface entry points, what the seam hides, tests that survive. A candidate that goes to implementation without the interview loop carries `skipped: <reason>` here, for example `skipped: direct-to-implementation`, so the entry says which path it took>
- graft-record: <optional; omitted unless the agreed shape is a hybrid from a Design-It-Twice fan-out. Then: what was taken from which design, and what was considered and left behind with its reason. The left-behind half is the higher-value half. It is what stops a later explorer re-proposing a shape this exploration already weighed and dropped. A hybrid recorded as a winner alone loses that permanently>
- rejected-reason: <only if status is rejected and the reason would help a future explorer>
```

After the candidates, when any finding was kept as it is, add one section:

```markdown
## Looked at, no change

- <title>: <one sentence: why the code stays as it is> (files: <comma-separated paths>)
```

End the file with two lines: `phase-1.5: downgraded=<n> dropped=<n> corrected=<n>` (the Phase 1.5 counts), then `top-recommendation: <candidate title>`.

**ADR conflicts**: check each candidate against the recorded architecture decisions. One that contradicts a decision is dropped unless its friction would justify reopening that decision; one that stays names the decision on its card.

**A reproduced live defect gets its own report.** A `runtime-claim` that Phase 1.5 reproduced as a live bug does not wait for its candidate to be picked: the refactor may never be chosen, and the defect is real either way. Name each one in the reply before the question, security defects first. A dead-code claim is not a defect, and a `runtime-claim` labeled `unverified` is named as unverified, not reported.

- **Not a security defect**: invoke `/bugs:write --file` (if that plugin is enabled) with the reproduction, so the report is saved to a file that outlives the session and the user is offered the choice to file it. Without it, give the report in the reply: a title, the steps that reproduce it, expected against actual, and the file and function to fix.
- **A security defect** (a missing access check, exposed data, an injection): state it to the user in the reply, and put its details in no tracker item, pull request, commit message or other text that may become public. Tell the user to report it through the repository's security policy or a private advisory, and file nothing yourself. Pointer: when the user asks how to report privately on GitHub, fetch [About reporting and disclosing vulnerabilities in projects on GitHub](https://docs.github.com/en/code-security/concepts/vulnerability-reporting-and-management/coordinated-disclosure#about-reporting-and-disclosing-vulnerabilities-in-projects-on-github) live.

The candidate keeps the defect as evidence for the refactor.

**Review-class problems belong to the skills that own them.** A scan also sees problems that are not about module shape: types that opt out of checking, errors caught and discarded, a hard-coded value that should be read from data. Keep each as evidence on the candidate it belongs to, add no finding or badge for it, and name the owning skill once in the reply: `/code-metrics:audit type-debt` (if that plugin is enabled) for typing, `/review:quality-gate code` (if that plugin is enabled) for the rest. Without either plugin, say that these were seen and not assessed.

Phase 2 proposes no interfaces. Once the report is written, the reply opens with the decision now up to the user, names the top recommendation, gives the report path (when one was written) and the artifact path, and asks: "Which candidate should we explore?"

## Phase 3: Interview loop on selected candidates

When the user has chosen a candidate, work through its decision tree in three groups: what the deepened module looks like (its shape, and what the seam hides), what it has to work within (its dependencies and constraints), and what will prove it (the tests that remain). When the user selects several, interview each to its own agreed shape in turn; each is its own design fork. The exception is a candidate that depends on another selected one, because it changes the same module or needs the other's interface first: interview those as one tree, the candidate the others depend on first, and say at the start which candidates are being treated as one tree and why. Each still gets its own `agreed-shape` entry. The skill still stops at the handoff and implements none of them.

The loop and the Handoff step below stay in this lens, not in `/planning:interview`: they write `agreed-shape` and `graft-record`, fields only this lens uses and the `/planning:interview` Brief has no place for, so reusing that skill would mean forking it.

Side effects inline as decisions crystallize:

- **New concept or sharpened term?** Invoke `/domain-driven-design:ubiquitous-language curate` via the Skill tool immediately
  when that skill is available in the current session; it owns active glossary maintenance and
  known-context routing.
  Otherwise preserve the existing fallback: update a consumer-declared ubiquitous-language glossary
  in its own shape. If no convention exists, offer discovery-first lazy creation without prescribing
  a filename.
- **User rejects a candidate with a substantive reason?** Offer to record it as an architecture decision, but only when the reason would help a future explorer avoid re-suggesting it.
- **Naming an exemplar call site to anchor the shape?** Read it before locking the shape around it. An exemplar chosen from memory or a candidate's file list can turn out not to fit once actually read; validate the fit first, and if it does not hold, search for a call site that does rather than shaping the interface around the wrong one.

### Design-It-Twice exploration mode

Branch here when the user wants alternative interfaces for the selected candidate, or a single proposed shape isn't converging. Grounded in Ousterhout's design-it-twice principle: the first workable design is rarely the deepest. Frame the problem space and show it to the user, fan out 3–4 parallel subagents each under a deliberately orthogonal design constraint, present the returned designs sequentially, compare on interface depth/leverage, locality of change, and seam placement, then close with an opinionated recommendation (hybrid allowed). Full process: [../research/deepening/interface-design.md](../research/deepening/interface-design.md). Feed the winning shape back into the interview loop. It becomes the `agreed-shape` once grilled.

### Handoff

When the candidate's shape is agreed, update its entry in the candidate artifact to `status: agreed-shape` and fill `agreed-shape` (interface entry points, what the seam hides, tests that survive). **When the agreed shape is a hybrid grafted from a Design-It-Twice fan-out, fill `graft-record` in the same edit**: what was taken from which design, and what was considered and left behind with its reason. It is a sibling field, not part of `agreed-shape`, and this is the only step that writes it: skip it here and the left-behind half survives nowhere, which is the half that stops a later explorer re-proposing a shape this exploration already weighed and dropped. Hand off to `/planning:design` (if enabled), which takes the `agreed-shape` entry as the module design and whose handoff carries it into the plan. If no design or planning tool is available in the project, summarize the agreed shape directly so implementation can proceed.

Before handing off, re-run the base-freshness check, and carry the implementer instructions and, for several candidates, their landing order ("Hand-off").

## Unattended mode

Entered only when the invocation carries `--unattended`. Phases 1, 1.5 and 2 run with the changes below, each of which wins over the phase text it changes. Phase 3 does not run.

- **Ask nothing.** Base freshness reports the behind count and carries on, and the run never merges or rebases. Scope comes from the invocation or the history step. Read the glossary, and write no glossary entry.
- **No page.** Skip the HTML report, the medium resolver and the opener. The candidate file is the deliverable.
- **The verification level applies as resolved.** Unattended mode neither raises nor lowers it, so under `light` and `off` no candidate has `signal-verified: true`.
- **Threshold.** After re-badging, keep only candidates at or above the `unattended_min_badge` setting, on the order `Speculative`, `Worth exploring`, `Strong`.
- **Candidate file.** Write `<memory_dir>/architecture/improve/<branch-slug>/deepening-candidates-<YYYYMMDDTHHMMSSZ>.md` ("Memory-tier writes"), in the durable artifact's format with `status: proposed` on every entry, opening with this header:

  ```markdown
  # Deepening candidates

  - mode: unattended
  - verification: <the resolved level line, without its leading "verification: ">
  - threshold: <the badge in effect>
  - producer: architecture:improve
  - source-sha: <full SHA of HEAD>
  ```

  The header holds these five fields and nothing else. `recommendation` holds the badge alone: `signal-verified` is what says a claim is unverified. With no candidate left, the file holds the header and its closing lines, and `top-recommendation: none`.
- **A security defect is one placeholder line.** For each security defect the scan raised, reproduced or not, write the line `security-defect: withheld` just before the file's closing lines. Nothing about it goes in the file or the final output: no title, path, symbol, defect class or reproduction. The file, route and symbols that hold the defect are named nowhere in either, even for an unrelated reason, because naming them beside the placeholder points at the defect. A candidate that rests on the defect, or cannot be stated without those names, is left out whole and is never the top recommendation; any other candidate keeps its entry with those names and that evidence removed.
- **Another reproduced live defect stays on its candidate** as evidence, and the final output names it. Invoke no bug-report skill.
- **Final output.** The candidate file's path, the count of candidates per badge, the verification level, and the number of `security-defect: withheld` lines with one instruction: run `/architecture:improve` with a person present to review them privately. End there, with no question.
