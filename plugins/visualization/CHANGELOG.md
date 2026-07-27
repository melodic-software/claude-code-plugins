# Changelog

All notable changes to the `visualization` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.1]

### Changed

- **Local HTML files get an explicit ephemeral-tier placement rule.** The
  local-file medium now writes via the platform temp primitive (`mktemp` on
  Unix/Linux, a user-scoped temp under `%LOCALAPPDATA%\Temp` on Windows), never
  into the consumer's repository tree, one file per run — and the handed-back
  path is never deleted. Previously the skill named no placement at all.

## [0.1.0]

### Added

- **Initial release.** `/visualization:visualize` — a form-and-medium router that
  infers what in the current conversation should be shown visually, picks a form
  (a mermaid diagram, a markdown table, a hand-authored SVG/CSS chart, ASCII/Unicode
  art, or a rich rendered page) and a medium (inline terminal, a local HTML file, or
  a published Artifact), renders good defaults, and asks only when the target is
  genuinely ambiguous and no form was named.
- **Three-tier medium model with a surface gate.** Delivery escalates inline
  terminal → local HTML file → published Artifact; the published-Artifact surface
  is presence-gated (heavily availability-constrained) and degrades visibly to a
  local file or terminal rather than assuming the surface exists.
- **`medium` `userConfig`** (string, default `auto`; values `auto` / `terminal` /
  `file` / `artifact`, validated in-skill since `userConfig` has no native enum
  type) — a personal preference for the auto-selected delivery medium, with `file`
  keeping richer output on the machine and never published.
- **Router, not craft.** Chart craft routes to a chart-craft/dataviz capability and
  rich-page fundamentals to an artifact-design capability and the Artifact tool's
  own contract — each presence-gated with a documented fallback, never restated.
- **Grounded catalog.** The skill's `context/decision-matrix.md` records the
  rendering-surface facts (terminal GFM, terminal mermaid as source only, the
  artifact CSP and availability gating), the thirteen stable mermaid families (with
  the newest set flagged unverified), and the zero-dependency chart paths — with
  sources and verification dates.
