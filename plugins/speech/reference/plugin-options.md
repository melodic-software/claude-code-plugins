# Plugin options: where to read the live specifics

The skills hand each plugin option to its script as a single-quoted `${user_config.<key>}`
argument, and the scripts own what an unset option means. A value that is empty, blank, or still
begins with `${` counts as unset: `model_dir` falls back to the plugin data directory's `models`
folder, and `elevenlabs_model` falls back to the script's `DEFAULT_MODEL`. The single quotes keep
the shell from expanding whatever text reaches the command.

- **Pointer**: when changing how an option reaches a script, or what a script treats as unset,
  fetch <https://code.claude.com/docs/en/plugins/manifest-reference#user-configuration> live.
- **As of**: 2026-10-09
- **Recheck trigger**: that section changes how an option with no stored value renders in a skill
  body, or a run shows a script receiving text it neither accepts as a value nor treats as unset.
