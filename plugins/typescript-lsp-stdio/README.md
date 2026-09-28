# typescript-lsp-stdio

A Claude Code plugin that starts `typescript-language-server` for TypeScript
and JavaScript without launching npm's Windows `.cmd` shim.

## Install

```shell
npm install -g typescript-language-server typescript
/plugin install typescript-lsp-stdio@melodic-software
```

`node` must be the real Node executable (`node.exe` on Windows). The `.cmd`
named `typescript-language-server` does not have to be the process Claude
starts.

## Spawn

`.lsp.json` runs `node` on `bin/typescript-lsp-stdio.mjs`. The script then
does one of two things, both with `shell` false:

1. Spawns a real `typescript-language-server` executable already on `PATH`
   (`typescript-language-server.exe` on Windows) with `--stdio`.
2. Otherwise spawns the absolute Node binary on
   `typescript-language-server/lib/cli.mjs` with `--stdio`.

`/typescript-lsp-stdio:probe` prints that plan as JSON.

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

## License

MIT (SPDX-License-Identifier: MIT).
