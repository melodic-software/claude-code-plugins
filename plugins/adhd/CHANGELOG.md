# Changelog

All notable changes to the `adhd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

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
