- **A skill splits only on distinct discovery intent, never per subcommand.** Two skills are
  warranted when their trigger vocabularies differ — a user reaching for each says different things;
  a capability's subcommands stay action arguments of one skill. The restraint has a context-cost
  basis: the listing of skill names and descriptions loads into every session, and each entry's
  combined description text is truncated at 1,536 characters in that listing
  ([skills](https://code.claude.com/docs/en/skills), fetched 2026-07-15) — every extra skill is an
  always-paid context line. The standing exception is the `setup` lane, always its own skill with
  `disable-model-invocation: true` — see the philosophy's "Setup is explicit and repeatable".
