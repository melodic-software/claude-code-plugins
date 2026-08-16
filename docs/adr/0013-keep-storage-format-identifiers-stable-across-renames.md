# Keep storage-format identifiers stable across renames

- Status: accepted
- Date: 2026-08-16

## Context

Renaming `youtube-digest` → `video-digest` swept every user-facing name: the skill directory,
invocation, env-var namespace (`YOUTUBE_*` → `VIDEO_DIGEST_*`), temp-file prefixes, CI job id,
and npm package. Two literals survived the sweep by design: the on-disk epic queue directory
`youtube-watch` (under every consumer's `.work/` tree, holding committed slices and the shared
`claims/` namespace) and the acquisition lock directory `youtube-extraction-acquire-locks`
(the cross-process mutual-exclusion point). A future reader will wonder why a rename this
thorough left the two most visible "youtube" strings in place.

## Decision

An identifier baked into consumer-owned state or cross-process coordination is a
**storage-format identifier**, not a name: it changes only through a data migration with a
compatibility window, never through a naming-hygiene sweep. Renaming the epic directory
orphans every consumer's committed slices and splits the queue's claims namespace; renaming
the lock directory silently breaks mutual exclusion across the upgrade boundary (old and new
versions would lock different directories and acquire concurrently). Source identity therefore
also never becomes a directory level — it lives in slice metadata (`watch.json` `sourceUrl`),
so mixed-source batches share one queue root and the layout never migrates.

The trade-off accepted: permanent naming inconsistency (a `video-digest` skill writing to a
`youtube-watch` directory) in exchange for zero consumer-state migration. Every user-facing
path rendering derives from the resolved slice directory, never from the constant, so the
inconsistency stays out of prompts and displays.
