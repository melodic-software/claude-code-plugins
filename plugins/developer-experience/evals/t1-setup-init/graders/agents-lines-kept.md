---
type: regex
target: { source: file, path: AGENTS.md }
pattern: '(?:^|\n)# tarnquill\n(?:[^\n]*\n)*?\n(?:[^\n]*\n)*?\.NET 10 solution: `src/Tarnquill\.Cli` \(the `tq` team CLI\), `src/Tarnquill\.Core` \(shared library\),\n(?:[^\n]*\n)*?`tests/Tarnquill\.Core\.Checks` \(a console project of checks; exit 0 means pass\)\.\n(?:[^\n]*\n)*?\n(?:[^\n]*\n)*?## Build and test\n(?:[^\n]*\n)*?\n(?:[^\n]*\n)*?- Build: `make build` \(runs `scripts/build\.sh`; `scripts/build\.ps1` on Windows\)\.\n(?:[^\n]*\n)*?- Check: `make check`\.\n(?:[^\n]*\n)*?- Run the CLI: `make tq ARGS="<command>"`\.(?:\n|(?![\s\S]))'
---
