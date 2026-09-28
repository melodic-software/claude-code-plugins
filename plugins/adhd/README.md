# adhd

A Claude Code plugin that shapes and restructures the assistant's output for a
reader with ADHD, and anyone who wants action-first, low-friction, digestible
responses. Two skills, one concern: arrange output so an ADHD brain can act on
it. `shape` sets a standing house style; `clarify` rescues one specific artifact.

| Skill | What it does |
|---|---|
| `/adhd:shape` | Shape responses to lead with the next action, number multi-step work, restate state, cap and rank lists, estimate time concretely, make wins visible, and cut preamble, recap, and closers |
| `/adhd:clarify` | Faithfully restructure a dense, decision-heavy message already on screen. Chunk it one-decision-at-a-time, define the session's jargon, and surface what you must decide; renders an HTML decision table for big content |

## What it does

### `/adhd:shape`, set the house style

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

### `/adhd:clarify`, rescue one dense artifact

Where `shape` governs how the assistant writes going forward, `clarify` acts once
on something already on screen: a wall-of-text interview round, a jargon-thick
design memo, a recommendation you have to re-read three times. It restructures
that exact artifact. One decision per chunk, a glossary of the session's own
shorthand, and the actual choices pulled to the surface, **faithfully**. The
move is restructure, never simplify: precision and reading level stay fixed;
only the arrangement changes (lowering the altitude is `education:explain`'s job
and turning it into a visual explainer is `education:eli5`'s, both deliberately
disjoint concerns). Four hard fidelity rules keep a clarification of
a decision document from corrupting the decisions: operative terms quoted verbatim,
original item numbers kept as back-links, omissions named explicitly, and a
closing line that the clarification is a lens. Final answers are validated against the
original text. For big or decision-dense content it renders an HTML decision
table (item, recommendation, alternative, and what you're deciding, with rows
numbered so a terminal answer maps back), honoring the Artifact tool contract and
degrading to a local HTML file, then structured terminal markdown, where the
Artifact surface is unavailable. A leading `terminal`, `file`, or `artifact`
argument forces that rung, then the `medium` option, then
`.claude/rendered-views.md`, then this shipped default.

## Triggering: on-demand, session-standing once invoked

The skill is on-demand by design. It does **not** auto-fire on every message.
It surfaces when you ask for it in plain language ("ADHD-friendly",
"action-first", "give me the structured version", "cut the preamble") or when
you invoke `/adhd:shape` directly.

Once invoked, `shape`'s rules persist as a **standing instruction for the rest of
the session**. Invoke it once at the start of a session and every following
response is shaped, no need to repeat it. Invoke it whenever you want that
output shape; skip it when you don't. Turn it off mid-session with **"stop
shaping"** or **"normal output"**.

One durability caveat: the standing posture is content-based persistence, so
context compaction/summarization in a long session can erode it. If responses
stop being shaped after a compaction, re-invoke `/adhd:shape`.

`clarify` is on-demand too, but **one-shot, not session-standing**: it surfaces on
a plain-language cue ("make this clear", "clarify this", "help me digest this",
"break this down", "I can't parse this", "what am I actually deciding") or a direct `/adhd:clarify`,
acts on one artifact, and changes nothing about how later responses are written.
Its triggers are kept disjoint from `education:explain`'s comprehension cues ("I
don't get it", "explain simply") and from `education:eli5`'s picture cues ("ELI5",
"draw me this") so the auto-firing skills route on intent, restructure faithfully
vs drop the altitude vs change the medium, rather than colliding on their shared
"previous response" default target.

### Deferred: deterministic zero-invocation always-on

Arming the shaping at every session start with **no** invocation at all is a
deliberate non-goal for this version, recorded here so it is not re-litigated:

- **Why it is not a `userConfig` switch.** A `userConfig` boolean substitutes
  only into an already-invoked skill's *body*; it cannot flip frontmatter or
  cause a skill to auto-invoke. So no config toggle can, by itself, turn on
  always-on. A switch that cannot act would be a dead knob.
- **The only mechanism that delivers it is a hook.** Deterministic
  every-session arming needs a `SessionStart` (or `UserPromptSubmit`) hook that
  injects the rules as additional context. That is a code-execution trust
  surface, adopted only on demonstrated need, and the session-standing
  behavior above already covers the common case (invoke once, shaped for the
  rest of the session).
- **Trigger to build it.** Demonstrated demand for zero-invocation auto-arm.
  When that lands, the hook ships **off by default** (opt-in), so enabling the
  plugin never silently rewrites every response.

## Mutual exclusion with terse-for-tokens output shapers

Do **not** run this alongside a token-minimizing output shaper such as
[caveman](https://github.com/JuliusBrussee/caveman) at the same time. They pull
in opposite directions on the same axis, the shape of the assistant's output:

| | `adhd:shape` | caveman |
|---|---|---|
| Objective | Add structure and cues for reader accessibility | Strip words to save tokens |
| For | The human reading the output | The token budget |

Two output-shape disciplines active at once produce a contradictory,
unpredictable mix. Pick one for a given session. (There is no runtime coupling
between the plugins to enforce this. It is a usage guideline.)

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install adhd@melodic-software
```

## Configuration

None. The plugin is zero-config and zero-prerequisite. No `userConfig`, no
setup skill, no external tools. Enable it and invoke `/adhd:shape` or
`/adhd:clarify`.

## Attribution

`/adhd:shape` is reauthored, not forked, from
[ayghri/i-have-adhd](https://github.com/ayghri/i-have-adhd) (MIT): the ten
rules' substance is preserved, the wrapper is adapted to this marketplace's
discovery discipline (no auto-fire-on-any-message), and the prose is
rewritten. The underlying communication strategies adapt *The Adult ADHD Tool
Kit* by J. Russell Ramsay and Anthony L. Rostain from personal organization to
how an assistant shapes its output. `/adhd:clarify` is original to this plugin.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `medium` | string | `"auto"` | `CLAUDE_PLUGIN_OPTION_MEDIUM` | Preferred medium when clarify auto-selects. One of: auto (the shipped artifact-forward default), terminal (structured markdown), file (a local HTML file, never published), artifact (a published Artifact when that surface exists, otherwise a local HTML file, otherwise terminal). An unrecognized value is reported and treated as unset. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively.** Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure adhd@<marketplace>`.
2. **Headless.** Repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install adhd@<marketplace> -s <scope> --config medium=<value>
   ```

   The same command reconfigures a plugin that is **already installed**: it prints
   `already installed` and still writes the value. The short-circuit message is
   about the install, not the config write. Do **not** `claude plugin uninstall` to
   reconfigure: uninstalling drops this plugin's whole stored `pluginConfigs` entry,
   resetting every option in the table above to its default. `-s` defaults to `user`,
   so pass the scope `claude plugin list` reports for this plugin. The verified-version
   record lives in the [plugin-reconfiguration convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/plugin-reconfiguration/README.md).

   The value is stored immediately; the session you are in does not change. Hooks are
   handed their `CLAUDE_PLUGIN_OPTION_*` when the session starts, so start a fresh
   Claude Code session before expecting new behavior. A check run in the old session
   still reports the old value, and that is not a failed write.

3. **By hand, in settings.** Add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "adhd@<marketplace>": {
         "options": {
           "medium": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only, **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration): the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin install options](https://code.claude.com/docs/en/plugins-reference#plugin-install): the `--config` flag's reference entry
- [Plugins and skills settings](https://code.claude.com/docs/en/settings-reference#plugins-and-skills): `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Settings files and who they affect](https://code.claude.com/docs/en/settings#settings-files-and-who-they-affect): user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins): enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->

## License

MIT. Because this is a derivative reauthor, the plugin ships its own
[`LICENSE`](LICENSE) retaining the upstream copyright notice (Ayoub Ghriss)
alongside Melodic Software's, per the MIT requirement that the original
copyright and permission notice travel with substantial portions of the work.
