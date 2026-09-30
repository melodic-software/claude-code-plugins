# Ratify consumer config location outliers in place

- Status: accepted
- Date: 2026-09-29

## Context

The [config-cascade convention](../conventions/config-cascade/README.md) places a surface's layers
at `${CLAUDE_PROJECT_DIR}/.claude/<name>`, with a gitignored `*.local.*` overlay beside the team
file. Four consumer-facing surfaces put their config elsewhere:

- `work-items` binds the tracker at `.work-item-tracker.json` in the repo root.
- `standards` keeps its team layer and overlay in `<standards_dir>/` (default `docs/standards/`),
  rooted by the `standards_dir` key of `.claude/standards.yaml`.
- `songwriting` reads project-level prompt-template overrides from
  `songwriting/templates/pat-pattison/<name>.md`. The `rhyme`, `song-form` and `meter-prosody`
  skills check that path before the bundled template, and `/songwriting:setup` scaffolds and
  inventories it.
- `work-items` reads the recurring schedule from `.github/recurring-schedule.json`, through
  `/work-items:setup`, `/work-items:work` and the `due` and `recheck` actions.

The options were to ratify each in place, relocate each under `.claude/`, or replace them with one
pointer file that names each surface's root. The overlay `.gitignore` line also drifted into
several spellings (#3577).

The headless probe on #3577 shows `.claude/` writes prompted in `acceptEdits` and does not
discriminate in `default` or `auto`. The Claude Code on the web case is unmeasured.

## Decision

Ratify each surface in place, as a declared exception in the config-cascade README, on local
justification:

- **`work-items` repo-root binding stays.** [ADR 0015](0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md)
  already ratifies it.
- **`standards` stays at `<standards_dir>/`.** The existing `.claude/standards.yaml` pointer
  already roots it, so it needs no new mechanism.
- **`songwriting/templates/` stays.** The files are content the consumer authors and reads as
  prose, not settings.
- **`.github/recurring-schedule.json` stays.** `.github/` belongs to workflow tooling, and the
  schedule is reconciled against tracker items that workflow tooling files.

The pointer file is not adopted as a fleet rule. It stays the sanctioned relocation mechanism, as
`standards` uses it, if a surface later needs a configurable root. Relocation under `.claude/` is
declined.

The canonical overlay spelling is the recursive `.claude/**/*.local.*` line, applied when each
surface next touches its setup, with no separate migration. The exceptions
[ADR 0040](0040-ratify-the-source-control-setup-append-of-the-recursive-overlay-gitignore-line.md)
and the config-cascade README name stay: the in-directory `.gitignore` under `<standards_dir>/`
and the `work-items` repo-root overlay line.

The ruling rests on each placement being locally justified, not on the `.claude/` write guard.

## Consequences

Consistent with #3573: keep the variants, declare the exceptions, record one ADR. Consumer paths
do not move, so no consumer breaks, and nothing shows the current placements cause harm.
Generalizing the pointer file would add a lookup to every resolution ladder for no measured
benefit.

Recheck when a web-session measurement shows plugin-owned `.claude/<name>` writes are fine
everywhere and a consumer reports confusion, or when Claude Code changes protected-path handling.
