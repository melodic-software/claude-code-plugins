# Native-references convention — changelog

Notable changes to the native-references contract. Per the README's Versioning section, changing a
required part of the description phrase, the canonical gate token, or an enforceability verdict is a
major change; additive guidance is minor; clarification is a patch. The doc shipped README-only and
unnumbered, which this file reads as **1.0**; the entry below is the first recorded change and lands
the changelog the README said would arrive with it.

## 1.0.1 — 2026-08-28

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
