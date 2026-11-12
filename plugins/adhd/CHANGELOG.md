# Changelog

All notable changes to the `adhd` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.10.15] - 2026-11-12

### Changed

- Pointer records no longer carry an as-of date or recheck trigger; stored values keep theirs.

## [0.10.14] - 2026-11-12

### Changed

- Synced the shared library copies this plugin carries; their pointer records no longer carry an as-of date or recheck trigger.

## [0.10.13] - 2026-11-11

### Changed

- The README options reference lists its upstream documentation as pointers only, with no as-of date or recheck trigger.

## [0.10.12] - 2026-11-11

### Changed

- Internal simplification, no behavior change.

## [0.10.11] - 2026-11-11

### Changed

- The shape skill's compaction gotcha points at Claude Code's skill content lifecycle section instead of describing what compaction keeps. No behavior change.

## [0.10.10] - 2026-11-09

### Changed

- Internal simplification of the shared view helpers this plugin carries, no behavior change.

- Simplified the shared yaml-subset parser copies; behavior is unchanged.

## [0.10.9] - 2026-11-09

### Changed

- Simplified the shared setup-apply.mjs, spawn_noise.py and state-key.sh library copies; behavior is unchanged.

## [0.10.8] - 2026-11-07

### Fixed

- `/adhd:clarify`'s medium resolver command takes `--option "<option>"` in place of the `${user_config.medium}` token, and the skill passes `""` when the `medium` option reads empty or unsubstituted, so a model no longer copies the token into the shell call ([#13955](https://github.com/melodic-software/claude-code-plugins/issues/13955)).

## [0.10.7] - 2026-11-07

### Changed

- The clarify and shape `evals.json` files are retired into the `evals/` case suite ([#8635](https://github.com/melodic-software/claude-code-plugins/issues/8635)). Fifteen new cases: `cl-previous-response-target` ('make this clear' restructures the previous message without asking, keeping Q ids, verbatim terms and the closing lens line), `cl-cold-start-asks-target` (with no earlier message it asks what to clarify and invents nothing), `cl-explain-simply-routes-explain` and `cl-eli5-picture-routes-illustrate` (a plain-words ask names `education:explain`, a picture or ELI5 ask names `education:illustrate`, and neither draws a diagram), `cl-explicit-earlier-target-glossary` (a named earlier memo wins over the previous message and gets a glossary of the session's coined terms), `cl-resolver-default-decision-table`, `cl-team-artifact-ignored` and `cl-retired-terminal-stays-local` (the shared medium resolver runs first, its report line and notices are printed as they stand, and no rendered-views file is read by hand), `sh-adhd-friendly-trigger` (a natural ADHD-friendly ask fires shape and leads with the action), `sh-bare-standing-ack` (a bare `/adhd:shape` says it holds for the rest of the session), `sh-force-push-confirms` (a terse force-push ask gets the risk and a confirmation first, in a flat tone), `sh-explain-runs-long` (a walk-through runs full length under headings), `sh-direct-answer-first` (the verdict is the first line), `sh-conflicting-shaper-asks` (an active caveman shaper is named and the user picks one) and `sh-off-switch-unshaped` (after 'stop shaping' the answer is plain prose). `cl-dense-identifiers` gains `lens-line-closes`, and `cl-trivial-escape-hatch` gains `no-glossary` and `no-left-out-note`. The `userConfig` medium case is held: a run cannot set the plugin's option. Both `evals.json` files are deleted.

## [0.10.6] - 2026-11-05

### Changed

- shape drops the first-line and last-line re-read from its pre-send check

  Rules 1, 3 and 5 already state what the first and last lines carry, and
  Opus 5 checks its own reply without being told to.

## [0.10.5] - 2026-11-04

### Changed

- Prose uses the vocabulary the planning chain settled on (scope, fallback chain, personal override, the Brief), and names the file or setting it means.

## [0.10.4] - 2026-11-04

### Changed

- Shared config-cascade library synced: the personal layer is now called the personal override in comments and in view-settings' warnings, and `overlayApplies` is `personalOverrideApplies` (#13187). Behavior is unchanged.

## [0.10.3] - 2026-11-04

### Fixed

- Shared `view-registry.mjs` synced where this plugin carries it: the architecture lane now declares that its plugin ships a `medium` option, which #13027 added; no other change to this plugin.

## [0.10.2] - 2026-11-04

### Changed

- `reference/html-chrome.html` is now generated from the marketplace's one canonical chrome, `lib/html-chrome.html`, and adds a system/light/dark theme toggle (system by default) and a comment box beside the tokens and the accessibility floor. Its token values are unchanged (#12654).

## [0.10.1] - 2026-11-04

### Changed

- **The shared view registry records whether each lane's plugin ships a `medium` option.** `lib/view-registry.mjs` gains `hasMediumOption` on every lane registration, and the retired `~/.claude/rendered-views.md` notice names the plugin's `medium` option only for a lane where it is set; this plugin's notices are unchanged.

## [0.10.0] - 2026-11-04

### Added

- A `medium` option (`auto` by default) sets where `/adhd:clarify` sends its decision table. Picking its value from a list in `/config` needs Claude Code v2.1.271 or later ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)).
- `prerequisites.json` declares `node`, which the medium resolver and the bundled prerequisites checker run on, so `/harness-ops:prerequisites` reports it when it is missing ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)).

### Changed

- Shared `view-settings.mjs` and `view-registry.mjs` synced where this plugin carries them: the planning lane's design kind and shipped `artifact` default, and the resolver output's `page` and `publishes` fields (#12650); no other change to this plugin.

- `/adhd:clarify` resolves its medium through the shared resolver (`lib/view-settings.mjs resolve --lane adhd:clarify`) and prints its report line, `view: <medium> (<what decided it>)`, plus one line per notice, instead of reading the settings files itself ([#12668](https://github.com/melodic-software/claude-code-plugins/issues/12668)). The scopes are now the `--medium` argument, the plugin's `medium` option, the team file `docs/conventions/rendered-views.yaml` and its untracked personal override `docs/conventions/rendered-views.local.yaml`. `~/.claude/rendered-views.md`, `.claude/rendered-views.md` and `.claude/rendered-views.local.md` are retired: each gives a notice naming where to set its value. A `terminal` or `file` value in one of them still keeps the view local while no scope sets a value; a publishing value in them is ignored. A team file's publishing value used to force a local file. The resolver now ignores that value with a notice, and the skill's content rule picks where the table goes.

## [0.9.3] - 2026-11-04

### Fixed

- Shared `view-settings.mjs` synced where this plugin carries it ([#12646](https://github.com/melodic-software/claude-code-plugins/issues/12646)): a `terminal` or `file` value in a retired `rendered-views.md` file keeps the view local when no scope sets one, instead of falling to a publishing default; no other change to this plugin.

## [0.9.2] - 2026-11-03

### Changed

- Shared medium resolver modules (`view-settings.mjs` and the modules it loads) synced into `lib/` ([#12667](https://github.com/melodic-software/claude-code-plugins/issues/12667)); no other change to this plugin.

## [0.9.1] - 2026-11-03

### Changed

- **README**: the always-on non-goal no longer restates which hook events inject context. It points at the `SessionStart` hooks section with an as-of date and a recheck trigger, and keeps the decision to build an opt-in hook only on demonstrated demand (#12693).

## [0.9.0] - 2026-11-02

### Added

- **`/adhd:clarify` styles its decision page from the shared chrome reference.** The plugin now ships `reference/html-chrome.html`, a byte-identical copy of the rendered-views chrome reference, and the artifact or local HTML file takes its palette, type stacks, radii and accessibility floor (link and focus contrast, color-scheme and reduced-motion behavior) from it instead of a look invented per page.

## [0.8.0] - 2026-10-31

### Added

- `time_units` setting (boolean, default off) that turns time units back on in `/adhd:shape` estimates: a `userConfig` option, and a key in `docs/conventions/adhd.yaml` that wins over it, validated by the new `schemas/adhd.schema.json`.
- The `sh-estimate-and-list-cap` eval grades a relative size and no time units, in place of a concrete time estimate.

### Changed

- `/adhd:shape` rule 6 sizes work as Small, Medium or Large, with what makes it that size, instead of estimating time. It states minutes, hours, days or weeks only when the new `time_units` option is on, and keeps a time budget the reader states in the reader's words.

## [0.7.0] - 2026-10-31

### Changed

- `/adhd:clarify` resolves the `rendered-views` `medium` before it picks a rung, from a
  `--medium` argument, then `~/.claude/rendered-views.md`, the team `.claude/rendered-views.md`
  and an untracked, gitignored `.claude/rendered-views.local.md`. `terminal` or `file` from any
  layer keeps the decision table local, even with the Artifact tool present. `artifact` (or
  `hosted`, read as `artifact`) publishes only from the argument, the user-global layer or that
  overlay; a team-layer publishing value keeps the page in a local file. With no layer set, the
  shipped ladder is unchanged, and the output names the layer that decided or "shipped default".

## [0.6.1] - 2026-10-30

### Changed

- Links and paths to marketplace plugin contracts now name `docs/contracts/<name>/`, where the contracts moved from `docs/conventions/<name>/`. The old paths keep a stub with every section heading.

## [0.6.0] - 2026-10-13

### Added

- Seven outcome eval cases for `clarify` and `shape` under `evals/`, and frozen trigger-probe sets under `probes/`.

### Changed

- `clarify`'s body and both skills' descriptions are shorter. Eval cases and trigger probes measured each change against the old text before it shipped. `shape` keeps its original body, because the shorter version confirmed less often before a destructive step on Opus.

## [0.5.7] - 2026-10-13

### Changed

- `/adhd:clarify` points at the live string-substitutions section instead of restating it, and reads the Artifact tool's requirements from its definition instead of listing them; the README points at where a saved option value can reach.

## [0.5.6] - 2026-10-03

### Changed

- `clarify` routes a picture request ("ELI5", "draw me this") to `education:illustrate`, which replaces `education:eli5`.

## [0.5.5] - 2026-10-02

### Fixed

- `plugin.json` no longer sets `$schema`. claude.ai's marketplace sync stripped it with a warning, and Claude Code ignores it at load time.
- The plugin description is 500 characters or fewer, the limit claude.ai's marketplace sync enforces.

## [0.5.4] - 2026-10-02

### Fixed

- `clarify` no longer lists a cream or off-white background among the styles to leave out, since
  the shared chrome's ivory background is the sanctioned default.

### Changed

- `clarify` names `discipline:wait-what` in its boundaries and says when to pick each.

## [0.5.3] - 2026-10-02

### Fixed

- The `clarify` `argument-hint` uses Claude Code's official bracket notation: it drops the prose
  after the grammar, which the skill body now carries.

## [0.5.2] - 2026-10-01

### Changed

- Dropped citations of the removed topic-docs convention and the `docs/specs` tree.

## [0.5.1] - 2026-09-28

### Changed

- **`clarify` carries the source recommendation's `Basis:` through.** The decision table gains a
  Basis column, copied verbatim, or "none stated" when the source gave none, per the
  [recommendation-basis convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/recommendation-basis/README.md).
- The skill states the label's three outcomes inline (an installed plugin cannot read the
  repository's `docs/`) and renders a withheld item as withheld, never with an invented
  recommendation.

## [0.5.0] - 2026-09-23

### Changed

- `clarify` names the styles a decision-table page leaves out (a hero banner, a cream or
  off-white background, italic accent words in headings, numbered "01 / 02 / 03" section labels,
  pill-shaped badges), plus any the reader names, and adds a disliked choice to that list before
  rendering again.
- `shape` takes the assistant's own next step in the same message as the state line when that
  step needs no input, and asks only when the step needs the reader or is destructive or hard to
  undo.

## [0.4.10]

### Changed

- **`clarify`: description prose no longer addresses the reader.** Anthropic's skill-authoring guidance keeps first and second person out of a description because it is injected into the system prompt; the rewritten clauses name the user, the session, or the repository instead. Quoted trigger phrases are unchanged.

## [0.4.9]

### Changed

- **Manifest description drops its em dashes.** Wording only; the plugin's behavior, options, and defaults are unchanged. The description renders into `docs/CATALOG.md`, which the repository's em-dash gate reads.
- **The plugin's prose drops its em dashes.** This changelog was rewritten. Wording only, with no change to any output-shape rule or fidelity constraint. The quoted retired and current wordings keep their quotes byte-identical, and no heading was touched. The released sections corrected in place are 0.4.1, 0.4.0, 0.3.2, 0.3.1, 0.3.0, 0.2.0, and 0.1.0: their wording changed, their facts did not.
- **The plugin's markdown is declared in `scripts/em-dash-purged-paths.txt`.** The gate now defends `CHANGELOG.md` alongside the README and SKILL bodies it already covered.

## [0.4.8]

### Changed

- **clarify:** the decision table's HTML media point at the rendered-views security baseline
  (`docs/conventions/rendered-views/README.md`, "Security baseline") and repeat its rules in
  place of the skill's own escaping wording: escape `&`, `<`, `>`, `"`, and `'` in text and
  attribute positions, no unescaped interpolation into `<script>` or `<style>`, no
  event-handler attributes from input, self-containment. Kept as skill-specific: escaping is
  what keeps the verbatim promise true in the rendered page, and terminal markdown wraps
  code-like terms in backticks (#3609).
- **clarify:** the repeated baseline passage carries a `contract-restatement` marker for the
  `rendered-views-security-baseline` clause, so `scripts/check-contract-clause-coverage.py`
  fails when the copy drifts from the convention's five escape characters, the
  `<script>`/`<style>` rule, the event-handler rule, or self-containment (#3609).

## [0.4.7]

### Changed

- **shape:** the Gotchas section keeps the compaction note and drops the dated audit header and the
  two bullets that restated the conflicting-shaper check and the rule 5 boundary test; rule 10
  states the no-preamble rule positively with one illustrative weak-versus-strong pair instead of
  an exhaustive banned-phrase list.
- **clarify:** the scratchpad rule states its reason without narrating upstream's decision.
- Applied from the 2026-09 prompt-audit against Claude Fable 5.1
  (docs/specs/prompt-audit-skills-2026-09.md).

## [0.4.6]

### Changed

- **`clarify`: each core-move step now states an observable done-condition.** The
  four-step restructure said what to do but not how to know a step was finished.
  The SKILL.md length warning (soft target 200) is unchanged and still a
  progressive-disclosure candidate, not a defect of this change.

## [0.4.5]

### Changed

- **`clarify`'s boundary splits three ways: structure, altitude, medium.** It previously named one
  neighbor for everything it is not, routing both "explain this simply" and "ELI5 this" to
  `education:explain`. Now a prose drop to plain words routes to `education:explain` and a picture
  explainer routes to `education:eli5`, while `clarify` keeps structure. The description, the
  Boundaries section, the altitude note, the not-a-simplifier line, and the README's routing
  passage all state the same three-way split, and the eval that mixed both triggers in one prompt
  is split so each case names one lane.

## [0.4.4]

### Changed

- **The working-memory rule states the positive (`shape`).** The bare prohibition ("Never ask the
  reader to 'keep in mind' something stated earlier") is replaced by the instruction it implies:
  restate any earlier state the reader needs, in the current response. Same constraint, now with a
  disposition attached. Docs-hygiene sweep, L5-noise.

## [0.4.3]

### Changed

- **Repo-wide `/ai-slop:audit fix` pass (#3359).** `shape/SKILL.md` now fences its
  weak-example line and forbidden-phrase lists with `ai-slop-ignore` markers: the
  chatbot-artifact phrases there are quoted as the tells the skill bans, not prose
  to rewrite.

## [0.4.2]

### Changed

- **Instruction-surface de-slop (#2891, adhd cluster).** Rewrote this plugin's `README.md` and every
  `SKILL.md` to drop em dashes under the repo's zero-tolerance house policy, using
  `/ai-slop:audit fix` semantics: periods or commas, or a restructured sentence, never
  parentheses, en dashes, or a spaced hyphen as a stand-in. Meaning stays; only the mark
  and the sentence break change. The generated options block is ignore-fenced because
  `scripts/sync-plugin-options-docs.py` still emits em dashes from its shared template.

## [0.4.1]

### Changed

- **`clarify`: the ELI5 hand-off names the Skill tool (#3002).** "hand off to `/education:explain`"
  became "hand off by invoking `/education:explain` via the Skill tool". Wording only. The
  routing condition, the presence gate, and the fallback are unchanged. The invocation-mode
  rubric's cross-skill phrasing rule is now unconditional; the fleet sweep retired the "new and
  edited text" scoping it used to carry.

## [0.4.0]

### Removed

- **The bare `/<skill>` alias for this plugin's skills.** Their `SKILL.md` files no longer
  declare a frontmatter `name`. The field is optional and defaults to the directory name, so
  declaring it only restated the path while registering a second, unnamespaced command, which
  the slash-command picker then echoed back as `/plugin:skill (skill)`. Invoke a skill by its
  namespaced command; the command itself is unchanged.

## [0.3.2]

### Changed

- **`clarify`: listing description tightened (1,058 → 766 chars).** Trimmed the explanatory
  prose from the frontmatter `description` toward the shared skill-listing budget
  (claude-code-plugins#2022, option 2). Every single-quoted trigger phrase is preserved verbatim
  (skill-quality check 3); the fidelity rules and structure-not-altitude contract are unchanged
  in the body.

## [0.3.1]

### Changed

- `clarify` places its local HTML file in the topic-docs **ephemeral tier**
  instead of preferring the session scratchpad. The old wording branched on
  whether the harness injected a scratchpad path. That branch made placement
  depend on how the session was launched, which is invisible from inside the
  skill, and it depended on an undocumented surface upstream has declined three
  times to support. The skill now resolves one temp path deterministically, and states
  explicitly that the file is not deleted before returning. The path is the
  delivery mechanism, so it must stay readable when the reader opens it. See
  `docs/conventions/topic-docs/README.md` §"The ephemeral tier".

## [0.3.0]

Fixes every finding from the 2026-07-23 live audit (handoff item
`20260723-082358-adhd-shape-clarify-audit`, #1130).

### Added

- **Conflicting-shaper check at the enforcing layer (H1, L4).** The
  caveman-style mutual-exclusion warning lived only in README/plugin.json,
  layers the model never reads at invocation time. The audit reproduced the
  failure live as a silent contradictory mix. Both SKILL.md bodies now surface
  an active terse-for-tokens shaper before applying, name the source found in
  session context, and ask the user to pick one. Advisory by necessity: no
  documented skill-to-hook detection mechanism exists.
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
  exempt from shape's five-item list cap (fidelity wins over shaping), stated
  in both skills. `clarify` on already-shape-formatted output is declared a
  no-op.
- **`clarify` fidelity rule 2 fallback (L5).** An original with no identifiers
  gets a declared synthesized locator (sequential marker or quoted opening
  phrase), never a chunk with no way back to its source passage.
- **README compaction caveat (L2).** The standing posture is content-based
  persistence; re-invoke after a context compaction if shaping stops.

Out of scope by design: description-length trimming (marketplace-level gate
decision, recorded in the audit's policy note).

## [0.2.0]

### Added

- **`/adhd:clarify`.** An on-demand, one-shot reshape of a dense, decision-heavy
  artifact already on screen (default target: the previous assistant response;
  an explicit target overrides). It restructures faithfully, chunking the content
  one-decision-at-a-time, defining the session's own jargon, and surfacing exactly
  what the reader must decide. Hard fidelity rules apply: operative terms of every
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

- **Initial release.** `/adhd:shape` shapes the assistant's output for a
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
- Reauthored, not forked, from
  [ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT): the ten
  rules' substance is preserved, the wrapper is adapted to this marketplace's
  discovery discipline (no auto-fire-on-any-message), and the prose is
  rewritten. Zero-config, zero-prerequisite; no `userConfig`, hooks, or setup
  skill.
