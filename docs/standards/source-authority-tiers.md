# Source authority tiers

Not every source that can be cited settles a question. A claim about how a tool
behaves, what a default is, or whether an option exists is only as strong as the
distance between the claim and the thing that decides it, and that distance is
what a citation alone does not record. This convention ranks that distance and
states how much corroboration a claim needs before it is treated as settled.
[`documentation-and-citations.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/documentation-and-citations.md) owns *whether
and where* a citation appears once a claim is accepted; this owns *what the
source is worth* and *how many are needed*. Neither answers the other's
question.

This spans two of the tiers [`enforceability-tiers.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/enforceability-tiers.md)
defines. A source floor is **deterministic** in nature: one primary plus two
corroborators is an exact count. But the sources are named in a session, not in
a tracked artifact, so no tool has anything to count. Deciding which rung a
source occupies, and whether two sources are independent, is **reasoning-only**
regardless: it turns on what the source owns and where its content came from.
The obligation stays with the author either way.

## The four rungs

Authority is a function of interpretive hops, not prestige or ranking position.

| Rung | What it is | Standing |
|---|---|---|
| **Observed** | the thing itself answering now: command output, a file's contents, an API or query response, a live configuration value | primary; a claim may rest on it |
| **Canonical** | the authority that owns the thing, read at its current version: the specification, the vendor's own reference, the source code, the changelog, the registry entry | primary; a claim may rest on it |
| **Secondhand** | someone else's account of a primary rung: a practitioner write-up, a community answer, a synthesis tool's response, a subagent's summary | corroborating only; a claim may not rest on it |
| **Recalled** | no retrieval behind it: memory, recall, an assertion whose source cannot be named | not a source; promote it to a primary rung or drop the claim |

A **Secondhand** source is not weak because it is wrong; it is weak because a
reader cannot tell whether it is wrong without consulting the primary it
paraphrases. Naming that primary is its whole value, and it holds its rung only
while it does: one that has lost the primary it rested on, a summary of a
summary, a report whose sources are gone, has decayed to **Recalled**, whatever
it originally read.

## Primary means owning the fact, not being reputable

A source is primary for the facts it owns and secondhand for everything else.
The same page moves rungs with the question: a vendor's reference is **Canonical**
for its own product's behavior and **Secondhand** for a competitor's; a
specification is **Canonical** for what it requires and **Secondhand** for
whether any implementation conforms; a maintainer's post is **Canonical** for
intent and **Secondhand** for shipped behavior. Resolve the rung against the
claim, never against the domain's reputation.

Two consequences follow. Where a claim asserts a *runtime* fact, such as what a
version does, what a flag accepts, or what actually installed, **Observed**
outranks **Canonical**: a release can ship ahead of the documentation that
describes it, so when the two disagree about behavior, the running system is the
one that decides. And a negative claim ("that option does not exist", "it was removed",
"nothing supports this") can only be carried by **Observed** or **Canonical**
retrieved for this claim: absence from a secondhand account, or from memory, is
evidence of nothing.

## Independence is what corroboration counts

The floor for a claim durable enough to act on is **one primary-rung source
retrieved for that claim, plus two independent corroborators of any rung**.
Corroborator count is not citation count. Two sources are one source when they
share an upstream pool, an author or author network, a generating tool, or a
single model's priors: three write-ups paraphrasing one release note are one
corroborator.

Scale from that floor by consequence, not by convenience:

- A claim steering reversible work inside the current session can run on the
  primary alone, provided the reversal cost is low.
- A claim entering durable content, gating an irreversible action, or bearing on
  security or identity needs **more primary-rung sources**, not more
  corroborators. Corroboration protects against one source being unrepresentative;
  it does not protect against every source being wrong.
- A claim where the retrieved sources disagree is not corroborated at any count.
  Resolve the disagreement against a primary rung, or record the claim as open.

## A rung expires with its retrieval

A source's rung is a property of when it was read, not of the source. A fetch
from a previous session has decayed to **Recalled**: its content is now
indistinguishable from memory, and the upstream may have moved. Re-retrieve
before relying on it. This governs a source's standing as evidence;
[`documentation-and-citations.md#time-bound-external-claims-need-a-recheck-trigger`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/documentation-and-citations.md#time-bound-external-claims-need-a-recheck-trigger)
governs the separate obligation attached to a time-bound fact once it is written
into durable content.

## Grounding a recommendation

A recommendation, option, or decision put in front of someone else rests on
sources retrieved for it before it is presented, without waiting to be asked.
Ground it in both directions:

- **Locally**: read the code, configuration, or document the recommendation
  affects, and list who consumes it: callers, dependents, and other
  repositories that read it. That inventory is **Observed** evidence; a
  recommendation that skips it is guessing at its own reach.
- **Externally**: for a tool, version, or API, the owner's current reference
  first. For a design pattern, the source that defines it (the Gang of Four
  catalog, Fowler's catalogs, *Enterprise Integration Patterns*, the
  domain-driven design books) and the recognized practitioners who build on
  it, with publication dates and any dissent noted. A pattern's definition
  does not weaken with age; a product default does.

Adoption is not authority. A pattern found in a template, a sample, or a
popular repository shows that people use it, not that it serves the principle
it claims to. Check it against that principle before recommending it, and say
so when a common pattern fails the check.

## Boundaries

- **vs [`documentation-and-citations.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/documentation-and-citations.md)**: that
  file owns whether a fact is cited rather than copied, where the link sits, and
  which footer it belongs to. This file owns how much the cited source is worth
  and how many are required.
- **vs [`reference-dont-duplicate.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/reference-dont-duplicate.md)**: that file
  owns one source of truth per fact inside the repository. This file ranks
  sources outside it, where there is no single owner to defer to.
- **vs [`deterministic-work-execution.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/deterministic-work-execution.md)**:
  that file owns whether an execution was honest enough for its output to count
  as evidence at all. This file owns what that output is worth beside other
  sources once it does. A primary rung means a claim may rest on the source; it
  does not mean the source answered the question that was asked.
- **vs [`enforceability-tiers.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/enforceability-tiers.md)**: that file
  classifies a *convention* by who can decide it. This file classifies a
  *source* by what it can establish. The two ladders are unrelated; only the
  vocabulary for this document's own classification is borrowed.
- **vs [`session-time-agent-output-trust.md`](https://github.com/melodic-software/standards/blob/main/conventions/engineering/session-time-agent-output-trust.md)**:
  that file governs an assertion an agent makes about its own work. An
  agent's assertion carries no rung of its own; it inherits the rung of the
  source it names, or **Recalled** when it names none.
- Not a research procedure. How many queries to run, in what order, and when to
  stop are a consuming tool's or process's concern. This file supplies only the
  ladder and the floor those procedures resolve against.
