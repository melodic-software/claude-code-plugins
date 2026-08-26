# L6-compress — `G-code-design`

1 COMPRESS file, finding C2. This is the only proposed cut in the whole sweep that is a plain
markdown edit rather than a generator edit.

## Cut

### `plugins/overengineering/skills/delta/context/recurring-wiring.md:83`

Flavor class: hedging intensifier, `flavor-vs-content-matrix.md` "Flavor (safe to cut)", the
`Hedging (perhaps/somewhat/might)` entry. `quite` is on `audit-scan.sh`'s curated flavor list.
The same shape is `plugins/ai-slop/skills/audit/reference/catalog.md:857` `rule-stacked-hedging`,
"Two hedges propping each other up".

`quite` intensifies `possibly` and adds no calibration the sentence does not already carry: the
clause is already conditional on a future audit's judgment, stated in the same sentence
("will later walk, judge on carry cost"). Dropping it changes no threshold, no directive, and no
scope qualifier.

Before:

```text
own audit will later walk, judge on carry cost, and quite possibly recommend retiring. Wire it
```

After:

```text
own audit will later walk, judge on carry cost, and possibly recommend retiring. Wire it
```

The line is 94 characters before the cut and 88 after. Both sit under this repo's markdownlint
line-length ceiling, so no reflow is needed and none should be applied: the semantic-diff gate then
sees one word removed and nothing else.

## Not proposed in this group

`plugins/architecture/skills/improve/actions/deepening.md:56` carries "benefits in terms of
**leverage** and **locality**". Held as SKIP: "in terms of" here means "measured by" and names the
two axes the card scores on. Removing it would need a rewrite, not a word drop, which puts it
outside this lane's word-level latitude and inside `write-for-humans`.

`plugins/event-storming/skills/methodology/reference/big-picture-workshop.md:224` carries "expensive
in terms of time, energy, coordination". Same call: the shorter form needs the list re-punctuated,
which is a rewrite. Lines 388, `design-level.md:175`, and `glossary-and-tools.md:5` in the same
plugin carry `in order to` inside verbatim Brandolini quotations, one of them already marked
`<!-- ai-slop-ignore: likely verbatim source phrasing (Brandolini) -->`. Not candidates.
