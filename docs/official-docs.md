# Official docs

Find a current Claude Code docs page in
[`https://code.claude.com/docs/llms.txt`](https://code.claude.com/docs/llms.txt), the platform's
self-updating page list, and read it through `/discovery:read-docs`. Model-behavior pages (prompting,
thinking, evaluation) are on `platform.claude.com`, listed in
[`https://platform.claude.com/docs/llms.txt`](https://platform.claude.com/docs/llms.txt). Never act on
remembered page content: re-fetch the page. The
[upstream-drift convention](contracts/upstream-drift/README.md) owns how a fetched page backs a
record, and its [fetch route](contracts/upstream-drift/README.md#reading-the-basis-the-fetch-route)
owns how to read one: a summarizing fetch of a long page truncates it and then reports what it never
reached as absent, so read the `.md` channel verbatim and record no verdict from a truncated read.

## Rules for citing these pages

- **Prompting doctrine.** The instruction text a plugin ships (skill bodies, agent definitions,
  hook-injected prose, embedded sample prompts) is authored against the platform prompting pages,
  not the harness pages.
- **Two `best-practices` pages.** The platform page
  (<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>) is the
  cross-product Agent Skills guide for skill bodies; the Claude Code page
  (<https://code.claude.com/docs/en/best-practices>) is the harness guide for CLAUDE.md,
  permissions, and sessions. They share only their slug, so cite the one you mean by its full URL.
- **The changelog.** The prose pages can lag
  [the changelog](https://code.claude.com/docs/en/changelog): a behavior can change in a release
  and reach the topic page a release or more later, and when the two disagree the changelog is the
  one that matches the running harness. The rendered page summarizes; fetch the raw markdown
  (`…/changelog.md`, or the upstream `CHANGELOG.md`) when you need a byte-exact version-pinned
  quote, because a summarizing fetch of this page has produced inconsistent readings of the same
  entries. A changelog citation records what changed **in a version**, so always pin the version,
  and pair it with the topic page rather than replacing it, since the topic page stays
  authoritative for mechanism and semantics.
- **JSON Schemas.** CI validates against these by URL and never treats them as a load-time
  contract: `marketplace.json` →
  [`https://json.schemastore.org/claude-code-marketplace.json`](https://json.schemastore.org/claude-code-marketplace.json),
  `plugin.json` →
  [`https://json.schemastore.org/claude-code-plugin-manifest.json`](https://json.schemastore.org/claude-code-plugin-manifest.json)
  (published on SchemaStore, sourced from the same plugin system the docs describe). `plugin.json`
  files carry no `$schema` key: claude.ai's marketplace sync strips it with a warning, and Claude
  Code ignores it at load time.

## Evaluation guidance (platform docs)

This marketplace authors model-graded eval fixtures for its skills (see the migration playbook's
eval warrant policy) and ships the `evals` plugin distilling this guidance.

| Page | Official doc page | As of |
|---|---|---|
| Define success criteria and build evaluations | <https://platform.claude.com/docs/en/test-and-evaluate/develop-tests> | 2026-08-08 |
| Evals cookbook (source: `anthropics/claude-cookbooks` `misc/building_evals.ipynb`) | <https://platform.claude.com/cookbook/misc-building-evals> | 2026-08-08 |

Each row's **As of** date is when the page was last read live; a fetch that no longer matches a row
is that row's recheck trigger.
