# Machine-prose tell catalog

## Attribution and license

The tells below are distilled from
[Lorewiki: Signs of machine-written prose](https://example.invalid/lorewiki/Signs_of_machine-written_prose),
shared under an open content license that allows adaptation with credit. Rule ids, detection,
scope and the split between script and rubric are this catalog's own.

## Upstream-drift record

- **Pointer**: the page above, section by section.
- **As of**: 2026-09-14.
- **Recheck trigger**: the page adds, removes or renames a sign.

## Content

### rule-importance-puffing: Puffed-up claims of importance and legacy

- detection: script for the phrase core, judgment for the rest
- scope: any prose
- first release: script
- Puffs up importance with stock phrases: "a lasting monument to", "watershed moment", "cements its
  standing", "speaks to wider", "storied heritage", "signals a turn", "shifting terrain", "lasting
  imprint", "firmly anchored", "paving the way for". The phrase list is the script rule
  (`rule-importance-puffing`); puffing worded without stock phrases falls to the rubric.

### rule-stock-notability: Stock claims of notability and press coverage

- detection: judgment
- scope: wiki articles only
- first release: recorded only
- Repeated listing of outlet types and phrases like "covered by several outlets" to argue
  notability. This follows Lorewiki's own notability rules; outside the wiki the same move, naming
  outlets without quoting any of them, is the name-drop cue under `rule-vague-sourcing`.

### rule-shallow-analysis: Shallow analyses

- detection: judgment
- scope: any prose
- first release: rubric
- Trailing "-ing" clauses making vague significance claims ("...underlining its place in...",
  "...pointing to the weight of...") without support.
