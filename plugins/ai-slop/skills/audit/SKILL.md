---
description: "Audit markdown prose for AI-writing tells (slop): em dashes (zero-tolerance by default), emoji formatting, AI vocabulary, negative parallelisms, citation artifacts, plus a judgment rubric for puffery, vague attribution, and promotional tone. Use when: 'check for AI slop', 'de-slop this doc', 'find AI tells', 'does this read AI-written', 'remove em dashes', or before publishing agent-written prose. Read-only by default; 'fix' as an explicit argument applies rewrites behind a semantic-diff guard. Empty target audits the repo's tracked markdown, high-impact and high-velocity files first."
argument-hint: "[audit|fix] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(git:*)", "Bash(grep:*)"]
---

## Status

Tracer-bullet skeleton (plan phase 2). The deterministic detector and its contract are live;
the full audit flow, judgment rubric, findings-file persistence, and the guarded `fix` action
land in plan phase 5. Until then this skill runs the detector and reports its output.

## Detector

`${CLAUDE_SKILL_DIR}/scripts/detect.sh [file ...]` scans markdown prose for the mechanical rules
in [`reference/catalog.md`](reference/catalog.md) (entries with `v1: script`). No arguments scans
the repo's tracked markdown. `--paths-file <f>`, `--offset N`, `--limit N` chunk large corpora.
Output is line-oriented and parseable: `Finding:` rows with `rule=`, `file=`, `line=`, `fired=`,
and `excerpt=` fields, then `Summary` rows with per-rule finding and declined counts.

Configuration resolves from `.claude/ai-slop.json` per the config-cascade convention (user-global,
team, local overlay). In-file opt-out markers and their semantics: see the plugin README.

## Interim usage

1. Run the detector on the target (or bare for repo-wide).
2. Read the `Finding:` rows and report them to the user grouped by file, with the fired condition.
3. Do not edit files: this skill is read-only until the `fix` action ships.
