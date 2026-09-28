---
description: "Report a shell-less spawn plan for typescript-language-server. Read-only, performs zero mutations. Use when: 'typescript-language-server .cmd', 'TypeScript language server will not start on Windows', 'DEP0190'."
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: anytime
  summary: Report a shell-less typescript-language-server spawn plan
---

## Purpose

Report how this plugin will start `typescript-language-server`, then stop.
The npm `bin` on Windows is a `.cmd` file. This plugin does not spawn that
file and does not set `shell`.

Run:

```shell
node "${CLAUDE_PLUGIN_ROOT}/bin/typescript-lsp-stdio.mjs" --probe
```

Exit 0 means `status` is `ready`. Exit 2 means `blocked`. Without `--probe`
the process stdout is the language-server stream, so do not omit the flag
when you only want the report.

## How to read the report

- `shell` is `false`.
- `mode` `node-cli` means `command` is the absolute `node` binary (`node.exe`
  on Windows, `process.execPath`) and `args` is `lib/cli.mjs` then `--stdio`.
- `mode` `path-executable` means `command` is a real executable named
  `typescript-language-server` (on Windows, `typescript-language-server.exe`)
  and `args` is `--stdio`.
- `rejected` lists `.cmd`, `.bat`, and `.ps1` paths that were not spawned.
- `command` never ends in `.cmd`.

When `status` is `blocked`, report `reason`. The host install is:

```shell
npm install -g typescript-language-server typescript
```

Do not edit the user `PATH` or turn on `shell` for the `.cmd`. A ready plan
uses `node` plus `lib/cli.mjs`, which does not require the `.cmd` name to be
on `PATH`.

## Claim

TypeScript on Windows starts as `node.exe` plus the absolute path of
`typescript-language-server` `lib/cli.mjs` and `--stdio`, or as a real
`PATH` executable named `typescript-language-server`. The npm `.cmd` shim is
never the spawned file, and `shell` is never set.

## Basis

- Claude Code's TypeScript binary name is `typescript-language-server`, and
  the documented install is `npm install -g typescript-language-server typescript`:
  [Code intelligence plugins](https://code.claude.com/docs/en/plugins/code-intelligence).
- npm package `typescript-language-server` 6.0.1 maps that bin name to
  `lib/cli.mjs` (registry `bin` field fetched 2026-09-28). On Windows a package
  `bin` is a `.cmd` file:
  [package.json bin](https://docs.npmjs.com/cli/v11/configuring-npm/package-json#bin).
- `.bat` and `.cmd` files cannot be launched with `execFile`. `spawn` with
  `shell` set is not recommended (DEP0190):
  [Spawning .bat and .cmd files on Windows](https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows).
- `CreateProcessW` runs a batch file only through `cmd.exe`, and appends
  `.exe` when the application name has no extension:
  [CreateProcessW](https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw).
- LSP `command` and `args` substitute `${CLAUDE_PLUGIN_ROOT}`:
  [Plugin manifest reference](https://code.claude.com/docs/en/plugins/manifest-reference).

## As of

2026-09-28. `typescript-language-server` 6.0.1 on the npm registry. The Claude
Code, npm, and Node pages above were fetched the same day.

## Recheck

When the code intelligence install command changes, when the npm `bin` field
stops pointing at `lib/cli.mjs`, when npm stops shipping Windows `bin` entries
as `.cmd` files, or when the Node child_process page gains a shell-less `.cmd`
launch.

## Gotchas

- Spawning the bare name `typescript-language-server` on Windows selects the
  `.cmd` through `PATHEXT`. This adapter either spawns `typescript-language-server.exe`
  or `node.exe` with the absolute `cli.mjs`.
- `shell: true` is the Node-documented way to run a `.cmd`, and it is the
  warning DEP0190. This plugin does not use it.
- Installing both this plugin and `typescript-lsp@claude-plugins-official`
  attaches two servers to TypeScript files. Use one of them.
