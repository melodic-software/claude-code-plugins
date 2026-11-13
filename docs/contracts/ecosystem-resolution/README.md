# Ecosystem resolution

A versioned, marketplace-wide contract for how a skill finds a consuming repository's language,
framework, tool, library and command choices. A generic skill reads those choices from the
repository it works in; it ships none of its own. The decision and its classification rules are in
[ADR 0101](../../adr/0101-resolve-ecosystem-specifics-from-the-consumer-repository.md).

This directory is the source of truth: this README (run kinds, recording, the record table,
carriers, versioning), [`generic-resolution.md`](generic-resolution.md) (the seven-step text a
carrier plugin holds as a synced copy) and [`CHANGELOG.md`](CHANGELOG.md) (version history).

## Scope

The contract owns the procedure: the order a skill reads, infers and asks in, and what it may do
when nothing resolves. It does not own the records it reads:

- [`ecosystem-commands`](../ecosystem-commands/README.md) owns the schema and examples of the
  per-ecosystem command file. That contract is not widened by this one. Its resolution list ends in
  the plugin's bundled portable defaults; once `toolchain`'s nine bundled files are deleted, in a
  later change under ADR 0101, a generic skill takes step 7 of the generic text (an unresolved
  report) in that step's place.
- [`standards`](../standards/README.md) owns the standards index and its paved-path row. Where its
  resolution ladder ends in safe ecosystem defaults, a generic skill resolving a language,
  framework, tool or library choice takes step 7 instead.
- [`enforcement-ladder`](../enforcement-ladder/README.md) owns the order of enforcement mechanisms
  and where a repository reorders it.

## Run kinds

Two run kinds, and the procedure differs only in what each may do.

| Run kind | Who is present | May ask | May write a record |
|---|---|---|---|
| attended | a person who can answer a question now | yes, once per choice | after the person says yes |
| unattended | nobody, or nobody known to be present | no | no; a lane may propose one, as the recording rule says |

The detector runs once, before the first read, and stops at the first check that holds:

1. The invocation says it is unattended: an `--unattended` argument, a scheduled, loop or CI lane,
   a headless run, or a subagent an unattended run dispatched. The run is unattended.
2. A person is in the session and can answer now. The run is attended.
3. Otherwise the run is unattended: a run that cannot tell counts as unattended.

An unattended run keeps the limits in the generic text's "Unattended limits" section.

## Resolution procedure

The procedure is the seven steps in [`generic-resolution.md`](generic-resolution.md): decide the
run kind, read the record, read what the repository states, infer from its files, ask (attended
only), record (attended only), and report what stays unresolved. A skill that follows it cites its
plugin's copy and never restates the steps.

Two guarantees hold across every step:

- **Repeatable.** A recorded choice is read before any inference, so the same repository run twice
  gets the same choice.
- **No bundled choice.** When nothing resolves, the skill skips the step and says so. It never
  falls back to a language, framework, tool, library or command it ships.

## Recording rule

- A choice is written to its record only by offer and acceptance. In an attended run, acceptance
  is the person's yes in the session.
- An unattended run writes no record. A lane may instead propose one in a pull request, holding
  only commands that pass the unattended limits. For an ecosystem record (a
  `.claude/ecosystems/<ecosystem>.yaml` file) a merged pull request counts as acceptance. Every
  other record still needs a person's yes.
- A record is written where the record table puts it, through the writer the table names, never
  into a file the skill picks itself.

## Record table

| Choice | Record | Owner | Writer |
|---|---|---|---|
| A build, test, lint or format command for one ecosystem | `.claude/ecosystems/<ecosystem>.yaml` | [`ecosystem-commands`](../ecosystem-commands/README.md) | the owning plugin's re-runnable `setup`; a lane's record pull request, once merged |
| A language, framework or library convention, or a review criterion | the standards index and the files its rows route to | [`standards`](../standards/README.md) | the standards setup, on acceptance |
| The chosen way for a repeated task | the file the index's `paved-path` row routes to | [`standards`](../standards/README.md#paved-paths) | `/discipline:reuse-or-replace`, after a yes |
| The order of enforcement mechanisms | the project instructions | [`enforcement-ladder`](../enforcement-ladder/README.md#reordering) | the person |

The generic text carries the first two columns of this table in its own words, with the default
paths spelled out, so a carrier's copy works offline. A new row changes both files in the same pull
request.

## Carrier rule

A carrier is a plugin holding a synced copy of a contract text; here, of `generic-resolution.md`.

- A plugin is a carrier only while one of its skills still takes a language-specific step after
  its cut. It joins or leaves in the pull request that changes that fact.
- `scripts/sync-shared-copies.sh` generates each copy and `scripts/shared-copies.txt` lists it,
  the same as the other contract texts with plugin copies.
- A carrier's skill cites its own copy. It never cites this README or the canonical file by path.

## Versioning

The contract version is the `ecosystem-resolution` key in `generic-resolution.md`'s frontmatter,
so every copy states which version it carries. [`CHANGELOG.md`](CHANGELOG.md) records each change.

- A wording change: patch.
- A new record row, or a new signal in the detector: minor.
- A guardrail change: major. The guardrails are the unattended limits, the rule that an unsure run
  counts as unattended, reading the record before any inference, writing a record only on
  acceptance, and shipping no bundled choice.

Every change to `generic-resolution.md` regenerates the copies, and each carrier takes a version
bump.
