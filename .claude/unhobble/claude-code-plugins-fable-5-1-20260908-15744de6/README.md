# unhobble experiment: Fable 5.1 bare baseline

Durable mirror for one run of `/claude-config:unhobble` (experiment id
`claude-code-plugins-fable-5-1-20260908-15744de6`). The canonical experiment state lives in the
plugin data directory on the machine that ran the snapshot; this directory is the tracked copy
that survives a reclaimed cloud container. It lives under `.claude/` rather than the topic-docs
contract slice because the contract-slice gate red-lines any pull request that carries a slice,
and this mirror has to outlive the whole observe window.

| File | Role |
|---|---|
| `stumbles.md` | The observation ledger. Append a row whenever the bare model stumbles, or does something better. |
| `manifest-mirror.json` | The Phase 1 manifest with absolute paths tokenized: every surface, its class, what was stripped, how to restore it, and the four resolved decisions. |
| `evidence/research-D*.md` | Source-backed research memos behind decisions D1 to D3 (official docs fetched 2026-09-11). |
| `evidence/decision-*.md` | Two independent decision agents' verdicts, one on Fable 5.1 and one on Opus 5, which agreed on all four decisions. |

Observe phase: work normally on real tasks from fresh sessions on this branch and log stumbles.
Readd phase: restore only what the ledger defends with repeated same-cause rows, plus the register
hold recorded in the manifest, then close the experiment. Whether this directory is kept as the
experiment's record or removed at close is the readd phase's call.
