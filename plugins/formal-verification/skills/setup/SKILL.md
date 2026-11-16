---
description: "Set up the formal-verification toolchain: check reports the script runtime, Java, the TLC jar and the renderer; apply install-model-checker or install-renderer downloads the pinned file into the plugin data directory, kept only on a checksum match. Use when: 'set up formal verification', 'install TLC', or /formal-verification:chart reported blocked: toolchain missing. Never installs Java."
argument-hint: "[check|apply] [install-model-checker|install-renderer] [--unattended]"
user-invocable: true
disable-model-invocation: true
---

**Arguments.** `[check|apply] [install-model-checker|install-renderer] [--unattended]`.
e.g. /formal-verification:setup, /formal-verification:setup apply install-model-checker

## Purpose

The plugin's settings have two owners, and this skill writes neither:

| Setting | Owner |
|---|---|
| Paths to the model checker jar, Java and the script runtime | Plugin options, set through `/plugin configure`. For headless use, the routes and caveats are in `docs/contracts/plugin-reconfiguration/README.md` of this marketplace's repository. |
| Version pins and default bounds | The consumer's `docs/conventions/formal-verification.yaml`, keys per `${CLAUDE_PLUGIN_ROOT}/schemas/formal-verification.schema.json`; an absent key takes `${CLAUDE_PLUGIN_ROOT}/defaults.json`. |

What this skill may install, and who installs the rest:

| Tool | Who installs it |
|---|---|
| Node, Bun or Deno, and Java | The user. The install hints come from `check`. |
| The model checker jar | `apply install-model-checker`, typed by the user. |
| The renderer, needed only for an image of a chart | `apply install-renderer`, typed by the user. |

Typing an `apply install-*` subaction is the interactive yes: nothing installs without it. With
`--unattended`, or in a run with no person present (a loop lane, CI, a background session), install
nothing: run `check`, and when it fails, report `blocked: toolchain missing` with its FAIL rows and
stop.

## `check` (read-only, default)

`${CLAUDE_PLUGIN_ROOT}/scripts/toolchain.mjs` owns the toolchain probes and
`${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs` the declared prerequisites. Run both:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/toolchain.mjs" check --data-dir "${CLAUDE_PLUGIN_DATA}" --project-dir "$PWD" --jar '${user_config.model_checker_jar}' --java '${user_config.java}' --runtime '${user_config.script_runtime}'
node "${CLAUDE_PLUGIN_ROOT}/lib/prerequisites.mjs" check "${CLAUDE_PLUGIN_ROOT}" --data-dir "${CLAUDE_PLUGIN_DATA}"
```

Keep the quoted option tokens exactly as shown: the script treats an unset option as unset. Each
prints one row per tool and a summary, and exits 1 when a required tool is missing. Report the rows
as printed, each FAIL with its remedy. The declared `tla2tools` row cannot see the plugin data
directory or the jar option, so it warns even with the jar present: the first command's
`model-checker` row decides. Then print the resolved pins and bounds:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/settings.mjs" --project-dir "$PWD"
```

A line it prints on stderr names a convention key that failed the schema; its shipped value stands.
Report it.

## `apply install-model-checker`

Before downloading, tell the user the version (the `model_checker.version` setting), and the URL
and pinned SHA-256 that `${CLAUDE_PLUGIN_ROOT}/releases.json` gives for it, and the destination
folder. URLs and checksums come only from that shipped file: the script refuses a repository
convention file that sets one, and a version the file does not pin. Then:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/toolchain.mjs" install model-checker --data-dir "${CLAUDE_PLUGIN_DATA}" --project-dir "$PWD"
```

It prints the jar's path and exits 0, skipping a jar already present and matching. On a failed
download or a checksum mismatch it exits 1 with the reason and keeps no file. Report the path or the
error, then run `check` and report its rows as the observed state.

## `apply install-renderer`

The same, with the `renderer` keys and `install renderer`:

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/toolchain.mjs" install renderer --data-dir "${CLAUDE_PLUGIN_DATA}" --project-dir "$PWD"
```

The download must be https, under the script's size cap and timeout. The tarball is kept only when
its sha512 integrity string matches the pin in `releases.json`; it is unpacked into the
plugin data directory, and no package script runs.

Bare `apply` has nothing to configure: say so and name the two install subactions.

## Next

/formal-verification:chart <SPEC.tla>

## Gotchas

- A pin changed in the convention file installs into a new versioned name beside the old one; the
  old file stays until removed by hand. `check` names the one in use.
- A model checker jar named by the option is checked for presence only: its checksum is the user's
  choice, not a pin.
