---
name: setup
description: "Configure the code-tidying plugin for this repository: interview the user, infer which lane patterns fit the repo layout, and scaffold tracked .claude/tidy-lanes/<lane>.md project lane files from the bundled templates. Use when: 'set up code-tidying', 'configure tidy lanes', 'code-tidying setup', 'scaffold a tidy lane', or the tidy skill reports no project lanes for this repo. Re-runnable — safe to invoke again to add or retune lanes."
argument-hint: "(no arguments — interactive interview)"
user-invocable: true
disable-model-invocation: false
---

## Purpose

Scaffold (or update) the consuming repo's tracked lane definitions at `.claude/tidy-lanes/<lane>.md`
so `/code-tidying:tidy` resolves project-specific scope globs and watch-for patterns deterministically
instead of falling back to the generic bundled lanes every run. A project lane at
`${CLAUDE_PROJECT_DIR}/.claude/tidy-lanes/<lane>.md` takes precedence over the bundled lane of the
same name — this is the plugin's seam-2 extension surface.

Idempotent: re-running reads the existing lane files and proposes additions or edits against that
baseline rather than overwriting a consumer lane blind.

## Lanes vs. templates — the distinction this skill turns on

- **Bundled lanes** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/lanes/*.md` — `shell-tooling`, `docs-prose`)
  cover surfaces that look the same in most repos. They resolve automatically with **no config**;
  a project override is worth writing only when this repo's tooling or doc directories differ from
  the bundled defaults.
- **Bundled templates** (`${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/*.template.md`) are `<placeholder>`
  scaffolds for the lanes that are project-specific **by design** — code the repo has but no generic
  lane can name. This skill's primary job is turning the fitting templates into real lane files.

Never tell the user to "copy the bundled lanes." Scaffold from templates; override a bundled lane only
when its defaults miss this repo's actual layout.

## Task

Apply the convention-resolution ladder — config present → use it; absent → infer from the repo and
persist; cannot infer → ask and offer to persist; else a safe default (skip that lane, no empty file).

1. **Read existing lanes first.** List `.claude/tidy-lanes/*.md`. If any exist, read each and present a
   short summary (lane name, scope globs, watch-for count). The interview proposes changes against that
   baseline; **never overwrite an existing consumer lane without explicit confirmation in this conversation.**
2. **Explore the repo to draft candidate lanes.** Before asking anything, map the four bundled template
   patterns against what actually exists, and check whether either bundled lane needs a project override:
   - **apps** (`templates/apps-lane.template.md`) — user-facing applications + their tests: web/API/CLI
     app roots and their sibling test projects.
   - **dependency-root** (`templates/dependency-root-lane.template.md`) — framework/library core that
     downstream code depends on: shared/domain/core library roots.
   - **host-wiring** (`templates/host-wiring-lane.template.md`) — hosting infrastructure, logging,
     registration, service defaults: composition roots, DI wiring, service-default projects.
   - **polyglot-services** (`templates/polyglot-services-lane.template.md`) — non-primary-language
     services, MCP servers, sidecars.
   - **bundled-lane override** — inspect the repo's actual tooling dirs and doc dirs; a project override
     of `shell-tooling` or `docs-prose` is warranted only when they diverge from the bundled scope globs.
   Read the actual directory names and file extensions from the repo — do not assume a stack. Skip any
   template pattern the repo has no surface for.
3. **Interview, one lane at a time** (recommendation-first). Present each candidate lane with its inferred
   scope globs and the source template, marked with a recommendation; let the user accept, edit the globs,
   or drop the lane. Offer a custom lane last ("any other glob-scoped slice this repo should tidy on its
   own rotation?"). Ask about the highest-blast-radius lane first.
4. **Fill the template placeholders from real repo values.** For each accepted lane, read the closest
   `templates/<pattern>.template.md` in full and replace every `<placeholder>` with values drawn from this
   repo: scope globs from real directory paths, watch-for patterns tuned to the stack, lane-specific
   exclusions for this repo's unverifiable surfaces, verification commands from the project's own
   CLAUDE.md / rules / CI config (never invented), the Conventional Commits type, and preferred research
   sources. Leave no `<placeholder>` behind.
5. **Write the lane files.** Materialize each accepted lane at `.claude/tidy-lanes/<lane>.md`. Confirm the
   directory is tracked, not gitignored. Write only lanes the user confirmed; produce no empty scaffolds.
6. **Offer the personal overlay.** A per-developer lane override is just another `.claude/tidy-lanes/<lane>.md`;
   a machine-local variant belongs in a gitignored path — recommend the consumer keep any `*.local.*`
   lane files gitignored if they want personal, untracked lanes. Team lanes stay tracked.

## Output

Tracked `.claude/tidy-lanes/<lane>.md` file(s) in the consuming repo, plus a one-paragraph summary of which
lanes were written, which template each came from, and how to re-run this setup to add or retune lanes.

## What this skill does NOT do

- Run a tidy sweep — that is `/code-tidying:tidy`.
- Ship its own template copies — lane files scaffold from `${CLAUDE_PLUGIN_ROOT}/skills/tidy/templates/`;
  duplicating those into this skill would drift from the source.
- Write machine-local state — lane configuration lives in the consumer's tracked `.claude/tidy-lanes/`,
  never in the plugin directory or a plugin data directory.
