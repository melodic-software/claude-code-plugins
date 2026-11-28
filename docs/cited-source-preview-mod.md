# Cited-source in-place preview mod (design record)

Design record for a Claude Code hooks module ("mod") that previews cited source lines in place inside a Claude Code session, without leaving the session to open a separate editor window.

- **Status:** Agreed design for v1 (no mod code shipped under this record)
- **Owner decisions recorded:**
  - 2026-11-25 (~8:21 AM EST, [#18928 comment 3](https://github.com/melodic-software/claude-code-plugins/issues/18928#issuecomment-7163805358)): v1 uses a **command trigger**, renders in the **terminal**, and shows the **exact cited lines**; hover/click triggers, the desktop pane, and curated summaries come later; this issue stops at the agreed design.
  - 2026-11-28 (7:58 AM EST, [#18928 comment 5](https://github.com/melodic-software/claude-code-plugins/issues/18928#issuecomment-7239617320)): record the proof of concept and full v1 mod implementation as deferred follow-ups inside this document rather than filing separate issues until open issues reach zero.

## Problem

When a skill cites code or documentation (first consumer: `/planning:interview` in [`plugins/planning/skills/interview/SKILL.md`](../plugins/planning/skills/interview/SKILL.md)), opening a whole file sends the reader out of the session to hunt for the relevant lines. Clicking a `vscode://file/<path>:<line>` link lands on the first cited line, but still switches applications, requires VS Code, and cannot show a multi-file citation or a tight multi-line excerpt side by side with the current turn.

The goal is to show only the exact cited lines the reader needs, in place inside the terminal session, while keeping the existing link formats as a zero-dependency fallback.

## First-version scope (v1)

| Dimension | v1 decision | Basis |
| --- | --- | --- |
| **Trigger** | Slash command registered by the mod (working name `/cite`, verified free of built-in command collisions in a live session) | Owner decision (2026-11-25); [`api.md#add-a-command`](https://code.claude.com/docs/en/plugins/mods/api#add-a-command) |
| **Surface** | Terminal side/above-prompt `Pane` opened via `$.ui.open`, with plain-line `$.ui.log` fallback when no pane can be placed | Owner decision (2026-11-25); [`interface.md#open-a-pane-at-the-right-time`](https://code.claude.com/docs/en/plugins/mods/interface#open-a-pane-at-the-right-time) |
| **Content** | Exact cited lines verbatim with line numbers, read locally via `$.fs.stat` and `$.fs.read` (zero model calls, zero subprocesses) | Owner decision (2026-11-25); [`api.md#reach-files-processes-and-the-network`](https://code.claude.com/docs/en/plugins/mods/api#reach-files-processes-and-the-network) |
| **Packaging** | Dedicated plugin (working name `source-preview`) with one mod, `engines["claude-code"]: ">=2.1.287"`, and per-hook enablement per the hook-enablement contract | [ADR 0052](adr/0052-adopt-claude-code-mods.md#packaging-and-loading); [hook enablement](contracts/hook-enablement/README.md#the-per-hook-setting) |

## Command trigger and citation grammar

The mod registers its command at `session.start` (and re-registers on the first `prompt.submit` after `session.end`, matching `plugins/context-budget/hooks/register.tsx` and `plugins/plugin-profiles/hooks/register.tsx`) with `immediate: true` so the reader can inspect a citation while Claude is mid-turn ([`interface.md#open-a-pane-at-the-right-time`](https://code.claude.com/docs/en/plugins/mods/interface#open-a-pane-at-the-right-time)).

### Accepted inputs

The command parses whitespace-separated citation specs directly compatible with `/planning:interview`'s citation grammar ([`plugins/planning/surface/README.md`](../plugins/planning/surface/README.md), `show --links` row, and `link_citations` in [`plugins/planning/surface/round.py`](../plugins/planning/surface/round.py)):

1. **Single line:** `/cite src/retry.ts:12`
2. **Contiguous multi-line range:** `/cite docs/guide.md:80-100`
3. **Disjoint lines and ranges in one file:** `/cite src/retry.ts:12,40-44`
4. **Multiple files in one command:** `/cite src/retry.ts:12,40-44 docs/guide.md:80-100`
5. **No arguments (`/cite`):** Scans the most recent assistant message via `$.session.messages()` ([`api.md#reach-files-processes-and-the-network`](https://code.claude.com/docs/en/plugins/mods/api#reach-files-processes-and-the-network)) for relative file citations (`path:line`, `path:start-end`, `path:a,b-c`, or markdown links wrapping those labels) and renders every citation found in message order using the multi-file rules below (merging spans for repeated paths on first occurrence and skipping absolute paths per the workspace-boundary rule).
6. **Close (`/cite close`):** Closes the open preview pane via `$.ui.close({ id })`.

### Multi-line and multi-file behavior

- **Contiguous ranges (`start-end`):** Validated (`1 <= start <= end`), clamped to file length with an explicit end-of-file notice if `end` exceeds the file's line count, and rendered with right-aligned line numbers.
- **Disjoint spans in one file (`12,40-44`):** Sorted in ascending line order, overlapping or adjacent spans merged, and non-adjacent hunks separated by a `---` / ellipsis divider showing how many lines were skipped between hunks.
- **Multi-file citations:** Rendered in argument or message order with a file header (`<relative-path>:<spans>`) per file. In the terminal `Pane`, the user can step between cited files (next/previous controls or file tabs when more than one file is loaded) while keeping each file's hunks compact.
- **Output cap:** To stay within what a person can hold at once, each preview caps total rendered lines per hunk and per invocation (defaults chosen during the PoC, e.g. 60 lines per hunk and 150 lines total), reporting any truncated line count explicitly and offering a narrow-range follow-up hint rather than flooding the terminal.

## Terminal rendering and state

- **Pane lifecycle:** User-triggered `$.ui.open({ id: 'source-preview', title: 'Source', focus: true, closeOnEscape: true })` opens the pane at any terminal width ([`interface.md#when-a-pane-waits-for-a-wider-terminal`](https://code.claude.com/docs/en/plugins/mods/interface#when-a-pane-waits-for-a-wider-terminal)). `command.run` returns `{}` so the preview never enters Claude's prompt or transcript ([`api.md#add-a-command`](https://code.claude.com/docs/en/plugins/mods/api#add-a-command)).
- **Non-pane fallback:** If `$.ui.open` resolves with `{ isPlaced: false }` (for example, a terminal host without pane placement), the mod calls `$.ui.close({ id })` and prints every cited file header and its numbered excerpt hunks in argument or message order (under the same per-hunk and per-invocation output caps) via `$.ui.log(line)` one line at a time, which displays to the user without starting a model turn ([`api.md#show-something-without-starting-a-turn`](https://code.claude.com/docs/en/plugins/mods/api#show-something-without-starting-a-turn)) and keeps `immediate: true` usable.
- **Mod state:** Active preview entries (resolved file headers, hunks, active file index, truncation notices) are stored in declared `$.state` atoms (`types/index.d.ts`) so `ui.render` (`{ component: 'Pane', requestId: 'source-preview' }`) redraws cleanly on navigation and clears on `session.end`.
- **Visual and accessibility floor:** Terminal output follows `/user-interface:design` guidance referenced by [mod authoring](contracts/mod-authoring/README.md#boundary) (`NO_COLOR`, plain-text legibility without relying on color alone, keyboard dismiss via `Esc`).

## File resolution, security, and enablement

- **Path resolution:** Relative paths resolve against `$.session.root()` (falling back to `e.cwd` from `session.start`). Before reading, `$.fs.stat(path, { resolve: true })` checks `kind === 'file'` and a file-size ceiling so directories, missing files, and multi-megabyte blobs produce a one-line notice rather than hanging the hooks worker.
- **Workspace boundary:** Because `$.fs.read` in a mod bypasses Claude's permission rules ([ADR 0052 amendment](adr/0052-adopt-claude-code-mods.md#amendment-2026-10-25-where-the-guard-is-absent-and-what-it-never-covers)), relative citations verify `realPath` stays inside the resolved session root (failing closed if `realPath` is absent on `{ resolve: true }`, per the `FsStat.realPath` guard guidance in [`mods/types/claude-code.d.ts`](https://github.com/anthropics/claude-code/blob/main/mods/types/claude-code.d.ts)). Explicit absolute paths passed directly by the user are allowed only for regular files under the size cap and are never followed automatically from untrusted assistant text without confirmation or an explicit path argument.
- **No subprocesses, no `tool.check`, no network in v1:** v1 calls only `$.command.register`, `$.session.root`, `$.session.messages`, `$.settings.read`, `$.env.get`, `$.fs.stat`, `$.fs.read`, `$.state.*`, and `$.ui.*`, every one of which passes `sec-default` ([`mods/sec-default/README.md#the-rows`](https://github.com/anthropics/claude-code/blob/main/mods/sec-default/README.md#the-rows)). Diagnostics go strictly to `$.ui.log(msg, { to: 'debug' })`.
- **Per-hook enablement:** The plugin declares a boolean `source_preview_enabled` `userConfig` option (default `true`, since it starts no background process or network call) resolved in-process with the user layer winning over the repository's `<convention-home>/source-preview.yaml` (using the shared mod enablement helper once available, per [hook enablement](contracts/hook-enablement/README.md#the-per-hook-setting)).

## Degradation where the mod cannot run

No skill depends on this mod being installed or loaded. Where the mod cannot run, skills continue emitting their standard citations unchanged:

- **Cases where the mod does not load:** plugin disabled in `enabledPlugins`, `source_preview_enabled: false` (user or repository layer), `disableAllHooks`, `--safe-mode`, `--bare`, `allowManagedHooksOnly`, `allowManagedModsOnly`, Desktop sessions in WSL, headless `claude -p` / Agent SDK sessions, or Claude Code builds below `2.1.287` ([ADR 0052 consequences](adr/0052-adopt-claude-code-mods.md#consequences); [`overview.md#where-mods-run`](https://code.claude.com/docs/en/plugins/mods/overview#where-mods-run); [`overview.md#turn-mods-on-or-off`](https://code.claude.com/docs/en/plugins/mods/overview#turn-mods-on-or-off)).
- **Standing fallback (`/planning:interview`):** `/planning:interview` keeps its `citation_links` setting (`plain`, `vscode`, `file`, implemented in `plugins/planning/surface/round.py`). With `citation_links: vscode`, every citation renders as a clickable `vscode://file/<absolute-path>:<first-line>` link (or `vscode://vscode-remote/wsl+<WSL_DISTRO_NAME>/<absolute-path>:<first-line>` inside WSL). That fallback requires no mod and stays available even when the mod is installed.
- **Other skills:** Any skill citing `path:line` or markdown file links continues rendering those links verbatim; typing `/cite` when the mod is absent simply produces Claude Code's standard unknown-command response without breaking any workflow.

## Later work (outside v1)

Explicitly excluded from the first version and deferred until after v1 proves useful in daily terminal sessions:

1. **Hover and click triggers:** Intercepting clicks or hover events on citations in the transcript instead of running a slash command.
2. **Desktop app pane:** Dedicated Desktop app layout, styling, and `Link` integration ([`interface.md#link-in-the-desktop-app`](https://code.claude.com/docs/en/plugins/mods/interface#link-in-the-desktop-app)).
3. **Agent-curated summaries:** Summarizing long cited sections via a model call (`$.model` / skill integration) rather than displaying verbatim cited lines.
4. **Live web-page section previews (beyond PoC):** Fetching remote URLs and extracting anchored HTML/markdown sections via `$.http.fetch`, with caching, redirect header stripping awareness ([`api.md#reach-files-processes-and-the-network`](https://code.claude.com/docs/en/plugins/mods/api#reach-files-processes-and-the-network)), and untrusted-content framing.

## Deferred follow-ups

Per the owner's 2026-11-28 decision, the build slices below are recorded here rather than filed as new issues until open issues reach zero:

1. **Proof of concept (spike, `--plugin-dir`):** Build a minimal prototype mod proving in-place terminal preview for (a) one local file line/range and (b) one web page section via `$.http.fetch`, plus `claude plugin validate` and `claude plugin test` coverage of `$.ui.open` placement and `$.ui.log` fallback. Measure terminal readability, line-cap defaults, and `/cite` command-name availability.
2. **Full v1 marketplace plugin:** Package the dedicated plugin (`plugins/source-preview/`), wire per-hook enablement (`source_preview_enabled`) per [hook enablement](contracts/hook-enablement/README.md#the-per-hook-setting), implement single-line, multi-line, disjoint-span, multi-file, and last-message citation parsing, add `schemas/source-preview.schema.json`, `README.md`, and `claude plugin test` suite, and document optional `/cite` usage beside `citation_links` in `/planning:interview`.

## Upstream pointer metadata

- **As of:** 2026-11-28, Claude Code 2.1.332
- **Recheck trigger:** Claude Code changes `$.command.register` (`immediate`), `$.ui.open` placement rules, `$.ui.log`, `$.fs.stat` (`realPath`), or `sec-default` rows for the calls listed above.
