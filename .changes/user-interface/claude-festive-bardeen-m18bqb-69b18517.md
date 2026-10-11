---
bump: minor
---

### Added

- A `LICENSE` carrying the MIT notice for content reauthored from emilkowalski/skills (pinned in `docs/upstream/emilkowalski-skills.md`) beside the Melodic Software derivative line.
- `scripts/check-emilkowalski-drift.sh`, run weekly by the upstream drift workflow: it reads the emilkowalski/skills tree once, compares each pinned file with its pin and reports new upstream skill files.
- `reference/animation/`: a shared animation catalog (whether to animate, purpose, cheapest tool, properties, easing and duration roles, reduced motion, feel check), stack-neutral component behaviors, gestures and springs, web animation performance, and a glossary of effect names.
- An `animation:` settings block (easing curves as four control points, `press`/`small`/`medium`/`large` role durations, a swipe velocity threshold), settable in the user, team and personal config files.
- `/user-interface:write-animation`: decides whether an element should animate and why, names the stack from the project's files, looks up its current animation guidance (a vendor skill, then docs lookup, research, official docs, repo patterns), and writes one animation from the project's motion tokens with reduced motion included; CSS is written through `/user-interface:write-css`.
- `/user-interface:audit-animation [tree|opportunities|performance] [--fix] [<target>]`: a read-only animation review of the diff, the whole tree, the opportunities (and where not to animate) or the frame cost, each finding with severity and "verified from code" or "needs a device recording"; CSS goes through write-css review mode first, and `--fix` applies one finding at a time after a yes.
- `scripts/detect.mjs --config` warns about a team routing row or `disable` entry that names a concern no bundled row has, so a renamed concern no longer goes quiet.

### Changed

- `/user-interface:write-css` takes its easing curves and its `duration` rule from the resolved `animation:` block instead of fixed values; at the defaults a dropdown or menu now stays within 250ms (was 300ms), and review mode judges the linter's `duration` findings against the configured role.
- Routing: the `motion` concern is now `animation-authoring` (first routes `/pixel-art:animate`, `/user-interface:write-animation`), joined by `animation-audit` (`/user-interface:audit-animation`); the external emilkowalski/skills rows are removed now that their content ships here, and `expo@expo-plugins` is added. A team config whose `routing` rows or `disable` entries name `concern: motion` should rename it to `animation-authoring`; detect now warns until it does.
- The accessibility floor's "Motion is optional" now says what a reduced-motion setting removes (movement) and what may stay (a short opacity or color change), with a pointer to WCAG 2.2 success criterion 2.3.3.
