# Changelog for the native-references convention

Notable changes to the native-references contract. Per the README's Versioning section, changing a
required part of the description phrase, the canonical gate token, or an enforceability verdict is a
major change; additive guidance is minor; clarification is a patch. The doc shipped README-only and
unnumbered, which this file reads as **1.0**; the entry below is the first recorded change and lands
the changelog the README said would arrive with it.

## [3.3.1] - 2026-09-29

Patch: clarification.

- **The Adopters table records the description phrases baked in `/source-control:commit` and
  `/source-control:pull-request`** for the bundled `commit` and `pr` skills and `/commit-push-pr`.

## [3.3.0] - 2026-09-29

Minor: additive guidance.

- **`builtin-agent` and `builtin-tool` are provenance classes.** The inventory now extracts
  Claude Code's built-in subagent types and built-in tools, and the overlap store can record a row
  against either. Their runtime relationship is `route` only: the model reaches them through the
  Agent tool or by tool name, never the Skill tool, and no person types them as a command.

## [3.2.2] - 2026-09-29

Patch: clarification.

- **The Adopters table lists the Boundary sections from the 2026-09-29 triage of every remaining
  discovered candidate**: `/autofix-pr` in `babysit-prs`, `/commit-push-pr` in `commit`,
  `/permissions` in `audit-permission-grants`, and new rows for `/bug` in `bugs:write`,
  `/install-github-app` in `github:advise`, and `/memory` in `claude-memory:stateless`.

## [3.2.1] - 2026-09-29

Patch: clarification.

- **The Adopters table lists the Boundary sections recorded against Claude Code 2.1.284**, across
  source-control, claude-config, verification, implementation, debugging, discovery, claude-ops,
  context-budget, session-flow, planning, and prototype. A stray blank line that split the table in
  two is removed.

## [3.2.0] - 2026-09-29

Minor: additive guidance.

- **`bundled-workflow` is a provenance class.** Claude Code bundles workflows (`deep-research`)
  beside its skills, and the overlap store can now record a row against one. Its runtime
  relationship is `route` or `suggest`, never `wrap`, because the Native step invokes through the
  Skill tool and a workflow is not a skill.

## [3.1.0] - 2026-09-29

Minor: additive guidance in the Runtime relationship section.

- **A model-disabled `suggest` row carries no description phrase.** The model never lists a
  `bundled-skill` carrying `model-invocation-disabled`, so a phrase in the component's description
  is dead text; the body's suggest sentence is the only baked line. The overlap self-check fails a
  row that sets `baked.description_phrase` on that combination
  ([#5303](https://github.com/melodic-software/claude-code-plugins/issues/5303)).

## [3.0.0] - 2026-09-28

Major: the canonical route-gate token changes, which the Versioning section names as a major change.
The suggest token from 2.0.0 is unchanged.

- **The route gate token is `resolves in this session`.** It was `resolves in your session`, which
  addressed the reader in a description that is injected into the system prompt. Anthropic's
  [skill-authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices#writing-effective-descriptions)
  say to always write a description in the third person (verified 2026-09-28). The old spelling is
  no longer an accepted variant; `claude-ops:audit-native-overlap` keys its parity checks on the new
  one ([#4112](https://github.com/melodic-software/claude-code-plugins/issues/4112)). The suggest
  sentence keeps `is available in your session (`, the person-facing token 2.0.0 added.

## [2.0.0] - 2026-09-28

Major. Two triggers from this convention's Versioning section fire together: an enforceability
verdict changes, and the canonical-token clause gains a second token. The one-owner amendment in
the Boundary section contributes. The 1.1.0 Boundary rule is unchanged.

- **The gate-token check is built.** The enforceability row that said "candidate check named, not
  built" now records the overlap self-check's presence-condition advisory as built. That verdict
  change is a major bump on its own.
- **A second token, `is available in your session (`.** `route` keeps `resolves in your session`,
  which the model observes in its listing. `suggest` uses the new token, which the person checks.
  Parity keys on the sentence shape `If /<name> is available in your session (`, never the bare
  phrase.
- **`wrap` is a body section, `## Native step: <name> (<class>)`.** It carries the gate token, the
  identity check, the mutation clause, the skip-and-report states including "mutation detected
  after a scoped invocation" and "resolved but degraded", and the caller's `unattended` argument.
- **Class table.** `builtin-command` takes `route` or `suggest`. `bundled-skill`,
  `plugin-backed-builtin`, and `marketplace-plugin` take `route` or `wrap`; the
  `marketplace-plugin` wrap grammar stays seam-phrasing's. A bundled skill marked
  `model-invocation-disabled` takes `suggest` only. `session-skill` takes `route`. A `defer`
  verdict takes `route` and overrides the class.
- **One owning description phrase per plugin per surface.** A sibling skill may carry a Native
  step or a suggest sentence with a same-plugin pointer. It may not carry a second phrase.

## [1.1.0] - 2026-09-11

Additive: no required part of the description phrase moves and the canonical gate token is
unchanged. One enforceability row is added, and the meaning of a store row with no baked line is
split by surface.

- **The Boundary section lands with the store row.** A non-`defer`, extraction-evidence row is
  written together with its `## Boundary` section in the component body, in the same change. The
  section is invocation-loaded, so it spends no listing budget and moves no routing; nothing the
  description-phrase gate protects against applies to it. Routing and mutation gate go in the body;
  the four-part records go in a reference file inside the same skill, linked from the section.
- **"Pending-sweep" is now phrase-only.** A row without a description phrase remains legal pending
  state. A row without its Boundary section is a problem the overlap self-check fails on (exit 1),
  so no row can be added silently unbaked. The new enforceability row is Deterministic and
  blocking: the tiers doc gives that tier no advisory grade, and the consumer gate's exit-3 pass
  is reserved for conditions this repository cannot fix by editing its own files.
- **The section must name the row's surface.** `baked.boundary_section` plus a bare `## Boundary`
  heading is not parity: a component may carry a section written for a surface with no row, and a
  component that overlaps several surfaces carries one section owing each of them a mention. The
  heading naming the surface is the preferred shape; a generic heading passes when the section
  text names the surface. Either way the name appears as a code span, so a native name that is
  also an ordinary English word is not satisfied by prose that happens to use the word.
- **Boundary-only baking may batch across plugins.** The one-plugin-per-unit sweep rule keeps its
  reason (routing and budget) and therefore keeps its scope: description phrases.
- Adopters table gains `/claude-config:audit-instructions`, `/evals:methodology`, and
  `/playbooks:fable-5`, each carrying a Boundary section for the bundled `claude-api` skill.

## [1.0.1] - 2026-08-28

Clarification patch: no required part of the description phrase moves, the canonical gate token is
unchanged, and no enforceability verdict changes. Three citations of another plugin's skill
internals become public invocations.

- **The Boundary section's worked model and both Adopters rows cited paths.** "The Boundary section"
  modeled its pattern on `(plugins/review/skills/quality-gate/context/pr.md,
  plugins/review/skills/fanout/SKILL.md)`, and the Adopters table keyed its Surface column on
  `plugins/claude-ops/skills/audit-install-state/SKILL.md` and on the same two `review` paths. Every
  one of them reaches across a plugin boundary into a skill's private tree, and one reaches a
  `context/` file, which is private under any reading.
  [ADR 0018](../../adr/0018-treat-the-plugin-as-the-encapsulation-boundary-for-skill-citation.md)
  makes the plugin the encapsulation boundary for citation: plugins install independently, so a
  cited path can be genuinely absent, and `docs/**` names skills by slash invocation. The three
  sites now read `/review:quality-gate`, `/review:fanout`, and `/claude-ops:audit-install-state`.
  The Boundary section still shows its pattern in the fenced block immediately below, so nothing a
  reader needed from those files left the page.
- **Two of the three were standing findings.** They are `V-review-13` and `V-review-14` in
  [`docs-hygiene-sweep-unapplied-remediations.md`](../../specs/docs-hygiene-sweep-unapplied-remediations.md)'s
  L4 group of 34, recorded open on 2026-08-26 and unapplied since. That roster is a point-in-time
  record and is not edited here, per its own decay rule, and re-deriving it against its own text
  test shows most of it is already closed: these two were the last open rows of its 24-row Group 1,
  twelve of the rest having been closed by #3380 itself, and its eight Group 2 rows remain. Found by
  the whole-repo
  extract-ssot sweep's encapsulation floor, which re-derived the shape rather than trusting the
  roster and reached the third site the roster did not carry.
