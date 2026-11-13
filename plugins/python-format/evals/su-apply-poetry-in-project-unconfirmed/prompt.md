---
description: "apply in a Poetry repository with no in-project virtualenv setting and no .venv, asked where apply install-ruff would put Ruff. setup SKILL.md apply principles 1 (lines 144-146: identify the manager from the repo's markers), 2 (lines 147-151: record through the manager's dev-dependency add, e.g. poetry add --group dev ruff; a bare pip install into its environment is state the next sync or clean removes), 3 (lines 152-156: never create or mutate an environment) and 4 (lines 157-162: the hook resolves only repo-ancestor .venv interpreters or PATH, so Poetry, which defaults its environment to a cache directory, needs an in-project environment confirmed first; otherwise guide: enable in-project mode and recreate, or put ruff on PATH). The prompt asks rather than authorizing an install, so the run installs nothing and needs no network. Legacy expectations 5 (ambiguity stops with the astral URL) and 6 (re-probe after a remediation) are dropped: this fixture declares one manager and no remediation runs. A host with ruff on PATH may make check PASS the binary; the question still asks where install-ruff would put it. Needs --scaffold --allow-tools Bash Write Edit so the must-not graders can fail."
tags: [python-format, setup, apply, install-target, must-not, no-network]
max_turns: 16
timeout_seconds: 420
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: "No install, Poetry add/install/sync/lock, virtual environment creation, Write or Edit; the reply says Poetry's in-project setting is not confirmed here, that the hook resolves only a repo .venv or PATH, names poetry add --group dev ruff as the record-through-the-manager route once in-project mode is on, says a bare pip install would be removed by Poetry's next sync, and guides to enable in-project mode and recreate the environment or put ruff on PATH."
---

/python-format:setup apply

We use Poetry here and Ruff isn't in the project's environment. Where would `apply install-ruff` put Ruff in this repository, and would the hook find it there? Could I just `pip install ruff` into Poetry's environment instead?
