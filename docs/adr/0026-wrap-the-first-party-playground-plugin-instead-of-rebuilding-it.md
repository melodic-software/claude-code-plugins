# Wrap the first-party playground plugin instead of rebuilding it

- Status: accepted
- Date: 2026-09-01

## Context

Anthropic's playground plugin (`playground@claude-plugins-official`) generates
interactive single-file HTML explorers whose output is a prompt pasted back into the
session. A 27-resource verified corpus (the announcement X article, the plugin source at
commit `ed404106fcd80ba98ecb7c851e531dcb626d13b7`, the Agent Skills standard site, and
seven implicated official docs pages) was mapped, digested, and worked through a full
decision chain: relentless interview rounds, discovery exploration and research with
independent fresh-context verifiers, blindspot/brainstorm passes, a devils-advocate
stress test, and per-answer adversarial validation, each verdict user-signed. The
working contracts lived in the branch's contract slices and prune with it per the
topic-docs convention; the shipping PR (#3618) carries both Briefs and the verification
record.

The corpus showed a valuable pattern with a rough reference implementation: three
incompatible output-prompt shapes across six templates, self-contradictory theming, a
partially stubbed prompt generator, an unescaped-innerHTML rendering shortcut, and a
desktop-only launch assumption. Genuine alternatives existed: build a hardened
competing implementation, integrate by routing lines alone, or ignore the capability.

## Decision

Wrap, never rebuild. The marketplace ships a thin `playgrounds` plugin that points to
the first-party implementation: a declared cross-marketplace dependency (with
`allowCrossMarketplaceDependenciesOn` on the root marketplace), provenance-based
presence checking, cross-plugin invocation with visible degradation, install uplift,
feature-detected cloud delivery guidance, recipes, and commit-stamped consumer notes.
It generates nothing itself; upstream owns generation, templates, and the
output-prompt contract. Overlap is recorded as human-gated registry verdicts (a
`marketplace-plugin` engine lane was added for exactly this class), and routing lives
in the two adjacent skills' own surfaces.

Two policies bind follow-on work:

- **No upstream contributions for the findings from this effort.** Defects observed in
  the upstream plugin at the pinned commit are recorded in this marketplace's registry
  evidence and consumer notes only, phrased as consumer guidance; nothing is filed to
  `anthropics/claude-plugins-official` (owner directive, 2026-09-01).
- **The design-sync family stays observation-only.** The binary-registered
  design-sync/consent/revoke/login surfaces are recorded as a `defer` registry row;
  no integration text ships until an operator adopts claude.ai/design or the family
  is documented upstream.

## Consequences

Consumers reach the maintained implementation in one step and inherit upstream
improvements for free; the wrapper's exit cost is a degradation to guidance. The
marketplace carries a live cross-marketplace dependency whose failure mode
(`failed to load` with the documented remedy) was verified empirically on CLI 2.1.251,
and this repository's own cloud sessions record the plugin `false` in enablement
because their environment lacks the official marketplace. Follow-on work is tracked as
issues #3612-#3616 (deferred corpus verticals) and #3617 (the user-run pilot whose
learnings feed wrapper content). Upstream drift past the pinned commit is observable
via the registry's `--upstream-sha` self-check seam and each row's recheck trigger.
