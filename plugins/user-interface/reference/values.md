# Values

How every user-interface skill picks a measurement and writes a key's value. Keys and allowed values
are in [`team.schema.json`](team.schema.json); shipped defaults are in
[`defaults.yaml`](defaults.yaml); the resolved values reach a skill as `config.values` from
`scripts/detect.mjs --config`, with each value's layer in `config.provenance`.

## Which value wins

For each measurement, take the first that applies:

1. **A matching project token.** The project's own token for that role (a `--press-scale` custom
   property, a `space-control` theme entry) wins over every config layer.
2. **A key set by the team or a person.** `config.provenance` names `userConfig`, `team` or `local`
   for the key.
3. **`css.token_fallback`, when the project has tokens of that kind but none matches.** "Of that
   kind" means tokens for the same quantity as the key: spacing tokens for a spacing key, duration
   tokens for a duration key, easing tokens for a curve. `ask` asks before writing a value and may
   propose the key's value in the question; `propose-token` adds a token holding the key's value,
   marked as a proposal; `literal` writes the key's value and names the key.
4. **The key's value**, only when the project has no tokens of that kind. Name each value used this
   way as a default the user can replace, with its key.

The key's value in steps 3 and 4 is its resolved value: the plugin default unless a layer set it.

A project value below a floor stands: use it and report it with the floor and its source. A team
value outside a key's schema bounds is refused by the resolver instead.

**Dropped settings.** Read `config.layers[].errors` and `error_keys`. Name every dropped key in the
answer, with its layer and the value used instead, so a team's typo is never silent.

**No resolver.** When `detect.mjs` cannot run (no shell, no `node`), read
[`defaults.yaml`](defaults.yaml) for the key's value, say that team and personal files were not
read, and continue. The glossary's common-usage numbers stay examples, never a key's value.

## Placeholders

A code block in a reference writes a configurable value as a placeholder naming its key; prose names
the key in backticks.

- **Form:** `{{animation.scale.press}}`, no spaces inside the braces, first segment a top-level key
  of the schema. Never with a `$` in front.
- **List part:** zero-based, `{{spacing.control_padding[0]}}`. A key's schema description states
  what each position holds. A placeholder naming a whole list expands to its items joined by `,`
  with no space.
- **Unit:** follows the braces, `{{animation.duration_ms.press}}ms`. A sample that takes seconds
  writes the arithmetic, `{{animation.duration_ms.medium}} / 1000`, and the written file holds the
  result.
- **Fill it.** Replace the whole token with the value that won above. A written file, or CSS in an
  answer, never holds `{{`.

Each mention is written in one of these forms:

| Form | Written as |
|---|---|
| direct | `{{animation.scale.press}}` |
| negated | a minus sign before the placeholder: `-{{spacing.control_padding[0]}}` |
| complement | rewritten so the placeholder holds the key's own quantity (the share of black in a mix, not the share left over), never `100% - x` |
| scaled by a key | a stated expression: `{{animation.duration_ms.small}} * {{animation.duration_ms.exit_factor}}` |
| derived, no stated formula | stays an example number, as the damping column in `animation/gestures.md` does |

## Key names

- Lowercase `snake_case` segments, grouped by namespace (`animation.`, `spacing.`).
- A unit the team may not change is in the name (`_ms`, `_px`, `_percent`) and the value is a
  number; a size whose unit the team may choose is a CSS length string with no unit in the name.
- A scale with named steps is one key per step (`animation.duration_ms.small`); a ladder with no step
  names is one list.
- A value bounded by a floor is its own numeric key, so the schema can hold the floor as its minimum.

## Setting a key

A team or personal file nests keys in block YAML, one level per segment. Never write a dotted key
such as `animation.scale.press:` on one line; the resolver reads it as an unknown top-level key and
drops it.

```yaml
animation:
  scale:
    press: 0.96
spacing:
  control_padding:
    - 0.5rem
    - 1rem
```
