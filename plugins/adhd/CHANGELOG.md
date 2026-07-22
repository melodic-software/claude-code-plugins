# Changelog

All notable changes to the `adhd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- **`/adhd:digest`** — on-demand, one-shot reshape of a dense, decision-heavy
  artifact already on screen (default target: the previous assistant response;
  an explicit target overrides). Restructures faithfully — chunks the content
  one-decision-at-a-time, defines the session's own jargon, and surfaces exactly
  what the reader must decide — with hard fidelity rules: operative terms of every
  recommendation quoted verbatim, original item numbers kept as back-links,
  omissions listed explicitly, and a closing line that the digest is a lens
  (validate answers against the original). Changes STRUCTURE, never altitude.
- **Artifact-forward rendering.** For big or decision-dense content, renders an
  HTML decision table (item | recommendation | alternative | what-you're-deciding,
  rows numbered so terminal answers map back), honoring the Artifact tool contract
  via the `artifact-design` skill; degrades to a local HTML file, then structured
  terminal markdown, when the Artifact surface is unavailable.

### Changed

- `/adhd:shape` description gains a one-line boundary vs `adhd:digest` (standing
  session posture vs one-shot artifact reshape). Behavior unchanged.

## [0.1.0]

### Added

- **Initial release.** `/adhd:shape` — shape the assistant's output for a
  reader with ADHD: lead with the concrete next action, number multi-step
  work, restate state across turns, cap and rank lists at five, give concrete
  time estimates, make finished work visible, keep a flat error tone, and cut
  preamble, recap, and closing pleasantries. Includes override rules for
  explain requests, destructive-action confirmation, debug spirals, and
  ambiguity, plus a pre-send check.
- On-demand and session-standing: the skill does not auto-fire on every
  message; it surfaces on plain-language request or direct invocation, and
  once invoked its rules persist as a standing instruction for the rest of the
  session.
- Reauthored — not forked — from
  [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT): the ten
  rules' substance is preserved, the wrapper is adapted to this marketplace's
  discovery discipline (no auto-fire-on-any-message), and the prose is
  rewritten. Zero-config, zero-prerequisite; no `userConfig`, hooks, or setup
  skill.
