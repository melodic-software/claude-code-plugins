---
bump: patch
---

### Fixed

- The lane record script's write mode now reads every cited file at the merge-base with the default branch (or `--base <ref>`), as verify mode does, and exits 2 with nothing written when `--repo` is not the root of a git work tree or git fails there. It no longer drafts from working-tree text when git cannot confirm the repository.
- A stated command is refused when its section (from the nearest heading above to the next one, where a `#` line inside a code fence is no heading) holds a forbidding word, emphasis marks ignored, now including `cannot`, `no`, `forbid`, `prohibit`, `unless`, `without`, `only` and a `n’t` with a typographic apostrophe.
- The install refusal no longer looks past a wrapper or shell keyword at a command's start (`env`, `nice`, `timeout`, `if`, `then`, `!`, `eval`, `source`, `.`), refuses any shell expansion, checks every word for a package manager and its install verbs, and adds `npm ic`, `install-clean`, `init`, `create`, `python -<flags>m pip install`, `setup.py install`, `uv --with`, `go run <module>@<version>`, `poetry add` and `bundle update`.
- `/toolchain:check --propose-records` now has the session open each record pull request as a draft with a `Hold:` line saying a person reads the proposed record before it merges, since verify proves where each command came from, not that it suits its key.
- A record holding a control or invisible character anywhere, a comment included, fails verify.
- The draft is refused inside `~/.claude/ecosystems` reached through a symlinked or differently cased path.
- The lane record script refuses a `package.json` script when git cannot list the lockfiles at the merge-base, instead of counting every lockfile present. Unattended runs keep the resolution ladder's lockfile rule unchanged.
