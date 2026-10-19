---
bump: minor
---

### Added

- `/planning:design`: the design defaults name the principles in `reference/design-principles.md` (SRP, OCP, LSP, ISP, DIP, composition over inheritance, reuse and DRY of knowledge, coupling and cohesion, information hiding, deep modules, YAGNI) and apply a new `reference/design-defaults.md` first: the Brief's quality bar, the consumer's standards through the standards-contract ladder, the Brief's quality requirements as settled (the interview's prompt list when none are recorded), generalize-now-or-wait under the interview's unattended rule, and a per-tenant configurability line labeled as vendor guidance.
- `/planning:design`: a new "Lifecycle and reversibility" section with `reference/reversibility.md`: each significant decision is called a one-way or two-way door, a one-way door gets deliberate design and an ADR prompt, the consumer's existing style is the baseline with a greenfield vertical slice as an overridable default, design investment scales by core, supporting or generic subdomain, and the depth scales with the quality bar (a prototype skips it and records a TAGGED-DEFERRED thread that `/planning:design-handoff` accepts); early-exit, `status` and trivial work skip the section.
- `/planning:design`: the design defaults write a `Principles` thread naming the principles and consumer overrides that shaped the design and how generalize-now-or-wait was settled, citing the Brief's `Intent:` line counts; a prototype records it as `deferred (prototype)`.
