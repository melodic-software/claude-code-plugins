---
bump: minor
---

### Changed

- fix-docs runs on the read runner with no write token, on ci-workflows' run-claude-cli and the
  automations role's API key first. pr-refine.yml calls the read runner twice, each call with one
  Claude secret: `fix-docs` passes only `AUTOMATIONS_CLAUDE_API_KEY`, and `fix-docs-subscription`
  passes only `AUTOMATIONS_CLAUDE_CODE_OAUTH_TOKEN` and runs only after a credit stop or with the
  key empty. Every pr-refine job trusts the default branch tip
  ([pr-run-activity.md, Two calls on one credential each](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#two-calls-on-one-credential-each)).
- fix-docs's change leaves as a patch that the `apply-patch` job pushes as one commit, only when
  a patch was written. A refused patch posts the `pr-refine / apply-patch` check neutral and
  labels nothing
  ([pr-run-activity.md, prepare: apply-patch](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/pr-pipeline/pr-run-activity.md#prepare-apply-patch)).
- The `default` row of
  [`patch-rules.json`](https://github.com/melodic-software/claude-code-plugins/blob/main/.github/actions/resolve-config/patch-rules.json)
  refuses every agent instruction path, caps a patch at 300 files and takes a moved head with
  `--3way` (`skip-moved-head: false`).
- The read runner's launcher takes a skill with no prepare mode that hands on a patch: Bash,
  Edit, Write and Agent as tools, no Bash allow rule, and `Read(./.git/**)` denied. It fails red
  on `checks`, `self-checks` and `verify-scripts`.
- fix-docs routes to the new `docs-fix` profile, a mechanical worker from the multi-agent role
  map, which resolves to sonnet.
- The launcher accepts `web-access` (`domains: any` only), staging the research skills and their
  plugins under `.lane/`. fix-docs leaves it off.
