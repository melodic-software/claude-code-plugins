# Home plugin customization in `docs/conventions/<concern>.yaml`, validated by a JSON Schema

- Status: accepted
- Date: 2026-10-04
- Supersedes, for structured configuration: [ADR 0044](0044-default-structured-team-config-to-a-docs-convention-file-with-a-claude-fallback.md)
  Decisions 1 and 2 (the fenced config block in `docs/conventions/<concern>.md` as the default team
  layer). ADR 0044's fixed root and its pointer-as-load-hint rule stand.
- Amends: the expression criterion of
  [ADR 0018](0018-express-team-shared-conventions-as-consumer-convention-docs.md) Decision 1, so a
  structured surface and a policy floor are expressed as the YAML file below.

## Context

ADR 0044 put a structured surface's team layer in one fenced `yaml config` block inside
`docs/conventions/<concern>.md`. The org standards then set the form for structured configuration
across repositories: a dedicated YAML file at `docs/conventions/<concern>.yaml`, checked against a
JSON Schema, beside the concern's prose `docs/conventions/<concern>.md`, and named this repository's
ADR 0044 as superseded for structured configuration (standards
`components/github-actions-conventions/README.md:131-136`, "Lane configuration", read 2026-10-04).

The PR pipeline already follows that form: `docs/conventions/pr-pipeline/README.md:37-39` keeps
config values only in `<root>/pr-pipeline.yaml` and agent instructions only in Markdown, with a
schema in the convention folder. This repository has several other homes in use at once: `.claude/*`
files, three ADR 0044 blocks (multi-agent, testing, `docs/conventions/review-digest.md`), and
guardrails' folder-form `docs/conventions/source-control/commit-convention.yml`
(`plugins/guardrails/hooks/block-convention-violation.sh:141,185`). The shared reader,
`lib/parse-concern-value.sh`, read only root scalars, so it could not read a nested key or a list
from a pipeline-shaped file.

## Decision

1. **File.** A plugin or skill customization's team layer is `docs/conventions/<concern>.yaml`, one
   file per concern, validated by a JSON Schema. `<concern>` is the owning plugin's name, or the
   convention's name for a cross-plugin concern (`pr-pipeline`, `execution-target`). New config
   takes no fenced config block and no folder form; per-instance settings are YAML maps inside the
   one file.
2. **Root.** Plugin readers use the fixed root `docs/conventions` (ADR 0044 Decision 1). The
   pipeline's relocatable `<root>` (`docs/conventions/pr-pipeline/README.md:37-38`) belongs to the
   pipeline, and how it resolves is not settled (`README.md:230`). Until it is, a plugin that reads
   `pr-pipeline.yaml` reads only `docs/conventions/pr-pipeline.yaml` and treats a relocated config
   as absent. The pipeline-input issue asks how `<root>` will be recorded.
3. **Prose home.** Prose and agent instructions for a concern live in `<concern>.md` in the
   convention home the pointer line names (`lib/resolve-convention-home.sh`; default
   `docs/conventions`, as the standards name it). The pointer line never moves a config file.
4. **Existing surfaces.** `.claude/*` files, the ADR 0044 blocks (multi-agent, testing,
   `docs/conventions/review-digest.md`) and guardrails' folder-form
   `docs/conventions/source-control/commit-convention.yml` keep working and migrate under #5906.
   Testing is the exception: its resolver migrates in its own slice.
5. **Policy floors.** The config-cascade rule that every policy floor stays a dedicated file holds:
   `docs/conventions/<concern>.yaml` is that dedicated file for the team layer. A floor is read from
   the default branch, the team layer wins, personal layers may only tighten it, and the surface may
   declare no `userConfig` option (`execution-target` is the first).
6. **Schema home.** A plugin concern's schema ships in the plugin at
   `plugins/<plugin>/schemas/<concern>.schema.json`, so it versions with the code that reads it. A
   cross-plugin convention's schema sits in its convention folder, as
   `docs/conventions/pr-pipeline/pr-pipeline.schema.json` and
   `docs/conventions/ecosystem-commands/ecosystem.schema.json` already do.
7. **Validation.** This repository's CI checks each committed `docs/conventions/*.yaml` against its
   schema with `scripts/check-convention-yaml.sh`, which runs the `check-jsonschema` CLI pinned in
   `.github/requirements-ci.txt` (the ci-workflows action takes one schema per call, so it cannot
   pick a schema per file). The step runs like the existing `check-jsonschema` steps: with
   `continue-on-error: true` and fed to the job's result aggregator, so a file that fails its
   schema fails CI. Runtime readers run no validator. An invalid value never stops the run: the
   reader names the file, key and value and drops that layer, so a valid higher layer still wins,
   otherwise the key's default; a lower layer's value is never used. Amended 2026-10-04 (user
   decisions): the earlier text said validation "reports and does not block", which the aggregator
   wiring of the cited steps already contradicted, and that readers fail closed on an invalid value.
8. **Layers**, lowest first: the plugin's `userConfig` < `~/.claude/<name>` < the repository YAML
   (or its `.claude/<name>` fallback) < the gitignored local overlay. `pluginConfigs` is read only
   from user and managed settings. Every resolver reports which layer supplied each value.
9. **Where to read.** A remote reader keeps its own fetch (babysit reads a target repository through
   the contents API from the default branch,
   `plugins/source-control/skills/babysit-prs/scripts/babysit_repo_config.py:4-7,303`) and passes the
   text to the shared reader on stdin. The reader's `--ref` option is for a local or CI checkout: it
   accepts only a 40-hex commit id or `origin/<name>` and passes it to git after `--end-of-options`.
   A reader a CI lane calls reads team config at the lane's base SHA
   (`docs/conventions/pr-pipeline/README.md:98-99`), so a pull request cannot change the rules it is
   judged by.

The shared reader changes to serve this decision. `lib/parse-concern-value.sh` reads dotted keys,
lists (`--list`), stdin (`-`) and a validated `--ref`, and routes every lookup, root keys included,
through `lib/yaml-subset.awk`, the YAML-subset parser promoted from the multi-agent plugin. The
parser keeps its contract (on a parse error it prints `error<TAB><line><TAB><message>` and exits 1);
the reader maps that to a stderr line and the fallback, and `--strict` makes it exit 3 for a caller
that must tell a broken file from an absent key.

## Alternatives considered

- **Keep ADR 0044's fenced block for new config.** Rejected: the org standards set the YAML file and
  schema for structured configuration, and a block inside Markdown cannot be checked by a JSON
  Schema validator without first extracting it.
- **A second YAML parser for the pipeline config.** Rejected: two parsers of the same files drift.
  One subset parser serves the reader and the multi-agent resolver.
- **PyYAML as a declared prerequisite.** Rejected: every host that runs a reader would need it.
  Revisit if the subset proves too small for a real config.
- **Plugin schemas under `docs/conventions/`.** Rejected: the schema would version apart from the
  plugin that reads it. Revisit when a schema becomes cross-plugin.
- **Migrate every existing surface now.** Rejected: version skew across the readers and the git
  hooks that read them; #5906 owns the migration.

## Consequences

- The config-cascade README names the team layer as `docs/conventions/<concern>.yaml` with a JSON
  Schema, lists the layers in Decision 8's order, and amends its expression doctrine; that is a
  minor `contract_version` bump, because existing locations keep working.
- New config surfaces ship a schema and a YAML file; no new `.claude/<topic>` file and no new
  fenced config block.
- Plugins that carry the shared reader also carry `yaml-subset.awk` beside it, synced by
  `scripts/sync-shared-copies.sh`.
- A malformed team file no longer reads as a partial value: the reader takes the fallback and says so
  on stderr, and a fail-closed caller uses `--strict`.
- CI schema validation reports without blocking, so a schema violation reaches a reviewer, not a
  required check.

Recheck when the pipeline settles how `<root>` resolves, or when #5906 finishes migrating the
existing surfaces.
