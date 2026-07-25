# Moved → `config-cascade`

This convention was renamed **`consumer-config-layering` → `config-cascade`** (#1188).

The contract now lives at
[`docs/conventions/config-cascade/README.md`](../config-cascade/README.md). Its raw URL:
`https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/config-cascade/README.md`.

This stub is a **compatibility tombstone**: earlier cached `code-tidying` (≤0.7.1) and `testing`
(≤0.3.1) plugin copies still fetch the old path, so it is preserved to avoid a 404 until those
installs update. New references must point at `config-cascade`; this file may be removed once the old
plugin versions are no longer in circulation.
