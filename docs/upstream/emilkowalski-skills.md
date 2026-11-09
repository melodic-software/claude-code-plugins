# Upstream source: emilkowalski/skills

Single source of truth for everything in this marketplace derived from
[emilkowalski/skills](https://github.com/emilkowalski/skills), MIT, Emil Kowalski's agent skills for
UI craft: animation, interface review, worst-case content, touch polish and prototyping. Provenance
lives here and in plugin changelog fragments, never in skill files, where it is agent-facing noise.

**Last audited upstream state:** `emilkowalski/skills@5206a950b715e0cabe7043ea0b2304332b91494e` under `skills/` (committed 2026-11-08T12:15:47Z; no tags or releases).

Upstream's skills install through `npx skills add`; this marketplace takes none of that path and
ships the content as its own plugin skills and references.

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

- **Pointer**: when re-auditing a row, fetch the compare view of upstream against the pin live:
  <https://github.com/emilkowalski/skills/compare/5206a950b715e0cabe7043ea0b2304332b91494e...main>.
- **As of**: the 40-hex pin above stands in for the as-of date: the commit fixes exactly what was
  read, and this page's git history records when.
- **Recheck trigger**: a change, between the pinned commit and upstream HEAD, to a path a row we
  took or rejected something from links, a unit removed or added under the scope: re-audit the
  affected rows. `scripts/check-upstream-drift.sh` detects these, and the monthly drift issue for
  this upstream lists them
  ([upstream-drift convention, "Pinned git upstreams"](../contracts/upstream-drift/README.md#pinned-git-upstreams)).
- **Re-pin procedure**: re-auditing the affected rows moves the pin and records the outcome per row,
  as [When a trigger fires](../contracts/upstream-drift/README.md#when-a-trigger-fires) requires:
  diff each flagged path against the pin, update the rows below and the shipped text they name,
  move the pin on the marker line and in every upstream link, `## Map` included, and run
  `scripts/check-upstream-drift.sh --links` on this page.

## Attribution table

Each upstream link is at the pin.

| Upstream path | Ours | Relation | Taken / rejected |
|---|---|---|---|
| [`LICENSE`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/LICENSE) | Per-plugin `LICENSE` files (above) | Notice | **Taken:** the MIT notice. |
| [`README.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/README.md) | This record | Omitted | **Taken:** the skill list (now including `choreograph` and `gestures`) and license facts. **Rejected:** the `npx skills add` install line, which would update outside the marketplace, and the newsletter links. |
| [`performance-cheatsheet.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/performance-cheatsheet.md) | `user-interface` `reference/animation/performance.md` | Absorbed | **Taken:** the property-cost and `will-change`-last rows, merged into the performance reference. **Rejected:** library-specific rows as rules (kept only as stack lookups at run time). |
| [`ui-cheatsheet.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/ui-cheatsheet.md) | `user-interface` `reference/types/web/generic-defaults.md` section 10, `reference/types/web/layout-stability.md` section 7 | Partial | **Taken:** absolute dates after a week, `Intl.PluralRules`, `flex-shrink: 0` on an avatar. **Already covered:** the other eight rows. |
| [`skills/choreograph/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/choreograph/SKILL.md) | `user-interface` `reference/animation/catalog.md` `choreography`, `behaviors.md` `view-swap`; a step-6 pointer in `/user-interface:write-animation` | Absorbed (skill omitted) | **Taken:** a role for each moving element, a single entrance for a container, the per-pair relationship (together by default, then overlap, sequence or carry), stagger ordered by importance with treatment varied by role, one timing family per component, secondary motion hooked to the lead, timing scaled to how much changed, direction and all-at-once group exits, interruption of a multi-part sequence, idle attention loops, reduced motion that collapses the group, and the timeline written before code. It replaces the catalog's earlier line that sequenced clashing elements by default. **Already covered:** high-frequency surfaces skip stagger and stagger never blocks input (`should-it-animate`, `stagger`), larger marketing offsets (`section-entrance`), exits shorter than entrances (`duration`, `exit`), leaving elements releasing their slot (`group-exit`), untrusted repository content. **Rejected:** the stagger interval and total figures (the `animation.stagger_ms` config and `aiforui-course.md` govern), the attention-loop and resize-clamp numbers (no config key earns them yet), library calls as guidance (run-time lookups), and a standalone skill. |
| [`skills/choreograph/RECIPES.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/choreograph/RECIPES.md) | `user-interface` `behaviors.md` `group-exit` and `view-swap` | Partial | **Taken:** the library-free slot release for a leaving element, the resize-scaled content fade, direction reaching a leaving view, the small-container crossfade, the duplicate-view option for a dense morph, and the stable-key check. **Already covered:** the index-variable CSS stagger and its fill mode (`section-entrance`). **Rejected:** every code block as shipped code, and per-library APIs as rules, each a run-time lookup. |
| [`skills/gestures/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/gestures/SKILL.md) | `user-interface` `reference/animation/gestures.md` `direct-manipulation` and `linked-progress`, `behaviors.md` `drag-to-dismiss`, `catalog.md` `reduced-motion`; config key `animation.gesture.distance_threshold` | Absorbed (skill omitted) | **Taken:** no spring or transition while tracking, one progress value driving linked visuals, a fast spring-back, and pointer tracking kept under reduced motion with momentum and bounce dropped. `animation.gesture.distance_threshold` defaults to `0.4`, the low end of his 40-50% of travel; no measured fact or accessibility floor changed it. **Already covered:** the velocity-seeded release spring (`velocity-handoff`), dismissal on a flick (`animation.gesture.velocity_threshold`), edge resistance (`rubber-banding`), catching a motion mid-flight (`interruptible`), writing the moving value on the element (`drag-details`), linear hold timing (`hold-to-confirm`), and the touch checklist (`reference/types/touch-web.md`). **Deferred:** dismissing in the direction an element entered. **Rejected:** the 500ms sheet duration and the position settle under reduced motion (`aiforui-course.md` wins any conflict with this upstream, and the catalog's floor removes movement), library drag props and thresholds as guidance (run-time lookups), and a standalone skill. |
| [`skills/emil-design-eng/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/emil-design-eng/SKILL.md) | `user-interface` `reference/animation/` (catalog, behaviors, gestures) | Absorbed (skill omitted) | **Taken:** the animation decision framework, springs and interruptibility, transform origin, stagger, gesture handling and the debugging checklist. **Rejected:** the non-motion design rules the `design` skill already covers; framework-specific code as guidance. **Superseded in part:** the catalog's easing, exit, duration, stagger and reduced-motion wording follows `docs/upstream/aiforui-course.md`. |
| [`skills/animate/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/animate/SKILL.md) | [`/user-interface:write-animation`](../../plugins/user-interface/skills/write-animation/SKILL.md) | Derived | **Taken:** the build sequence (decide whether to animate, then purpose, properties, curve, duration, origin, reduced motion), the hard rules and the feel check. **Changed:** project tokens first, stack detection and run-time lookup, CSS authoring delegated to `/user-interface:write-css`. |
| [`skills/animate/RECIPES.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/animate/RECIPES.md) | `user-interface` `reference/animation/behaviors.md` | Derived | **Taken:** each recipe's behavior (what moves, properties, curve, duration, origin, interruptibility, reduced-motion fallback) as a stack-neutral spec. **Rejected:** the CSS and JS blocks as shipped code; library-specific attributes. **Superseded in part:** component recipes added and re-timed per `docs/upstream/aiforui-course.md`. |
| [`skills/animation-vocabulary/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/animation-vocabulary/SKILL.md) | [`/user-interface:glossary`](../../plugins/user-interface/skills/glossary/SKILL.md) | Absorbed | **Taken:** the terms by category and the reverse lookup from the effect someone wants to its name. |
| [`skills/animation-performance/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/animation-performance/SKILL.md) | `user-interface` `reference/animation/performance.md`; the `performance` sub-mode of the motion lane of [`/user-interface:audit`](../../plugins/user-interface/skills/audit/SKILL.md) | Absorbed (skill omitted) | **Taken:** the frame budget, property cost tiers, cheaper-property swaps, main-thread versus off-thread drivers, the per-frame re-render and inherited-variable traps, `will-change` last, the ordered cause list and the "verified from code / needs a device recording" labels. **Rejected:** library and product anecdotes as rules; browser-support lists, replaced by dated pointers. **Superseded in part:** the `transition: all`, blur, `will-change` and library-shorthand text follows `docs/upstream/aiforui-course.md`. |
| [`skills/apple-design/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/apple-design/SKILL.md) | `user-interface` `reference/animation/gestures.md` | Partial | **Taken:** fluid-interface principles, momentum projection and rubber-banding math, velocity handed to the spring. **Deferred:** materials and typography notes. |
| [`skills/break-ui/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/break-ui/SKILL.md) | The `worst-case` action of [`/testing:run-e2e`](../../plugins/testing/skills/run-e2e/SKILL.md) | Derived, re-posture | **Taken:** mapping every rendered value, the worst-case fixture shaped like the demo data, the environments, the failure-signature table, the truncate-wrap-clamp rule and the three-part report. **Changed:** report-first, injection at the network layer where possible, a backup and a proven revert, the fixture kept only on request. **Rejected:** a standalone skill. |
| [`skills/break-ui/CATALOG.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/break-ui/CATALOG.md) | `testing` `skills/run-e2e/context/worst-case.md` | Derived | **Taken:** the worst-case values for people, states and environment, extendable by a consumer file. |
| [`skills/find-animation-opportunities/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/find-animation-opportunities/SKILL.md) | The `opportunities` sub-mode of the motion lane of `/user-interface:audit` | Absorbed (skill omitted) | **Taken:** the search for places motion helps and the list of what not to animate. |
| [`skills/improve-animations/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/improve-animations/SKILL.md) | The `tree` scope of `/user-interface:audit` | Partial | **Taken:** the codebase-wide audit and prioritization. **Rejected:** plan files written into the consumer's repository root; implementation hands off to `/implementation:implement` when installed. |
| [`skills/improve-animations/AUDIT.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/improve-animations/AUDIT.md) | `user-interface` `reference/animation/catalog.md` | Absorbed | **Taken:** the audit categories as the catalog's sections. |
| [`skills/improve-animations/PLAN-TEMPLATE.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/improve-animations/PLAN-TEMPLATE.md) | `user-interface` `reference/animation/catalog.md` | Partial | **Taken:** the feel-check block. **Rejected:** the plan file shape. |
| [`skills/remove-animations/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/remove-animations/SKILL.md) | The `removal` sub-mode of the motion lane of `/user-interface:audit` | Absorbed (skill omitted) | **Taken:** the reversed burden of proof, delete, reduce and keep verdicts, the required kept list, the removal hazards and the cleanup. **Changed:** the gate is the catalog's `should-it-animate`, and reductions use the resolved config's roles rather than fixed numbers; read-only unless `--fix`. **Rejected:** a standalone skill; library-specific sweep terms as rules. |
| [`skills/review-animations/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/review-animations/SKILL.md) | The default (diff) scope of `/user-interface:audit` | Derived, re-posture | **Taken:** the review standards and escalation triggers as catalog-backed checks. **Changed:** read-only by default; an explicit `--fix` applies one finding at a time. |
| [`skills/review-animations/STANDARDS.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/review-animations/STANDARDS.md) | `user-interface` `reference/animation/catalog.md` | Absorbed | **Taken:** the standards, de-duplicated with `AUDIT.md`, with the corpus's internal contradictions resolved. **Superseded in part:** the catalog's graded findings and its ease-in row follow `docs/upstream/aiforui-course.md`. |
| [`skills/mobile-native/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/mobile-native/SKILL.md) | `user-interface` `reference/types/touch-web.md` | Derived, re-posture | **Taken:** capability-based touch rules: hover gated by pointer capability, tap highlight, safe areas, dynamic viewport units, no zoom lock, target sizes. **Rejected:** framework-specific setup. **Superseded in part:** the course record [`aiforui-course.md`](aiforui-course.md) (S29, S37) now shapes this file, with course wording verbatim and Tailwind and Next.js notes as dated pointers. |
| [`skills/pick-ui-library/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/pick-ui-library/SKILL.md) | `user-interface` `reference/component-libraries.md` | Partial | **Taken:** identify the task rather than the library named; prefer a library already installed; selection criteria. **Rejected:** the library list as guidance (one framework, quickly stale); a React primitives table with pointer records and a `components.primitives_default` setting stand in its place. |
| [`skills/prototype/SKILL.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/prototype/SKILL.md) | [`/prototype:explore-directions`](../../plugins/prototype/skills/explore-directions/SKILL.md) and `prototype` `context/discipline.md` | Absorbed (skill omitted) | **Taken:** variants differ on a named axis, the tradeoff table, never pre-pick a winner, cut a converged variant. |
| [`skills/prototype/PICKER.md`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/skills/prototype/PICKER.md) | `prototype` `skills/explore-directions/assets/variant-switcher.html` | Derived | **Taken:** the floating switcher's controls and behavior. **Rejected:** URL persistence, which a `file://` page cannot rely on. |

## Map

Units we took nothing from; each counts only if removed upstream.

- [`.gitattributes`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/.gitattributes)
  and [`.gitignore`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/.gitignore):
  repository plumbing.
- [`.pl`](https://github.com/emilkowalski/skills/blob/5206a950b715e0cabe7043ea0b2304332b91494e/.pl):
  an empty stray file.
- [`skills/ask-sonner`](https://github.com/emilkowalski/skills/tree/5206a950b715e0cabe7043ea0b2304332b91494e/skills/ask-sonner):
  one library's API and prop tables, the most volatile content in the corpus and the kind of
  specific a skill looks up at run time.
- [`skills/animate-expo`](https://github.com/emilkowalski/skills/tree/5206a950b715e0cabe7043ea0b2304332b91494e/skills/animate-expo):
  the platform vendor's own plugin covers it, so `user-interface` `reference/routing.json` routes
  to `expo@expo-plugins`; its shared gesture math is taken from `apple-design` instead.
- [`skills/write-swift`](https://github.com/emilkowalski/skills/tree/5206a950b715e0cabe7043ea0b2304332b91494e/skills/write-swift):
  one language, no interface surface in this marketplace.
