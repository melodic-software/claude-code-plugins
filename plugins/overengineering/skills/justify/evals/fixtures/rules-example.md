> Fixture. A standing rules file of the kind a consumer loads by construction on every session,
> rather than on demand: it states the rule and nothing else, and no part of it is anything but
> instruction text.

# Migration files are append-only

A migration that has run anywhere other than a local machine is never edited. Correct it with a new
migration.

Editing one that has already run leaves two databases with the same recorded version and different
schemas, and nothing detects the divergence until a later migration fails on one of them.

A migration still only on a local machine may be edited freely. The dividing line is whether it has
been merged, because merging is what puts it on someone else's machine.

Rolling back is a new migration too. There is no down step in this project; a reversal is written
forward, so the history stays a list of things that happened rather than a thing that can be
replayed differently.
