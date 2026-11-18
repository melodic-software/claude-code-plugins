---
description: "Control skill /app-control:drive reads to run this repository's plugin skills in Claude Code, one plugin at a time, through the control-claude-code driver."
disable-model-invocation: true
---

App: claude-code-plugins, this repository's plugins. A module is one plugin, `plugins/<module>`; a
feature is one of its skills, id `<module>/<skill>`, or a cross-plugin surface keyed by its sources.
Driving tool: `/harness-ops:control-claude-code`, its hub at
`plugins/harness-ops/skills/control-claude-code/SKILL.md` and its driver beside it.

Each section below hands off to the driving tool's section of the same name, with `<skill-dir>` set
to the absolute path of `plugins/harness-ops/skills/control-claude-code` in the folder that holds
this skill's `.claude/`, never a relative path (from a pull request's checkout it would run that
checkout's copy of the driver), and `<plugin-dir>` set to the absolute path of `plugins/<module>`
of the feature driven in the checkout under test; timeouts come from that skill's `config/`. Write
both as literal paths, with no shell variable, and run every command from the root of the checkout
under test. The run uses the account Claude Code is already signed in with and never signs in
or out.

## Launch

The driving tool's `## Launch`. Only terminal-session entry points need it: a `logs` capture runs
Claude Code in print mode and starts and stops its own process.

The pr-verify capture and the whole-map pass drive Claude Code on an API key whose credits do not
pay for an interactive session, so a turn typed there is refused. What those credits cover:
<https://platform.claude.com/docs/en/about-claude/api-credits-for-subscribers#what-the-credits-cover>.
In those two runs, launch the session, since the Mask's `values:` source reads it, and type no
turn in it. Record each entry point typed at the prompt as
`not driven (the key's credits do not cover interactive Claude Code)`, drive the print-mode entry
point alone, and take every step's result, the Proof included, from its `logs` capture: a step
that asks for a terminal screenshot records the `logs` path and its `Budget:` values instead.

Data: none: a run reuses the person's signed-in Claude Code config directory, per the driving
tool's `Data:` line.

Side by side: yes, one `<session>` name per run, per the driving tool's `Side by side:` line.

Session: one session per plugin, per the driving tool's `Session:` line.

## Ready

The driving tool's `## Ready`.

## Capture

The driving tool's `## Capture`. `logs` is the kind a run with no one present uses.

## Cleanup

The driving tool's `## Cleanup` when this run launched a session; a run of `logs` captures alone
has nothing to stop.

## Mask

The driving tool's `## Mask`.

## Next

/app-control:drive claude-code-plugins <module>/<skill>

## Gotchas

- A local drive launches Claude Code with `--restricted`. A skill step that needs a tool that launch
  removes stops there: record the step and its entry point, and never drop the flag. Which tools it
  removes: the `--restricted` row of <https://code.claude.com/docs/en/cli-reference#cli-flags>. The
  pr-verify capture's driven session launches through the broker with `--in-sandbox`, without
  `--restricted`, so Bash is there, and starts in a writable clone of the pull request's head with
  its git history.
- A Parts line marked `No slash command.` or `No plain-words entry.` names the entry points that
  skill lacks.
- After the first turn the session may draw "Teach auto mode about your environment?". Escape
  dismisses it; record that as its own step.
- `wait-for` matches any text on the screen, so the second entry point in one session can match the
  first one's answer, and a tool-call line can match a file name. For the later entry point, wait
  on text only its own answer prints, then check the screenshot shows a new answer. In that same
  session the skill is already loaded, so the plain-words turn does not show whether the model would
  pick it unaided.
- The terminal session draws tables with box characters and can wrap or scroll long output off the
  visible screen, so a literal read from a SKILL.md or a print-mode log may never match there.
  Matching is case-exact.
- Many skill turns run longer than `stepMs` (25 s to over a minute here). When a wait times out,
  take the screenshot after the turn's `done` line and record what it shows.
- A skill step that needs Bash rarely stops at once: the session tries a subagent, which has no
  shell either, then applies the script's rules by hand. Record that result as hand-applied, not
  as the script's output.

## Features

- actionlint | features/actionlint/README.md | entry points: 4 | sources: plugins/actionlint/skills/*/SKILL.md
- adhd | features/adhd/README.md | entry points: 4 | sources: plugins/adhd/skills/*/SKILL.md
- ai-briefing | features/ai-briefing/README.md | entry points: 4 | sources: plugins/ai-briefing/skills/*/SKILL.md
- ai-slop | features/ai-slop/README.md | entry points: 4 | sources: plugins/ai-slop/skills/*/SKILL.md
- animation | features/animation/README.md | entry points: 4 | sources: plugins/animation/skills/*/SKILL.md
- app-control | features/app-control/README.md | entry points: 4 | sources: plugins/app-control/skills/*/SKILL.md
- architecture | features/architecture/README.md | entry points: 4 | sources: plugins/architecture/skills/*/SKILL.md
- attribution | features/attribution/README.md | entry points: 4 | sources: plugins/attribution/skills/*/SKILL.md
- autonomy | features/autonomy/README.md | entry points: 4 | sources: plugins/autonomy/skills/*/SKILL.md
- bash-format | features/bash-format/README.md | entry points: 4 | sources: plugins/bash-format/skills/*/SKILL.md
- bugs | features/bugs/README.md | entry points: 4 | sources: plugins/bugs/skills/*/SKILL.md
- code-metrics | features/code-metrics/README.md | entry points: 4 | sources: plugins/code-metrics/skills/*/SKILL.md
- code-tidying | features/code-tidying/README.md | entry points: 4 | sources: plugins/code-tidying/skills/*/SKILL.md
- codebase-health | features/codebase-health/README.md | entry points: 4 | sources: plugins/codebase-health/skills/*/SKILL.md
- computer-use | features/computer-use/README.md | entry points: 4 | sources: plugins/computer-use/skills/*/SKILL.md
- context-budget | features/context-budget/README.md | entry points: 4 | sources: plugins/context-budget/skills/*/SKILL.md
- context-usage | features/context-usage/README.md | entry points: 4 | sources: plugins/context-usage/skills/*/SKILL.md
- context7 | features/context7/README.md | entry points: 4 | sources: plugins/context7/skills/*/SKILL.md
- corrections | features/corrections/README.md | entry points: 4 | sources: plugins/corrections/skills/*/SKILL.md
- coupling | features/coupling/README.md | entry points: 4 | sources: plugins/coupling/skills/*/SKILL.md
- debugging | features/debugging/README.md | entry points: 4 | sources: plugins/debugging/skills/*/SKILL.md
- desktop-notification | features/desktop-notification/README.md | entry points: 4 | sources: plugins/desktop-notification/skills/*/SKILL.md
- developer-experience | features/developer-experience/README.md | entry points: 4 | sources: plugins/developer-experience/skills/*/SKILL.md
- discipline | features/discipline/README.md | entry points: 4 | sources: plugins/discipline/skills/*/SKILL.md
- discovery | features/discovery/README.md | entry points: 4 | sources: plugins/discovery/skills/*/SKILL.md
- disk-hygiene | features/disk-hygiene/README.md | entry points: 4 | sources: plugins/disk-hygiene/skills/*/SKILL.md
- docs-hygiene | features/docs-hygiene/README.md | entry points: 4 | sources: plugins/docs-hygiene/skills/*/SKILL.md
- docs-naming | features/docs-naming/README.md | entry points: 4 | sources: plugins/docs-naming/skills/*/SKILL.md
- domain-driven-design | features/domain-driven-design/README.md | entry points: 4 | sources: plugins/domain-driven-design/skills/*/SKILL.md
- dometrain | features/dometrain/README.md | entry points: 4 | sources: plugins/dometrain/skills/*/SKILL.md
- education | features/education/README.md | entry points: 4 | sources: plugins/education/skills/*/SKILL.md
- eol-normalizer | features/eol-normalizer/README.md | entry points: 4 | sources: plugins/eol-normalizer/skills/*/SKILL.md
- evals | features/evals/README.md | entry points: 4 | sources: plugins/evals/skills/*/SKILL.md
- event-storming | features/event-storming/README.md | entry points: 4 | sources: plugins/event-storming/skills/*/SKILL.md
- explainer-video | features/explainer-video/README.md | entry points: 4 | sources: plugins/explainer-video/skills/*/SKILL.md
- firecrawl | features/firecrawl/README.md | entry points: 4 | sources: plugins/firecrawl/skills/*/SKILL.md
- fleet | features/fleet/README.md | entry points: 4 | sources: plugins/fleet/skills/*/SKILL.md
- formal-verification | features/formal-verification/README.md | entry points: 4 | sources: plugins/formal-verification/skills/*/SKILL.md
- gaming | features/gaming/README.md | entry points: 4 | sources: plugins/gaming/skills/*/SKILL.md
- github | features/github/README.md | entry points: 4 | sources: plugins/github/skills/*/SKILL.md
- go-format | features/go-format/README.md | entry points: 4 | sources: plugins/go-format/skills/*/SKILL.md
- guardrails | features/guardrails/README.md | entry points: 4 | sources: plugins/guardrails/skills/*/SKILL.md
- harness-config | features/harness-config/README.md | entry points: 4 | sources: plugins/harness-config/skills/*/SKILL.md
- harness-memory | features/harness-memory/README.md | entry points: 4 | sources: plugins/harness-memory/skills/*/SKILL.md
- harness-ops | features/harness-ops/README.md | entry points: 4 | sources: plugins/harness-ops/skills/*/SKILL.md
- hooks | features/hooks/README.md | entry points: 3 | sources: plugins/*/hooks/**
- implementation | features/implementation/README.md | entry points: 4 | sources: plugins/implementation/skills/*/SKILL.md
- improvement | features/improvement/README.md | entry points: 4 | sources: plugins/improvement/skills/*/SKILL.md
- instruction-placement | features/instruction-placement/README.md | entry points: 4 | sources: plugins/instruction-placement/skills/*/SKILL.md
- javascript-format | features/javascript-format/README.md | entry points: 4 | sources: plugins/javascript-format/skills/*/SKILL.md
- kindle-dedrm | features/kindle-dedrm/README.md | entry points: 4 | sources: plugins/kindle-dedrm/skills/*/SKILL.md
- knowledge | features/knowledge/README.md | entry points: 4 | sources: plugins/knowledge/skills/*/SKILL.md
- machine-health | features/machine-health/README.md | entry points: 4 | sources: plugins/machine-health/skills/*/SKILL.md
- markdown-format | features/markdown-format/README.md | entry points: 4 | sources: plugins/markdown-format/skills/*/SKILL.md
- mcp-tools | features/mcp-tools/README.md | entry points: 4 | sources: plugins/mcp-tools/skills/*/SKILL.md
- miro | features/miro/README.md | entry points: 4 | sources: plugins/miro/skills/*/SKILL.md
- mods | features/mods/README.md | entry points: 3 | sources: plugins/*/hooks/*.ts, plugins/*/hooks/*.tsx
- multi-agent | features/multi-agent/README.md | entry points: 4 | sources: plugins/multi-agent/skills/*/SKILL.md
- mutation-testing | features/mutation-testing/README.md | entry points: 4 | sources: plugins/mutation-testing/skills/*/SKILL.md
- naming | features/naming/README.md | entry points: 4 | sources: plugins/naming/skills/*/SKILL.md
- overengineering | features/overengineering/README.md | entry points: 4 | sources: plugins/overengineering/skills/*/SKILL.md
- performance | features/performance/README.md | entry points: 4 | sources: plugins/performance/skills/*/SKILL.md
- pixel-art | features/pixel-art/README.md | entry points: 4 | sources: plugins/pixel-art/skills/*/SKILL.md
- planning | features/planning/README.md | entry points: 4 | sources: plugins/planning/skills/*/SKILL.md
- playbooks | features/playbooks/README.md | entry points: 4 | sources: plugins/playbooks/skills/*/SKILL.md
- playgrounds | features/playgrounds/README.md | entry points: 4 | sources: plugins/playgrounds/skills/*/SKILL.md
- playwright | features/playwright/README.md | entry points: 4 | sources: plugins/playwright/skills/*/SKILL.md
- plugin-quality | features/plugin-quality/README.md | entry points: 4 | sources: plugins/plugin-quality/skills/*/SKILL.md
- powershell-format | features/powershell-format/README.md | entry points: 4 | sources: plugins/powershell-format/skills/*/SKILL.md
- prototype | features/prototype/README.md | entry points: 4 | sources: plugins/prototype/skills/*/SKILL.md
- python-format | features/python-format/README.md | entry points: 4 | sources: plugins/python-format/skills/*/SKILL.md
- rate-limits | features/rate-limits/README.md | entry points: 4 | sources: plugins/rate-limits/skills/*/SKILL.md
- repo-fleet-hygiene | features/repo-fleet-hygiene/README.md | entry points: 4 | sources: plugins/repo-fleet-hygiene/skills/*/SKILL.md
- repo-hygiene | features/repo-hygiene/README.md | entry points: 4 | sources: plugins/repo-hygiene/skills/*/SKILL.md
- retro-audio | features/retro-audio/README.md | entry points: 4 | sources: plugins/retro-audio/skills/*/SKILL.md
- review | features/review/README.md | entry points: 4 | sources: plugins/review/skills/*/SKILL.md
- session-flow | features/session-flow/README.md | entry points: 4 | sources: plugins/session-flow/skills/*/SKILL.md
- skill-quality | features/skill-quality/README.md | entry points: 4 | sources: plugins/skill-quality/skills/*/SKILL.md
- songwriting | features/songwriting/README.md | entry points: 4 | sources: plugins/songwriting/skills/*/SKILL.md
- source-control | features/source-control/README.md | entry points: 4 | sources: plugins/source-control/skills/*/SKILL.md
- speech | features/speech/README.md | entry points: 4 | sources: plugins/speech/skills/*/SKILL.md
- spelling | features/spelling/README.md | entry points: 4 | sources: plugins/spelling/skills/*/SKILL.md
- tdd | features/tdd/README.md | entry points: 4 | sources: plugins/tdd/skills/*/SKILL.md
- testing | features/testing/README.md | entry points: 4 | sources: plugins/testing/skills/*/SKILL.md
- toolchain | features/toolchain/README.md | entry points: 4 | sources: plugins/toolchain/skills/*/SKILL.md
- user-experience | features/user-experience/README.md | entry points: 4 | sources: plugins/user-experience/skills/*/SKILL.md
- user-interface | features/user-interface/README.md | entry points: 4 | sources: plugins/user-interface/skills/*/SKILL.md
- verification | features/verification/README.md | entry points: 4 | sources: plugins/verification/skills/*/SKILL.md
- visualization | features/visualization/README.md | entry points: 4 | sources: plugins/visualization/skills/*/SKILL.md
- wizard | features/wizard/README.md | entry points: 4 | sources: plugins/wizard/skills/*/SKILL.md
- work-items | features/work-items/README.md | entry points: 4 | sources: plugins/work-items/skills/*/SKILL.md
- writing | features/writing/README.md | entry points: 4 | sources: plugins/writing/skills/*/SKILL.md
- x | features/x/README.md | entry points: 4 | sources: plugins/x/skills/*/SKILL.md
