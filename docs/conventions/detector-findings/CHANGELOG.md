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
- Every rule another doc owns is **cited, never copied** — the findings-file schema and the
  cell-escaping and path-relativization rules to
  `plugins/review/skills/fanout/context/default-mode.md`; the severity-tier and confidence
  vocabularies (and the consumer-precedence rule that overrides the baseline) to
  `plugins/review/context/severity.md`; the merge-set, admission-test, and consumption-ledger
  mechanics to `context/fix-pass-mode.md`.
- **Destination stated** for a producer that cannot follow the review plugin's own
  `${CLAUDE_PLUGIN_ROOT}`-relative pointer chain: memory-tier resolution routed to the `topic-docs`
  convention, plus the three specifics that pointer does not carry — the
  `<memory_dir>/reviews/<branch-slug>/` sub-path, the lossy slug rule, and the self-ignore guard.
- Four producer-owned fields fixed: machine-computed `Tier` in the owner's vocabulary; `Confidence`
  `high`-or-omitted and **never `low`**, which ranks below absent; repo-relative `file:line`
  `Location`; producer-side cell escaping. `Confidence` is confidence-of-realness, never confidence
  in the fix.
- Coexistence obligations stated: write your own file rather than appending into another producer's,
  name yourself in `Surface(s)`, and do not pre-deduplicate against another producer's output.
- Re-emission rule stated: a detector re-runs and writes what it currently finds; it never replays.
- Minimal conformance defined by pointer to the admission test; omit an absent coverage field rather
  than fabricating it, and always emit `date:`.
- Liveness relationship recorded: persisting a conforming file satisfies the
  `liveness-assertion` agent-readable-channel limb.
- Enforceability classified; all mechanical enforcement deferred with event triggers (first detector
  on `main`; pilot completion or a second adopter). Adopters table ships **empty** — `review:fanout`
  is the reference writer, not an adopter, and sits on the other side of this doc's boundary.
- Convention registry row added in `PLUGIN-PHILOSOPHY.md`; `review:fanout`'s writer contract gains a
  pointer to this doc.
