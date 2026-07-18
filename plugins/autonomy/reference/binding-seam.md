# Binding seam

Normative contract for how an adopting org maps the roles in `role-topology.md` (and every
per-capability contract that follows) to its real instances — repositories, trackers, tools,
policies. The contract defines the SHAPE of a binding; every concrete value is org-supplied.

## Binding shape

A binding is a written, schema-versioned record mapping contract vocabulary to org instances:
each topology role to a repository, each capability's seam to the org's chosen instance, plus
the org's declared postures (budget, substrate availability). Bindings carry a
`schema_version` field from v0 — consumers read the version before the body, and schema
changes are reviewed migrations.

## Resolution ladder

A consumer resolves the effective binding as an ADDITIVE layer merge — a later layer adds to
or refines earlier layers per value, never wholesale replacement:

1. **User-global base** — the consumer's own machine-level binding config.
2. **Org binding at the org-policy home** — the org's binding instance document. Reaching this
   layer requires an org-policy-home pointer, which persists in repo-local or user-global
   config; the fetch mechanism is the hosting platform's own CLI with the consumer's own
   authentication (the contract grants no credentials).
3. **Repo-local binding** — tracked config in the consuming repository (the concrete location
   is a tool-specific detail the setup capability documents). Per value, this layer overrides
   the org binding.
4. **Local overlay** — the consumer's untracked personal refinement of the repo-local layer.

A value no layer answers falls to the **setup interview**, which asks and persists the answer
into the repo-local layer so the next resolution is deterministic.

Terminal default when no org exists (solo adopter, no org-policy home): the merge degenerates
to the local layers, populated with free-tier defaults — zero paid dependencies.

## Known limitation

The org-policy-home pointer can go stale when an org moves its policy home. A consumer that
fails to fetch the org layer surfaces that failure (warned as not-considered) and falls to the
remaining layers or the interview rather than silently reusing a cached org binding; setup
re-records the pointer.

## Layout convention

Each capability this plugin ships lands exactly one contract document in `reference/` with its
owning work package. The convention states shape only — it enumerates no future filenames.
