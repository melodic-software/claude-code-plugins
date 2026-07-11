# thariq-skills

A Claude Code plugin that ships Anthropic's internal skill-authoring playbook as
an on-demand knowledge skill — the 9 skill categories, the 9 authoring tips
(gotchas sections, progressive disclosure, description-as-trigger discipline,
config.json first-run setup, persistent storage, effort-aware behavior, helper
scripts, on-demand hooks), and distribution guidance.

Invoke it with `/thariq-skills:thariq-skills`, or let Claude load it
automatically when you ask about creating or improving a skill.

## What it provides

- **9 skill categories** — a taxonomy for scoping a skill to one cohesive
  concern (library reference, product verification, runbooks, and so on).
- **9 authoring tips** — the highest-leverage practices Anthropic learned
  running hundreds of skills in production, distilled into a quick-reference
  table.
- **Distribution guidance** — when to check skills into a repo versus publish
  them through a plugin marketplace, plus measuring and composing skills.

The content is distilled from
[Thariq's March 17, 2026 post](https://x.com/trq212/status/2033949937936085378);
a verbatim upstream baseline is vendored inside the skill for drift detection.

## Update workflow (maintainers)

`/thariq-skills:thariq-skills update` runs the bundled drift-check script:
`--check` (default) reports upstream version and vendor SHA drift read-only;
`--apply` refreshes the vendored baseline and frontmatter metadata. Integrating
upstream deltas into the distilled skill body stays a manual, reviewed step.
Run it in a working-tree checkout of this plugin (the marketplace clone, or a
directory loaded via `--plugin-dir`) — consumers receive updates through
`/plugin marketplace update` once a new plugin version is published.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install thariq-skills@melodic-software
```

## Configuration

This plugin has no `userConfig`. It is a pure knowledge skill: nothing to
configure, no state, no network access on normal invocation (only the
maintainer-facing update script fetches the upstream source).

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
