# Upstream source: emilkowalski/skills

Single source of truth for everything in this marketplace derived from
[emilkowalski/skills](https://github.com/emilkowalski/skills), MIT, Emil Kowalski's agent skills for
UI craft: animation, interface review, worst-case content, touch polish and prototyping. Provenance
lives here and in plugin changelog fragments, never in skill files, where it is agent-facing noise.

**Pinned upstream state:** `main@2d228630ba1446365f614a108cb8252f1feda202` (committed
2026-10-11T15:58:32+02:00). The repository has no tags or releases, so the pin is a commit. It
installs through `npx skills add`; this marketplace takes none of that path and ships the content as
its own plugin skills and references.

**Adaptation posture.** Every row is a **reauthor**, not a fork and not a vendored copy. Substance
that earns its place is kept, verbatim where the wording carries it; the wrapper follows this
marketplace's conventions. Two rules shape every row:

- **Stack-agnostic.** Upstream targets React, Framer Motion, Tailwind, Sonner and Vaul. Shipped
  text keeps only principles that hold on any stack; a skill detects the project's stack and looks
  up that stack's current guidance at run time. A plain-CSS example survives only as a separate,
  dated illustration framed "adapt this to the project's framework, language and styling model".
- **Configurable taste.** Upstream's numbers (curves, durations, gesture threshold, blur limit) are
  defaults in the `user-interface` config cascade, overridden by team and user config and beaten by
  the project's own tokens.

Dropped without further note in each row: the canned "I'm ready to..." openers, the first-person
persona voice, cross-skill pointers to upstream skill names, and the `npx` install lines.

**MIT notice.** `Copyright (c) 2026 Emil Kowalski`. Each plugin that takes a substantial portion of
the text carries the full notice in its own `LICENSE`, beside a Melodic Software line for the
reauthored derivative: [`user-interface`](../../plugins/user-interface/LICENSE),
[`testing`](../../plugins/testing/LICENSE), [`prototype`](../../plugins/prototype/LICENSE).

- **Pointer**: re-audit by diffing upstream against the pin:
  <https://github.com/emilkowalski/skills/compare/2d228630ba1446365f614a108cb8252f1feda202...main>.
- **As of**: 2026-10-11
- **Recheck trigger**: the weekly drift check
  (`plugins/user-interface/scripts/check-emilkowalski-drift.sh`, run by
  `.github/workflows/maintenance-check-upstream-drift.yml`) reports a changed, removed or new file.
- **Re-pin procedure**: diff each flagged file against the pin, update the affected rows below and
  the shipped text they name, then update the pin and blob SHAs in the drift script and this file
  in the same change.

## Attribution table

Blob SHAs are `git hash-object` values at the pin; the drift script pins the same values.

| Upstream path | Blob SHA at the pin | Ours | Relation | Taken / rejected |
|---|---|---|---|---|
| `LICENSE` | `57b46f1fd11dc62351ea548104a88aa3f659c11b` | Per-plugin `LICENSE` files (above) | Notice | **Taken:** the MIT notice. |
| `README.md` | `3cc865e4f4d678c29dd938d11f96342942b7b52c` | This record | Omitted | **Taken:** the skill list and license facts. **Rejected:** the `npx skills add` install line, which would update outside the marketplace, and the newsletter links. |
| `.gitattributes` | `a0652a605e6b418261a2b4fb1ad82576be0c3b53` | none | Omitted | Repository plumbing. |
| `.gitignore` | `e43b0f988953ae3a84b00331d0ccf5f7d51cb3cf` | none | Omitted | Repository plumbing. |
| `.pl` | `e69de29bb2d1d6434b8b29ae775ad8c2e48c5391` | none | Omitted | An empty stray file. |
| `performance-cheatsheet.md` | `5b279577685cebabbfbb0197bd6b3a74591b3392` | `user-interface` `reference/animation/performance.md` | Absorbed | **Taken:** the property-cost and `will-change`-last rows, merged into the performance reference. **Rejected:** library-specific rows as rules (kept only as stack lookups at run time). |
| `skills/emil-design-eng/SKILL.md` | `62ce902af8dd32c590ea7203e9ab2edb1d6ef81a` | `user-interface` `reference/animation/` (catalog, behaviors, gestures) | Absorbed (skill omitted) | **Taken:** the animation decision framework, springs and interruptibility, transform origin, stagger, gesture handling and the debugging checklist. **Rejected:** the non-motion design rules the `design` skill already covers; framework-specific code as guidance. |
| `skills/animate/SKILL.md` | `7c3b20c6ed681b2d47c9ca9e3ee0e659ed47d032` | [`/user-interface:write-animation`](../../plugins/user-interface/skills/write-animation/SKILL.md) | Derived | **Taken:** the build sequence (decide whether to animate, then purpose, properties, curve, duration, origin, reduced motion), the hard rules and the feel check. **Changed:** project tokens first, stack detection and run-time lookup, CSS authoring delegated to `/user-interface:write-css`. |
| `skills/animate/RECIPES.md` | `6744891261bdf0bb0473d77f2cc706f2d78b574e` | `user-interface` `reference/animation/behaviors.md` | Derived | **Taken:** each recipe's behavior (what moves, properties, curve, duration, origin, interruptibility, reduced-motion fallback) as a stack-neutral spec. **Rejected:** the CSS and JS blocks as shipped code; library-specific attributes. |
| `skills/animation-vocabulary/SKILL.md` | `5ab2976514c74a194ebf069506d95ff3a5a0084f` | `user-interface` `reference/animation/glossary.md` | Absorbed (skill omitted) | **Taken:** the terms by category and the reverse lookup from the effect someone wants to its name. |
| `skills/animation-performance/SKILL.md` | `d688dd7c3ba143c6ae17efd2bc665380d5252c5a` | `user-interface` `reference/animation/performance.md`; the `performance` focus of [`/user-interface:audit-animation`](../../plugins/user-interface/skills/audit-animation/SKILL.md) | Absorbed (skill omitted) | **Taken:** the frame budget, property cost tiers, cheaper-property swaps, main-thread versus off-thread drivers, the per-frame re-render and inherited-variable traps, `will-change` last, the ordered cause list and the "verified from code / needs a device recording" labels. **Rejected:** library and product anecdotes as rules; browser-support lists, replaced by dated pointers. |
| `skills/apple-design/SKILL.md` | `adf68c517f2d7d2781587d619de07f4de286da57` | `user-interface` `reference/animation/gestures.md` | Partial | **Taken:** fluid-interface principles, momentum projection and rubber-banding math, velocity handed to the spring. **Deferred:** materials and typography notes. |
| `skills/ask-sonner/SKILL.md` | `6cf9217f409315466ecfd7796de4591879983637` | none | Omitted | One library's API, the kind of specific a skill looks up at run time. |
| `skills/ask-sonner/API.md` | `d2b0f3cf93d9495a8496275dc6e70199302df0f1` | none | Omitted | Prop tables, the most volatile content in the corpus. |
| `skills/break-ui/SKILL.md` | `091a28d488662d2451131f1aaa60a6dcd2391932` | The `worst-case` action of [`/testing:run-e2e`](../../plugins/testing/skills/run-e2e/SKILL.md) | Derived, re-posture | **Taken:** mapping every rendered value, the worst-case fixture shaped like the demo data, the environments, the failure-signature table, the truncate-wrap-clamp rule and the three-part report. **Changed:** report-first, injection at the network layer where possible, a backup and a proven revert, the fixture kept only on request. **Rejected:** a standalone skill. |
| `skills/break-ui/CATALOG.md` | `46962bb89445b8526ea94994a79b49508573b5fd` | `testing` `skills/run-e2e/context/worst-case.md` | Derived | **Taken:** the worst-case values for people, states and environment, extendable by a consumer file. |
| `skills/find-animation-opportunities/SKILL.md` | `d3b030fbca9abad9220a032f72d425c6b7fa2de8` | The `opportunities` focus of `/user-interface:audit-animation` | Absorbed (skill omitted) | **Taken:** the search for places motion helps and the list of what not to animate. |
| `skills/improve-animations/SKILL.md` | `d6e77f37272329af0cc36f9eeedbe5226e86ce63` | The `tree` focus of `/user-interface:audit-animation` | Partial | **Taken:** the codebase-wide audit and prioritization. **Rejected:** plan files written into the consumer's repository root; implementation hands off to `/implementation:implement` when installed. |
| `skills/improve-animations/AUDIT.md` | `94056154e532d695b8792ea67d701625b4f43b6e` | `user-interface` `reference/animation/catalog.md` | Absorbed | **Taken:** the audit categories as the catalog's sections. |
| `skills/improve-animations/PLAN-TEMPLATE.md` | `239026b91f8032df191dde2085fd796b8c116d91` | `user-interface` `reference/animation/catalog.md` | Partial | **Taken:** the feel-check block. **Rejected:** the plan file shape. |
| `skills/review-animations/SKILL.md` | `577a64397267ce20960de2202950594d5bd6f9b6` | The default (diff) scope of `/user-interface:audit-animation` | Derived, re-posture | **Taken:** the review standards and escalation triggers as catalog-backed checks. **Changed:** read-only by default; an explicit `--fix` applies one finding at a time. |
| `skills/review-animations/STANDARDS.md` | `863ea12ea94c1f7a47b5f7e1019e976aa82bd4cd` | `user-interface` `reference/animation/catalog.md` | Absorbed | **Taken:** the standards, de-duplicated with `AUDIT.md`, with the corpus's internal contradictions resolved. |
| `skills/mobile-native/SKILL.md` | `94bba21fcb990b850e06effbf5709c96a07446ad` | `user-interface` `reference/types/touch-web.md` | Derived, re-posture | **Taken:** capability-based touch rules: hover gated by pointer capability, tap highlight, safe areas, dynamic viewport units, no zoom lock, target sizes. **Rejected:** framework-specific setup. |
| `skills/pick-ui-library/SKILL.md` | `5e0028e988b88d2a88a019fdc978b4732243e467` | `user-interface` `reference/component-libraries.md` | Partial | **Taken:** identify the task rather than the library named; prefer a library already installed; selection criteria. **Rejected:** the library list as guidance (one framework, quickly stale). |
| `skills/prototype/SKILL.md` | `dbcc1a23c66933f7372c0aacbce2b0d7cc6100b6` | [`/prototype:explore-directions`](../../plugins/prototype/skills/explore-directions/SKILL.md) and `prototype` `context/discipline.md` | Absorbed (skill omitted) | **Taken:** variants differ on a named axis, the tradeoff table, never pre-pick a winner, cut a converged variant. |
| `skills/prototype/PICKER.md` | `aaa88c0eba38eb01c00d4eb2b144e39f808fc26a` | `prototype` `skills/explore-directions/assets/variant-switcher.html` | Derived | **Taken:** the floating switcher's controls and behavior. **Rejected:** URL persistence, which a `file://` page cannot rely on. |
| `skills/animate-expo/SKILL.md` | `78b39e1d22e8c3c15be96ccebe04bf39792f3455` | Routed to `expo@expo-plugins` in `user-interface` `reference/routing.json` | Omitted | The platform vendor's own plugin covers it. |
| `skills/animate-expo/RECIPES.md` | `a02e6b80f9dec86f196590f2f7a4fe3310ea1cb4` | none | Omitted | Its shared gesture math is taken from `apple-design` instead. |
| `skills/write-swift/SKILL.md` | `a09a8f693304fe1c04ed56d61dde9833a516849e` | none | Omitted | One language, no interface surface in this marketplace. |
