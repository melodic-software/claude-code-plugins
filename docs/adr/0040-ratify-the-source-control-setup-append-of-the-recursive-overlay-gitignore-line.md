# Ratify the source-control setup append of the recursive overlay gitignore line

- Status: accepted
- Date: 2026-09-29

## Context

The [config-cascade convention](../conventions/config-cascade/README.md) says no plugin writes
the consumer's `.gitignore`: a setup skill recommends the ignore line and leaves the edit to the
consumer. That is the recommend posture, the default.

`/source-control:setup apply` does not follow it for one line. At team-layer bind (`layer=team`) it probes a
nested sentinel (`.claude/nested/overlay.local.md`) with `git check-ignore --no-index -v`, and when
no repository `.gitignore` rule matches it appends the recursive `.claude/**/*.local.*` line to the
consumer `.gitignore`, announces the edit, and stages that line with the team file
(`plugins/source-control/skills/setup/reference/apply-convention.md`, the `layer=team` step). The
skill's boundary list names it as the only `.gitignore` write, and the `Local overlay ignore rule`
check reports a missing rule as a FAIL that `apply` remediates
(`plugins/source-control/skills/setup/SKILL.md`).

The append happens at bind time, before any overlay exists, because an overlay written before the
line is present leaks a personal file into the index. A recommendation the consumer may act on
later cannot close that window.

[ADR 0015](0015-bind-the-tracker-at-repo-root-with-an-allowlisted-personal-overlay.md) already
declares the same kind of exception for `/work-items:setup apply`, which appends
`.work-item-tracker.local.json`. The source-control append had no record of its own.

## Decision

Ratify the source-control append as a declared exception, on equal footing with the work-items
append in ADR 0015. The three gitignore postures stay:

- **Recommend** is the default.
- **Append-announced** has two consumer-root exceptions: `/source-control:setup apply` appends the
  recursive `.claude/**/*.local.*` line, and `/work-items:setup apply` appends
  `.work-item-tracker.local.json`. Each announces the edit and touches nothing else in
  `.gitignore`.
- **Own-ignore-file**, a self-ignoring `.gitignore` inside a plugin-owned directory (a memory root
  or `<standards_dir>/`), is a different file from the consumer's `.gitignore` and is not a third
  exception.

Converging the postures fleet-wide is declined.

## Consequences

The source-control append is a sanctioned behavior, not drift, and the config-cascade README
carries the same two-append wording. A new plugin that wants to write the consumer's `.gitignore`
needs its own ADR. The append stays limited to the one recursive line, announced and staged, so a
consumer's other ignore rules remain theirs.
