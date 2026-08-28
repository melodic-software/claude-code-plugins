# Build graph notes

Written up after the third time someone asked why a missing file stops the whole run.

Widget Runner reads the manifest once, resolves every declared input to a concrete path, and
builds the dependency graph before it schedules a single task. A task whose inputs cannot all be
resolved is not scheduled and not skipped: it is reported as unresolvable, with the first
missing input named, and the run stops before any sibling task starts.

On our repository this happens most often after a rebase drops a generated file.

A cycle is detected during construction rather than at execution time. The runner prints the
shortest cycle it found, in declaration order, and exits without executing anything, because a
partially executed cyclic graph leaves a cache nobody can reason about afterwards.
