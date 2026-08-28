# ai-slop

Detects and removes AI-writing tells ("slop") in checked-in markdown prose.

## Skills

- `/ai-slop:audit [target]` reports AI-writing tells in the target (default: the whole repo's
  tracked markdown). Read-only. `fix` as an explicit argument applies rewrites behind a
  semantic-diff guard.
- `/ai-slop:setup` configures the consumer repo: exemption paths, word-list tuning, thresholds.

## How it detects

Two layers:

1. A deterministic detector (`skills/audit/scripts/detect.sh`) for mechanical tells: em dashes
   (zero-tolerance by default), emoji formatting, AI vocabulary density, negative parallelisms,
   chatbot phrases, filler phrases, stacked hedging, citation artifacts, and more.
2. A judgment rubric applied by the skill for tells no script can rule on: superficial analysis,
   promotional tone, vague attribution, elegant variation, false ranges, colon crutches,
   abstract metaphor jargon, mechanism-free claims. (Significance inflation ships as a *script*
   rule, not a rubric tell — its stock-phrase core is mechanical.)

The rule inventory in [`skills/audit/reference/catalog.md`](skills/audit/reference/catalog.md) is
distilled from Wikipedia's
["Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing)
(revision-pinned, tracked under the upstream-drift convention), plus a set of additions inspired by
[Cursor's `unslop` skill](https://github.com/cursor/plugins/blob/main/pstack/skills/unslop/SKILL.md)
and deduplicated against it in the catalog's overlap map. What that port took, deduplicated, and
rejected is recorded in the marketplace's upstream ledger,
[`docs/upstream/cursor-pstack.md`](../../docs/upstream/cursor-pstack.md) (the `unslop` row), which
is also where the next drift recheck against upstream is decided. Fix-time rewrite guidance (plain
speech, substitution guardrails, adding voice) lives in
[`skills/audit/reference/rewrite-guide.md`](skills/audit/reference/rewrite-guide.md), which the
`fix` action applies.

Detector output names every exempted file (`Declined:` rows with a cause: excluded glob or
file marker) alongside per-rule declined counts, so an exemption is always visible, never
silent. Script findings persist to the review findings relay via
`skills/audit/scripts/emit-findings.sh`, which composes the findings file deterministically
from detector output; the skill resolves the destination and the producer-contract gate first
(see [`skills/audit/context/persist-findings.md`](skills/audit/context/persist-findings.md)).

## Configuration

`.claude/ai-slop.json`, resolved per the config-cascade convention (user-global, team, local
overlay; later layers refine earlier ones per key):

```json
{
  "excluded_paths": ["docs/legacy/**"],
  "em_dash_allowed_paths": ["docs/style-guide.md"],
  "rule_allowed_paths": { "rule-ai-vocabulary": ["docs/marketing/**"] },
  "vocab_add": ["utilize"],
  "vocab_remove": ["landscape"],
  "phrase_add": ["chef.s kiss architecture"],
  "phrase_remove": ["(the|my) honest take"],
  "disabled_rules": ["rule-emoji-formatting"],
  "thresholds": { "ai_vocabulary": 3.0, "copulative_avoidance": 4.0 }
}
```

`phrase_add`/`phrase_remove` tune the model-era phrase roster (`rule-model-era-phrases`, the
catalog's "Model-era additions" section). Fragments are whole EREs — spaces allowed,
apostrophes spelled `.` (the detector's phrase convention), metacharacters live — and each key
replaces wholesale per config layer, like `vocab_add`. A fragment that is not a valid ERE, or
an empty one, is skipped with a stderr note rather than allowed to flood the rule or silently
disable it; removing every shipped phrase leaves the rule inert. `phrase_remove` matches the
shipped fragments verbatim (the shipped roster is listed by `--show-config`). Replacement is
keyed on the key being present: an explicit `"phrase_add": []` in a later layer clears an
inherited list, and a config layer that fails to parse whole (for example one caught
mid-write) is refused rather than partially applied.

`rule_allowed_paths` exempts ONE rule on the named globs and counts the file as declined for
that rule — the proportionate closure when a whole document legitimately trips a single rule
(a density verdict especially, which no line marker can quiet). `em_dash_allowed_paths` is the
older spelling of the same thing for `rule-em-dash` and stays supported.

Every path-list key takes shell case-match globs, matched against the absolute path and the
repo-relative path: `*` and `**` both cross `/` (there is no gitignore-style single-level
`*`), so `docs/*.md` also matches `docs/guides/deep.md`. Spell the glob for the subtree you
mean, not the directory level.

In-file opt-outs: `<!-- ai-slop-ignore -->` on a line exempts that line;
`<!-- ai-slop-ignore-start -->` and `<!-- ai-slop-ignore-end -->` fence a block;
`<!-- ai-slop-ignore-file -->` exempts the whole file. Every form takes an
optional `: reason` (`<!-- ai-slop-ignore: quotes the tell it documents -->`),
which the fix flow's suppression outcome expects; a reason may not contain `>`.
Exempted candidates are counted as declined, never silently dropped.

Markers are the LAST resort, not the first: the detector's quotation exemption already keeps
wording rules out of blockquotes, double-quoted spans, and inline code spans, so quoted source
text and mentions of a tell need no marker — writing about the phrase `in order to` in
backticks or quotes never fires the filler rule. Typography rules (em dash, curly artifacts,
emoji formatting, citation tokens, tracking parameters) still scan quoted material, because
byte residue is a defect wherever it sits.

## Updating the model-era inventory

The catalog's "Model-era additions (repo-owned)" section is the evolving layer: when a new
model generation introduces a tic, it is added there first. The workflow, in order:

1. **Catalog entry first.** Add the tell to the section with its era, model attribution, and
   an honest evidence grade: `locally-observed` (you saw it; nobody has documented it),
   `community-attested` (independent sources document it), or `measured` (a frequency
   measurement backs it). The grade gates placement — a `locally-observed` phrase is
   `recorded-only` or a rubric cue, never a shipped script rule (the test suite asserts this).
2. **Detector second, measurement first.** A `community-attested`+ phrase joins the shipped
   `MODEL_PHRASES` roster in `detect.sh` only in an ANCHORED form measured at (or near) zero
   hits on a real technical corpus; a vocabulary word joins the density list only through the
   measured-narrowing gate (density gate quiet on legitimate files, firing on files with genuine
   residue). Until then the closure for a repo that wants it is `phrase_add`/`vocab_add`.
3. **Record third.** Date the addition in the section's model-era record with its sources, and
   bump the plugin release per changelog parity. The record's recheck triggers (each release,
   each new frontier model, a second frequency pool) are when entries are promoted, demoted to
   Historical indicators, or handed to the upstream inventory if Wikipedia absorbs them.

Vocabulary candidates that have NOT passed the gate (single-pool measurements: `gating`,
`dedup`, `decisive`, `verdict`, `scaffolds`, `settles`, `handoff`, `genuinely`, `errored`,
`drift`, `silently`, `verbatim`, `canonical`) stay `recorded-only` in the catalog; a repo
whose corpus tolerates one adds it via `vocab_add` — measured here, even the distinctive core
fired mostly on domain-literal prose. `pre-existing` is the one word that passed (the density
gate stayed quiet on all 61 files containing it) and ships in the default list.

The metaphor word-cues this layer added to the judgment rubric ("load-bearing", "seam") have
no config lever — the rubric reads no config, and its findings reach the human report only.
The catalog entry's literal-sense boundary is the suppression surface; saturation-level house
usage of either word is a fix-pass decision for that repo, not a per-audit re-report.
