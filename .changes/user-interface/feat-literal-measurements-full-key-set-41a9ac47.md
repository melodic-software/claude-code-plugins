---
bump: minor
---

### Added

- The full set of user-interface taste keys in `reference/defaults.yaml`, `reference/team.schema.json` and the README key table: 101 roles across `animation`, `color`, `css`, `icon`, `layout`, `performance`, `radius`, `spacing`, `states`, `touch` and `typography`, among them hover duration, show delays, enter and hover scales, travel, springs, gesture constants, color ramp and triage thresholds, border widths, focus ring, icon sizes, layout widths, the spacing steps, fluid type inputs, line heights, measure and small text sizes. A team sets any of them in its config file; a project's own tokens still win. Skills start reading them as their references are rewritten to name the keys.
- `animation.scale.press_min` (default `0.95`): the lower limit `/user-interface:audit` will report a project press scale below; it never rewrites the value.
- `touch.target_desktop_px` refuses a value under the 24px target-size floor, and `typography.fluid_body.min_rem` and `typography.fluid_scale.size_narrow_rem` refuse one under `1` (the 16px body floor); a refused value leaves the default and is named in the config report.
- Each default's source is recorded: course and Emil Kowalski keys in their upstream records, independent sources in the new `docs/upstream/user-interface-default-sources.md`, and heuristics labeled in the defaults file.

### Changed

- `animation.easing.out` is now `0.32, 0.72, 0, 1` (was `0.23, 1, 0.32, 1`), the curve the course names as its default for entering elements.
- Hover feedback has its own `animation.duration_ms.hover` (`150`) and is no longer under `medium`; each duration key is stated as both the value a recipe writes and the role's ceiling.
- `animation.blur_max_px` is no longer described as a heuristic: its `20` now has a recorded source.
