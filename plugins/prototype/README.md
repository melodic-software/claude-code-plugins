# prototype

A Claude Code plugin for settling one design question with **code written to be deleted**, before
you commit to an architecture. A prototype shows cheaply that "X works like THIS": you drive a
model by hand or step between layouts, write the answer down, and delete the code.

It ships **two skills**, one per kind of question:

| Skill | Invoke | Answers |
|---|---|---|
| `pressure-test` | `/prototype:pressure-test <scope>` | "Does this state machine / data model / API surface hold up?" A portable logic module you can lift into production, driven by hand from a disposable shell: a terminal app by default, or a self-contained HTML demo that someone outside engineering operates by clicking buttons. |
| `explore-directions` | `/prototype:explore-directions <scope>` | "What should this look like?" A few structurally different layouts (three by default) behind one route, toggled from a floating switcher, on the real stack or as a self-contained HTML mockup. For the mockup it also tells you that you can run `/design`, the bundled `design` skill's editable canvas, yourself. |

Both skills follow the six rules in `context/discipline.md`, from "Starts with one command" to
"Delete or absorb when done", and both write the validated answer into a durable note before the
code is deleted.

## When to use which

- **Logic** is a behavioral or feasibility spike: the open question concerns data shape, state
  transitions, or business rules. The result is a **pure logic module** behind a disposable shell;
  once the question is answered, the module moves into production and the shell is deleted.
- **UI** is a design prototype: the open question is how something should look. The variants
  differ in structure, not only in color, so you can compare them side by side, then merge the
  winner into the page it belongs to.

Each skill auto-invokes on its own trigger phrases, or you can call it directly. If you're not sure
which fits, a backend/logic question routes to `pressure-test` and a page/component question routes to `explore-directions`.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install prototype@melodic-software
```

## Configuration

This plugin has no `userConfig`. Its only inputs are conversational, the scope you pass and the
variant count you ask for (UI defaults to 3, capped at 5). It reads your project's own stack and
conventions rather than imposing its own, and it writes throwaway code next to where your
production code lives.

## Requirements

- **Bash** for the bundled ecosystem-detection script. On native Windows,
  install
  [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
  it runs under Git Bash. Without Bash, detection reports "none detected" and
  the skills read the host project directly to pick the stack.

Prototypes are built in whatever language and task runner your host project
already uses; the plugin adds no runtime of its own.

## License

MIT (SPDX-License-Identifier: MIT).
