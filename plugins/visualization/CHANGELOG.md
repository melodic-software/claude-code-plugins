# Changelog

All notable changes to the `visualization` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.5.1]

### Changed

- visualize: the description names the intent (visualize, diagram, chart, draw, sketch, render, or which form fits) instead of ten near-synonym phrases, and drops its all-caps emphasis; three "do not restate here" sentences addressed to the file's editor rather than the model are removed, along with the Purpose section's fourth copy of the not-a-craft-teacher boundary (the Gotchas and Boundary sections keep it).
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.5.0]

### Added

- **Code-shape sketches in `visualize`.** Seven new Step 2 form rows: pseudocode (for logic
  described in prose or not yet written), call tree, component tree with file paths, shallow file
  tree with one line of responsibility per entry, types and signatures, a diff-shaped delta over any
  of those when the surrounding shape is already in the conversation, and the whole block as the
  fallback when no sketch is smaller than the code. A code-vs-domain tie-break keeps them disjoint
  from the mermaid row, and the smallest-view heuristic (pick the smallest view that makes the key
  point clear, place it beside the short text it supports, keep only what the question needs, use
  one form, sometimes several, rarely all) joins Step 2. One example per form lives in a new
  `context/code-shapes.md` spoke, with real box-drawing glyphs and placeholder paths. The family is
  inspired by and adapted from the humanlayer/skills `show-me` skill; the element-by-element
  attribution table is `docs/upstream/humanlayer-skills.md` in the marketplace repository. The skill
  body and its spokes carry no provenance by design.
- **Context-driven prompting on a bare code paste, tunable.** Step 4's form-ambiguity rule now
  covers pasted code with thin context: when two or more code-shape forms fit about equally the
  skill asks one ranked question (two to four forms, recommended first) and renders nothing until
  the answer; when one form dominates it renders without asking. A new `thin_context_prompt` option
  (`auto` default, `always`, `never`) tunes that behavior.
- **A new trigger and a form-list word.** `'show me the shape of this'` joins the quoted triggers
  and "code-shape sketches" joins the form list in the description, paid for by shortening the
  closing clause; every existing trigger is preserved and the description stays at the
  1024-codepoint field maximum.
- **Rich-page genres and product matching.** The rich-page row names an infographic and a short
  slide deck; Step 5 matches a product's own colors, type, spacing, and components when the subject
  is a product UI, uses real labels and data, and supports desktop and mobile.
- **Evals 8-12** (pseudocode stays terminal; delta over a known shape picks a diff; smallest-view
  restraint; thin-context paste offers one ranked menu; a pull-request diff with the `artifact`
  argument stays a terminal fence). Eval 4's third expectation now reads "when the target is obvious
  and one form dominates, or a form was named".
- **Notice.** The example blocks in `skills/visualize/context/code-shapes.md` carry text from
  humanlayer/skills (MIT). This paragraph travels with them, is the copy that ships with the
  installed plugin, and must survive any future trim of this changelog:

  ```text
  Copyright (c) 2026 HumanLayer

  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and
  associated documentation files (the "Software"), to deal in the Software without restriction,
  including without limitation the rights to use, copy, modify, merge, publish, distribute,
  sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is
  furnished to do so, subject to the following conditions:

  The above copyright notice and this permission notice shall be included in all copies or
  substantial portions of the Software.

  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT
  NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
  DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
  ```

### Changed

- **Delivery rule for attacker-controlled content, stated once.** Code-shape sketches take the same
  medium ladder as every other form (terminal under `auto`, `file`/`artifact` and the configured
  preference honored), except that a pull-request diff, fetched content, or another repository's
  files are never rendered to HTML until the rendered-views escape helper ships; that exception
  overrides an explicit argument and the preference, with a one-line notice. The rendered-views
  security baseline already governed this; the skill now says so.

### Fixed

- **Catalog: the artifact CSP is no longer described as blocking every external host.** The
  current contract allows Google Fonts and scripts from four CDN hosts (cdnjs, jsDelivr `/npm/`
  paths, the Tailwind and jQuery CDNs) and blocks everything else; corrected at five sites, with
  "inline everything, no network calls" restated as this plugin's own policy rather than a platform
  fact. Verified 2026-09-04 against the artifacts page.
- **Catalog: the terminal-mermaid-is-source citation pointed at a page that does not say it.** The
  `output-styles` citation is replaced by a scoped absence claim (the interactive-mode and fullscreen
  pages and the docs corpus), the binary's lack of a terminal-side renderer, and the open issues that
  request rendering.
- **Catalog: the bundled mermaid runtime is recorded as a version-specific fact** (11.16.1, read from
  the Claude Code 2.1.260 binary, with a per-release recheck) instead of "undocumented", and the
  newest mermaid families are described as present upstream but unverified in the viewer.
- **Catalog: public sharing of artifacts with mermaid, SVG data URIs, or AVIF** is listed as a
  reported open issue (anthropics/claude-code#79824), mechanism unconfirmed, with its recheck
  trigger.

## [0.4.2]

### Changed

- **Options reference cites the plugin-reconfiguration convention.** The generated
  How-to-set-these block no longer restates the 2.1.240 verified-version record.

## [0.4.1]

### Added

- **A `## Boundary` section in the visualize skill** routing the explorer shape out:
  an interactive parameter explorer whose output returns as a prompt goes to the
  first-party playground skill (or the `playgrounds` wrapper) when installed, with a
  visible static-form fallback when it is not. Traced to its verdict row in the
  native-surfaces registry.

### Changed

- **Design-canvas catalog facts refreshed to v2.1.251.** The decision-matrix spoke
  now records the `/design` skill's subcommand dispatch (with `consent`/`revoke`
  reserved for the hidden grant-management commands), the registered design-sync
  family and its registry disposition, and an updated verified-on/recheck line.

## [0.4.0]

### Added

- **A cascade rung in the medium ladder.** When neither an explicit argument nor the
  `medium` userConfig option decides the delivery tier, `/visualization:visualize` now
  resolves the `rendered-views` config-cascade surface (user-global, team, and local
  overlay layers of `.claude/rendered-views.md`, per-key override on `medium`), names the
  winning layer when reporting the choice, and degrades visibly on a malformed layer.
  Auto remains the shipped default when every rung is unset. The rung verifies layer
  state per the cascade contract (tracked team layer, gitignored overlay) before
  honoring a value. Wave-1 exemplar of the rendered-views convention
  (`docs/conventions/rendered-views/` in the marketplace repository); a new eval
  exercises cascade resolution and provenance reporting.
- **The bundled chrome reference.** `reference/html-chrome.html` ships the corpus
  design-token system and the provisional accessibility floor, with WCAG-compliant
  link and focus tokens derived from the clay accent; the rich-page path now takes
  its chrome from that reference instead of inventing a look per page.

## [0.3.6]

### Changed

- **The form-selection sentence is the reference table it already was.** 73 words with seven clause
  interrupters and two slash chains that read as compound terms rather than as lists. Docs-hygiene
  sweep, L8-write-for-humans.
- **The generated options block sits under `## Configuration`.** It was under `## Possible future
  change`, a section about something the plugin deliberately does not do. The generated table itself
  is unchanged; only its placement moved. Docs-hygiene sweep, L8-write-for-humans.

## [0.3.5]

### Changed

- **Options-reference regeneration.** `scripts/sync-plugin-options-docs.py` dropped the
  phrase `in order to` from its shared options template, per the repo's own
  write-for-humans style rule that the phrase is just `to`. The generated options
  block in `README.md` regenerated with the shorter wording; no other change.

## [0.3.4]

### Changed

- **Instruction-surface de-slop (#2891, visualization cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.3.3]

### Changed

- Normalized fleet-wide framing this plugin restates (cross-vendor advisor
  fallback, untrusted-content posture, attribution/idiom prose — as touched) to the canonical
  SSOT wording, operable text kept inline with provenance-only citations (#2698).

## [0.3.2]

### Fixed

- **Docs:** the generated options block's headless route no longer implies `--config` applies
  only at install time, and now carries the CLI version its claim was verified against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)). The block also
  now separates the write from its effect: the value is stored immediately, but hooks are handed
  their `CLAUDE_PLUGIN_OPTION_*` at session start, so a check run in the same session still
  reports the old value and that is not a failed write. Two upstream links that pointed at empty
  backward-compatibility anchors on the settings page were repointed at the headings that hold
  the content. The hand-written Configuration section carried the same correction, so the
  headless route there is now a plain `claude plugin install … --config medium=<value>` rerun
  rather than an install-time-only note.

### Unchanged, deliberately

- **No `setup` skill.** One was written and then dropped: `medium` is **trivial** by
  [PLUGINPHILOSOPHY](../../docs/PLUGIN-PHILOSOPHY.md)'s own test — a self-contained scalar with
  a default preserving zero-config behavior, whose out-of-set values are documented as falling
  back to that default — and this plugin has no external prerequisite and no consumer-project
  configuration surface. None of the three criteria that require a `setup` skill holds, so
  shipping one would be the blanket ceremony that doctrine warns against
  ([#3111](https://github.com/melodic-software/claude-code-plugins/issues/3111)).

## [0.3.1]

### Changed

- **Explicit `disable-model-invocation` on `visualize` (#2968).** The skill now states the
  invocation mode the harness already applied for an absent key (`false`), so the choice is
  auditable and gated by `skill-quality:check` check 24. No behavior change. Rubric:
  `docs/conventions/invocation-mode/README.md`.

## [0.3.0]

### Added

- **`visualize`: a design-canvas form row.** A visual layout the user would rather tweak by
  hand (UI mockup, screen flow, poster, banner, one-pager) now routes to a design-canvas
  capability — the bundled `design` skill (the Claude Design canvas preview), when it appears
  in the session's skill list — offered as an explicit alternative, never a silent default.
  Fallbacks branch on two states: absent from the list → the rich rendered page, with no
  mention of `/design`; listed but invocation refused → suggest the user run `/design`. No new
  `medium` config value: the canvas rides the existing published-Artifact tier — and because that
  is its only surface, the offer is also skipped when an explicit `terminal`/`file` argument or
  the configured medium preference pins delivery on-machine (the rich page or local file carries
  the layout instead), so a "never publish" choice is honored. Surface facts,
  gating (server-side rollout flag, first-party-only, Artifact `capabilities` support,
  `disableBundledSkills`/`skillOverrides`, platform limits), and the four-part
  verified-on/recheck record live in `context/decision-matrix.md` per the catalog-spoke rule.

## [0.2.2]

### Changed

- **Docs:** actionable `/plugin configure` guidance now uses the marketplace-qualified form
  (`<plugin>@<marketplace>`; generated option blocks use `@<marketplace>`) per
  [`docs/extensibility-contract-smoke-tests.md`](../../docs/extensibility-contract-smoke-tests.md)
  Test E (#1360). Targetless references to the flow stay unqualified.

## [0.2.1]

### Changed

- **Catalog taxonomy.** Add `presentation` category for visualization plugin listing in generated
  catalog output.

## [0.2.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command — which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.1.2]

### Changed

- **Decision matrix covers connector-backed live data on published Artifacts.**
  The published-Artifact tier now notes that from Claude Code v2.1.209 a
  published page can call declared MCP connectors at view time — through
  claude.ai (the CSP still holds; the page itself makes no network call), via
  each viewer's own approved connector account, never shareable to a public
  link, and gated on Team/Enterprise by the org Owner "Enable artifact
  connectors" toggle. Previously the matrix presented published pages as
  build-time snapshots with no path to outside data.

## [0.1.1]

### Changed

- **Local HTML files get an explicit ephemeral-tier placement rule.** The
  local-file medium now writes via the platform temp primitive — a private run
  directory from `mktemp -d "${TMPDIR:-/tmp}/visualize-XXXXXX"` on
  Unix/Linux/Git Bash with the page inside it, a user-scoped temp under
  `%LOCALAPPDATA%\Temp` on Windows — never into the consumer's repository tree,
  one file per run, and the handed-back path is never deleted. Previously the
  skill named no placement at all.

  The temp root rides in the positional TEMPLATE rather than in a flag.
  `-p` (which GNU also spells `--tmpdir`) is documented in both dialects but does
  not mean the same thing: GNU treats the template as relative to that directory
  and lets the flag beat `TMPDIR`, while BSD/macOS consult it only as a fallback
  for `-t` when `TMPDIR` is unset — so with a bare template and no `-t` the flag
  does nothing there and the template resolves against the current directory,
  silently writing into the consumer's repo. GNU additionally marks `-t`
  deprecated. The `XXXXXX` is also **trailing**: BSD `mktemp` substitutes only
  trailing Xs, so `visualize-XXXXXX.html` cannot be created at all on macOS.
  Naming the page inside a generated directory is what preserves the `.html`
  extension without an unportable suffix on the template.

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
