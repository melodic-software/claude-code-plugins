---
description: "Hold a UI pixel-for-pixel steady through a change: PNG screenshots of the listed states before the first edit (baseline), then again at each green checkpoint, with differing pixels counted against pixel_tolerance (compare). Never edits a baseline. Use when: a plan phase has a Parity contract line, a refactor must leave the UI unchanged, 'check visual parity', 'did this change the UI'."
argument-hint: "<baseline|compare> [states]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: test
  summary: Baseline screenshots before a change, pixel counts against them after
---

## Purpose

A change that promises "the UI looks the same" is checked here by counting pixels, not by looking
at screenshots. `baseline` records PNG images of the screens and states to hold, before any code
changes. `compare` records the same screens and states again and reports, per image, how many
pixels differ. The count is held to the repository's `pixel_tolerance`, which is 0 unless the team
records a reason for more.

The baseline is the reference the change answers to. This skill never edits, replaces or
re-captures it, and it never edits a capture harness or the app's styles to make a compare pass.

## Arguments

`$ARGUMENTS`: `<baseline|compare> [states]`.

- `baseline`: capture the reference images. Run it before the first edit of the change.
- `compare`: capture again and count. Run it at each green checkpoint.
- `[states]`: the screens and states to hold, for example `invoice list (empty), invoice list (40
  rows), invoice editor (validation errors)`. Without it, read the plan phase's `**Parity
  contract:**` line; with neither, ask once which screens and states to hold, and stop when there
  is no answer.

## Step 1: Pick the capture route

1. **The repository's own visual suite first.** When the repository already runs a
   visual-regression suite (a Playwright `toHaveScreenshot` spec, a Storybook visual test, a
   screenshot test in its unit runner), run it at each checkpoint and report its verdict as the
   result for the states it covers. Capture here only the states it does not cover.
2. **A driver that writes PNG files.** Capture only through the Playwright CLI
   (`/playwright:playwright`, when it is among the available skills) or through the repository's
   own harness when that harness writes PNG files. Any other driver, including one that returns
   screenshots only into the conversation, cannot feed a pixel count: stop with the gap report
   (what to hold, which driver resolved, and that a PNG-writing driver is needed).
3. **One launch path.** Start and restart the app the way `/testing:run-e2e` starts it, through
   its launch path (its orchestrator rule, the bundled `run` skill, or the already-running app).
   Never start a second instance beside the one that path starts.

This step is done when each listed state has a route: the repository's suite, a PNG-writing
driver, or the gap report.

Fix the capture settings before the baseline and keep them for every compare: the browser and its
version, the viewport, the device scale factor, and the same seed data, clock and fonts the app
renders with. Freeze or hide anything that changes on its own (a clock, a spinner, a caret).

## Step 2: Resolve the tolerance

Run, with the repository root as `--repo`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/check-visual-parity/scripts/visual-compare.sh" config --repo "<repository root>" --user 'pixel_tolerance=${user_config.pixel_tolerance}'
```

It prints one line, `pixel_tolerance=<n> source=<layer> reason=<text>`. The team value lives in
`docs/conventions/testing.yaml` as a map, read from origin's default branch:

```yaml
pixel_tolerance:
  pixels: 2
  reason: "subpixel text: the CI image renders without hinting"
```

The user-global `~/.claude/testing.yaml`, the overlay `.claude/testing.local.yaml` and the plugin
option can only lower the team value. The script reports a raise as ignored, and names an invalid
layer and drops it. Quote a `reason` that holds a colon followed by a space. A tolerance above 0 is used only with its
recorded reason; never pass a higher `--tolerance` than this line gives.

## Step 3: baseline

Before the first edit of the change:

1. Launch the app through the route in Step 1 and capture each listed state as one PNG in
   `<memory_dir>/<branch-slug>/visual-parity/baseline/` (`<memory_dir>` is `.work/` unless the
   project's instructions name another root). Name each file for its state, such as
   `invoice-list-empty.png`.
2. Record the manifest:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/check-visual-parity/scripts/visual-compare.sh" manifest --dir "<baseline dir>" --browser "<name and version>" --viewport <W>x<H> --scale <n>
   ```

   It stores each image's sha256 with the OS, browser, viewport, scale and commit. It refuses a
   directory that already has a manifest; a new baseline goes in a new directory, and only when
   the person asks for one.

## Step 4: compare

At each green checkpoint:

1. Capture the same states, on the same host with the same settings, into
   `<memory_dir>/<branch-slug>/visual-parity/after/<checkpoint>/`, and run `manifest` on that
   directory with the same `--browser`, `--viewport` and `--scale`.
2. Compare:

   ```bash
   bash "${CLAUDE_PLUGIN_ROOT}/skills/check-visual-parity/scripts/visual-compare.sh" compare --baseline "<baseline dir>" --after "<after dir>" --tolerance <n> --reason "<reason>" --diff-dir "<memory_dir>/<branch-slug>/visual-parity/diff/<checkpoint>" --deps-dir "${CLAUDE_PLUGIN_DATA}"
   ```

   Pass `--reason` only when the tolerance is above 0. The first run installs pixelmatch and pngjs
   from the committed lockfile; when `npm` is missing or the install fails, the script prints one
   repair line, which goes in the report as is.
3. Read the exit code: 0 every image passed, 1 at least one failed, 2 the run could not compare (a
   baseline image changed after its manifest, the after capture's browser, viewport, scale or OS
   differs from the baseline's, or the install is broken).

A failing image is a finding, not something to fix here. Report it with its diff image and stop
the checkpoint. A change that the person accepts as intended is recorded by them as a new baseline
in a new directory, never by overwriting this one.

## Report

Per checkpoint: the `pixel_tolerance` line from Step 2; each image's
`differing=<n> tolerance=<t> verdict=<pass|fail> name=<image>` line; the diff image path for each
failure; the visual suite's verdict when Step 1 ran one; and the capture cost, as the number of
images captured and the seconds the capture and compare took.

## Upstream facts this rests on

| Claim | Pointer | As of | Recheck trigger |
|---|---|---|---|
| pixelmatch counts a pixel as differing by a perceptual colour threshold, `0.1` by default, which the script passes and prints | [pixelmatch README, API](https://github.com/mapbox/pixelmatch#api) | 2026-10-10, pixelmatch 8.0.0 | A pixelmatch release that changes the default or the option's meaning (a Dependabot bump of this skill's lockfile) |
| Packages a plugin loads at run time install on first use from a committed lockfile with `npm ci` into the plugin data directory | [On-demand dependencies, Rule 2](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/on-demand-dependencies/README.md#rule-2-install-on-first-use-with-npm-ci-into-the-plugin-data-directory-spec) | 2026-10-10, version 2.2.0 | A new version of that convention |

## Next

- Continue the change one structural step at a time: /implementation:implement refactor
- Verify the changed flows end to end beyond the pixels: /testing:run-e2e

## Gotchas

- A compare on a different host, browser version or scale factor counts rendering noise as
  regressions; the manifest check stops it with exit 2 rather than reporting a misleading count.
- Anti-aliased text and gradients shift by a few pixels between GPU and software rendering; that
  is what a team `pixel_tolerance` with a reason is for, never a per-run `--tolerance`.
- A screenshot taken before the page settles (web fonts, lazy images, an animation) differs on
  every run; wait for the state before capturing.
