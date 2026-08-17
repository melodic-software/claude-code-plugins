# local-markdown adapter — operations reference

The `local-markdown` adapter is **offline-only**: it is **NEVER a coordination
surface** and never invokes `gh` or `curl`. Coordination verbs still go through
the seam (`work-item-tracker.sh <verb>`; see [`../../CONTRACT.md`](../../CONTRACT.md)).
This file covers the local-markdown operational mechanics a skill needs and does
not restate the full contract.

## Resolve item ID

Seam verbs (`get-item`, `claim`, `renew-lease`, `link-blocks`, `add-sub-item`)
take a fully-qualified ID (`local-markdown:<owner>/<repo>#<N>` — CONTRACT.md
"ID grammar"); a bare `#N` is rejected. The default namespace is
`local/markdown`, so a typical id is `local-markdown:local/markdown#N`.
`create-item --repo <owner>/<repo>` overrides that namespace at create time.
Lookups key by number only; the owner/repo in the id is not re-validated
against the store. `cross_repo_edges` is `false` means there is no second store
to consult — not that a foreign-looking qualified id fails lookup.

The **seam** verbs (`list-frontier`, `get-item`, `create-item`) already emit the
qualified `id` — pass it straight through.

## Storage

`config.storage_dir` is required (no baked default). One markdown file per item
at `<storage_dir>/<number>.md`. A relative `storage_dir` roots against the
**binding file's directory**, not CWD (`lib/binding.sh`); an absolute path is
used as given. The store is single-writer files: `wit_next_number` is max
existing file number + 1 with no file lock.

## Claim / lease

Claim identity is `git config user.name`, then `$USER`, then `local`. The same
git user in two worktrees looks like the same holder. The lease handle is a
store-global `lease_comment_id` in the marker JSON (not a GitHub comment id);
`renew-lease` addresses that handle. The manifest declares `reclaim: false`;
invoking `reclaim` exits `6`. On expiry, `list-items` reports empty `assignees`
while `get-item` still shows the stored assignee.

## Branch, worktree, and lease confinement

The store is working-tree files, so items, leases, and ids are confined to the
tree that holds those files. Branch visibility, worktree copies vs a shared
absolute store, number races, and why this adapter is never a coordination
surface are the seam contract's "Branch, worktree, and lease confinement"
subsection under "local-markdown adapter" — do not treat this README as a
second copy of that fact set.

## List / frontier

There is no provider search syntax. Listing and frontier selection are seam
verbs only: `work-item-tracker.sh list-items` (raw candidates; `--state
open|closed|all`; `--repo` is accepted for interface parity and does not
re-target the single-namespace store) and the core-derived
`work-item-tracker.sh list-frontier`. Filter, search, and aggregation stay on
those verbs; do not invent a query language against the markdown files.

## Auth

None. The adapter touches no network and has no credential. Claim identity is
the git user name as under "Claim / lease" above.
