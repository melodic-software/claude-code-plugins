# The candidate ladder

How `show-options` resolves *which skills exist* and *what they are for*. Two separate needs — a
complete name set, and per-skill enrichment — resolved by separate ladders, because the sources that
answer them well are not the same.

## Why the in-context listing cannot be the sole source

Officially documented behavior of the skill listing, and the reason this ladder exists at all:

- The listing **always carries every skill name**, but when many skills are installed Claude Code
  **shortens descriptions to fit a character budget**, and on overflow it **drops descriptions
  starting with the skills you invoke least**. The budget scales with the context window
  (`skillListingBudgetFraction`, default 1%); `skillListingMaxDescChars` caps each entry.
- A skill set to `disable-model-invocation: true` is **absent from the model's listing entirely** —
  not truncated, gone.

Both cut against this skill's purpose in the same direction. "Forgotten" correlates with
"rarely invoked", which is exactly what the drop-order sheds first; and a manual-only skill is
invisible no matter how relevant it is. A recommender sourced from the listing alone is blindest
precisely where the operator needs it most, and it cannot tell that it is blind.

## Ladder A — names (completeness)

| Rung | Source | Gate | Yields |
|---|---|---|---|
| 1 | `/claude-ops:inventory` | if that plugin is installed | Every **installed** skill across every marketplace, manual-only included — reconcile against the enabled set, below |
| 2 | An operator-supplied catalog file | if the consuming project provides one | Whatever the project chose to publish |
| 3 | The in-context listing | always available | Every *name*, minus manual-only skills |

**Rung 1 is a reuse, not a reimplementation.** `claude-ops:inventory` owns whole-fleet enumeration
and ships a bundled script for it. Do not walk `~/.claude/plugins/cache` directly: only the cache's
*existence* is documented, its `<marketplace>/<plugin>/<version>` nesting is not, and the version
directory changes on every update — the consuming marketplace's own `skill-quality:check` refuses
that move on exactly those grounds.

**Rung 1 supplies names only.** Verified against its output: entries are bare leaf names under a
plugin key, with a version and a manifest flag — no descriptions, no `metadata.*`. That is why
Ladder B exists rather than being folded into this one.

**Read its output from stdout; never pass `--out` into the consuming project.** Inventory's own
documented example writes `./claude-inventory.json` into the working directory. `show-options`
advertises the Spotlight ledger as its only write, so leaving an untracked artifact in a consumer's
repository just to render a menu would break that promise. If a temporary file is unavoidable in
some environment, it belongs in a temp path that is cleaned up, never in the project tree.

**Installed is not invocable — reconcile against the enabled set.** Inventory reports
`installed_plugins` and `enabled_plugins` as distinct keys, and its own contract asks callers to
"report the one the question is actually about, and say which you used". A plugin can sit in the
cache while `enabledPlugins` does not load it, so its skills cannot run. Following rule 1, a skill
from an installed-but-disabled plugin is **named with a `(plugin not enabled)` annotation**, never
silently listed as runnable and never silently dropped — the same annotate-don't-omit treatment a
`skillOverrides: "off"` skill gets. State which set the pool was built from.

**Rung 2's shape.** The consuming project publishes a catalog at a documented path it declares; a
marketplace that generates one already has the right artifact shape. In the source marketplace here,
`docs/SKILL-CHEAT-SHEET.md` is generated from skill frontmatter by `scripts/generate-cheatsheet.mjs`
and CI-enforced against drift — that is the shape to accept, since it already carries per-skill
stage grouping and a one-line summary. Do **not** hardcode that path: the file lives outside any
plugin directory, so a plugin copied into a cache cannot reach it, and a consuming repo will not
have it. Resolve whatever path the project declares; if none is declared, this rung is simply absent.

**Rung 3 obligates disclosure.** See "Disclosure" below.

## Ladder B — descriptions and stage metadata (enrichment)

| Rung | Source | Yields |
|---|---|---|
| 1 | Frontmatter read, where the SKILL.md files are reachable | Full untruncated `description` plus `metadata.workflow-stage` / `summary` |
| 2 | The in-context listing's surviving descriptions | Whatever escaped the budget |
| 3 | Nothing | Name only |

`metadata` is **never** in the listing — the docs are explicit that it is free-form data Claude Code
does not act on — so stage grouping always requires a file read or a supplied catalog. A session
running inside a marketplace repository can read `plugins/**/SKILL.md` directly; a session in an
unrelated consuming repo generally cannot.

## Absent enrichment means tier 2, never omission

This is the join between the two ladders and the reason a thin catalog does not break the no-omission
rule. Tier 1 rendering needs a description (it must say what the skill would add *here*, and when you
would skip it). Tier 2 needs only a name. So:

- Name present, enrichment present → eligible for tier 1.
- Name present, enrichment absent → tier 2, by name, counted.
- Name absent → the skill is not in the catalog, and inventing it is forbidden.

A skill never disappears for lack of a description. It just cannot be promoted.

## Bucket assignment without metadata

With `metadata.workflow-stage` available, it seeds the Now / Next split directly. Without it — a
third-party marketplace, or a listing-only pool — assign from the name and whatever description
survives, and **say that the assignment is heuristic**. A guessed bucket presented as a known one is
the same false-confidence failure as an undisclosed truncated pool.

## Disclosure

Whenever the pool came from Ladder A rung 3, or Ladder B could not enrich, the output states it —
briefly, once, near the top. For example:

```text
Pool: in-context listing only (claude-ops:inventory not installed) — manual-only skills are not
visible here, and descriptions for rarely-invoked skills may be missing.
```

This conforms to the consuming marketplace's `docs/conventions/liveness-assertion/`, the owner doc
for whether a status or advisory surface may report success while its findings are invisible: a
conforming surface **fails loud or routes its findings into a visible channel — never both green and
silent**. A menu that looks complete while silently missing a quarter of the catalog is that
violation exactly.
