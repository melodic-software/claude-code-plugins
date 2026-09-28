# typescript-lsp

A Claude Code language server for TypeScript and JavaScript that starts on
Windows. The stock `typescript-lsp@claude-plugins-official` plugin sets
`command` to `typescript-language-server`. npm's Windows `bin` for that name
is a `.cmd` file, and Claude Code spawns language servers with no shell, so
the stock command never starts.

This plugin keeps the same extension map and the same `--stdio` argument. It
changes only the process that gets created.

## Install

Install the server and TypeScript next to a real `node` executable (`node.exe`
on Windows; the official Node installer and fnm both ship that executable):

```sh
npm install -g typescript-language-server typescript@6
```

Enable `typescript-lsp@melodic-software`. Disable
`typescript-lsp@claude-plugins-official` in the same session. Both plugins
claim `.ts`, `.tsx`, `.js`, and `.jsx`, and two servers for one extension
fight each other.

Nothing else is installed by the plugin. The global npm package is the
operator step, and this section is the only place it is written down.

## How it starts

`.lsp.json` sets `command` to `node` and `args` to the bundled launcher plus
`--stdio`. `${CLAUDE_PLUGIN_ROOT}` in those args is substituted by Claude Code
before the process starts.

The launcher looks for `node_modules/typescript-language-server/lib/cli.mjs`
beside PATH entries, inside an npm prefix layout (`bin/../lib/node_modules`),
in the text of a `.cmd` shim (`%dp0%` expanded), and under the stable fnm
alias directory. It does not treat an fnm multishell directory as a hardcoded
root. A hit on PATH is still used, because that directory exists for the
current process.

When the JavaScript file exists, the launcher spawns `process.execPath` with
that file and the original arguments. `shell` is false. On Windows, if the
only thing on PATH is an unparsed `.cmd`, the launcher spawns `cmd.exe` with
`/d /s /c` and the shim, which is the form that can run a batch file.

`vtsls` is the same shape (`bin` points at a `.js` file), so swapping servers
does not remove the need for this launcher.

## Verification

**Claim:** Claude Code can start `typescript-language-server` on Windows by
spawning `node` (resolved as `node.exe`) and passing `lib/cli.mjs`. Spawning
the npm `.cmd` name directly does not work, because a batch file is not an
executable. The same `node` plus JavaScript entry also works on Linux, where
npm's `bin` is a symlink, so one manifest covers both.

**Basis:** `typescript-language-server` 6.0.1 publishes
`"bin": { "typescript-language-server": "lib/cli.mjs" }` (`npm view`,
2026-09-28) and documents `npm install -g typescript-language-server typescript@6` plus
`typescript-language-server --stdio`
(<https://github.com/typescript-language-server/typescript-language-server/blob/master/README.md>).
npm's `bin` field creates a Windows `.cmd` that runs that file
(<https://docs.npmjs.com/cli/v11/configuring-npm/package-json#bin>). Node.js
documents that `.cmd` files cannot be launched with `execFile` and that the
supported path is to spawn `cmd.exe` and pass the `.cmd` as an argument
(<https://nodejs.org/api/child_process.html#spawning-bat-and-cmd-files-on-windows>).
`CreateProcessW` says a batch file runs only when the application is `cmd.exe`
and the command line is `/c` plus the batch name, and that a name with no
extension gets `.exe` appended
(<https://learn.microsoft.com/en-us/windows/win32/api/processthreadsapi/nf-processthreadsapi-createprocessw>).
Claude Code's plugin reference lists `command` as the language server binary,
substitutes `${CLAUDE_PLUGIN_ROOT}` in LSP `command` and `args`, and shows
`node` plus a plugin-root script as a server command
(<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-09-28, LSP
servers and environment variables). `@vtsls/language-server` 0.3.0 publishes
`"bin": { "vtsls": "bin/vtsls.js" }`, the same JavaScript-entry shape.

A workspace whose only TypeScript is 7.0.2 fails initialize with "provides no tsserver.js". The same launcher against `typescript@6` in that workspace returns a hover (`const n: number`). That is why the install line pins `@6`, matching the upstream README, until TypeScript's own LSP replaces this server.

**As of:** 2026-09-28

**Recheck:** a `typescript-language-server` or Node release that ships a
native Windows executable under the bin name, or a Claude Code release whose
changelog says language servers are spawned through a shell, or a plugins
reference change that stops substituting `${CLAUDE_PLUGIN_ROOT}` in LSP
`args`.

## Operator check

On a Windows desktop, open a `.ts` file in a real project after this plugin is
enabled and confirm the LSP tool answers hover, go-to-definition, and
find-references. This repository's tests prove the spawn plan and a stdio
handshake against a stand-in entry. They do not open Claude Code's UI.
