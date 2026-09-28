# audit-enforceability: Unicode NFC/NFD stub-home fence parked

## Decision

**Parked — known gap; Unicode NFC/NFKC until funded.** This repository does not close the
stub-home fence's Unicode-normalization hole
([#3934](https://github.com/melodic-software/claude-code-plugins/issues/3934)). The shipped
ASCII/case fold and inode walk stay as they are. The gap is documented here and in the
existing comments on `fold_path` / `may_be_within`.

**Claim:** `fold_path` covers CASE, not Unicode NORMALIZATION; on APFS and HFS+ an NFC versus
NFD spelling of an absent directory is one directory, so the absent-ancestor escape remains
reachable at ladder rungs 2–4 when a consumer supplies `--out` and `--scan-dir` independently.
NTFS and ext4 treat the pair as distinct, so a fold that equated them would over-refuse there.
**Basis:** #3934 (derived from the fold's definition plus documented APFS/HFS+ behavior; not
executed — available hosts were byte-exact); comments at
`plugins/review/skills/audit-enforceability/scripts/emit-stubs.sh` (header ~51–56 and
`fold_path` ~352–355). **As of:** 2026-09-28. **Recheck:** an operator funds NFC/NFD fence work
on a normalizing volume (APFS or HFS+) and unparks #3934.

## Known gap (documented, not closed)

`fold_path` maps ASCII letters to upper case and every run of anything else to one
placeholder. Precomposed `é` (NFC, U+00E9) yields one placeholder; decomposed `e` + combining
acute (NFD, U+0065 U+0301) yields `E` plus a placeholder. Those strings differ, so the fold
reports two directories.

On APFS and HFS+ they are one directory. When the ancestor does not yet exist, the `-ef` arm
cannot settle identity (nothing on disk). Stubs can then land inside `--scan-dir` at exit 0.

This is defense in depth, not a live corruption of the fix pass: a stub declares
`type: enforceability-stub` and the fix pass admits only `type: review-findings`. It is
unreachable through the skill's own home composition (both homes from the same charset-sanitized
slug). It is reachable when a consumer supplies the two homes independently (rungs 2–4).

NFKC is the same class of unpaid fold (compatibility equivalents), not a separate funded
slice.

## What a funded close would owe

Acceptance stays on #3934: refuse an NFC/NFD pair of the same absent directory on a
normalizing filesystem at the same exit code as when it exists; do not over-refuse genuinely
distinct normalization pairs on NTFS/ext4; skip the test on byte-exact CI with a stated
filesystem reason; refresh the `emit-stubs.sh` comments; bump `plugins/review`.

## Rationale

- Closing the hole needs a host whose filesystem folds NFC/NFD. CI and the available
  verification hosts do not. Implementing a fold untested on APFS would guess.
- Equating NFC and NFD everywhere would over-refuse on NTFS and ext4, which treat the names as
  distinct directories.
- The load-bearing exclusion (stub type versus findings type) still holds if the fence is
  bypassed.

## Revisit when

- An operator funds a macOS (or other normalizing-volume) probe host and unparks #3934, or
- `scripts/check-shell-portability.sh` drops macOS as a target platform (the hole's relevance
  here).

## Prior requests

- #3934 (2026-09-28): stub-home fence Unicode normalization remainder after #3927; drain
  shipper documents the known gap and parks NFC/NFKC until funded (fold unchanged).
