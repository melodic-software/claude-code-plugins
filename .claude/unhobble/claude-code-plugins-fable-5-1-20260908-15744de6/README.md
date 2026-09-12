# unhobble experiment: Fable 5.1 bare baseline

Durable mirror for one run of `/claude-config:unhobble` (experiment id
`claude-code-plugins-fable-5-1-20260908-15744de6`). The snapshot ran in an ephemeral cloud
container; that container goes away when the session that opened pull request #4090 ends, and
the plugin-data copy of the manifest goes with it, so from then on this directory is the
canonical experiment record, not a copy. It lives under `.claude/` rather than the topic-docs
contract slice because the contract-slice gate red-lines any pull request that carries a slice,
and this record has to outlive the whole observe window.

| File | Role |
|---|---|
| `stumbles.md` | The observation ledger. Append a row whenever the bare model stumbles, or does something better. |
| `manifest-mirror.json` | The Phase 1 manifest with absolute paths tokenized: every surface, its class, what was stripped, how to restore it, and the four resolved decisions. |
| `evidence/research-D*.md` | Source-backed research memos behind decisions D1 to D3 (official docs fetched 2026-09-11). |
| `evidence/decision-*.md` | Two independent decision agents' verdicts, one on Fable 5.1 and one on Opus 5, which agreed on all four decisions. |

Observe phase: on 2026-09-12 the operator decided to merge #4090 so the window runs on main;
from that merge on, the bare state is the state of main (the manifest records this under
`checkout.merged_to_main`). Work normally on real tasks from fresh sessions on main and append a
row here whenever the model stumbles or does something better without an instruction.

Restoring the canonical state before readd: the skill compares `checkout.worktree_path` with the
resolved absolute checkout before every phase command and aborts on a mismatch, so the mirror
cannot be copied back verbatim. Copy `manifest-mirror.json` to
`${CLAUDE_PLUGIN_DATA}/unhobble/<experiment-id>/manifest.json` with the `<worktree>` token
replaced by the output of `git rev-parse --show-toplevel` and the `<CLAUDE_PLUGIN_DATA>` token
replaced by the resolved plugin data directory, copy `stumbles.md` alongside it, and create an
empty `backups/` directory next to them. Keep the tokenized copy here unchanged.

Readd phase: start a fresh branch off main, restore `.claude/rules/pr-body-contract.md` from
`git show c41c6422:.claude/rules/pr-body-contract.md` regardless of the ledger (register hold,
contested external-publication), restore only what the ledger defends with repeated same-cause
rows, re-render the AGENTS.md rules index with
`plugins/instruction-placement/scripts/render-index.sh write --file AGENTS.md`, set
`"phase": "closed"` in the manifest, and close the experiment. Every stripped surface is
recoverable from commit `c41c6422` (the pre-strip base); the manifest names each one. Whether this
directory is kept as the experiment's record or removed at close is the readd phase's call.
