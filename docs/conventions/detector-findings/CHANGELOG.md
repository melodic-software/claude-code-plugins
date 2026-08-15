# Changelog — detector-findings convention

Notable changes to the detector-findings contract (SemVer). Changing a producer-owned field's rule,
the coexistence obligations, or an enforceability verdict is a major bump; additive guidance or a new
adopter row is a minor bump; docs-only clarification is a patch.

## 1.0.0 — 2026-08-15

Initial published contract — a deliberate stub, per
[#2679](https://github.com/melodic-software/claude-code-plugins/issues/2679). It lands before the
first detector pilot because `PLUGIN-PHILOSOPHY.md`'s registry rule sets a deadline ("before a second
plugin adopts it"), and the pilot is that second adopter. Depth trails the pilot, which is what
produces the evidence to harden against.

- Contract stated as **format-only**: a producer reaches the apply relay by writing a conforming
  file into the current branch's findings directory, with no fanout edit, registration, or dispatch
  wiring. Nothing authenticates the writer.
- The findings-file schema is **cited, never copied** — owned by
  `plugins/review/skills/fanout/context/default-mode.md` "Findings-file shape".
- Four producer-owned fields fixed: machine-computed `Tier`; `Confidence` `high`-or-omitted and
  **never `low`**, which ranks below absent; repo-relative `file:line` `Location`; producer-side cell
  escaping.
- Coexistence obligations stated: write your own file rather than appending into another producer's,
  and name yourself in `Surface(s)` so a presence-only collapse stays legible.
- Consumption semantics stated for producers: per file, marked by the consumer's record, and a
  detector re-runs rather than replaying.
- Minimal conformance defined — `type:`, `branch:`, and a parseable `## Findings` table are the
  admission test; omit an absent coverage field rather than fabricating it.
- Liveness relationship recorded: persisting a conforming file satisfies the
  `liveness-assertion` agent-readable-channel limb.
- Enforceability classified; all mechanical enforcement deferred with event triggers (first detector
  on `main`; pilot completion or a second adopter).
- Convention registry row added in `PLUGIN-PHILOSOPHY.md`; `review:fanout`'s writer contract gains a
  pointer to this doc.
