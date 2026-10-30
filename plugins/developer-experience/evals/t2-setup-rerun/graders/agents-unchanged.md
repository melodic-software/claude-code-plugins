---
type: regex
target: { source: file, path: AGENTS.md }
pattern: '^# tarnquill\n\n\.NET 10 solution: `src/Tarnquill\.Cli` \(the `tq` team CLI\), `src/Tarnquill\.Core` \(shared library\),\n`tests/Tarnquill\.Core\.Checks` \(a console project of checks; exit 0 means pass\)\.\n\n## Build and test\n\n- Build: `make build` \(runs `scripts/build\.sh`; `scripts/build\.ps1` on Windows\)\.\n- Check: `make check`\.\n- Run the CLI: `make tq ARGS="<command>"`\.\n\n<!-- BEGIN GENERATED: plugin-conventions -->\n- Before creating, changing or cleaning up CLIs, scripts or other developer tools, read `docs/conventions/developer-experience\.md`\. Use /developer-experience:build-cli to create a tool or change its interface, and /developer-experience:audit-tools to take stock of or clean up tools; a bug fix inside one needs neither\.\n<!-- END GENERATED: plugin-conventions -->\n(?![\s\S])'
---
