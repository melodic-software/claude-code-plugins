# Changelog

All notable changes to the `adhd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.1]

### Changed

- `clarify` places its local HTML file in the topic-docs **ephemeral tier**
  instead of preferring the session scratchpad. The old wording branched on
  whether the harness injected a scratchpad path, which made placement depend
  on how the session was launched — invisible from inside the skill — and
  depended on an undocumented surface upstream has declined three times to
  support. The skill now resolves one temp path deterministically, and states
  explicitly that the file is not deleted before returning — the path is the
  delivery mechanism, so it must stay readable when the reader opens it. See
  `docs/conventions/topic-docs/README.md` §"The ephemeral tier".

## [0.3.0]

Fixes every finding from the 2026-07-23 live audit (handoff item
`20260723-082358-adhd-shape-clarify-audit`, #1130).

### Added

- **Conflicting-shaper check at the enforcing layer (H1, L4).** The
  caveman-style mutual-exclusion warning lived only in README/plugin.json —
  layers the model never reads at invocation time; reproduced live as a silent
  contradictory mix. Both SKILL.md bodies now surface an active
  terse-for-tokens shaper before applying, name the source found in session
  context, and ask the user to pick one. Advisory by necessity: no documented
  skill-to-hook detection mechanism exists.
- **`clarify` trivial-target escape hatch (M1).** A resolved target with fewer
  than ~2 decisions gets a one-line "nothing dense here" + a question for the
  intended target instead of the full table/glossary apparatus.
- **`shape` off-switch (L1).** "stop shaping" / "normal output" ends the
  standing posture; documented in SKILL.md and README.
- **`shape` Gotchas section (L6, audit trail).** Records the audit's observed
  failures, the compaction-durability caveat, and the explicit rules-5-vs-10
  boundary test (last-completed step + next step only; never a running
  done-list). Clears the skill-quality no-Gotchas WARN.
- **Evals for every observed failure mode (M4).** shape: conflicting-shaper-
  active, off-switch. clarify: trivial target, cold start (no prior message).

### Changed

- **`clarify` local-file rung writes to an OS temp path (M2).** The previous
  destination leaned on a plugin-data substitution variable that is not
  documented for skill-body substitution and substituted unpredictably in live
  use (including to the wrong plugin's data dir when the token traveled through
  another skill's arguments). OS temp/scratchpad is now the primary local-file
  destination and the variable is gone from the skill body.
- **Sibling precedence made explicit (M3, L3).** clarify's decision table is
  exempt from shape's five-item list cap (fidelity wins over shaping) — stated
  in both skills; clarify on already-shape-formatted output is declared a
  no-op.
- **`clarify` fidelity rule 2 fallback (L5).** An original with no identifiers
  gets a declared synthesized locator (sequential marker or quoted opening
  phrase) — never a chunk with no way back to its source passage.
- **README compaction caveat (L2).** The standing posture is content-based
  persistence; re-invoke after a context compaction if shaping stops.

Out of scope by design: description-length trimming (marketplace-level gate
decision, recorded in the audit's policy note).

## [0.2.0]

### Added

- **`/adhd:clarify`** — on-demand, one-shot reshape of a dense, decision-heavy
  artifact already on screen (default target: the previous assistant response;
  an explicit target overrides). Restructures faithfully — chunks the content
  one-decision-at-a-time, defines the session's own jargon, and surfaces exactly
  what the reader must decide — with hard fidelity rules: operative terms of every
  recommendation quoted verbatim, original item numbers kept as back-links,
  omissions listed explicitly, and a closing line that the clarification is a lens
  (validate answers against the original). Changes STRUCTURE, never altitude.
- **Artifact-forward rendering.** For big or decision-dense content, renders an
  HTML decision table (item | recommendation | alternative | what-you're-deciding,
  rows numbered so terminal answers map back), honoring the Artifact tool contract
  via the `artifact-design` skill; degrades to a local HTML file, then structured
  terminal markdown, when the Artifact surface is unavailable.

### Changed

- `/adhd:shape` description gains a one-line boundary vs `adhd:clarify` (standing
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
