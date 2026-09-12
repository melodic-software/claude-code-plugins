# Declare a canonical-plus-copies cluster as one arrow line

- Status: accepted
- Date: 2026-09-11

## Context

`scripts/cross-plugin-source-registry.txt` declares the replication this
repository does on purpose, one path-within-plugin per line, and three readers
key on that shape: the drift checker (`scripts/check-cross-plugin-source-drift.sh`),
the code-metrics replica collapser (`replica-collapse.py`), and the
duplication audit's exclusion filter (`registry-filter.py`). A path-within-plugin
cannot name a canonical copy that lives outside every plugin, so the eighteen
byte-identical copies of `hook-utils.sh` (root `lib/` plus seventeen plugins)
survived the duplication audit as one class with eighteen instances: the
seventeen plugin copies matched the line and the root copy did not.

## Decision

**A registry line containing ` -> ` is a cluster line:** the text before the
arrow is the root-relative canonical copy, the whitespace-separated tokens
after it are the members, each a literal root-relative path or a gitignore-style
glob (`lib/hook-utils.sh -> plugins/*/hooks/hook-utils.sh`). The duplication
filter excludes a clone class when every instance is the canonical or matches a
member and the instances sit in pairwise distinct directories; the drift
checker and the replica collapser skip the line, because they key clusters by
path-within-plugin and a root path is not one. A plain line keeps its meaning,
taken whole with any spaces. Lines are tried in file order and the first match
wins.

## Why

The registry is a contract every reader parses, so its grammar is hard to
change once lines exist. Splitting on whitespace was rejected: the drift
checker deliberately protects a registered path that contains a space, and a
second file or a YAML registry would have doubled the surface every reader
resolves. A marker that cannot occur in a path-within-plugin (` -> `) lets the
readers that do not understand a cluster ignore it with one test and lets the
one reader that does carry the whole class, canonical included, as a single
exclusion the report names by its line.
