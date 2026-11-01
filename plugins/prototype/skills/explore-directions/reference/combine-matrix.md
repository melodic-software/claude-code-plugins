# The combine matrix

The switcher answers "which direction"; the [control panel](../../../context/control-panel.md)
answers "which value"; the matrix answers "which parts". Run it when the user's reaction spans
variants ("Scene, but with the trim handles from Trim") and never make them describe that in prose.
A cross-variant merge described in a sentence loses exactly the details that mattered, and the
rebuild drifts from what they meant. The matrix makes every part a checkbox with its trade-off next
to it.

## When it runs

- `combine [<base>]`: explicit. With no base named, ask which variant is the base, as one
  question.
- The reply to the step 4 handover names parts of more than one variant (`direction: graft`, or
  `steal` lines from two or more variants). That is a combine, not a `vary`: run the matrix instead
  of asking for a description.
- **Not** when the user wants a different direction (`vary`) or a different value (`controls`).
  Only when they've picked a base and want pieces of the others on it. A graft reply that names no
  base: ask which variant is the base, as one question, before building the rows.

## Building the rows

Walk this in order:

1. **The base is fixed.** The variant they named keeps its axis, layout, and every behavior no row
   replaces.
2. **Diff every other variant against the base, one variant pair at a time.** A candidate is one
   thing the user can see or do (an element, a behavior, a state) that another variant has and the
   base lacks or does differently. Implementation differences are not rows.
3. **Keep only portable candidates.** Test: say the base plus this feature in one sentence. If the
   sentence changes the base's axis ("Cards, but with the Map layout"), it isn't portable,
   it's a different base. Drop it, and if the user asked for it, say the base pick was wrong and
   offer to combine the other way around.
4. **Merge dependents.** Two features that only make sense together are one row. A feature that
   needs another one ticked says so in its description: "requires trim handles".
5. **Cap at 8 rows.** Past that the matrix reads as a spec, not a decision, and the user ticks
   everything. Split into two rounds: combine the top 8 by how much they change the base, build,
   then combine again.

State what you dropped in step 3 in one line above the matrix, so the user knows the feature was
considered rather than forgotten.

## Row content

The matrix is a table keyed by variant pair: each row's key names the donor variant or variants
and the base, and the remaining three columns follow in this order:

| Column | What goes in it | Why |
| --- | --- | --- |
| **Pair** (the key) | `<donor> to <base>` for each non-base variant that has the feature: `Trim to Scene`, or `Filmstrip, Trim to Scene` | The user remembers "the one from Trim", not the feature's name; this column is their index |
| **Feature** | 2 to 5 word name, then one line of what the user sees, never how it's built | The name is what gets ticked; the line is what they're agreeing to |
| **`<Base>` today** | What the base does instead, in the same terms as the feature line | It turns the checkbox into a trade. Without it, every box gets ticked and the base's character disappears |
| **Choice** | Add · Add as a mode | Below |

Below the rows, one free-text line: "Anything else about how `<Base>` should work?" It catches the
feature you didn't list.

### The mode option

"Add" replaces the base's behavior. "Add as a mode" keeps both and gives the end user a control
to flip between them. A row gets the mode option only when you can name both modes in two words
each (`Scene | Take`, `Trim on | off`) and show those names in the cell. If the modes don't name
themselves, it isn't a mode, it's indecision, and offering the mode lets the user dodge the choice
the matrix exists to force.

Every mode is one the product's users have to learn. It is a product decision, not a merge
detail: the summary line under the matrix counts them separately ("2 added, 1 of them as a
mode"), and the record step records each one.

## Rendering

Render the matrix with the richest form tool the host has: a widget with real checkboxes and a
submit button where the host offers one, a multi-select question tool where it doesn't. In Claude
Code that tool is `AskUserQuestion`. If the tool caps options per question, split rows across
questions in matrix order and ask about modes as a second question over the rows they ticked.

Pointer: [AskUserQuestion tool behavior](https://code.claude.com/docs/en/tools-reference#askuserquestion-tool-behavior).
As of 2026-10-29. Recheck when that section renames the tool or changes how a question takes
several options.

The floor is a numbered markdown table in chat with a reply grammar under it: `1, 3m, 4`, row
numbers, `m` for mode. Never go below the floor. Asking "which ones do you want?" in prose puts
the user back where they started.

## After the choices

- **Build one merged variant**: the base plus every ticked row plus the free-text line. Nothing
  else gets in because it was easy to add while you were there; an unticked row is a decision.
- **Name it after the base with a plus** (`Scene+`) and add it to the existing switcher as a new
  variant. The originals stay. A combination that felt right in the matrix can lose on the page,
  and it can only lose against the pure directions it came from.
- **Modes are part of the design, not the harness.** They render inside the variant, in the
  product's materials, where the end user would see them. The control panel is for numbers, never
  for modes.
- **Re-test the base's worst content** against every ported feature. A feature built inside a
  variant that happened to sit on short data has never met the base's forty rows.

Present the result as one line per adopted feature: where it landed and what it cost the base, if
anything. Then stop: recording the answer, `combine`, or `vary` is theirs to call.

## The decision block

The record step writes the decision down first; it's the only artifact that survives. After a
single pick it names the direction, the values, and what was rejected and why:

```md
Dropdown entrance: decided from the dropdown mockup
- Direction: scale + fade, not slide
- scale from 0.96, opacity 0 to 1
- 180ms enter, 140ms exit, cubic-bezier(0.32, 0.72, 0, 1)
- Rejected: slide-down felt heavy at 200ms and jittery below it
```

After a combine, the record step adds a base line, one line per adopted feature with its source and
mode status, and one line per feature left behind with the reason, in the user's words when they
gave one:

```md
Scene: decided from the timeline mockup, combined from Trim and Filmstrip
- Base: Scene (whole-scene bar; shots as segments)
- Adopted from Trim: in/out trim handles, as a mode (Trim on | off)
- Adopted from Filmstrip + Trim: zoom to this take, as a mode (Scene | Take)
- Left behind: stop at end of take: running into the next shot is the point of Scene
- Left behind: scene bar at trimmed lengths: no one had trimmed anything yet
```

The left-behind lines are the ones that matter. Without them the same matrix gets rebuilt in three
weeks.
