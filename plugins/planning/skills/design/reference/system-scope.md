# System scope: quality scenarios, capacity estimates, risks

Read by `/planning:design` "System-scope steps" when the scope is `system`. The three steps are
suggested, not required: run each one the design touches. Each one that runs is a thread in
`design-threads.md` under the name given here, and like every thread it ends RESOLVED, directional
or tagged-deferred, because `/planning:design-handoff` checks every thread the file holds. Each
rule names the stumble it answers.

## Quality scenarios

Turn each quality requirement into a scenario with six parts: source, stimulus, artifact,
environment, response and measure. One scenario per requirement, written as a row:

```markdown
| Requirement | Source | Stimulus | Artifact | Environment | Response | Measure |
|---|---|---|---|---|---|---|
```

The requirements come from the Brief's `Quality requirement:` lines and `target assumed` lines,
and from `Quality requirement:` lines a design round already recorded in `design-threads.md`. They
are settled inputs, never asked again
([`design-defaults.md`](design-defaults.md) "Quality requirements (NFRs)"). The measure is the
requirement's target, quoted; a requirement recorded in words with no target gets a measure in
words, never an invented number. A part the requirement does not state is filled from the system
the design describes and marked `(design)`, so the reader sees which parts the Brief fixed.

A prototype Brief whose `Quality requirements deferred (prototype)` line stands writes one line
and asks nothing:
`Quality scenarios: deferred (prototype) [RESEARCH: write the scenarios if it heads for production]`.

Stumble: a requirement written as one sentence named no environment and no measure, so nothing
said under which load or failure it had to hold, or how a check would grade it.

- **Pointer**: the six parts are the SEI quality attribute scenario form, read in
  [Quality Attribute Workshops (QAWs), Third Edition, CMU/SEI-2003-TR-016](https://www.sei.cmu.edu/documents/716/2003_005_001_14249.pdf),
  section 3.8 "Step 8: Scenario Refinement", when a part's meaning is in doubt.

## Capacity estimates

Estimate the load the components must carry where a quality scenario's measure, or a topology
choice, depends on it: requests per second at peak, stored data and its growth, fan-out per
request. Each estimate shows its inputs and the arithmetic, and ends with a `Basis:` line naming
where each input came from (the Brief, a file or metric read this session, or `judgment`).

An input nobody can supply is not asked as a blocker and not invented silently: record it in the
thread as `- <prompt> target assumed: <value>: revisit if <trigger>`, the line
[`../../interview/context/nfr-prompts.md`](../../interview/context/nfr-prompts.md) uses for an
assumed target, and carry on with that value.

Stumble: a topology picked for "high load" with no number behind it could not be checked against
the load the system actually expects.

## Risks

List what could make the design fail, one row per risk, in the columns `/planning:plan` uses for
its `### Risks and Mitigations` section
([`../../plan/templates/plan-md-anatomy.md`](../../plan/templates/plan-md-anatomy.md)):

```markdown
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
```

Likelihood and Impact are each `Low`, `Med` or `High`. Draw the rows from the quality scenarios a
candidate design may miss, the `target assumed` inputs, and the deferred threads. A mitigation
names a design decision, a check or a phase, never "monitor closely". The thread is named `Risks`
so `/planning:design-handoff` lists its rows and `/planning:plan` seeds its risk table from them.

Stumble: risks found during design were lost at the handoff, and the plan listed its own from
scratch.
