# Session-flow Convention

Prose rules for the session-flow plugin in this repository. Its settings live in
[`session-flow.yaml`](session-flow.yaml).

## Observer guidance

The session observer reads this section from the default branch at session start and adds it to
every live check, so a check can judge this repository's rules even when the session has not loaded
the file that states them. Each line names the rule and where it is written.

- Pull requests open, go ready and merge through `/source-control:pull-request`, never a bare
  `gh pr create`, ready flip or merge (`AGENTS.md`, "Pull request states").
- A plugin ships consumer-agnostic behavior: a value of one user, machine, organization or
  repository lives in that consumer's config layer, and a new behavior ships as an option
  (`.claude/rules/consumer-agnostic-plugins.md`).
- A plugin's repository settings go in `docs/conventions/<plugin>.yaml` with a schema in the plugin,
  never hardcoded (`docs/adr/0064-home-plugin-customization-in-docs-conventions-yaml.md`).
- Code and prose take the fewest lines and words that keep the meaning, and carry no origin or
  history notes (`AGENTS.md`, "Team standards").
- Before editing a hooks module, load the built-in `plugin-authoring` skill
  (`.claude/rules/mod-authoring.md`).
