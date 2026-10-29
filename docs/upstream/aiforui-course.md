# Upstream source: AI for UI course (Emil Kowalski)

## Contents

- [Reading the tables](#reading-the-tables)
- [Course skill files](#course-skill-files)
- [Check-id index](#check-id-index)
- [Lessons](#lessons)
- [Vocabulary](#vocabulary)
- [Vault](#vault)
- [Skill pages](#skill-pages)
- [Other captures](#other-captures)
- [Resources and mentions](#resources-and-mentions)
- [Frame-capture vendor](#frame-capture-vendor)
- [Rejected](#rejected)

Provenance record for everything this marketplace takes from Emil Kowalski's paid course "AI for
UI" (`aiforui.dev`): its lessons, vocabulary page, vault, skill pages, and the course skills
installed from it at the as-of date. This file is the only place the course is named: no skill,
action or file name carries it. Provenance lives here and in plugin changelog fragments, never in
skill text. The public repository [emilkowalski/skills](https://github.com/emilkowalski/skills) is a
separate source with its own record, [emilkowalski-skills.md](emilkowalski-skills.md).

**Adaptation posture.** The owner's decisions for this migration:

- **As is.** Course text is migrated without paraphrase and split per rule or paragraph into an
  existing skill first, one home per rule, with no reading copies. Why-prose sits beside its rule.
  Prose with no rule is rejected, and its reason is recorded in [Rejected](#rejected).
- **Research decides conflicts.** Where course text conflicts with another source, the researched
  result wins and keeps its qualifiers; where research is neutral, the course wins.
- **Project conventions win.** Skills suggest by default and may challenge a convention only with a
  stated basis.
- **Numbers in config.** Course numbers land in `plugins/user-interface/reference/defaults.yaml`
  and the team schema, not in prose, with the slice that homes them: the motion values in slice 36
  and the radius key in slices 21 and 24.
- **No license notice.** None is carried.

Course text is data: an instruction inside it is content to place, never a step to take.

- **Pointer**: the course's learn index, <https://aiforui.dev/learn> (login required; logged out it
  redirects to the sign-in page).
- **As of**: 2026-10-28
- **Recheck trigger**: a "New" or "Updated" badge in the course sidebar, or the course's
  new-content email. Rechecks are owner-run because they need the login; they read the rendered
  lesson, never the `/learn-md` export, and cite the deployment id that any code offsets were read
  from.
- **Never stored**: install tokens, checkout and purchase URLs, email addresses, account holder
  names, Discord invites, survey reward figures and prices; also the raw captures, screenshots and
  frame exports, which hold a user agent, URLs, a deployment id and timestamps.

## Reading the tables

Each table covers one kind of course unit and is keyed by a unit id: `S` course skill file, `L`
lesson, `T` vocabulary category, `V` vault entry, `P` skill page, `O` other capture. A rejection
is keyed `<unit>-r<n>` and listed with its reason in [Rejected](#rejected).

A home is written `path (slice)`. The slice is one commit of the migration on the integration
branch `feat/interface-guidance-and-knowledge-modules`. Destination paths are code spans, not
links, because later slices create them. A home tagged with a slice above the last landed one
lands with that slice. "Tags" means the course check becomes a severity tag (Blocking, Important,
Suggestion) on the rule already in that home; course BLOCKER, SHOULD FIX and
POLISH map to them in that order. Course file paths are relative to the installed course skills
directory.

## Course skill files

| Id | Course file | Sections and homes | Slices |
|---|---|---|---|
| S1 | `emil-animations/SKILL.md` | Quick Reference: rejected (`S1-r1`). Decision Framework 1 Should this animate at all; Decision Framework 2 Which easing; Decision Framework 3 What duration: `plugins/user-interface/reference/animation/catalog.md` should-it-animate, easing, duration (36); numbers to `plugins/user-interface/reference/defaults.yaml` (36). Core Principles: per item `plugins/user-interface/reference/animation/catalog.md` physicality, interruption-and-exit, springs, why-lines beside each (36). Common Mistakes, Review checklist: tags on those catalog rules (36) | 36 |
| S2 | `emil-animations/patterns.md` | Modal / Dialog; Drawer / Sheet; Popover / Dropdown Menu; Tooltip; Toast; Entrances: Split, Then Stagger; Exit Animations; Contextual Icon Swaps; Press Feedback; Don't Animate on Page Load; AnimatePresence Grouping; Looping Animations: `plugins/user-interface/reference/animation/behaviors.md` sections (36); popover and dialog CSS to `plugins/user-interface/skills/write-css/reference/show-and-hide.md` (36) | 36 |
| S3 | `emil-animations/techniques.md` | Easing Curve Library: values to `plugins/user-interface/reference/defaults.yaml`, names to `plugins/user-interface/reference/animation/catalog.md` easing (36). Springs; Interruptibility: Transitions vs. Keyframes: `plugins/user-interface/reference/animation/gestures.md` spring parameters, interruptible (36). Performance: `plugins/user-interface/reference/animation/performance.md` (36). Reduced Motion: `plugins/user-interface/reference/animation/catalog.md` reduced-motion, recipe `plugins/user-interface/skills/write-css/reference/motion.md` (36). Debugging & Polish Fixes; Final Calibration: `plugins/user-interface/reference/animation/catalog.md` feel-check, diagnosis to `plugins/user-interface/reference/animation/performance.md` diagnose (36) | 36 |
| S4 | `emil-ask-emil/SKILL.md` | Route in two questions; Decide; Start here; Build; Refine; Check: `plugins/user-interface/skills/design/SKILL.md` section "Order of work", rows naming our skills (40). Underneath: `plugins/user-interface/skills/glossary/SKILL.md` description and design `## Next` (6, 40). Standalone: rejected (`S4-r1`). Overlaps; Stacking: `plugins/user-interface/reference/routing.json` precedence rows and each skill's `## Next`, overlap notes beside the concern in "Order of work" (40). When nothing fits: already-have (`plugins/user-interface/skills/design/SKILL.md` Combine routes), no change (40) | 6, 40 |
| S5 | `emil-ask-lapse/AGENTS.md` | MCP server; Playwright adapter; Browser extension: rejected (`S5-r1`), except the motion-study line (`:126`) to `plugins/prototype/skills/build-generator/reference/visual-research.md` (19) | 9, 19 |
| S6 | `emil-ask-lapse/API.md` | all sections: rejected (`S6-r1`) | 9 |
| S7 | `emil-ask-lapse/SKILL.md` | Answering posture; Name and install; Mounting; The panel; Takes; Moments; Diffs; Deeper reference: rejected (`S7-r1`). Annotations and the export; Jank and triggers; The review loop: `plugins/user-interface/skills/audit/reference/frame-capture.md` (38), capture through `/app-control:drive capture --kind animation` (38) | 9, 38 |
| S8 | `emil-ask-lapse/TROUBLESHOOTING.md` | all sections: rejected (`S8-r1`) | 9 |
| S9 | `emil-borrow-a-brain/SKILL.md` | Phase 1 Scope: `plugins/knowledge/skills/distill/SKILL.md` "1.2 Survey the book, or scope the web corpus" (17). Phase 2 Collect; Phase 3 Extract, one piece at a time; Phase 4 Cluster: `plugins/knowledge/skills/distill/reference/web-corpus.md` Collect, Extract and Cluster (17). Phase 5 Write SKILL.md: `plugins/knowledge/skills/distill/SKILL.md` Phase 4 "Web corpus target" (17). Phase 6 Test: `plugins/knowledge/skills/distill/SKILL.md` Phase 5 "Web corpus test" (17). Keeping it alive: `plugins/knowledge/skills/distill/SKILL.md` "Refresh a web corpus" (17) | 17 |
| S10 | `emil-borrow-a-brain/templates.md` | all sections: `plugins/knowledge/skills/distill/context/templates.md` corpus folder, corpus file, note, theme, glossary, article index, corpus SKILL.md, progress and continuation templates (17); cost lines rejected (`S10-r1`); pricing example bullet in the theme template rejected (`S10-r2`) | 17 |
| S11 | `emil-build-a-tool/SKILL.md` | Phase 1 Diagnose the gap; Phase 2 Suggest the tool; Phase 3 Build it; Phase 4 Harvest: `plugins/prototype/skills/build-generator/SKILL.md` (8). Invocation variants: `plugins/prototype/skills/build-generator/SKILL.md` arguments `save-output`, `add-controls`, `export <format>` (8) | 8 |
| S12 | `emil-color/SKILL.md` | Before touching any code; How to read a value; Operating principles; Numbers worth memorizing; Failure modes to catch; Going deeper: `plugins/user-interface/reference/types/web/color.md` (23). Reporting changes: audit report shape in `plugins/user-interface/skills/audit/SKILL.md` (39) | 23, 39 |
| S13 | `emil-color/building-scales.md` | all sections: `plugins/user-interface/reference/types/web/color/building-scales.md` (23) | 23 |
| S14 | `emil-color/contrast.md` | all sections: `plugins/user-interface/reference/types/web/color/contrast.md` (23) | 23 |
| S15 | `emil-color/converting-colors.md` | all sections: `plugins/user-interface/reference/types/web/color/converting-colors.md` (23) | 23 |
| S16 | `emil-color/gamut-p3-tailwind.md` | The shape of the displayable; When a value doesn't fit; Progressive enhancement for P3: `plugins/user-interface/reference/types/web/color/gamut-and-p3.md` (23). Tailwind v4: `plugins/user-interface/reference/types/web/color/tailwind.md` (23) | 23 |
| S17 | `emil-component-design/SKILL.md` | Quick Reference: rejected (`S17-r1`). Core Principles: `plugins/user-interface/reference/types/web/component-api.md` (20). Common Mistakes; Checklist: tags in `plugins/user-interface/reference/types/web/component-api.md` (20) | 20 |
| S18 | `emil-component-design/implementation.md` | all sections: `plugins/user-interface/reference/types/web/component-api/implementation.md` (20) | 20 |
| S19 | `emil-design-foundations/SKILL.md` | Quick Reference: rejected (`S19-r1`). Core Principles: restraint line to `plugins/user-interface/reference/principles.md` "Work in this order" (37), rest to `plugins/user-interface/reference/types/web/layout.md` (21). How to Review UI: audit sweep order in `plugins/user-interface/skills/audit/SKILL.md` (39). Typography: `plugins/user-interface/reference/types/web/typography.md` (22). Color: `plugins/user-interface/reference/types/web/color.md` (23). Layout & Spacing: `plugins/user-interface/reference/types/web/layout.md` (21). Information Architecture: `plugins/user-experience/reference/flows-ia.md` (16); item 4 lead-in "Tabs trick question:" rejected (`S19-r2`). Interaction: per line `plugins/user-interface/reference/types/web/layout-stability.md` (29), `plugins/user-interface/reference/types/web/states.md` (30), `plugins/user-interface/reference/types/web/accessibility.md` (33). Motion Timing: tags on `plugins/user-interface/reference/animation/catalog.md` duration (36). Accessibility: floor examples to `plugins/user-interface/reference/principles.md` Accessibility floor (37), web specifics to `plugins/user-interface/reference/types/web/accessibility.md` (33). Copywriting: `plugins/user-interface/reference/principles.md` plain-language copy rules (37). Components: per line `plugins/user-interface/reference/types/web/forms.md` (25), `plugins/user-interface/reference/types/web/states.md` (30), `plugins/user-interface/reference/component-libraries.md` (20). Common Mistakes Checklist: tags on the rules above (21, 22, 23, 25, 29, 30, 33) | 16, 20, 21, 22, 23, 25, 29, 30, 33, 36, 37, 39 |
| S20 | `emil-design-foundations/icons-and-illustrations.md` | Iconography; Illustrations: `plugins/user-interface/reference/types/web/icons.md` (27) | 27 |
| S21 | `emil-design-system-docs/SKILL.md` | Process; Button: `plugins/user-interface/reference/design-system-doc.md` procedure and worked example behind design "Fill gaps" (28) | 28 |
| S22 | `emil-design-vocabulary/SKILL.md` | Source of truth; How to use it; Near-synonyms worth disambiguating; Examples; Guidelines: `plugins/user-interface/skills/glossary/SKILL.md` (10). Categories at a glance: rejected (`S22-r1`) | 10 |
| S23 | `emil-design-vocabulary/terms-index.md` | all sections: rejected (`S23-r1`) | 10 |
| S24 | `emil-design-vocabulary/vocabulary.md` | Typography; Color; Iconography; Layout; Interaction; Motion; Accessibility; Information Architecture; Copywriting; Tools; Analysis; Components: merged by term into the `plugins/user-interface/skills/glossary/reference/` files of the [Vocabulary](#vocabulary) table, site wording kept except where the migration's vocabulary research rules (10) | 10 |
| S25 | `emil-engineering-vocabulary/SKILL.md` | Quick Start; Instructions; Examples: `plugins/user-interface/skills/glossary/SKILL.md` behavior lookup (10). Glossary: `plugins/user-interface/skills/glossary/reference/engineering.md` (10) | 10 |
| S26 | `emil-forms-and-inputs/SKILL.md` | Core Principles: 1-2 and 5-13 `plugins/user-interface/reference/types/web/forms.md` (25); 3 (16px input) `plugins/user-interface/reference/types/touch-web.md` (34); 4 (visible focus) `plugins/user-interface/reference/types/web/accessibility.md` (33); 14 (accessible primitives) `plugins/user-interface/reference/component-libraries.md` (20). Checklist; Common Mistakes: tags on those homes (25) | 20, 25, 33, 34 |
| S27 | `emil-get-creative/SKILL.md` | Phase 0 Route: `plugins/prototype/skills/build-generator/SKILL.md` diagnosis (8); two-round rule (`:34`) to `plugins/user-interface/reference/principles.md` "Work in this order" naming `build-generator` as run by a person (37). Phase 1 Research the visual language; Hard rules for the generator; Phase 2 Sort the rules into buckets: `plugins/prototype/skills/build-generator/reference/visual-research.md` (19). Phase 3 Build the tool; Phase 4 Harvest; Invocation variants: merged into `plugins/prototype/skills/build-generator/SKILL.md` (8) | 8, 19, 37 |
| S28 | `emil-marketing-pages/SKILL.md` | Core Principles; Header Navigation; Call-to-Action Buttons; Documentation Sites; Blog & Changelog; Code-Built Illustrations; Pre-Ship Checklist: `plugins/user-interface/reference/types/web/marketing-pages.md` (26). Motion Restraint: tags on `plugins/user-interface/reference/animation/catalog.md` (36). Performance: `plugins/user-interface/reference/types/web/performance.md` (35) | 26, 35, 36 |
| S29 | `emil-mobile-native/SKILL.md` | Operating Posture: audit posture lines in `plugins/user-interface/skills/audit/SKILL.md` (39). Hard Rules: `plugins/user-interface/reference/types/touch-web.md` opening rules (34). The Symptom Table: `plugins/user-interface/reference/types/touch-web.md` new H2 "Symptoms" (34). The Fixes: design rule to `plugins/user-interface/reference/types/touch-web.md` sections, code to `plugins/user-interface/skills/write-css/reference/interaction.md`, `plugins/user-interface/skills/write-css/reference/scroll-and-viewport.md` (34); 12 to `plugins/user-interface/reference/types/web/performance.md` (35); 13 to `plugins/user-interface/reference/types/web/theming.md` (31); 15 to `plugins/user-interface/reference/types/touch-web.md` "Verify on hardware" (34). Baseline: `plugins/user-interface/skills/write-css/reference/foundations.md` and `plugins/user-interface/reference/types/web.md` new H2 "Document head" (34). Never Ship: tags in `plugins/user-interface/reference/types/touch-web.md` (34). Output: audit report shape in `plugins/user-interface/skills/audit/SKILL.md` (39). Tone: rejected (`S29-r1`) | 31, 34, 35, 39 |
| S30 | `emil-performance/SKILL.md` | Core Principles: 1-3 and 5 `plugins/user-interface/reference/animation/performance.md` (36); 4 and 7-9 `plugins/user-interface/reference/types/web/performance.md` (35); 6 `plugins/user-interface/reference/types/web/layout-stability.md` (29); 10 `plugins/user-interface/reference/types/web/theming.md` (31). Review Checklist; Common Mistakes: tags on those homes (35, 36) | 29, 31, 35, 36 |
| S31 | `emil-prep-for-prod/SKILL.md` | Operating Posture; Hard Rules; Workflow; Required Output Format; Never Ship: `plugins/user-interface/skills/audit/reference/launch-scope.md` and the launch part of `plugins/user-interface/skills/audit/SKILL.md` (39); hard rule 9 (leave tools in place) is not taken; it yields to prototype discipline in `plugins/prototype/context/discipline.md` "Rules (every facet)", its `build-generator` exception (8). Invocation Variants: audit arguments (scope, lane) in `plugins/user-interface/skills/audit/SKILL.md` (39). Tone: rejected (`S31-r1`) | 39 |
| S32 | `emil-prep-for-prod/accessibility.md` | A1-A7, A10-A14, A16-A20: tags in `plugins/user-interface/reference/types/web/accessibility.md` (33). A8: `plugins/user-interface/reference/animation/catalog.md` reduced-motion (36). A9: `plugins/user-interface/reference/types/web/color/contrast.md` (23). A15: `plugins/user-interface/reference/types/touch-web.md` hover section (34). A21: launch human checklist `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 23, 33, 34, 36, 39 |
| S33 | `emil-prep-for-prod/baseline.md` | Head: `plugins/user-interface/reference/types/web.md` "Document head" (34). Root CSS: `plugins/user-interface/skills/write-css/reference/foundations.md` (34). The two gates: hover gate `plugins/user-interface/skills/write-css/reference/interaction.md` (34), reduced-motion swap `plugins/user-interface/skills/write-css/reference/motion.md` (36). Theme provider: `plugins/user-interface/reference/types/web/theming.md` (31). Dev-only mounts: `plugins/user-interface/skills/audit/reference/launch-scope.md` leftovers (39). What the baseline doesn't cover: rejected (`S33-r1`) | 31, 34, 36, 39 |
| S34 | `emil-prep-for-prod/content-and-leftovers.md` | Content: `plugins/user-interface/reference/types/web/generic-defaults.md` with fabricated proof as Blocking (32), right-characters lines to `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22), plain-language lines to `plugins/user-interface/reference/principles.md` (37). Leftovers: `plugins/user-interface/skills/audit/reference/launch-scope.md`, pointing to `/code-tidying:audit-dead-code` and `/work-items:scan-todos` for the generic part (39) | 22, 32, 37, 39 |
| S35 | `emil-prep-for-prod/forms.md` | D1-D12: tags in `plugins/user-interface/reference/types/web/forms.md` (25). D13: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 25, 39 |
| S36 | `emil-prep-for-prod/marketing.md` | I1-I13: tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26). I14: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 26, 39 |
| S37 | `emil-prep-for-prod/mobile.md` | C1-C18: tags in `plugins/user-interface/reference/types/touch-web.md` sections (34). C19: `plugins/user-interface/reference/types/touch-web.md` "Verify on hardware" (34) | 34 |
| S38 | `emil-prep-for-prod/motion.md` | F1-F4, F6-F12: tags in `plugins/user-interface/reference/animation/catalog.md` (36). F5: `plugins/user-interface/reference/animation/behaviors.md` popover (36). F13: `plugins/user-interface/reference/animation/catalog.md` feel-check (36) | 36 |
| S39 | `emil-prep-for-prod/performance.md` | B1-B4, B7, B12, B13, B15-B17: tags in `plugins/user-interface/reference/types/web/performance.md` (35). B5, B6, B8-B11: `plugins/user-interface/reference/animation/performance.md` (36). B14: `plugins/user-interface/reference/types/web/theming.md` (31). B18: launch leftovers in `plugins/user-interface/skills/audit/reference/launch-scope.md` (39). B19: launch device checklist in `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 31, 35, 36, 39 |
| S40 | `emil-prep-for-prod/stability-and-states.md` | E1-E4, E12, E13: `plugins/user-interface/reference/types/web/states.md` (30). E5-E8, E10: `plugins/user-interface/reference/types/web/layout-stability.md` (29). E9, E11: `plugins/user-interface/reference/types/web/layout.md` (21). E14: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39). Lane lead: framing, scope note and routing line rejected (`S40-r1` to `S40-r3`) | 21, 29, 30, 39 |
| S41 | `emil-prep-for-prod/theming.md` | G1, G2, G4-G9: `plugins/user-interface/reference/types/web/theming.md` (31). G3: `plugins/user-interface/reference/types/web/color/contrast.md` (23). G10: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 23, 31, 39 |
| S40 | `emil-prep-for-prod/stability-and-states.md` | E1-E4, E12, E13: `plugins/user-interface/reference/types/web/states.md` (30), with E4's skeleton-size hunt clause and `.row-skeleton` block in `plugins/user-interface/reference/types/web/layout-stability.md` (29). E5-E8, E10: `plugins/user-interface/reference/types/web/layout-stability.md` (29). E9, E11: `plugins/user-interface/reference/types/web/layout.md` (21). E14: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39). Lane lead: framing, scope note and routing line rejected (`S40-r1` to `S40-r3`) | 21, 29, 30, 39 |
| S42 | `emil-product-thinking/SKILL.md` | How to run it; The verdict; The twenty principles; When the user asks a question instead of pitching an idea; Scope: `plugins/planning/skills/interview/context/product.md` (11), its why-line as the opening paragraph; framing paragraphs rejected (`S42-r1`); sentences on where the principles come from rejected (`S42-r2`) | 11 |
| S43 | `emil-product-thinking/principles.md` | Reason to exist; What to build; How to test it; How it wins: `plugins/planning/skills/interview/reference/product-principles.md` (11); cost amounts rejected (`S43-r1`) | 11 |
| S44 | `emil-prototype/CONTROLS.md` | What goes on the panel; Two implementation rules; Placement; Replay: `plugins/prototype/context/control-panel.md` (8) | 8 |
| S45 | `emil-prototype/MIX.md` | When it runs; Building the rows; Row content; Rendering; After the choices; The decision block: `plugins/prototype/skills/explore-directions/reference/combine-matrix.md` (18) | 18 |
| S46 | `emil-prototype/PICKER.md` | Markup; Styles; Rules; Behavior contract; Reference wiring: `plugins/prototype/skills/explore-directions/reference/switcher.md` and `plugins/prototype/skills/explore-directions/assets/variant-switcher.html` (18); verbatim markup and CSS, the `?v=` URL, `data-active`, the `:active` press scale and the width-transition exception rejected (`S46-r1`) | 18 |
| S47 | `emil-prototype/SKILL.md` | Operating posture; Hard rules: `plugins/prototype/skills/explore-directions/SKILL.md` Process and Anti-patterns, duplicates as examples (18); "keep the variant, leave the picker" rejected (`S47-r2`); the course default host and "state the reason out loud" rejected (`S47-r3`); the restrained no-project palette rejected (`S47-r4`); the sub-16px inputs flag rejected here (`S47-r5`). Workflow: `plugins/prototype/skills/explore-directions/SKILL.md` Process; Phase 3 to `plugins/prototype/skills/explore-directions/reference/mockup-setup.md`; Phase 7 is the existing record step (18). Invocation variants: arguments of `plugins/prototype/skills/explore-directions/SKILL.md`: `vary <variant>`, `combine`, `controls`; the course `keep` is the existing record step (18). Tone: rejected (`S47-r1`) | 18 |
| S48 | `emil-surfaces/SKILL.md` | Match the project's styling system: already-have (`plugins/user-interface/reference/principles.md` Project first), no copy. Core Principles; Nested Radii; Depth Without Borders; Hairline Borders; Gradients and Fades; Image Outlines; Symptoms and Their Fixes; Review Checklist: `plugins/user-interface/reference/types/web/shape-and-depth.md` (24). Dark Mode Surfaces: `plugins/user-interface/reference/types/web/theming.md` (31) | 24, 31 |
| S49 | `emil-touch-and-accessibility/SKILL.md` | Core Principles: 1-3 `plugins/user-interface/reference/types/touch-web.md` (34); 4 `plugins/user-interface/reference/types/web/performance.md` media row (35); 5-7 and 9-10 `plugins/user-interface/reference/types/web/accessibility.md` (33); 8 `plugins/user-interface/reference/animation/catalog.md` reduced-motion (36). Tooltips & Menus; Feedback: `plugins/user-interface/reference/types/web/accessibility.md` (33), tooltip motion to `plugins/user-interface/reference/animation/behaviors.md` tooltip (36). Review Checklist; Common Mistakes: tags on those homes (33, 34) | 33, 34, 35, 36 |
| S50 | `emil-typography/SKILL.md` | Reference files: rejected (`S50-r1`). The rules; Auditing existing code; Fast diagnoses; Checklist: `plugins/user-interface/reference/types/web/typography.md` (22) | 22 |
| S51 | `emil-typography/font-capabilities.md` | all sections: `plugins/user-interface/reference/types/web/typography/font-capabilities.md` (22) | 22 |
| S52 | `emil-typography/line-behavior.md` | all sections: `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22) | 22 |
| S53 | `emil-typography/polish-and-accessibility.md` | Underlines; Selection and highlights; Placeholders and carets; Font smoothing; Ornamental text; The floors: `plugins/user-interface/reference/types/web/typography/details-and-floors.md` (22). Mobile input zoom: `plugins/user-interface/reference/types/touch-web.md` (34) | 22, 34 |
| S54 | `emil-typography/scale-and-rhythm.md` | all sections: `plugins/user-interface/reference/types/web/typography/scale-and-rhythm.md` (22) | 22 |
| S55 | `emil-typography/tailwind-map.md` | all sections: `plugins/user-interface/reference/types/web/typography/tailwind.md`, read only when detect reports Tailwind (22) | 22 |
| S56 | `emil-typography/typefaces-and-formats.md` | all sections: `plugins/user-interface/reference/types/web/typography/typefaces-and-formats.md` (22) | 22 |
| S57 | `emil-ui-polish/SKILL.md` | Match the project's styling system: already-have (`plugins/user-interface/reference/principles.md` Project first). Core Principles: 1 and 5 `plugins/user-interface/reference/types/web/typography/line-behavior.md` "The right characters" (22); 2-4, 6, 13 `plugins/user-interface/reference/types/web/layout-stability.md` (29); 7, 9, 12 `plugins/user-interface/reference/types/web/layout.md` (21); 8 `plugins/user-interface/reference/types/touch-web.md` targets (34); 10 `plugins/user-interface/skills/write-css/reference/scroll-and-viewport.md` (34); 11 `plugins/user-interface/reference/types/web/states.md` (30). Details: `plugins/user-interface/skills/write-css/reference/interaction.md`, `plugins/user-interface/skills/write-css/reference/scroll-and-viewport.md` (34), `plugins/user-interface/skills/write-css/reference/text-and-media.md` (29). Frequent Offenders; Review Checklist: tags on those homes (29) | 21, 22, 29, 30, 34 |
| S58 | `emil-ui-review/SKILL.md` | Operating posture; What to review, in priority order; Escalation triggers flag on sight; Output format; What earns approval: `plugins/user-interface/skills/audit/SKILL.md` diff scope (39); priority order becomes `audit.order` in `plugins/user-interface/reference/concerns.json`, set on each concern row in the slice that adds it (4, 20-35); escalation triggers become Blocking tags on their concern spokes under `plugins/user-interface/reference/types/web/` and `plugins/user-interface/reference/animation/` (20-36) | 39 |
| S59 | `emil-ui-review/STANDARDS.md` | Interaction correctness; Accessibility floor; Layout stability; Motion; Spacing & hierarchy; Typography; Surface & depth; Component API; Performance; Final polish: each line a tag on its concern spoke, listed per section in the [Check-id index](#check-id-index) (20, 21, 22, 24, 29, 33, 35, 36); the check-id to home index lives only in this record (9) | 9, 20, 21, 22, 24, 29, 33, 35, 36 |
| S60 | `emil-unslop-code/SKILL.md` | The pass; Comments; Defensive theater; Type escape hatches; Naming; Structure; Logging; Tests; Scope: `plugins/code-tidying/skills/tidy-diff/reference/generated-code-residue.md` (14); Final audit: goal and constraints in its "The pass" (14); intro paragraphs rejected (`S60-r1`); Fix-cell rationale rejected (`S60-r2`); divider, summary-block and private-docstring units as examples in `plugins/code-tidying/skills/dissolve-comments/reference/triage.md` (14) | 14 |
| S61 | `emil-unslop-design/SKILL.md` | The pass; Subtract first; Color; Typography; Layout; Decoration; Iconography; Final audit: `plugins/user-interface/reference/types/web/generic-defaults.md` (32). Fabricated proof: `plugins/user-interface/reference/types/web/generic-defaults.md` Blocking (32). The copy on the screen: `/ai-slop:audit` `plugins/ai-slop/skills/audit/reference/catalog.md` interface-copy rows (13). Motion: tags on `plugins/user-interface/reference/animation/catalog.md` (36). Looking designed by someone: `plugins/user-interface/reference/types/web/generic-defaults.md`, marketing and brand surfaces only (32) | 13, 32, 36 |
| S62 | `emil-unslop-writing/SKILL.md` | The pass; Words; Sentences; Punctuation and formatting; Claims; Sounding like someone; Final audit: `plugins/ai-slop/skills/audit/reference/catalog.md` and `plugins/ai-slop/skills/audit/reference/rewrite-guide.md` (13) | 13 |
| S63 | `emil-writing-skills/SKILL.md` | Core Principles: 1 process half why-line beside `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` degrees of freedom (12), decision-tree-default half rejected (`S63-r1`); 2, 4, 6 `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` state-the-action and every-line rules (12); 3 precision to `/docs-hygiene:write-for-agents` firm-wording line (12), emphasis words rejected (`S63-r2`); 5 one skill per aspect rejected (`S63-r3`). Easing Decision Flowchart: rejected (`S63-r4`). Common Mistakes; Checklist: tags on the adopted rows or rejected (`S63-r5`) (12) | 12 |

## Check-id index

The launch-sweep checks of `emil-prep-for-prod` carry lettered ids, one lane per letter. Each id
below names its course title, the course severity, and its home. Lane H (content and leftovers) is
homed by section, not by id.

| Id | Course file | Check | Course severity | Home |
|---|---|---|---|---|
| A1 | `emil-prep-for-prod/accessibility.md` | Icon buttons have a name | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A2 | `emil-prep-for-prod/accessibility.md` | Buttons are buttons | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A3 | `emil-prep-for-prod/accessibility.md` | Focus is visible | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A4 | `emil-prep-for-prod/accessibility.md` | Labels are associated | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A5 | `emil-prep-for-prod/accessibility.md` | Modals manage focus | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A6 | `emil-prep-for-prod/accessibility.md` | Hidden things are out of the tab order | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A7 | `emil-prep-for-prod/accessibility.md` | Errors aren't color-only | BLOCKER | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A8 | `emil-prep-for-prod/accessibility.md` | Reduced motion is honored | BLOCKER for large movement, SHOULD FIX otherwise | `plugins/user-interface/reference/animation/catalog.md` reduced-motion (36) |
| A9 | `emil-prep-for-prod/accessibility.md` | Contrast passes in both themes | BLOCKER for body text, SHOULD FIX otherwise | `plugins/user-interface/reference/types/web/color/contrast.md` (23) |
| A10 | `emil-prep-for-prod/accessibility.md` | Illustrations and decoration are labeled or hidden | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A11 | `emil-prep-for-prod/accessibility.md` | DOM order matches visual order | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A12 | `emil-prep-for-prod/accessibility.md` | Page structure is real | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A13 | `emil-prep-for-prod/accessibility.md` | Skip link on pages with long navigation | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A14 | `emil-prep-for-prod/accessibility.md` | Tooltips hold no interactive content | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A15 | `emil-prep-for-prod/accessibility.md` | Hover enhances, never enables | SHOULD FIX | `plugins/user-interface/reference/types/touch-web.md` hover section (34) |
| A16 | `emil-prep-for-prod/accessibility.md` | Async changes are announced | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A17 | `emil-prep-for-prod/accessibility.md` | Time-limited actions pause when the tab is hidden | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A18 | `emil-prep-for-prod/accessibility.md` | Keyboard focus is never lost or off-screen | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A19 | `emil-prep-for-prod/accessibility.md` | Shortcuts show the right modifier | POLISH | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A20 | `emil-prep-for-prod/accessibility.md` | Menus keep their content in the DOM | POLISH | tags in `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| A21 | `emil-prep-for-prod/accessibility.md` | Test with a keyboard and a screen reader | always | launch human checklist `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| B1 | `emil-prep-for-prod/performance.md` | Media reserves its space | BLOCKER | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B2 | `emil-prep-for-prod/performance.md` | Fonts are preloaded, subset, and limited to used weights | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B3 | `emil-prep-for-prod/performance.md` | Above-the-fold images are preloaded; below-the-fold are lazy | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B4 | `emil-prep-for-prod/performance.md` | Images are the size they're shown at | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B5 | `emil-prep-for-prod/performance.md` | Only `transform` and `opacity` animate | BLOCKER on frequent interactions, SHOULD FIX otherwise | `plugins/user-interface/reference/animation/performance.md` (36) |
| B6 | `emil-prep-for-prod/performance.md` | No `transition: all` | SHOULD FIX | `plugins/user-interface/reference/animation/performance.md` (36) |
| B7 | `emil-prep-for-prod/performance.md` | React doesn't re-render per frame | BLOCKER when found | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B8 | `emil-prep-for-prod/performance.md` | Motion under load runs off the main thread | SHOULD FIX | `plugins/user-interface/reference/animation/performance.md` (36) |
| B9 | `emil-prep-for-prod/performance.md` | CSS variables don't drive child transforms | SHOULD FIX | `plugins/user-interface/reference/animation/performance.md` (36) |
| B10 | `emil-prep-for-prod/performance.md` | Blur stays under 20px | SHOULD FIX | `plugins/user-interface/reference/animation/performance.md` (36) |
| B11 | `emil-prep-for-prod/performance.md` | `will-change` is targeted, not sprinkled | POLISH | `plugins/user-interface/reference/animation/performance.md` (36) |
| B12 | `emil-prep-for-prod/performance.md` | Long lists are virtualized | SHOULD FIX, BLOCKER when the list is unbounded | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B13 | `emil-prep-for-prod/performance.md` | Off-screen work pauses | POLISH | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B14 | `emil-prep-for-prod/performance.md` | Theme switches don't animate every color | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| B15 | `emil-prep-for-prod/performance.md` | Content routes are static | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B16 | `emil-prep-for-prod/performance.md` | Search and resize handlers are debounced | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B17 | `emil-prep-for-prod/performance.md` | Heavy, rarely-seen UI is split out | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/performance.md` (35) |
| B18 | `emil-prep-for-prod/performance.md` | Nothing dev-only ships in the bundle | see lane H | launch leftovers `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| B19 | `emil-prep-for-prod/performance.md` | Verify on a mid-range phone | always | launch device checklist `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| C1 | `emil-prep-for-prod/mobile.md` | Never disable zoom | BLOCKER | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C2 | `emil-prep-for-prod/mobile.md` | Hover is gated | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C3 | `emil-prep-for-prod/mobile.md` | Inputs are 16px on touch | BLOCKER | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C4 | `emil-prep-for-prod/mobile.md` | Tap targets are 44px | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C5 | `emil-prep-for-prod/mobile.md` | Taps feel instant | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C6 | `emil-prep-for-prod/mobile.md` | Tap highlight is off, and press feedback replaces it | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C7 | `emil-prep-for-prod/mobile.md` | Viewport height is `dvh` or `svh`, not `vh` | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C8 | `emil-prep-for-prod/mobile.md` | Safe areas are respected | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C9 | `emil-prep-for-prod/mobile.md` | Scroll doesn't chain or pull-to-refresh in app UI | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C10 | `emil-prep-for-prod/mobile.md` | Controls aren't selectable; content is | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C11 | `emil-prep-for-prod/mobile.md` | Gesture surfaces declare their axis | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C12 | `emil-prep-for-prod/mobile.md` | Video autoplays inline | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C13 | `emil-prep-for-prod/mobile.md` | No autofocus on touch | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C14 | `emil-prep-for-prod/mobile.md` | The keyboard doesn't cover the input | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C15 | `emil-prep-for-prod/mobile.md` | Fixed bottom CTAs don't cover the last field | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C16 | `emil-prep-for-prod/mobile.md` | Sticky headers leave room on a phone | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C17 | `emil-prep-for-prod/mobile.md` | Nothing scrolls sideways | SHOULD FIX | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C18 | `emil-prep-for-prod/mobile.md` | Status bar matches the page | POLISH | tags in `plugins/user-interface/reference/types/touch-web.md` sections (34) |
| C19 | `emil-prep-for-prod/mobile.md` | Test on hardware | always | `plugins/user-interface/reference/types/touch-web.md` "Verify on hardware" (34) |
| D1 | `emil-prep-for-prod/forms.md` | Submission can't double-fire | BLOCKER | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D2 | `emil-prep-for-prod/forms.md` | Inputs live in a `<form>` | BLOCKER on auth and checkout, SHOULD FIX otherwise | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D3 | `emil-prep-for-prod/forms.md` | A failed submit says so, and keeps what was typed | BLOCKER | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D4 | `emil-prep-for-prod/forms.md` | Validation waits for the user to finish | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D5 | `emil-prep-for-prod/forms.md` | Errors sit next to their field and name the fix | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D6 | `emil-prep-for-prod/forms.md` | Inputs carry the right `type` and `autocomplete` | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D7 | `emil-prep-for-prod/forms.md` | Destructive actions confirm | SHOULD FIX, BLOCKER when irreversible with no undo | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D8 | `emil-prep-for-prod/forms.md` | Buttons respond to a press | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D9 | `emil-prep-for-prod/forms.md` | No dead zones in checkbox and radio rows | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D10 | `emil-prep-for-prod/forms.md` | Input decorations sit inside the input | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D11 | `emil-prep-for-prod/forms.md` | Forms are prefilled | POLISH | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D12 | `emil-prep-for-prod/forms.md` | Unsaved work survives an accident | POLISH | tags in `plugins/user-interface/reference/types/web/forms.md` (25) |
| D13 | `emil-prep-for-prod/forms.md` | Walk each critical form by hand | always | `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| E1 | `emil-prep-for-prod/stability-and-states.md` | Empty states exist and teach | BLOCKER on a first-run screen, SHOULD FIX elsewhere | `plugins/user-interface/reference/types/web/states.md` (30) |
| E2 | `emil-prep-for-prod/stability-and-states.md` | Failed requests render something useful | BLOCKER | `plugins/user-interface/reference/types/web/states.md` (30) |
| E3 | `emil-prep-for-prod/stability-and-states.md` | Every wait over 400ms has an indicator | SHOULD FIX | `plugins/user-interface/reference/types/web/states.md` (30) |
| E4 | `emil-prep-for-prod/stability-and-states.md` | Loading states hold the page's shape | SHOULD FIX | `plugins/user-interface/reference/types/web/states.md` (30); the skeleton-size hunt clause and `.row-skeleton` block in `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E5 | `emil-prep-for-prod/stability-and-states.md` | Persisted state is correct on first paint | SHOULD FIX | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E6 | `emil-prep-for-prod/stability-and-states.md` | Changing numbers and labels don't shift the layout | SHOULD FIX | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E7 | `emil-prep-for-prod/stability-and-states.md` | Font weight never changes on interaction | SHOULD FIX | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E8 | `emil-prep-for-prod/stability-and-states.md` | Late UI doesn't push content | SHOULD FIX | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E9 | `emil-prep-for-prod/stability-and-states.md` | Stacking comes from a scale | SHOULD FIX | `plugins/user-interface/reference/types/web/layout.md` (21) |
| E10 | `emil-prep-for-prod/stability-and-states.md` | Long content is handled | SHOULD FIX | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| E11 | `emil-prep-for-prod/stability-and-states.md` | Decorative layers don't steal clicks | SHOULD FIX | `plugins/user-interface/reference/types/web/layout.md` (21) |
| E12 | `emil-prep-for-prod/stability-and-states.md` | Optimistic updates revert on failure | SHOULD FIX | `plugins/user-interface/reference/types/web/states.md` (30) |
| E13 | `emil-prep-for-prod/stability-and-states.md` | Copy actions confirm | POLISH | `plugins/user-interface/reference/types/web/states.md` (30) |
| E14 | `emil-prep-for-prod/stability-and-states.md` | Walk the app as a new user | always | `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| F1 | `emil-prep-for-prod/motion.md` | High-frequency and keyboard actions don't animate | BLOCKER when it delays input, SHOULD FIX otherwise | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F2 | `emil-prep-for-prod/motion.md` | Nothing enters with `ease-in` | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F3 | `emil-prep-for-prod/motion.md` | UI animation stays under 300ms | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F4 | `emil-prep-for-prod/motion.md` | Nothing enters from `scale(0)` or from off the planet | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F5 | `emil-prep-for-prod/motion.md` | Popovers scale from their trigger | SHOULD FIX | `plugins/user-interface/reference/animation/behaviors.md` popover (36) |
| F6 | `emil-prep-for-prod/motion.md` | Toggled UI is interruptible | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F7 | `emil-prep-for-prod/motion.md` | Paired elements share timing | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F8 | `emil-prep-for-prod/motion.md` | Exits exist | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F9 | `emil-prep-for-prod/motion.md` | Resting elements don't animate on page load | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F10 | `emil-prep-for-prod/motion.md` | Hover motion doesn't make the target run away | SHOULD FIX | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F11 | `emil-prep-for-prod/motion.md` | Sequential tooltips don't each wait | POLISH | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F12 | `emil-prep-for-prod/motion.md` | Staggers are short | POLISH | tags in `plugins/user-interface/reference/animation/catalog.md` (36) |
| F13 | `emil-prep-for-prod/motion.md` | Watch it on a slow device, slowed down | always | `plugins/user-interface/reference/animation/catalog.md` feel-check (36) |
| G1 | `emil-prep-for-prod/theming.md` | A single-theme app says so | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G2 | `emil-prep-for-prod/theming.md` | Half a dark mode is worse than none | BLOCKER when reachable | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G3 | `emil-prep-for-prod/theming.md` | Text is readable in both themes | BLOCKER for body text | `plugins/user-interface/reference/types/web/color/contrast.md` (23) |
| G4 | `emil-prep-for-prod/theming.md` | Hardcoded colors don't flip | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G5 | `emil-prep-for-prod/theming.md` | Elevation survives the dark theme | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G6 | `emil-prep-for-prod/theming.md` | Images and media work on both backgrounds | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G7 | `emil-prep-for-prod/theming.md` | Third-party surfaces follow the theme | SHOULD FIX | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G8 | `emil-prep-for-prod/theming.md` | Browser chrome follows the theme | POLISH | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G9 | `emil-prep-for-prod/theming.md` | The theme is right on first paint and switches cleanly | see E5, B14 | `plugins/user-interface/reference/types/web/theming.md` (31) |
| G10 | `emil-prep-for-prod/theming.md` | Open every route in the other theme | always | `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H1 | `emil-prep-for-prod/content-and-leftovers.md` | No placeholder content | BLOCKER on a public page | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H2 | `emil-prep-for-prod/content-and-leftovers.md` | No fabricated proof | BLOCKER | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H3 | `emil-prep-for-prod/content-and-leftovers.md` | Buttons and errors say something specific | SHOULD FIX | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H4 | `emil-prep-for-prod/content-and-leftovers.md` | Missing weights fail visibly | SHOULD FIX | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H5 | `emil-prep-for-prod/content-and-leftovers.md` | Headings and paragraphs break well | POLISH | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H6 | `emil-prep-for-prod/content-and-leftovers.md` | Real typographic characters | POLISH | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H7 | `emil-prep-for-prod/content-and-leftovers.md` | Casing lives in CSS | POLISH | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H8 | `emil-prep-for-prod/content-and-leftovers.md` | The locale is declared | SHOULD FIX | Content section: `plugins/user-interface/reference/types/web/generic-defaults.md`, fabricated proof as Blocking (32); right-characters lines `plugins/user-interface/reference/types/web/typography/line-behavior.md` (22); plain-language lines `plugins/user-interface/reference/principles.md` (37) |
| H9 | `emil-prep-for-prod/content-and-leftovers.md` | Dev tools aren't mounted in production | BLOCKER | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H10 | `emil-prep-for-prod/content-and-leftovers.md` | Scaffolding routes aren't publicly reachable | BLOCKER | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H11 | `emil-prep-for-prod/content-and-leftovers.md` | No debug output | BLOCKER when it prints user data, SHOULD FIX otherwise | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H12 | `emil-prep-for-prod/content-and-leftovers.md` | No secrets or dev URLs in client code | BLOCKER | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H13 | `emil-prep-for-prod/content-and-leftovers.md` | Commented-out code and stale markers | SHOULD FIX | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H14 | `emil-prep-for-prod/content-and-leftovers.md` | Agent tells in the diff | POLISH | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H15 | `emil-prep-for-prod/content-and-leftovers.md` | Generated-looking surfaces | POLISH | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| H16 | `emil-prep-for-prod/content-and-leftovers.md` | Read every public page out loud | always | Leftovers section: `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |
| I1 | `emil-prep-for-prod/marketing.md` | Every public route has a title and description | BLOCKER | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I2 | `emil-prep-for-prod/marketing.md` | Shared links have a preview | SHOULD FIX, BLOCKER for a launch that depends on sharing | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I3 | `emil-prep-for-prod/marketing.md` | Crawlers can find the real pages and not the fake ones | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I4 | `emil-prep-for-prod/marketing.md` | Favicon and app icons are the product's | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I5 | `emil-prep-for-prod/marketing.md` | Motion maps to user input | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I6 | `emil-prep-for-prod/marketing.md` | Intro animations play once per session | POLISH | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I7 | `emil-prep-for-prod/marketing.md` | Heroes don't shift or overflow | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I8 | `emil-prep-for-prod/marketing.md` | Nav submenu content lives in the DOM | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I9 | `emil-prep-for-prod/marketing.md` | CTAs know who's looking | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I10 | `emil-prep-for-prod/marketing.md` | The conversion path works end to end | BLOCKER | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I11 | `emil-prep-for-prod/marketing.md` | Docs are for copying | POLISH | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I12 | `emil-prep-for-prod/marketing.md` | Blogs and changelogs are feeds | POLISH | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I13 | `emil-prep-for-prod/marketing.md` | Analytics and consent are wired, once | SHOULD FIX | tags in `plugins/user-interface/reference/types/web/marketing-pages.md` (26) |
| I14 | `emil-prep-for-prod/marketing.md` | Look at it as a stranger | always | `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) |

`emil-ui-review/STANDARDS.md` carries no ids. Each of its lines becomes a tag on the concern spoke
named for its section:

| Section | Home |
|---|---|
| Interaction correctness | per line, a tag on the owning concern spoke |
| Accessibility floor | `plugins/user-interface/reference/types/web/accessibility.md` (33) |
| Layout stability | `plugins/user-interface/reference/types/web/layout-stability.md` (29) |
| Motion | `plugins/user-interface/reference/animation/catalog.md` (36) |
| Spacing & hierarchy | `plugins/user-interface/reference/types/web/layout.md` (21) |
| Typography | `plugins/user-interface/reference/types/web/typography.md` (22) |
| Surface & depth | `plugins/user-interface/reference/types/web/shape-and-depth.md` (24) |
| Component API | `plugins/user-interface/reference/types/web/component-api.md` (20) |
| Performance | `plugins/user-interface/reference/types/web/performance.md` (35) |
| Final polish | per line, a tag on the owning concern spoke |

## Lessons

Every lesson's Feedback section is page chrome and is rejected. A lesson's Resources section
becomes rows in [Resources and mentions](#resources-and-mentions).

| Id | Lesson | Sections and homes | Slices |
|---|---|---|---|
| L1 | [Developing taste](https://aiforui.dev/learn/developing-taste) | lead: why-line beside `plugins/user-interface/reference/animation/catalog.md` feel-check and write-animation Report "Feel check" (36). Can you improve your taste?: dropdown demo as worked example beside `plugins/user-interface/reference/animation/catalog.md` physicality, easing, duration (36); "every taste decision has a logical reason" why-line beside `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` state-the-action (12); rest rejected (`L1-r1`). Why does taste matter?: "an agent produces the average" why-line beside `plugins/user-interface/reference/principles.md` generic-defaults rule (37); car and commodity paragraphs rejected (`L1-r2`). How to get better?: rejected (`L1-r3`). Think about why you like something: why-line in `plugins/user-interface/skills/glossary/SKILL.md` (10); record-and-scrub why-line in `plugins/user-interface/skills/audit/reference/frame-capture.md` (38). Practice; Care; Homework: rejected (`L1-r4`). Resources: this record (9). Feedback: rejected (`L1-r5`) | 9, 10, 12, 36, 37, 38 |
| L2 | [Friction as a feature](https://aiforui.dev/learn/friction-as-a-feature) | lead: first two paragraphs rejected (`L2-r3`); Plato and assembly narrative rejected (`L2-r1`). Being selective about friction: rule in `plugins/planning/skills/interview/context/product.md` "What this action changes, and what still holds" (judgment questions to the user; market research and feedback summaries to the agent) (11); essay part rejected (`L2-r4`). How to bring friction back: `/planning:interview product` (11); grill-me mention to this record (9). Feedback: rejected (`L2-r2`) | 9, 11 |
| L3 | [Get good at telling AI what you want](https://aiforui.dev/learn/get-good-at-telling-ai-what-you-want) | lead: rejected (`L3-r4`). Be specific: rule in `plugins/user-interface/skills/glossary/SKILL.md` (10); demo pairs as worked examples beside their rules: popover origin `plugins/user-interface/reference/animation/behaviors.md` (36), tabular numbers `plugins/user-interface/reference/types/web/layout-stability.md` (29), nested radius `plugins/user-interface/reference/types/web/shape-and-depth.md` (24), tracking `plugins/user-interface/reference/types/web/typography/scale-and-rhythm.md` (22). You don't need to know every number: why-line and reference-image rule in `plugins/user-interface/skills/glossary/SKILL.md` (10). When you don't know the word: `plugins/user-interface/skills/glossary/SKILL.md` reverse lookup (10); vocabulary-page paragraphs rejected (`L3-r1`). What if LLMs get better?: rejected (`L3-r2`). Feedback: rejected (`L3-r3`) | 10, 22, 24, 29, 36 |
| L4 | [Getting into someone’s brain](https://aiforui.dev/learn/getting-into-someone-brain) | lead: why-line in `plugins/knowledge/skills/distill/reference/web-corpus.md` (17). Building a fleet of brain skills: rejected (`L4-r1`) (9). Make your own brain skills: `plugins/knowledge/skills/distill/reference/web-corpus.md` procedure (17); install command and token rejected (`L4-r3`). Feedback: rejected (`L4-r2`) | 9, 17 |
| L5 | [How to build with aiforui skills](https://aiforui.dev/learn/how-to-build-with-aiforui-skills) | lead: rejected (`L5-r1`). Invoke skills by name: rejected (`L5-r2`). One or two skills at a time: why-line beside the spoke cap in `plugins/user-interface/skills/design/SKILL.md` (4). The loop for your work; Decide, if you haven't; Refine; Review; When you don't know which skill; Before you ship: `plugins/user-interface/skills/design/SKILL.md` "Order of work" rows naming explore-directions, write-css, write-animation, audit, glossary and audit `launch` (40). Build on the foundation first: `plugins/user-interface/reference/types/web/layout.md` (21), its forms worked example ("This screen is a form", demo 37) in `plugins/user-interface/reference/types/web/forms.md` (25); "Generic UI is intentional" habits-versus-conventions line to `plugins/user-interface/reference/principles.md` (37). Summary: rejected (`L5-r3`). Feedback: rejected (`L5-r4`) | 4, 21, 25, 37, 40 |
| L6 | [How to write good skills](https://aiforui.dev/learn/how-to-write-good-skills) | lead and testimonials: rejected (`L6-r1`). What a skill is actually for: why-line beside `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` degrees of freedom (12); easing blueprint rejected (`L6-r2`). Write down the why: `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` state-the-action with Bad/Good example (12). Be strict: precision paragraphs to `/docs-hygiene:write-for-agents` firm-wording line (12); never/always paragraph rejected (`L6-r3`); most-common-mistake sentence rejected (`L6-r7`); Bad/Good motion values rejected (`L6-r8`). Every line must earn its place: domain-expertise example in `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` (12). Keep your skills focused: rejected (`L6-r4`). Should you write the skill yourself?; Use a skill to create skills: rule "start from the expert's written knowledge dump" in `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` (12); install line rejected (`L6-r5`). Resources: this record (9). Feedback: rejected (`L6-r6`) | 9, 12 |
| L7 | [Intro](https://aiforui.dev/learn/intro) | lead: rejected (`L7-r1`). AI is only as good as the person directing it: rejected (`L7-r2`). How the course works: rejected (`L7-r3`). You're in early access: rejected (`L7-r4`). Bonus features: rejected (`L7-r5`). Ready?: rejected (`L7-r6`). Resources: this record (9). Feedback: rejected (`L7-r7`) | 9 |
| L8 | [Knowing where to learn from](https://aiforui.dev/learn/knowing-where-to-learn-from) | lead; Why does this matter?: why-line beside the practitioner-source rule in `plugins/discovery/skills/research/SKILL.md` (15). Who should you trust?: practitioner-source rule in `plugins/discovery/skills/research/SKILL.md` (proof of shipped work, hard-to-join employer, followers are no proxy) (15); Sonner and Vaul demos rejected (`L8-r1`). Some of the best people don't share their work: rejected (`L8-r2`). Extending this idea further: rejected (`L8-r3`). Homework assignment: rejected (`L8-r4`); people list as rows in this record (9). Feedback: rejected (`L8-r5`) | 9, 15 |
| L9 | [Mental models](https://aiforui.dev/learn/mental-models) | lead: rejected (`L9-r1`). Invite friction to your work: rejected (`L9-r4`). Don't get caught up in the hype: rejected (`L9-r2`). Be selective: why-line beside the practitioner-source rule in `plugins/discovery/skills/research/SKILL.md` (15). Feedback: rejected (`L9-r3`) | 15 |
| L10 | [Prototyping interfaces](https://aiforui.dev/learn/prototyping-interfaces) | lead: why-line in `plugins/prototype/skills/explore-directions/SKILL.md` (18). When should you actually prototype?: `plugins/prototype/skills/explore-directions/SKILL.md` when-to-use rule (18). How to prototype with AI: `plugins/prototype/skills/explore-directions/SKILL.md` Process (18). Let people tweak the values: why-line in `plugins/prototype/context/control-panel.md` (8). Use your worst content: worst-content toggle in `plugins/prototype/skills/explore-directions/reference/switcher.md` (18). Summary: rejected (`L10-r1`). Feedback: rejected (`L10-r2`) | 8, 18 |
| L11 | [What are skills](https://aiforui.dev/learn/what-are-skills) | lead: rejected (`L11-r1`). What is an agent skill?: rejected (`L11-r2`); granular-skills paragraph rejected (`L11-r3`). Anatomy of a skill: rejected (`L11-r4`). Progressive disclosure: "depth costs nothing until used" why-line beside `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` "Scope is a vertical slice" (12). User-invoked skills: why-line beside invocation class (i) in `docs/conventions/invocation-mode/README.md` (12). Where to go from here: rejected (`L11-r5`). Feedback: rejected (`L11-r6`) | 12 |
| L12 | [AI for creative work](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) | lead; How it works; Going further; You can also use it for research: `plugins/prototype/skills/build-generator/reference/visual-research.md` (19); research cost table and model-token line rejected (`L12-r2`); poster attribution to named models and apps and the four branded posters rejected (`L12-r3`); "run this type of workflow even when I'm not looking" and "an agent running at all times" rejected (`L12-r4`). Making it repeatable: the detection rule in `plugins/user-interface/reference/principles.md` (37), same rule as lesson 14 (one home); install line and example prompt rejected (`L12-r5`). Vocabulary link and image URLs: rejected (`L12-r6`). Capture annotations: rejected (`L12-r7`). Resources: this record (9). Feedback: rejected (`L12-r1`) | 9, 19, 37 |
| L13 | [Reviewing your work](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/reviewing-your-work) | lead: `plugins/prototype/skills/build-generator/reference/review-tools.md` (19). How it works: nested-radius rule, the build-a-checking-tool line, the preview-url paragraph and the inspector ask `plugins/user-interface/reference/types/web/shape-and-depth.md` and check script `plugins/user-interface/scripts/nested-radius.mjs` (24); the working-habit opener rejected (`L13-r4`). Expanding it further: focus walk script `plugins/user-interface/scripts/focus-path.js` (33). Don't fall into it too deeply: `plugins/prototype/skills/build-generator/reference/review-tools.md` (19). Vendor video and install line: rejected (`L13-r2`). Capture annotations: rejected (`L13-r3`). Feedback: rejected (`L13-r1`) | 19, 24, 33 |
| L14 | [Tools as means to an end](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) | lead: why-line beside the `plugins/user-interface/reference/principles.md` detection rule (37). Let me give you an example; Getting more precise results: `plugins/prototype/skills/build-generator/reference/examples.md` (19); the personal name, handle, product link and source-app name rejected (`L14-r4`). Capture annotations: rejected (`L14-r5`). Others do it too: rejected (`L14-r1`). Making it repeatable: rule in `plugins/user-interface/reference/principles.md` "Work in this order": when the agent cannot reach the thing, propose the tool, naming `build-generator` as run by a person (37); install line rejected (`L14-r2`). Feedback: rejected (`L14-r3`) | 9, 19, 37 |
| L15 | [Defining a system](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) | lead; Tokens; Documentation; Iterate on the system; Putting it all together: `plugins/user-interface/reference/design-system-doc.md` (28). Components: finite-choices and union-type rules and the `className` audience qualifier in `plugins/user-interface/reference/types/web/component-api.md` (20); button-variant flowchart to `plugins/user-interface/reference/design-system-doc.md` (28); copy-button capture annotation rejected (`L15-r2`). Design system sample (Tokens, Components, When to use what): worked example in `plugins/user-interface/reference/design-system-doc.md` (28). Flowchart and link-card annotations and the skill-page link: rejected (`L15-r3`). Lead claim, anecdote, framing, playground and duplicated documentation and iterate rules: rejected (`L15-r4` to `L15-r8`); "This lesson is about" read as "This procedure is about" (`L15-r9`). Feedback: rejected (`L15-r1`) | 20, 28 |
| L16 | [Using AI at work](https://aiforui.dev/learn/workflows/how-i-work/using-ai-at-work) | lead: rejected (`L16-r1`). Expanding it further: quiz result rule (delegate or build by hand) in `plugins/user-interface/reference/principles.md` (37); cards to this record (9). Judgment Execution pipeline: spot, document, delegate in `/bugs:write` (38); portal popover-in-modal fix `plugins/user-interface/skills/write-css/reference/show-and-hide.md` (36); mask-fade overflow fix `plugins/user-interface/skills/write-css/reference/scroll-and-viewport.md` (34). Tooling: rejected (`L16-r2`). Feedback: rejected (`L16-r3`) | 9, 34, 36, 37, 38 |
| L17 | [Handing it to your agent](https://aiforui.dev/learn/workflows/reviewing-animations/handing-it-to-your-agent) | lead; Copy the state of a given frame: `plugins/user-interface/skills/audit/reference/frame-capture.md` (38). Sample export headings (Performance LoAF tier recorded; Triggers evidence graded not; Account menu div menu; Annotations user feedback pinned; Annotations): format evidence described in `plugins/user-interface/skills/audit/reference/frame-capture.md` "Reading an export", never copied as fixtures (38). Feedback: rejected (`L17-r1`) | 38 |
| L18 | [Recording an interaction](https://aiforui.dev/learn/workflows/reviewing-animations/recording-an-interaction) | lead; Slow it down; Record and scrub: `plugins/user-interface/skills/audit/reference/frame-capture.md` (38); slow-motion toggle in `plugins/prototype/skills/explore-directions/reference/switcher.md` "Slow motion" (18); speed steps 0.75x, 0.1x and ping-pong rejected (`L18-r2`). Analyze yourself: why-line beside `plugins/user-interface/reference/animation/catalog.md` feel-check (36). Feedback: rejected (`L18-r1`) | 18, 36, 38 |
| L19 | [Setting up Lapse](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) | lead: rejected (`L19-r1`). Installing it: rejected (`L19-r2`). Dropping it in: rejected (`L19-r3`). What you get; Something to point it at: `plugins/user-interface/skills/audit/reference/frame-capture.md` (38); capture kind in `/app-control:drive` (38). A skill to help you: rejected (`L19-r4`). Feedback: rejected (`L19-r5`) | 9, 38 |

## Vocabulary

The vocabulary page (`aiforui.dev/learn/vocabulary`) holds 22 categories and 244 terms. Each term
keeps its site anchor as an H3 in its glossary file, with a platform-neutral base definition and
web, iOS and Android detail. No image is committed.

| Id | Category | Site anchor | Terms | Glossary file | Slice |
|---|---|---|---|---|---|
| T1 | Typography | `typography` | 21 | `plugins/user-interface/skills/glossary/reference/typography.md` | 10 |
| T2 | Color | `color` | 13 | `plugins/user-interface/skills/glossary/reference/color.md` | 10 |
| T3 | Iconography | `iconography` | 12 | `plugins/user-interface/skills/glossary/reference/icons.md` | 10 |
| T4 | Layout | `layout` | 18 | `plugins/user-interface/skills/glossary/reference/layout.md` | 10 |
| T5 | Interaction | `interaction` | 12 | `plugins/user-interface/skills/glossary/reference/interaction.md` | 10 |
| T6 | Motion | `motion` | 7 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T7 | Entrances & exits | `entrances-and-exits` | 6 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T8 | Sequencing & timing | `sequencing-and-timing` | 8 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T9 | Easing | `easing` | 7 | `plugins/user-interface/skills/glossary/reference/easing-and-springs.md` | 10 |
| T10 | Spring animations | `spring-animations` | 6 | `plugins/user-interface/skills/glossary/reference/easing-and-springs.md` | 10 |
| T11 | Movement & transforms | `movement-and-transforms` | 8 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T12 | Transitions between states | `transitions-between-states` | 7 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T13 | Scroll | `scroll` | 4 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T14 | Feedback & interaction | `feedback-and-interaction` | 5 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T15 | Polish & effects | `polish-and-effects` | 8 | `plugins/user-interface/skills/glossary/reference/motion.md` | 10 |
| T16 | Performance | `performance` | 5 | `plugins/user-interface/skills/glossary/reference/rendering-performance.md` | 10 |
| T17 | Accessibility | `accessibility` | 11 | `plugins/user-interface/skills/glossary/reference/accessibility.md` | 10 |
| T18 | Information Architecture | `information-architecture` | 15 | `plugins/user-interface/skills/glossary/reference/information-architecture.md`; the operative depth, labeling and content-inventory sentences in `plugins/user-experience/reference/flows-ia.md` (16) | 10, 16 |
| T19 | Copywriting | `copywriting` | 15 | `plugins/user-interface/skills/glossary/reference/copywriting.md` | 10 |
| T20 | Tools | `tools` | 12 | `plugins/user-interface/skills/glossary/reference/design-tools.md` | 10 |
| T21 | Analysis | `analysis` | 10 | `plugins/user-interface/skills/glossary/reference/analytics.md` | 10 |
| T22 | Components | `components` | 34 | `plugins/user-interface/skills/glossary/reference/components.md` | 10 |
| | **Total** | | **244** | 15 files, plus `plugins/user-interface/skills/glossary/reference/engineering.md` | |

## Vault

The vault page (`aiforui.dev/vault`) lists links with no rules, so each entry is a row here only.
Its intro and filter demo are rejected (`V0-r1`). Follow-ups are separate runs after this
migration.

| Id | Entry | Kind | Link | Follow-up |
|---|---|---|---|---|
| V1 | How always-on agents work | talks | <https://x.com/leerob/status/2108650243365736855> | none |
| V2 | How to turn your AI into a designer | articles | <https://www.lennysnewsletter.com/p/how-to-turn-your-ai-into-a-world> | none |
| V3 | How I design with AI | articles | <https://x.com/reactiverobot/status/2092638003789439075> | none |
| V4 | Designing Grok Bot with Grok Bot | articles | <https://x.com/johnbai/status/2092019324797989023> | none |
| V5 | @anshuc | people | <https://x.com/anshuc> | none |
| V6 | index.how | other | <http://index.how/> | none |
| V7 | @leerob | people | <https://x.com/leerob> | `/knowledge:video-digest` of the talk |
| V8 | Agents with Taste | articles | <https://emilkowal.ski/ui/agents-with-taste> | none |
| V9 | LLM Wiki | tools | <https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f> | reading for `/knowledge:distill` web corpus |
| V10 | @poteto | people | <https://x.com/poteto> | none |
| V11 | emilkowalski/skills | skills | <https://github.com/emilkowalski/skills> | existing record [emilkowalski-skills.md](emilkowalski-skills.md) |
| V12 | anthropic/skills | skills | <https://github.com/anthropics/skills> | `/knowledge:absorb-upstream` |
| V13 | mattpocock/skills | skills | <https://github.com/mattpocock/skills> | existing record [mattpocock-skills.md](mattpocock-skills.md) |
| V14 | pstack | skills | <https://github.com/cursor/plugins/tree/main/pstack> | none; existing record [cursor-pstack.md](cursor-pstack.md) |
| V15 | Claude Code best practices | articles | <https://www.anthropic.com/engineering/claude-code-best-practices> | none |
| V16 | Writing effective tools for agents | articles | <https://www.anthropic.com/engineering/writing-tools-for-agents> | none |
| V17 | @MSchwaibold | people | <https://x.com/MSchwaibold> | none |
| V18 | Designing with Code | articles | <https://justinjay.wang/designing-with-code/> | reading for `/prototype:build-generator` |
| V19 | @kunchenguid | people | <https://x.com/kunchenguid> | none |
| V20 | emilkowal.ski | people | <https://emilkowal.ski> | none |

## Skill pages

Each course skill has a page at `aiforui.dev/learn/skills/<skill>`. Its example prompt, with the
install token removed, becomes a happy-path eval case in the slice that lands its home. The install
lead, command, token and "rename skills" text are rejected (`O1-r1`).

| Id | Page | Course skill | Home it describes | Eval case slice |
|---|---|---|---|---|
| P1 | Animations | `emil-animations` (S1-S3) | `/user-interface:write-animation` and the motion lane of `/user-interface:audit`; spokes under `plugins/user-interface/reference/animation/` (36) | 36 |
| P2 | Ask Emil | `emil-ask-emil` (S4) | `/user-interface:design` "Order of work" (40); `/user-interface:glossary` description (6) | 40 |
| P3 | Ask Lapse | `emil-ask-lapse` (S5-S8) | `plugins/user-interface/skills/audit/reference/frame-capture.md` (38); vendor manual rejected, see [Frame-capture vendor](#frame-capture-vendor) | 38 |
| P4 | Borrow a Brain | `emil-borrow-a-brain` (S9-S10) | `/knowledge:distill` web corpus (17) | 17 |
| P5 | Build a Tool | `emil-build-a-tool` (S11) | `/prototype:build-generator` (8) | 8 |
| P6 | Color | `emil-color` (S12-S16) | `plugins/user-interface/reference/types/web/color.md` and its spokes (23) | 23 |
| P7 | Component Design | `emil-component-design` (S17-S18) | `plugins/user-interface/reference/types/web/component-api.md` (20) | 20 |
| P8 | Design Foundations | `emil-design-foundations` (S19-S20) | `plugins/user-interface/reference/types/web/layout.md` (21), with typography (22) and color (23) | 21 |
| P9 | Design System Docs | `emil-design-system-docs` (S21) | `plugins/user-interface/reference/design-system-doc.md` (28) | 28 |
| P10 | Design Vocabulary | `emil-design-vocabulary` (S22-S24) | `/user-interface:glossary` term files (10) | 10 |
| P11 | Engineering Vocabulary | `emil-engineering-vocabulary` (S25) | `plugins/user-interface/skills/glossary/reference/engineering.md` (10) | 10 |
| P12 | Forms & Inputs | `emil-forms-and-inputs` (S26) | `plugins/user-interface/reference/types/web/forms.md` (25); example prompt as eval case `plugins/user-interface/evals/forms-signup-validation/` | 25 |
| P13 | Get Creative | `emil-get-creative` (S27) | `/prototype:build-generator` (8) and `plugins/prototype/skills/build-generator/reference/visual-research.md` (19) | 19 |
| P14 | Marketing Pages | `emil-marketing-pages` (S28) | `plugins/user-interface/reference/types/web/marketing-pages.md` (26) | 26 |
| P15 | Mobile Native | `emil-mobile-native` (S29) | `plugins/user-interface/reference/types/touch-web.md` (34) | 34 |
| P16 | Performance | `emil-performance` (S30) | `plugins/user-interface/reference/types/web/performance.md` (35) and `plugins/user-interface/reference/animation/performance.md` (36) | 35 |
| P17 | Prep for Prod | `emil-prep-for-prod` (S31-S41) | `launch` scope of `/user-interface:audit`, `plugins/user-interface/skills/audit/reference/launch-scope.md` (39) | 39 |
| P18 | Product Thinking | `emil-product-thinking` (S42-S43) | `/planning:interview` `product` action (11) | 11 |
| P19 | Prototyping | `emil-prototype` (S44-S47) | `/prototype:explore-directions` (18) | 18 |
| P20 | Surfaces & Depth | `emil-surfaces` (S48) | `plugins/user-interface/reference/types/web/shape-and-depth.md` (24); example prompt as eval case `plugins/user-interface/evals/shape-and-depth-card-elevation/` | 24 |
| P21 | Touch & Accessibility | `emil-touch-and-accessibility` (S49) | `plugins/user-interface/reference/types/web/accessibility.md` (33) and `plugins/user-interface/reference/types/touch-web.md` (34) | 33 |
| P22 | Typography | `emil-typography` (S50-S56) | `plugins/user-interface/reference/types/web/typography.md` and its spokes (22) | 22 |
| P23 | UI Polish | `emil-ui-polish` (S57) | `plugins/user-interface/reference/types/web/layout-stability.md` (29), with layout (21), typography (22), states (30) and touch (34) | 29 |
| P24 | UI Review | `emil-ui-review` (S58-S59) | default `diff` scope of `/user-interface:audit` (39) | 39 |
| P25 | Unslop Code | `emil-unslop-code` (S60) | `/code-tidying:tidy-diff` generated-code residue pass (14) | 14 |
| P26 | Unslop Design | `emil-unslop-design` (S61) | `plugins/user-interface/reference/types/web/generic-defaults.md` (32) | 32 |
| P27 | Unslop Writing | `emil-unslop-writing` (S62) | `/ai-slop:audit` (13) | 13 |
| P28 | Writing Skills | `emil-writing-skills` (S63) | `/playbooks:skill-authoring` skill criteria (12) | 12 |

## Other captures

| Id | Capture | Disposition |
|---|---|---|
| O1 | The 28 skill pages | Rows in [Skill pages](#skill-pages); install text rejected (`O1-r1`) |
| O2 | Course pages: home `/`, `/boss`, `/team`, the learn index `/learn`, the skills index `/learn/skills`, `/settings`, `/certificate` | Rows below only; marketing copy, purchase links and cost lines rejected (`O2-r1`) |
| O3 | Sign-in, survey and search pages | Eval specimens only: 16px input (34), multi-step form (25), command palette (39) |
| O4 | Alternate captures of a lesson (copy-page, fresh and raw captures, the design-system sample) | Diffed against the primary capture; text only an alternate holds takes the home of its section |
| O5 | The 14 frame-export and bug-report captures | Format evidence for `plugins/user-interface/skills/audit/reference/frame-capture.md` (38) and this record; never fixtures, because they hold a user agent, URLs, a deployment id and timestamps |

Course pages (O2) recorded without content:

| Page | What it is | Record |
|---|---|---|
| `/` | Public landing page | The author's proof of work; no rule taken |
| `/boss` | A letter to your boss, for an employer to fund the course | Course meta; no rule taken |
| `/team` | Team license page | Course meta; no rule taken |
| `/learn` | Logged-in landing page and curriculum | Source of the [Lessons](#lessons) list |
| `/learn/skills` | Skills index | Source of the [Skill pages](#skill-pages) list |
| `/settings` | Account settings | Track only; account data is never stored |
| `/certificate` | Course certificate page | Track only; no content captured or stored |

## Resources and mentions

Links and names a lesson cites without a rule. They are pointers for reading, not content.

| Lesson | Item | Link | Note |
|---|---|---|---|
| L1 | Taste for Makers | <https://paulgraham.com/taste.html> | Resources |
| L1 | Taste is eating Silicon Valley | <https://www.workingtheorys.com/p/taste-is-eating-silicon-valley> | Resources |
| L2 | Matt's grill-me skill | <https://www.aihero.dev/skills-grill-me> | Named as the general "ask me anything" alternative; our counterpart is `/planning:interview` |
| L4 | The author's brain skills: marketing, product thinking, `/steve-jobs` (interviews), `/paul-graham` (essays), apple-design (WWDC talks) | <https://www.paulgraham.com/> | The section is rejected (`L4-r1`); the procedure it illustrates lands in `plugins/knowledge/skills/distill/reference/web-corpus.md` (17) |
| L6 | AI is a copycat so we gave it good examples to copy | <https://astryx.atmeta.com/blog/astryx-cli-build-command> | Resources |
| L6 | Judgment Is the Decisive Skill | <https://www.youtube.com/watch?v=eoLAIDGM4zI> | Resources |
| L7 | Discord community | none | Resources; a Discord invite, never stored |
| L7 | animations.dev | <https://animations.dev> | Resources; the author's animation course |
| L8 | Mitchell Hashimoto | <https://x.com/mitchellh> | Homework people list |
| L8 | Steph Ango | <https://x.com/kepano> | Homework people list |
| L8 | Raphael Schaad | <https://x.com/raphaelschaad> | Homework people list |
| L8 | Rasmus Andersson | <https://x.com/rsms> | Homework people list; also named as the designer of Inter |
| L8 | Andy Matuschak | <https://x.com/andy_matuschak> | Homework people list |
| L8 | Justin Jay Wang | <https://x.com/justinjaywang> | Homework people list |
| L8 | Benji Taylor | <https://x.com/benjitaylor> | Homework people list |
| L8 | Ryo Lu | <https://x.com/ryolu_> | Homework people list |
| L8 | Ben Leonard | <https://x.com/lenjaminbeonard> | Homework people list |
| L8 | Jason Ginsberg | <https://x.com/JasonBud> | Homework people list |
| L8 | Jiro, a Japanese sushi chef | <https://en.wikipedia.org/wiki/Jiro_Ono> | Homework example from outside the field |
| L12 | Designing with code | <https://justinjay.wang/designing-with-code/> | Resources; also vault entry V18 |
| L14 | Hector Simpson of Superlogical, Super Icon Studio | <https://www.superlogical.com/> | The "Others do it too" anecdote, rejected (`L14-r1`) |

The delegate-or-build quiz in L16 ("Expanding it further") has 20 cards. Its rule, delegate what
is a lot of code you can spell out and build by hand what depends on your judgment, lands in
`plugins/user-interface/reference/principles.md` (37). The cards are recorded here with the
author's call:

| Card | Task | Author's call |
|---|---|---|
| 1 | A ⌘K command menu | Delegate |
| 2 | Tuning the drawer’s spring | Build |
| 3 | An empty state illustration | Build |
| 4 | A virtualized data table | Delegate |
| 5 | That button from your inspiration folder | Build |
| 6 | Migrating hardcoded colors to tokens | Delegate |
| 7 | A date range picker | Delegate |
| 8 | Your landing page hero | Build |
| 9 | A drag-and-drop kanban board | Delegate |
| 10 | Optically aligning an icon set | Build |
| 11 | Picking the brand’s accent color | Build |
| 12 | A multi-step signup flow | Delegate |
| 13 | Storybook stories for the whole kit | Delegate |
| 14 | A non-generic loading spinner | Build |
| 15 | A global keyboard shortcuts layer | Delegate |
| 16 | Choreographing the onboarding intro | Build |
| 17 | Cropping screenshots for the marketing page | Build |
| 18 | Infinite scroll with optimistic likes | Delegate |
| 19 | Migrating styled-components to Tailwind | Delegate |
| 20 | Setting the blog’s type scale | Build |

## Frame-capture vendor

The course ships an animation inspector, Lapse, as the scoped package `@aiforui/lapse` with
companions `@aiforui/lapse-mcp` and `@aiforui/lapse-playwright`. It installs from a private
registry behind the course login and is not on the public npm registry. This marketplace takes the
capture-reading practice (`plugins/user-interface/skills/audit/reference/frame-capture.md`, slice
38) and keeps no vendor manual: a vendor's API, defaults and install steps are the volatile
specifics a skill points at instead of restating.

- **Pointer**: the setup lesson,
  <https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse> (login required), and
  the installed `emil-ask-lapse` skill files.
- **As of**: 2026-10-28, Lapse 0.19.0 (the version the captured exports report).
- **Recheck trigger**: a Lapse version other than 0.19.0 in a new export, or an update badge on a
  reviewing-animations lesson.

| Course unit | Sections | Disposition |
|---|---|---|
| S5 `emil-ask-lapse/AGENTS.md` | MCP server; Playwright adapter; Browser extension | Rejected (`S5-r1`), except the motion-study line, which lands in `plugins/prototype/skills/build-generator/reference/visual-research.md` (19) |
| S6 `emil-ask-lapse/API.md` | all | Rejected (`S6-r1`) |
| S7 `emil-ask-lapse/SKILL.md` | Answering posture; Name and install; Mounting; The panel; Takes; Moments; Diffs; Deeper reference | Rejected (`S7-r1`) |
| S7 `emil-ask-lapse/SKILL.md` | Annotations and the export; Jank and triggers; The review loop | `plugins/user-interface/skills/audit/reference/frame-capture.md` (38), captured through `/app-control:drive` (38) |
| S8 `emil-ask-lapse/TROUBLESHOOTING.md` | all | Rejected (`S8-r1`) |
| L19 Setting up Lapse | lead; Installing it; Dropping it in; A skill to help you | Rejected (`L19-r1` to `L19-r4`) |
| L19 Setting up Lapse | What you get; Something to point it at | `plugins/user-interface/skills/audit/reference/frame-capture.md` (38) |

## Rejected

| Id | Course unit | What is rejected | Reason | Source |
|---|---|---|---|---|
| S1-r1 | `emil-animations/SKILL.md` | Quick Reference | reading copy of rules homed below | [skill page](https://aiforui.dev/learn/skills/emil-animations) |
| S4-r1 | `emil-ask-emil/SKILL.md` | Standalone | lists course-only skills | [skill page](https://aiforui.dev/learn/skills/emil-ask-emil) |
| S5-r1 | `emil-ask-lapse/AGENTS.md` | MCP server; Playwright adapter; Browser extension | vendor agent integration text; pointer row in this record | [skill page](https://aiforui.dev/learn/skills/emil-ask-lapse) |
| S6-r1 | `emil-ask-lapse/API.md` | all sections | vendor API reference; pointer row in this record | [skill page](https://aiforui.dev/learn/skills/emil-ask-lapse) |
| S7-r1 | `emil-ask-lapse/SKILL.md` | Answering posture; Name and install; Mounting; The panel; Takes; Moments; Diffs; Deeper reference | third-party product manual, volatile vendor specifics; pointer row in this record | [skill page](https://aiforui.dev/learn/skills/emil-ask-lapse) |
| S8-r1 | `emil-ask-lapse/TROUBLESHOOTING.md` | all sections | vendor support text; pointer row in this record | [skill page](https://aiforui.dev/learn/skills/emil-ask-lapse) |
| S10-r1 | `emil-borrow-a-brain/templates.md` | cost lines | cost-claims rule | [skill page](https://aiforui.dev/learn/skills/emil-borrow-a-brain) |
| S10-r2 | `emil-borrow-a-brain/templates.md` | pricing example bullet in the theme template | cost-claims rule | [skill page](https://aiforui.dev/learn/skills/emil-borrow-a-brain) |
| S17-r1 | `emil-component-design/SKILL.md` | Quick Reference | reading copy | [skill page](https://aiforui.dev/learn/skills/emil-component-design) |
| S19-r1 | `emil-design-foundations/SKILL.md` | Quick Reference | reading copy | [skill page](https://aiforui.dev/learn/skills/emil-design-foundations) |
| S19-r2 | `emil-design-foundations/SKILL.md` | Information Architecture item 4 lead-in "Tabs trick question:" | framing, no rule; the tabs rule it introduces lands in `plugins/user-experience/reference/flows-ia.md` (16) | [skill page](https://aiforui.dev/learn/skills/emil-design-foundations) |
| S19-r3 | `emil-design-foundations/SKILL.md` | Interaction 4: "Long list loads get skeletons, not spinners. ..." | merged duplicate of the E4 sentences in `plugins/user-interface/reference/types/web/states.md` | [skill page](https://aiforui.dev/learn/skills/emil-design-foundations) |
| S22-r1 | `emil-design-vocabulary/SKILL.md` | Categories at a glance | reading copy; the skill lists its term files | [skill page](https://aiforui.dev/learn/skills/emil-design-vocabulary) |
| S23-r1 | `emil-design-vocabulary/terms-index.md` | all sections | reading copy of the term files; the capture's categories and terms are the source, per the [Vocabulary](#vocabulary) table | [skill page](https://aiforui.dev/learn/skills/emil-design-vocabulary) |
| S29-r1 | `emil-mobile-native/SKILL.md` | Tone | house writing rules govern | [skill page](https://aiforui.dev/learn/skills/emil-mobile-native) |
| S30-r1 | `emil-performance/SKILL.md` | Core Principle 6: "Hardcode dimensions on images and videos." and "Reserve space for async content with skeletons." | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is ui-polish's reserve-space line | [skill page](https://aiforui.dev/learn/skills/emil-performance) |
| S30-r2 | `emil-performance/SKILL.md` | Core Principle 6: the tabular-numbers line | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is ui-polish's tabular-numbers line | [skill page](https://aiforui.dev/learn/skills/emil-performance) |
| S30-r3 | `emil-performance/SKILL.md` | Core Principle 6: "Never change font weight on hover." | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is the ui-review standards weight line | [skill page](https://aiforui.dev/learn/skills/emil-performance) |
| S30-r4 | `emil-performance/SKILL.md` | Core Principle 6: the HTML-equivalent comment's font path `inter.woff2` | the course's own preload example names `inter-var.woff2` on the line above; the comment in `plugins/user-interface/reference/types/web/layout-stability.md` names the same file so the two are equivalent | [skill page](https://aiforui.dev/learn/skills/emil-performance) |
| S31-r1 | `emil-prep-for-prod/SKILL.md` | Tone | house writing rules govern | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S33-r1 | `emil-prep-for-prod/baseline.md` | What the baseline doesn't cover | scope note pointing at other lanes | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S40-r1 | `emil-prep-for-prod/stability-and-states.md` | lane lead: "The lane the seeded dev account hides." | framing, no rule | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S40-r2 | `emil-prep-for-prod/stability-and-states.md` | lane lead: the sentence widening the lane to what moves the page after reading starts | scope note; that content is `layout-stability` (29) | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S40-r3 | `emil-prep-for-prod/stability-and-states.md` | lane lead: the owning-skills routing line | routing between course skills; names course skills | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S40-r4 | `emil-prep-for-prod/stability-and-states.md` | E7 bold-on-hover sentence | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is the ui-review standards weight line | [skill page](https://aiforui.dev/learn/skills/emil-prep-for-prod) |
| S42-r1 | `emil-product-thinking/SKILL.md` | framing paragraphs: "The bottleneck was never building" (its why-line kept as the opening of `plugins/planning/skills/interview/context/product.md`); "This action is opinionated in that it asks you questions based on notes made from podcasts" | rule-free prose, cut in the wave 1 review (R4) | [skill page](https://aiforui.dev/learn/skills/emil-product-thinking) |
| S42-r2 | `emil-product-thinking/SKILL.md` | Scope sentences "These principles come from a fixed set of interviews" and "They do not carry citations by design"; "The principles carry no citations by design" | rule-free prose, cut in the wave 1 review (R4) | [skill page](https://aiforui.dev/learn/skills/emil-product-thinking) |
| S43-r1 | `emil-product-thinking/principles.md` | cost amounts | cost-claims rule | [skill page](https://aiforui.dev/learn/skills/emil-product-thinking) |
| S46-r1 | `emil-prototype/PICKER.md` | verbatim markup and CSS, the `?v=` URL, `data-active`, the `:active` `scale(0.97)` press and the width-transition exception | the existing switcher asset `plugins/prototype/skills/explore-directions/assets/variant-switcher.html` is kept; its rules land in `plugins/prototype/skills/explore-directions/reference/switcher.md` (18) | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S47-r1 | `emil-prototype/SKILL.md` | Tone | house writing rules govern | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S47-r2 | `emil-prototype/SKILL.md` | "keep `<variant>`, leave the picker" | conflicts with prototype discipline rule 6 in `plugins/prototype/context/discipline.md` (delete or absorb when done) | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S47-r3 | `emil-prototype/SKILL.md` | the course default host (an isolated `/proto` route, in place only when the context can't be faked) and "state the reason out loud" | project conventions win: the HTML-mockup default host and the order A before B in `plugins/prototype/skills/explore-directions/SKILL.md` (R3) | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S47-r4 | `emil-prototype/SKILL.md` | the restrained palette for a run with no project | conflicts with each variant declaring its own direction | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S47-r5 | `emil-prototype/SKILL.md` | the sub-16px inputs flag | homed in the touch lane, `plugins/user-interface/reference/types/touch-web.md` (34) | [skill page](https://aiforui.dev/learn/skills/emil-prototype) |
| S50-r1 | `emil-typography/SKILL.md` | Reference files | course file index; our hub lists its own spokes | [skill page](https://aiforui.dev/learn/skills/emil-typography) |
| S57-r1 | `emil-ui-polish/SKILL.md` | Core Principle 2: "Weight changes on hover" line; the "Interaction states that stay put" heading and "Hover must not change layout" | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is the ui-review standards weight line | [skill page](https://aiforui.dev/learn/skills/emil-ui-polish) |
| S59-r1 | `emil-ui-review/STANDARDS.md` | Layout stability: the dynamic-content line and the tabular-numbers line | merged duplicate; the one wording in `plugins/user-interface/reference/types/web/layout-stability.md` is ui-polish's reserve-space and tabular-numbers lines | [skill page](https://aiforui.dev/learn/skills/emil-ui-review) |
| S59-r2 | `emil-ui-review/STANDARDS.md` | Layout stability: "and spinners" in "Skeletons and spinners occupy the same box" | conflicts with the course's own E4 (a spinner collapses the page); the choice between them is the `states` concern's, so `plugins/user-interface/reference/types/web/layout-stability.md` keeps "Skeletons occupy the same box" | [skill page](https://aiforui.dev/learn/skills/emil-ui-review) |
| S60-r1 | `emil-unslop-code/SKILL.md` | intro paragraphs: "Nobody flags AI code for one bad line", "Slop is rarely buggy", "Models over-defend because defensive code" | rule-free prose, cut in the wave 1 review (R4) | [skill page](https://aiforui.dev/learn/skills/emil-unslop-code) |
| S60-r2 | `emil-unslop-code/SKILL.md` | residue Fix-cell rationale, such as "The model comments the way it was rewarded", "Worse than no comment", "The compiler error was information", "Every unused degree of freedom", "emoji and celebration in log output" | rule-free prose, cut in the wave 1 review (R4) | [skill page](https://aiforui.dev/learn/skills/emil-unslop-code) |
| S63-r1 | `emil-writing-skills/SKILL.md` | Core Principles 1: decision-tree-default half | owner skill-writing decision | [skill page](https://aiforui.dev/learn/skills/emil-writing-skills) |
| S63-r2 | `emil-writing-skills/SKILL.md` | Core Principles 3: emphasis words | emphasis anchors, owner skill-writing decision | [skill page](https://aiforui.dev/learn/skills/emil-writing-skills) |
| S63-r3 | `emil-writing-skills/SKILL.md` | Core Principles 5: one skill per aspect | `plugins/playbooks/skills/skill-authoring/reference/skill-criteria.md` "Scope is a vertical slice" | [skill page](https://aiforui.dev/learn/skills/emil-writing-skills) |
| S63-r4 | `emil-writing-skills/SKILL.md` | Easing Decision Flowchart | illustrates the rejected decision-tree default | [skill page](https://aiforui.dev/learn/skills/emil-writing-skills) |
| S63-r5 | `emil-writing-skills/SKILL.md` | Common Mistakes; Checklist: lines that restate the rejected principles | the same rejected principles | [skill page](https://aiforui.dev/learn/skills/emil-writing-skills) |
| L1-r1 | Developing taste | rest | argument, no action | [lesson](https://aiforui.dev/learn/developing-taste) |
| L1-r2 | Developing taste | car and commodity paragraphs | no action | [lesson](https://aiforui.dev/learn/developing-taste) |
| L1-r3 | Developing taste | How to get better? | human study advice | [lesson](https://aiforui.dev/learn/developing-taste) |
| L1-r4 | Developing taste | Practice; Care; Homework | human practice advice | [lesson](https://aiforui.dev/learn/developing-taste) |
| L1-r5 | Developing taste | Feedback | page chrome | [lesson](https://aiforui.dev/learn/developing-taste) |
| L2-r1 | Friction as a feature | Plato and assembly narrative | history, no action | [lesson](https://aiforui.dev/learn/friction-as-a-feature) |
| L2-r2 | Friction as a feature | Feedback | page chrome | [lesson](https://aiforui.dev/learn/friction-as-a-feature) |
| L2-r3 | Friction as a feature | lead, first two paragraphs: "We treat friction as something bad" | rule-free prose, cut in the wave 1 review (R4) | [lesson](https://aiforui.dev/learn/friction-as-a-feature) |
| L2-r4 | Friction as a feature | Being selective about friction: essay part of "Friction is a good thing, but you need to be selective" | rule-free prose, cut in the wave 1 review (R4) | [lesson](https://aiforui.dev/learn/friction-as-a-feature) |
| L3-r1 | Get good at telling AI what you want | vocabulary-page paragraphs | course feature | [lesson](https://aiforui.dev/learn/get-good-at-telling-ai-what-you-want) |
| L3-r2 | Get good at telling AI what you want | What if LLMs get better? | speculation | [lesson](https://aiforui.dev/learn/get-good-at-telling-ai-what-you-want) |
| L3-r3 | Get good at telling AI what you want | Feedback | page chrome | [lesson](https://aiforui.dev/learn/get-good-at-telling-ai-what-you-want) |
| L3-r4 | Get good at telling AI what you want | lead: "One way of adding friction" | rule-free prose, cut in the wave 1 review (R4) | [lesson](https://aiforui.dev/learn/get-good-at-telling-ai-what-you-want) |
| L4-r1 | Getting into someone’s brain | Building a fleet of brain skills | the author's own skill list; record row | [lesson](https://aiforui.dev/learn/getting-into-someone-brain) |
| L4-r2 | Getting into someone’s brain | Feedback | page chrome | [lesson](https://aiforui.dev/learn/getting-into-someone-brain) |
| L4-r3 | Getting into someone’s brain | Make your own brain skills: install command and token | course install mechanics; the token is on the never-stored list | [lesson](https://aiforui.dev/learn/getting-into-someone-brain) |
| L5-r1 | How to build with aiforui skills | lead | course framing | [lesson](https://aiforui.dev/learn/how-to-build-with-aiforui-skills) |
| L5-r2 | How to build with aiforui skills | Invoke skills by name | course invocation mechanics; discovery is `## Next`, owner discovery decision | [lesson](https://aiforui.dev/learn/how-to-build-with-aiforui-skills) |
| L5-r3 | How to build with aiforui skills | Summary | reading copy | [lesson](https://aiforui.dev/learn/how-to-build-with-aiforui-skills) |
| L5-r4 | How to build with aiforui skills | Feedback | page chrome | [lesson](https://aiforui.dev/learn/how-to-build-with-aiforui-skills) |
| L6-r1 | How to write good skills | lead and testimonials | promotion | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r2 | How to write good skills | easing blueprint | decision-tree default, owner skill-writing decision | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r3 | How to write good skills | never/always paragraph | emphasis anchors, owner skill-writing decision | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r4 | How to write good skills | Keep your skills focused | one skill per aspect, owner skill-writing decision | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r5 | How to write good skills | install line | course install mechanics | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r6 | How to write good skills | Feedback | page chrome | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r7 | How to write good skills | Be strict: most-common-mistake sentence | unsupported frequency claim | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L6-r8 | How to write good skills | Be strict: Bad/Good motion values | course numbers go to config, not prose; the skill shows the form with a neutral example | [lesson](https://aiforui.dev/learn/how-to-write-good-skills) |
| L7-r1 | Intro | lead | motivation | [lesson](https://aiforui.dev/learn/intro) |
| L7-r2 | Intro | AI is only as good as the person directing it | motivation | [lesson](https://aiforui.dev/learn/intro) |
| L7-r3 | Intro | How the course works | course mechanics | [lesson](https://aiforui.dev/learn/intro) |
| L7-r4 | Intro | You're in early access | course status and skill-count claim | [lesson](https://aiforui.dev/learn/intro) |
| L7-r5 | Intro | Bonus features | course features; tooltip demo has no rule | [lesson](https://aiforui.dev/learn/intro) |
| L7-r6 | Intro | Ready? | page chrome | [lesson](https://aiforui.dev/learn/intro) |
| L7-r7 | Intro | Feedback | page chrome | [lesson](https://aiforui.dev/learn/intro) |
| L8-r1 | Knowing where to learn from | Sonner and Vaul demos | self-reference | [lesson](https://aiforui.dev/learn/knowing-where-to-learn-from) |
| L8-r2 | Knowing where to learn from | Some of the best people don't share their work | human scouting advice | [lesson](https://aiforui.dev/learn/knowing-where-to-learn-from) |
| L8-r3 | Knowing where to learn from | Extending this idea further | human scouting tactic | [lesson](https://aiforui.dev/learn/knowing-where-to-learn-from) |
| L8-r4 | Knowing where to learn from | Homework assignment | human exercise | [lesson](https://aiforui.dev/learn/knowing-where-to-learn-from) |
| L8-r5 | Knowing where to learn from | Feedback | page chrome | [lesson](https://aiforui.dev/learn/knowing-where-to-learn-from) |
| L9-r1 | Mental models | lead | course framing | [lesson](https://aiforui.dev/learn/mental-models) |
| L9-r2 | Mental models | Don't get caught up in the hype | volatile opinion, no action | [lesson](https://aiforui.dev/learn/mental-models) |
| L9-r3 | Mental models | Feedback | page chrome | [lesson](https://aiforui.dev/learn/mental-models) |
| L9-r4 | Mental models | Invite friction to your work: "Friction slowly goes away" | rule-free prose, cut in the wave 1 review (R4) | [lesson](https://aiforui.dev/learn/mental-models) |
| L10-r1 | Prototyping interfaces | Summary | reading copy | [lesson](https://aiforui.dev/learn/prototyping-interfaces) |
| L10-r2 | Prototyping interfaces | Feedback | page chrome | [lesson](https://aiforui.dev/learn/prototyping-interfaces) |
| L11-r1 | What are skills | lead | course framing | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L11-r2 | What are skills | What is an agent skill? | already held by `/playbooks:skill-authoring` | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L11-r3 | What are skills | granular-skills paragraph | owner skill-writing decision | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L11-r4 | What are skills | Anatomy of a skill | already-have | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L11-r5 | What are skills | Where to go from here | course navigation | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L11-r6 | What are skills | Feedback | page chrome | [lesson](https://aiforui.dev/learn/what-are-skills) |
| L12-r1 | AI for creative work | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r2 | AI for creative work | You can also use it for research: the research cost table and the model-token line | cost-claims rule; volatile model name | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r3 | AI for creative work | Going further: poster attribution to named models and apps, and the four branded posters | vendor specifics; course-branded artwork | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r4 | AI for creative work | Going further: "I like to run this type of workflow even when I'm not looking" and "The goal for me is to have an agent running at all times" | personal habit, no rule | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r5 | AI for creative work | Making it repeatable: install line and example prompt | course install mechanics | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r6 | AI for creative work | vocabulary link and image URLs | course-site links | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L12-r7 | AI for creative work | capture annotations | the capturer's notes, not course text | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/ai-for-creative-work) |
| L13-r1 | Reviewing your work | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/reviewing-your-work) |
| L13-r2 | Reviewing your work | vendor video and install line | vendor demo; course install mechanics | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/reviewing-your-work) |
| L13-r3 | Reviewing your work | capture annotations | the capturer's notes, not course text | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/reviewing-your-work) |
| L13-r4 | Reviewing your work | How it works opener "looking for ways to improve the workflow" | rule-free working-habit prose; the review-tool workflow is `plugins/prototype/skills/build-generator/reference/review-tools.md` (19) | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/reviewing-your-work) |
| L14-r1 | Tools as means to an end | Others do it too | third-party anecdote; a row in this record | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) |
| L14-r2 | Tools as means to an end | install line | course install mechanics | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) |
| L14-r3 | Tools as means to an end | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) |
| L14-r4 | Tools as means to an end | Let me give you an example; Getting more precise results: the personal name, handle, product link and source-app name | third-party anecdote details; the pattern lands in `plugins/prototype/skills/build-generator/reference/examples.md` (19) | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) |
| L14-r5 | Tools as means to an end | capture annotations | the capturer's notes, not course text | [lesson](https://aiforui.dev/learn/workflows/build-a-tool-to-build-the-tool/tools-as-means-to-an-end) |
| L15-r1 | Defining a system | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r2 | Defining a system | Components: the `[DEMO]` copy-button capture annotation | capture annotation, no rule | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r3 | Defining a system | `[VISUAL]` flowchart and link-card annotations, and the skill-page link | capture annotation; page chrome | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r4 | Defining a system | lead sentences 1-3 (download count, strictness claim, and the strict-foundation sentence that leans on it) | self-claim with an unverifiable figure, no rule | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r5 | Defining a system | Documentation: the design-system documentation anecdote and its link | first-person anecdote, no rule | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r6 | Defining a system | Documentation: the tool-agnostic, timeless-approach sentence; the "I've packaged this whole section" sentence and the skill link card | course framing; course skill reference | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r7 | Defining a system | Putting it all together: the playground lead and its demo source files | interactive demo framing; the DESIGN.md deliverable and the Tokens block carry the rules | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r8 | Defining a system | Documentation per-component list and Bad/Good card; Iterate: READING THE MISTAKES table, the fix-one-screen restatement, and the "Here's how you know whether your system is defined well enough" lead-in | the same rules as the course skill's four-part list, language rule 1, drift table and fix-the-docs sentence, placed once in `plugins/user-interface/reference/design-system-doc.md` (one home per rule) | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L15-r9 | Defining a system | lead: "This lesson is about" | course framing word; the sentence stays, reading "This procedure is about" in `plugins/user-interface/reference/design-system-doc.md` because the file is a procedure, not a lesson | [lesson](https://aiforui.dev/learn/workflows/how-i-work/defining-a-system) |
| L16-r1 | Using AI at work | lead | narrative | [lesson](https://aiforui.dev/learn/workflows/how-i-work/using-ai-at-work) |
| L16-r2 | Using AI at work | Tooling | personal tool preferences | [lesson](https://aiforui.dev/learn/workflows/how-i-work/using-ai-at-work) |
| L16-r3 | Using AI at work | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/how-i-work/using-ai-at-work) |
| L17-r1 | Handing it to your agent | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/handing-it-to-your-agent) |
| L18-r1 | Recording an interaction | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/recording-an-interaction) |
| L18-r2 | Recording an interaction | Slow it down: speed steps 0.75x, 0.1x and ping-pong | `plugins/prototype/context/control-panel.md` multipliers are the one source | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/recording-an-interaction) |
| L19-r1 | Setting up Lapse | lead | vendor introduction | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) |
| L19-r2 | Setting up Lapse | Installing it | vendor install, private-registry token lines | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) |
| L19-r3 | Setting up Lapse | Dropping it in | vendor mounting; pointer row | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) |
| L19-r4 | Setting up Lapse | A skill to help you | course skill pointer | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) |
| L19-r5 | Setting up Lapse | Feedback | page chrome | [lesson](https://aiforui.dev/learn/workflows/reviewing-animations/setting-up-lapse) |
| V0-r1 | Vault page | The intro and filter demo | page UI | `aiforui.dev/vault` |
| O1-r1 | [Skill pages](#skill-pages) | install lead, command, token and "rename skills" text | course install mechanics | [Other captures](#other-captures) |
| O2-r1 | Course pages (home, boss, team, learn index, skills index, settings, certificate) | marketing copy, purchase links and cost lines | marketing copy holds no rule; purchase links are on the never-stored list; cost lines fall under the cost-claims rule (`.claude/rules/cost-claims.md`) | [Other captures](#other-captures) |
