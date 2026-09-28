# Changelog

All notable changes to the `typescript-lsp-stdio` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0] - 2026-09-28

### Added

- Shell-less TypeScript language-server spawn ([#3537](https://github.com/melodic-software/claude-code-plugins/issues/3537)). `.lsp.json` starts `node` on `bin/typescript-lsp-stdio.mjs`. The adapter runs `node` on `typescript-language-server/lib/cli.mjs` with `--stdio`, or a real `typescript-language-server` executable already on `PATH` (absolute entries only). A `.cmd` shim is never the process. `/typescript-lsp-stdio:probe` reports the plan.
