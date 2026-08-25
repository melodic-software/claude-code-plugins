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
  "disabled_rules": ["rule-emoji-formatting"],
  "thresholds": { "ai_vocabulary": 3.0, "copulative_avoidance": 4.0 }
}
```

`rule_allowed_paths` exempts ONE rule on the named globs and counts the file as declined for
that rule — the proportionate closure when a whole document legitimately trips a single rule
(a density verdict especially, which no line marker can quiet). `em_dash_allowed_paths` is the
older spelling of the same thing for `rule-em-dash` and stays supported.

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
