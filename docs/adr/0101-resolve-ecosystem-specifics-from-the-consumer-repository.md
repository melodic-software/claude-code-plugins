# Resolve ecosystem specifics from the consumer repository

- Status: accepted
- Date: 2026-11-13
- Refs: [#15703](https://github.com/melodic-software/claude-code-plugins/issues/15703) (spec),
  [#15706](https://github.com/melodic-software/claude-code-plugins/issues/15706); owner decision of
  2026-11-12 (Q5: one record, not four)

## Context

Generic skills ship language, framework, tool and library choices that a model reads and acts on.
In a repository the skill's authors did not anticipate, those choices run the wrong command, or a
shipped default runs unnoticed in place of the repository's own tool. Two examples on `main`:

- `toolchain` bundles nine per-ecosystem default files under
  `plugins/toolchain/reference/ecosystems/`. The Python file's `check-cmd` runs
  `uv run ruff check . --no-fix && uv run ruff format . --check && uv run pyright`, so a repository
  with a ruff config and no ecosystem record gets pyright in its check whether or not it uses
  pyright.
- `/corrections:codify`'s finding classes route the whole `testing/audit/` family to a Roslyn
  `custom-analyzer`, or to a Semgrep rule outside .NET: tool choices the consumer never made.

The structure to resolve choices from the consumer already exists: the
[`ecosystem-commands`](../contracts/ecosystem-commands/README.md) record, the four-step
convention-resolution ladder in the [migration playbook](../migration-playbook.md#convention-resolution-ladder),
and executed adapters in six plugins. What is missing is one procedure every generic skill follows,
a rule for what may stay shipped, and an end to the bundled fallback.

## Decision

1. **Resolve ecosystem specifics from the consumer repository.** A generic skill reads the
   repository's record, then what it states, then what its files imply, then asks when a person is
   present. The procedure is the
   [`ecosystem-resolution`](../contracts/ecosystem-resolution/README.md) contract.
2. **Ship no bundled default.** When nothing resolves, the skill reports the choice as unresolved
   and skips the step visibly. It does not fall back to a choice it ships.
3. **Keep executed adapters.** Code a script runs to parse or drive a named tool stays.
4. **Classify shipped content by the rules below.** Each language, framework, tool, library or
   command named in shipped content is one of these:

   | Class | What it is | Treatment |
   |---|---|---|
   | Model-read specific | text a model reads to choose what to run, recommend or build: skill and agent bodies, plugin-level reference and context files, a bundled default file a skill reads | cut from a generic skill; the choice is resolved from the consumer |
   | Executed adapter | code a script runs that parses or drives a named tool | kept; it names each file or value it cannot read, and accepts a value it has no adapter for, reporting that no shipped adapter covers it |
   | Security or safety floor | a check that holds whatever the consumer chose, such as a secret pattern or a guard on a destructive command | kept; removing or narrowing one is the owner's decision each time |
   | Declared-ecosystem surface | a plugin or skill whose purpose is one ecosystem, declaring that narrower scope at the coupling site | kept, as [ADR 0060](0060-abstract-provider-details-in-skills-behind-consumer-conventions-and-adapters.md) keeps declared-provider surfaces |
   | Source citation | a documentation URL or name cited for a reader to consult, not a choice the skill makes | kept |

   The named exceptions are the last four classes. A model-read specific in a generic skill outside
   them is a review finding: [`docs/review/skills-and-agents.md`](../review/skills-and-agents.md).

5. **Cuts follow the existing evidence rule.** A cut to an existing skill ships with eval evidence
   of no loss. Removing shipped specifics applies to existing model-read content only.

### One-way doors

- **The contract.** Once a plugin carries a synced copy of `generic-resolution.md`, a guardrail
  change is a major version and every carrier takes a bump. The guardrails are listed in the
  contract's versioning section.
- **Deleting `toolchain`'s nine bundled files.** A repository with no ecosystem record then gets an
  unresolved skip where it used to get a command. Restoring a bundled default would take a new
  record reversing this one.

## Considered options

- **Keep the bundled defaults as the last fallback.** Rejected: the fallback is where the wrong
  commands come from, and a repository cannot tell a default ran in place of its own tool.
- **Widen `ecosystem-commands` to hold the procedure.** Rejected (design Q23, recorded on #15706):
  that contract owns a record's schema and examples. The procedure also covers records it does not
  own (the standards index, project instructions), so it gets its own contract.
- **Let each skill carry its own resolution text.** Rejected: the copies would drift, as
  `/toolchain:check` and `/toolchain:lint` already did before `ecosystem-commands` existed.
- **Four records** (this decision, the verification tier, the renamed public ids, the contract).
  Rejected by the owner (Q5, recorded on #15706): the reason for the verification tier and the
  renamed ids go in the changelog entry of the enforcement ladder's next major version (3.0.0, a
  later item), which its versioning rule already requires.

## Consequences

- The [`ecosystem-resolution`](../contracts/ecosystem-resolution/README.md) contract exists with no
  carriers. A plugin joins as a carrier in the pull request whose cut leaves one of its skills
  taking a language-specific step.
- Reviewers apply the classification rules to new skill and agent text now, and hold a new skill
  that recommends, places or builds enforcement or an instruction to the enforcement ladder and to
  the consumer's own tooling: [`docs/review/skills-and-agents.md`](../review/skills-and-agents.md).
- The migration playbook's convention-resolution ladder ends in an unresolved report, not a generic
  default, for a consumer-tool seam, and a merged pull request counts as acceptance for an
  ecosystem record only.
- `ecosystem-commands` keeps its schema and examples. Its bundled-defaults step stops applying to
  generic skills when `toolchain`'s nine files are deleted, in a later change.

## Revisit triggers

- A consumer reports that an unresolved skip blocks work a shipped default used to do, and no
  record, statement or inference could have resolved it.
- A class of shipped content that fits none of the five classes above.
