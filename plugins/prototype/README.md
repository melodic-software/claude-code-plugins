# prototype

A Claude Code plugin for building **throwaway code that answers a design question** before you
commit to architecture. A prototype proves "X works like THIS" cheaply — you push buttons, watch
state change or flip between designs, keep the answer, and delete the code.

It ships **two skills**, split by the shape of the question you're answering:

| Skill | Invoke | Answers |
|---|---|---|
| `pressure-test` | `/prototype:pressure-test <scope>` | "Does this state machine / data model / API surface feel right?" — an interactive terminal app driving a portable, liftable logic module by hand. |
| `explore-directions` | `/prototype:explore-directions <scope>` | "What should this look like?" — several radically different visual variations on one route, switchable from a floating control bar (real stack, or a self-contained HTML mockup). |

Both skills share one throwaway discipline (no persistence, skip polish, surface the state, delete
or absorb when done) and both capture the validated answer in a durable note before the code is
thrown away.

## When to use which

- **Logic** is a behavioral / feasibility spike — the question is about business logic, state
  transitions, or data shape. It produces a **pure logic module** behind a disposable TUI shell;
  when the question is answered, the module lifts into production and the shell is deleted.
- **UI** is a design prototype — the question is about appearance. It generates structurally
  different variants (not just recolors) so you can judge them side by side, then fold the winner
  into the real page.

Each skill auto-invokes on its own trigger phrases, or you can call it directly. If you're not sure
which fits, a backend/logic question routes to `pressure-test` and a page/component question routes to `explore-directions`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install prototype@melodic-software
```

## Configuration

This plugin has no `userConfig`. Its only inputs are conversational — the scope you pass and the
variant count you ask for (UI defaults to 3, capped at 5). It reads your project's own stack and
conventions rather than imposing its own, and it writes throwaway code next to where your
production code lives.

## Requirements

- **Bash** for the bundled ecosystem-detection script — on native Windows,
  install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  it runs under Git Bash. Without Bash, detection reports "none detected" and
  the skills read the host project directly to pick the stack.

Prototypes are built in whatever language and task runner your host project
already uses; the plugin adds no runtime of its own.

## License

MIT (SPDX-License-Identifier: MIT).
