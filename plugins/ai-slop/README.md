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
   citation artifacts, and more.
2. A judgment rubric applied by the skill for tells no script can rule on: significance inflation,
   promotional tone, vague attribution, elegant variation.

The rule inventory is distilled from Wikipedia's
["Signs of AI writing"](https://en.wikipedia.org/wiki/Wikipedia:Signs_of_AI_writing) into
[`skills/audit/reference/catalog.md`](skills/audit/reference/catalog.md), revision-pinned and
tracked under the upstream-drift convention.

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
  "vocab_add": ["utilize"],
  "vocab_remove": ["landscape"],
  "disabled_rules": ["rule-rule-of-three"],
  "thresholds": { "ai_vocabulary": 3.0, "copulative_avoidance": 4.0, "rule_of_three": 3.0 }
}
```

In-file opt-outs: `<!-- ai-slop-ignore -->` on a line exempts that line;
`<!-- ai-slop-ignore-start -->` and `<!-- ai-slop-ignore-end -->` fence a block;
`<!-- ai-slop-ignore-file -->` (with an optional `: reason`) exempts the whole file.
Exempted candidates are counted as declined, never silently dropped.
