# Deletion-evidence attribution: making the consequential tier clearable

Design record for the mechanism decision Q1 depends on. Signed off 2026-09-01 as a two-tier
threshold: an editorial pass may delete trivial legacy guards, a consequential rule needs ledger
evidence. That second tier was deliberately unclearable at sign-off, because the evidence grammar
it names runs the other direction. This document closes that gap by specifying the mechanism, and
records why the obvious shortcut does not work.

## The problem

`claude-config:unhobble` ships a re-add gate: after a branch-local strip of the project's standing
instructions, an instruction is restored only on at least two ledger rows sharing one underlying
cause, and the restoring commit cites those rows. Undefended deletions stay deleted.

That grammar is sound and it is the repo's only existing evidence discipline for instruction
removal, so Q1 reached for it. But it answers a different question:

| | unhobble's shipped gate | what Q1's consequential tier needs |
|---|---|---|
| Question | should this rule come *back*? | may this rule be *removed*? |
| Default | stays deleted absent evidence | stays present absent evidence |
| Evidence | stumbles observed while it was absent | dispensability while it is present |
| Scope | everything stripped at once | one rule at a time |

The last row is the mechanical blocker. The experiment strips the whole surface, so a stumble is
attributable to "the bare configuration", not to any individual rule. Nothing shipped attributes an
observed stumble to the specific instruction whose absence caused it, and a per-rule deletion
warrant cannot be derived from an aggregate absence.

## The mechanism

Three parts, all of them the deletion counterpart of an existing unhobble concept rather than a new
vocabulary.

### 1. The observation window is per-rule and stated up front

A consequential deletion candidate enters a **watch**, recorded before any removal:

- the rule, quoted, and the surface it lives on
- the class of work the rule governs, stated as the situations where its absence would show
- the window: a count of qualifying sessions, not a wall-clock duration, since an idle week proves
  nothing. Qualifying means a session that actually entered the rule's governed situation
- the disqualifier: what would end the watch immediately (any stumble attributable to the rule)

A watch that never accumulates qualifying sessions expires unresolved. That is a real outcome and
it is reported as one; it is never read as evidence of dispensability, which is the asymmetry the
whole design turns on.

### 2. Attribution is by governed situation, not by proximity

A stumble counts against a deletion candidate when the session entered the situation the rule
governs and the outcome went wrong in the way the rule exists to prevent. Two guards:

- **Same-cause aggregation**, inherited from unhobble: two stumbles count as one row when they
  share an underlying cause. A single flaky session does not decide a rule's fate in either
  direction.
- **Co-absence is not attribution.** When several rules were removed in one change, a stumble is
  attributed only if exactly one removed rule governs the situation. If two do, the row attaches to
  the group and the group's deletions are reverted together. Splitting a group's evidence between
  its members is how a wrong deletion survives its own evidence.

### 3. The warrant, and what it is not

A consequential deletion is warranted when the watch closes with its qualifying-session count met
and zero attributed rows. The removing commit cites the watch record, exactly as unhobble's
restoring commit cites its ledger rows.

Three things this explicitly is not:

- **Not a proof of harmlessness.** It is bounded evidence over a stated window, and the window is
  named in the commit so a later reader can judge its weight.
- **Not available for a protected class.** A rule matching the [instruction exception
  register](../conventions/instruction-exception-register/README.md) is not deletable at all,
  so it never enters a watch. Compression in place or hook conversion are its remedies.
- **Not required for the editorial tier.** Derivable content, restated obviousness, and stale
  model-era scaffolding are deleted on the auditing skill's normal criteria without a watch. The
  watch is the price of removing something that governs behavior, not of tidying.

## Why not simply run the bare experiment per rule

Considered and rejected: strip one rule, work, observe. It is the cleanest possible attribution and
it is unaffordable. The experiment's cost is a full branch-local strip plus a working period per
rule, and an instruction surface has tens of candidates. The watch above buys most of the
attribution for the marginal cost of recording a decision that was being made anyway, and it
degrades honestly (an expired watch resolves nothing) where a shortcut would degrade silently.

## Adoption

Not yet wired into a skill. The mechanism is recorded here so the sign-off's consequential tier has
a specification to point at; wiring it into `claude-config:unhobble` (as a deletion mode alongside
the re-add gate, sharing the ledger grammar) is tracked separately. Until that lands, the
consequential tier remains unclearable in practice, which is the honest state and is preferable to
a tier that clears itself on absent evidence.
