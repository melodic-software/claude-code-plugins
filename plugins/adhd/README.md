# adhd

A Claude Code plugin that shapes the assistant's output for a reader with
ADHD — and anyone who wants action-first, low-friction responses. One skill,
one job: rearrange output so an ADHD brain can act on it.

| Skill | What it does |
|---|---|
| `/adhd:shape` | Shape responses to lead with the next action, number multi-step work, restate state, cap and rank lists, estimate time concretely, make wins visible, and cut preamble, recap, and closers |

## What it does

The skill re-anchors ten output rules grounded in five facts about how an ADHD
brain reads: working memory is small, knowing is not doing, starting is the
hardest step, time reads as uniform, and dopamine is scarce. It shapes output
to lead with a concrete next action, number multi-step work, restate state
across turns, cap and rank lists at five, give time estimates in real units,
make finished work visible, keep an error tone flat, and drop preamble, recap,
and closing pleasantries.

It knows when **not** to compress: an "explain / walk me through" request runs
full-length, a destructive action gets a confirmation first (safety over
brevity), a debug spiral pauses to name the wrong assumption, and a genuinely
ambiguous request earns one clarifying question.

## Triggering: on-demand, session-standing once invoked

The skill is on-demand by design — it does **not** auto-fire on every message.
It surfaces when you ask for it in plain language ("ADHD-friendly",
"action-first", "give me the structured version", "cut the preamble") or when
you invoke `/adhd:shape` directly.

Once invoked, its rules persist as a **standing instruction for the rest of the
session** — invoke it once at the start of a session and every following
response is shaped, no need to repeat it. Invoke it whenever you want that
output shape; skip it when you don't.

### Deferred: deterministic zero-invocation always-on

Arming the shaping at every session start with **no** invocation at all is a
deliberate non-goal for this version, recorded here so it is not re-litigated:

- **Why it is not a `userConfig` switch.** A `userConfig` boolean substitutes
  only into an already-invoked skill's *body*; it cannot flip frontmatter or
  cause a skill to auto-invoke. So no config toggle can, by itself, turn on
  always-on — a switch that cannot act would be a dead knob.
- **The only mechanism that delivers it is a hook.** Deterministic
  every-session arming needs a `SessionStart` (or `UserPromptSubmit`) hook that
  injects the rules as additional context. That is a code-execution trust
  surface, adopted only on demonstrated need — and the session-standing
  behavior above already covers the common case (invoke once, shaped for the
  rest of the session).
- **Trigger to build it.** Demonstrated demand for zero-invocation auto-arm.
  When that lands, the hook ships **off by default** (opt-in), so enabling the
  plugin never silently rewrites every response.

## Mutual exclusion with terse-for-tokens output shapers

Do **not** run this alongside a token-minimizing output shaper such as
[caveman](https://github.com/JuliusBrussee/caveman) at the same time. They pull
in opposite directions on the same axis — the shape of the assistant's output:

| | `adhd:shape` | caveman |
|---|---|---|
| Objective | Add structure and cues for reader accessibility | Strip words to save tokens |
| For | The human reading the output | The token budget |

Two output-shape disciplines active at once produce a contradictory,
unpredictable mix. Pick one for a given session. (There is no runtime coupling
between the plugins to enforce this — it is a usage guideline.)

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install adhd@melodic-software
```

## Configuration

None. The plugin is zero-config and zero-prerequisite — no `userConfig`, no
setup skill, no external tools. Enable it and invoke `/adhd:shape`.

## Attribution

Reauthored — not forked — from
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT): the ten
rules' substance is preserved, the wrapper is adapted to this marketplace's
discovery discipline (no auto-fire-on-any-message), and the prose is
rewritten. The underlying communication strategies adapt *The Adult ADHD Tool
Kit* by J. Russell Ramsay and Anthony L. Rostain from personal organization to
how an assistant shapes its output.

## License

MIT — see the marketplace root `LICENSE`.
