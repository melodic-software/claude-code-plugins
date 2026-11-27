---
description: "Container rename with a TOML manifest: the package folder moved from packages/ledger-sync to packages/ledger-bridge, and its pyproject.toml still declares name = \"ledger-sync\", the one stale reference in the repository. The folder and manifest make this a container rename, the mode that suppresses bare-token residue, so the declaration is found only through Form 14's `=`-delimited TOML alternative and the manifest exemption. Written from rename-references context/patterns.md Form 14 (the TOML declaration bullet) and Phase 0b's mode ladder (a package or plugin manifest as container evidence)."
tags: [docs-hygiene, rename-references, container-mode, scaffold]
runs: 3
max_turns: 40
timeout_seconds: 900
allowed_tools: [Skill, Read, Glob, Grep, TodoWrite]
expected_outcome: "The reply lists packages/ledger-bridge/pyproject.toml, line 2, name = \"ledger-sync\", as a reference that still needs changing. No file is edited."
---

I renamed our Python package from ledger-sync to ledger-bridge and moved its folder from packages/ledger-sync to packages/ledger-bridge. Before I open the PR, find everything in the repo that still points at the old name. Don't edit anything; list every place that still needs changing, with file and line.
