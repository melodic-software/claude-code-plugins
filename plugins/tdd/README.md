# tdd

A Claude Code plugin that ships a TDD knowledge base as an on-demand knowledge
skill — distilled from cover-to-cover readings of Kent Beck's *Test-Driven
Development: By Example* (2003) and Vladimir Khorikov's *Unit Testing:
Principles, Practices, and Patterns* (2020). It answers the WHY behind test
design decisions: when to mock, what makes a good test, classical vs London
school, observable behavior vs implementation details, test doubles, coverage
metrics, testable architecture, and more.

Invoke it with `/tdd:tdd <question or concept>`, or let Claude load it
automatically when you ask a test design question.

## What it provides

- **Routing table** — a hub SKILL.md routes each question to one of fourteen
  author-attributed reference files (Beck methodology, Khorikov four pillars,
  test doubles, testable architecture, integration testing, anti-patterns,
  worked examples, and more), so only the relevant slice loads.
- **Quick decision guide** — one-line answers to the twelve most common test
  design questions, with no reference file load needed.
- **Author attribution throughout** — shared concepts carry attributed
  sections with synthesis where the authors overlap; single-author concepts
  are named `{concept}-{author}.md`.

## Scope boundary

This skill is **knowledge** (WHY behind testing decisions), not **workflow**
(HOW to run tests). It never runs, scaffolds, or filters tests — your
project's own test tooling and conventions own that; this skill informs the
design decisions those workflows execute.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install tdd@melodic-software
```

## Configuration

This plugin has no `userConfig`. It is a pure knowledge skill: nothing to
configure, no state, no scripts, no network access.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
