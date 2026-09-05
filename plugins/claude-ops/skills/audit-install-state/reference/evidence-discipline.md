# Evidence discipline

The rules below are not exhortations to be careful. Each one changes the **shape of the output**, so
that an under-supported claim looks wrong on the page instead of relying on somebody remembering to
doubt it.

The reason for that design: an author can state a rule and break it in the next paragraph, and a
producer rarely catches its own error. So the fix cannot be care, seniority, or expertise. It has
to be a property of the artifact.

## 1. The artifact carries the caveat, not the author

Every claim the engine emits carries an `evidence` field:

| Value | Meaning |
|---|---|
| `measured` | Read directly off the filesystem or a config file in this run |
| `documented-default` | Not present locally; the value is upstream's documented default |
| `inferred` | A step was taken beyond what was measured |
| `no-upstream-row` | No documentation covers this path, so no claim is made either way |

Hedging in prose does not work. A downstream reader, human or agent, consumes an inference and an
observation identically unless the artifact distinguishes them structurally. An unmarked inference
handed from one lane to another gets adopted as evidence, because nothing in the artifact says it
is not.

The concrete instance in this engine: an `age-exceeds-window` finding reports the file count under
`measured` and the *interpretation* under `evidence: inferred`, with the sweep's documented unit of
retention inline. The count is a fact; "the sweep is failing" is not, and the schema will not let the
two be spelled the same way.

## 2. Report a range with its sample count, never a central tendency

Any quantity that can change while the scan runs is emitted as `{min, max, n}`. There is no field a
single averaged number could go in.

`~60 s` passes review silently. `59–62 s, n=4` visibly invites a fifth sample. That is the whole
mechanism.

## 3. Agreement within one moment is not evidence

For a timing, racing, or periodic property, repeated sampling *at one instant* proves nothing —
sample across the varying dimension.

Two samples of a timestamp comparison taken in one moment can return a clean, unanimous
`equal=True`, and two more taken a moment later a clean, unanimous `equal=False`. Neither
mismeasured. When the underlying gap **flips per write cycle**, the test returns a confident answer
determined by which cycle you happened to sample.

So the engine flags `unanimous_small_n_on_volatile_path` when a known-churning directory returns the
same count across fewer than three samples. **A clean unanimous small-n result on a dynamic system is
a red flag, not a confirmation.**

Corollary worth keeping: prefer the deterministic discriminator. `CreationTime` *advancing* is
reproducible across samplers; `CreationTime == LastWriteTime` is not.

## 4. The "safe" tier is the one that most needs an independent check

An operation labelled mechanically provable, no judgment required, is where the check gets skipped.
A case-insensitive comparer collapses deny rules that differ only by case into one, and the
"provable" dedupe then drops protections.

Two consequences, both encoded:

- The engine's deny-root list is compared **case-sensitively**, and a test asserts that three paths
  differing only by case survive as three. Surface classification is case-sensitive for the same
  reason.
- This skill encodes **no** rule deduplication or subsumption logic of any kind. That is deliberate,
  and stated here so it is not mistaken for an oversight. Permission-rule hygiene belongs to
  `/claude-config:audit` and `/claude-config:audit-permission-grants`.

## 5. Peer review, not just parallelism

Errors get caught by cross-checking, not by self-review. A fan-out of independent producers writing
into one report ships every one of them.

So the review stage is a dispatch, not a re-read: hand the findings to a **fresh-context** reviewer
subagent that did not produce them. A reviewer carrying the producing agent's context inherits the
producing agent's blind spot, which is exactly the failure mode this section documents. If this skill
is run across several agents, that delegation is not optional. What works:

- lanes broadcast load-bearing findings mid-flight, not only at the end;
- a receiving lane **verifies before adopting** rather than propagating;
- retractions stay in place as worked examples, so the next reader does not re-derive the same dead
  hypothesis, which several lanes can reach independently when one grep would falsify it;
- disagreements nothing depends on are recorded as **unresolved**, not silently settled.

A third failure mode is worth naming separately because the first two remedies miss it: a coordinator
relaying a peer's claim into a durable artifact without measuring it. Cheap to prevent, easy to miss
under time pressure.

## 6. Doc-derived claims are graded too

A summarizing web fetch returns a small model's answer *about* a page, not the page. **Absence from a
paraphrase is not evidence of absence.** Any claim about upstream behaviour must come from the raw
`.md` endpoint (`curl` the page to a file, then read the file), and a destructive conclusion may
never rest on a summarized read. The sanctioned channel is `code.claude.com`.
