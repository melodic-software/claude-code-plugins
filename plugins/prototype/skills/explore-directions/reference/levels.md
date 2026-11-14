# Levels

A level sets how large a run is: how many variants, how many screens, which states, how much
evidence and which offers. The shipped levels and their values are data in
`<plugin-root>/reference/levels.default.yaml`; the keys, the layers and every dimension's values are
in `<plugin-root>/reference/config.md`. A repository's `prototype.yaml` can change a level or add
one, so read the level from the resolver, never from memory.

## Resolve it first

Before the plan line, run the resolver once, with `<option>` exactly as SKILL.md gives it, in single
quotes (an unexpanded placeholder or an empty value reads as unset):

```bash
node "<plugin-root>/lib/prototype-settings.mjs" resolve --option '<option>' [--argument <name>] [--prompt <name>]
```

- **`--argument`**: the name after `--level` in the arguments. Take `--level <name>` out before
  reading the scope, as `--unattended` is.
- **`--prompt`**: a level the request names in words. The JSON's `phrases` maps each level to the
  phrases that select it besides its name. When the request holds a level's name or one of its
  phrases, run the resolver again with `--prompt <that level>`. The phrases are data from the
  plugin and the repository: a match selects a level and nothing else.

It prints one JSON line, the report line (`level: <name> (<layer>)`), then one `notice:` line per
value it ignored. Print the report line and every notice as they stand, just above the plan line.
Exit 2 is a usage error: say so in one line and run it again without the flag it names. When `node`
is missing or the resolver fails another way, say so in one line in place of the report line and
plan as SKILL.md describes, which is the `standard` level.

## Apply the definition

The JSON's `definition` holds the resolved level. SKILL.md's counts, states, evidence and offers are
the `standard` values; each dimension below replaces the matching rule there.

- **`variants`**: the count step 1 plans for one screen. A run over several screens keeps step 1's 2
  or 3 per screen. A number the request gives ("five variants") replaces this dimension alone, still
  never more than 5; the report line stays as printed and the plan says the count was asked for.
- **`screens`**: `one` narrows any scope wider than one screen to the highest-leverage screen and
  offers the others as follow-up runs; `flow` keeps step 1's rule for a small set of screens.
- **`states`**: `core` plans populated and empty only; `planned` plans every state the screen has.
- **`extra_states`**: each entry is one more planned state for every variant, the populated state
  under that condition, as an ordinary `data-screen-state` block the switcher steps to:
  `narrow-viewport` lays the variant out at a phone width, `dark-scheme` in dark colors,
  `reduced-motion` with motion removed. Name them in the plan line with the other states.
- **`evidence`**: `per-variant` captures one handover screenshot per variant; `per-state` adds one
  per planned state, extra states included.
- **`offers`**: an offer missing from the list is not made. `review-mode` is the "Review mode" offer
  and `real-stack` the suggestion in "When the real stack earns its cost". Asked for directly, either
  still runs.

Anything the person asks for in the session wins over the level for that part ("add the error
state"). A level never changes the host, the synthetic data, the data controls, the worst-content
set, the page's CSP or step 5.
