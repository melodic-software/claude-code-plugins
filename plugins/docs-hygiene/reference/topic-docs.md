# Topic-docs placement: where the file-name findings land

How `/docs-hygiene:audit-file-names` and `/docs-hygiene:realign-file-names`
resolve where the rename plan lands in a consuming repository. Both skills read
this one document; neither bakes its own path.

Implements the topic-docs convention:
<https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>.
The contract owns the tier table, the concern-file schema, the slug spec, and
the lifecycle; this document binds this plugin's artifact to it.

## What this plugin writes

**Memory tier only, concern-scoped.** A rename plan's axis is the **branch**,
not a topic, so it sits under the memory root's `docs-hygiene/` concern name
rather than inside a topic slice:

| Artifact | Location (default) |
|---|---|
| the file-name rename plan | `.work/docs-hygiene/<branch-slug>/file-names.md`, never committed |

One stable filename per home, rewritten in place. A re-audit merges into it
rather than depositing a timestamped sibling.

The plan is process state that nothing outside this plugin enforces against,
which is what makes it memory-tier by the convention's placement question. It is
read back, by the realign, so durability inside the lane matters: losing one
loses the operator's accepted and declined decisions for that branch. It is
lane-local by design, so a sibling worktree or a cloud clone never sees it.
Decisions that must cross checkouts graduate to the tracked concern file, as
`file_names.exempt_paths` entries the realign offers and never takes.

Every other skill in this plugin writes to the tier its own body names, and none
of them writes here.

## Resolution (the contract's five-rung order, earlier wins)

1. `.claude/topic-docs.yaml` present, use its `memory_dir`:
   `<memory_dir>/docs-hygiene/<branch-slug>/`.
2. A location for this plugin's artifacts declared in the consumer's
   `CLAUDE.md` or `.claude/rules`, use it, and offer to persist it into the
   concern file (prose is an inference source, not the runtime authority).
3. An existing conforming layout inferred from the repository (a self-ignoring
   memory root already holding this plugin's artifacts), confirm with the user,
   persist to the concern file.
4. Ask once, one question with the recommended option first; persist the answer.
5. The documented default, `.work/docs-hygiene/<branch-slug>/`.

Only rungs 1 and 5 compose `docs-hygiene/<branch-slug>` themselves. Rungs 2 to 4
yield whatever location the consumer declared, inferred, or chose. **Resolve the
home, never assume its shape.** A skill that hardcodes the default reads or
writes a directory the other side never touched, and the realign's failure mode
for that is a clean "no plan found" stop indistinguishable from "no audit has
been run".

## The branch slug

The slug is the branch name with every character outside `[A-Za-z0-9._-]`
replaced by `-`. A detached checkout has no branch, so it slugs as
`detached-<short-sha>`; the artifact still records the real state in its
`branch:` frontmatter, which is what a consumer checks.

The mapping is lossy: two branch names can slug to one directory. That is why
the artifact's own `branch:` line, never its directory, is what proves which
branch it describes.

## The self-ignore guard

The memory root is checkout-local and never committed. Before the first write of
a session, confirm the resolved root is ignored by the consumer's git, following
the convention's guard, including its invalid cases. Where no checkout governs
the destination, the convention's own rule is that the guard does not run; where
one does and the root is not ignored, report the resolved destination and
persist nothing rather than committing a branch-local plan into the consumer's
history.

## Non-interactive runs

A run that cannot ask the user or persist configuration, a dispatched agent or a
scheduled lane, resolves the rungs that confirm or ask through the convention's
non-interactive collapse and surfaces the assumption it took in its summary.
Inventing an answer to those rungs resolves to a directory the realign never
reaches.
