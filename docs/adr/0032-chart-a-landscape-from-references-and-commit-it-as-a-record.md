# Chart a landscape from references and commit it as a record

- Status: accepted
- Date: 2026-09-11

## Context

`/architecture:map-landscape` charted only repositories that were local
checkouts, and it drew a relationship only where a collected fact in one
checkout named another. In a cloud session, or on any machine holding one
repository rather than a fleet, that yields a single box: this checkout names
nineteen other organisation repositories in its workflows, marketplace sources
and docs, and the skill saw none of them.

Two further defects came out of the same pass. The facts probe mixed runtime
and development dependencies, so a repository of shell and markdown whose CI
installs `ruff` reported a Python runtime. And the artifacts were rendered by
hand from collected JSON, so two runs over identical facts produced different
files and nothing recorded what had changed between them.

## Decision

**A repository's own references are the landscape.** A bare invocation charts
the current repository plus every repository its tracked files name, one hop
out. Edges are extracted by a script, typed by the syntax that carries them,
and counted; `--repos` and `--root` remain as explicit overrides. The working
directory is still never walked for nested repositories.

**Each edge type trusts exactly one syntax.** `uses-workflow` a workflow
`uses:` step, `installs-plugin` a marketplace source, `depends-on` a module
path, `cites` a github.com URL or a bare `owner/repo` whose owner matches the
subject's own. A single `owner/repo` regex over all tracked text is rejected.

**Runtime versus development is a scope axis, not a path bucket.** A manifest's
scope is read from the manifest, with one override: anything under a
dot-directory is development scope whatever its content says.

**The answer is committed as a record, and the artifacts derive from it.**
`landscape.json` holds facts and edges; both rendered artifacts are produced
from it by a script doing only reasoning-free work. A later run compares before
it writes and reports what moved, and `--check` makes that comparison a CI gate.

**A repository outside the subject's own owner is read-only reference.** It is
drawn and recorded, never written to, and never fetched from unless the
explicitly opt-in `--remote=all` is passed.

## Evidence

**Every surveyed dependency standard separates runtime from development on
scope, and none on path.** CycloneDX carries a `scope` field
(`required`/`optional`/`excluded`); SPDX types the relationship
(`RUNTIME_DEPENDENCY_OF`, `DEV_DEPENDENCY_OF`, `BUILD_TOOL_OF`,
`TEST_TOOL_OF`); npm splits `dependencies` from `devDependencies`; PEP 735
adds `[dependency-groups]`; the GitHub dependency-submission API takes
`scope: runtime|development`. A separate `ci_tooling` bucket keyed on path was
considered and rejected against this evidence.

**The dot-directory override has its own precedent.** GitHub Linguist vendors
`(^|/)\.github/` out of a repository's language statistics, on the same
reasoning: what a repository's automation installs is not what the repository
runs on.

**A naive reference regex is not merely imprecise, it is wrong on this
repository.** Over all tracked text, `owner/repo` matches `sponsors/…` from a
funding URL, `en/…` from a documentation path, and every `acme/billing` in
every test fixture. Each surviving edge type anchors on a syntax that only ever
names a repository, or requires the owner to match the subject's own.

**Committing the record is what makes drift reportable.** Without it each run
is a snapshot with no memory, and nothing distinguishes a system that was
removed from one that was never charted. Two fields are deliberately excluded
from the comparison: the collector's `path`, because a committed artifact
naming one machine's directory layout differs on every other machine that
regenerates it, and `last_touched`, because the subject repository advances its
own HEAD on every commit and a check lane red for that gets turned off.

## Consequences

A referenced repository that is not checked out is a node with edges and no
probed facts. That is the honest answer without `--remote`, and the portfolio
reports it as `unknown` rather than filling it in.

`cites` outnumbers every other edge type several times over on a
documentation-heavy repository. It means a name appears in tracked text and
nothing more; a high count is not a dependency.

The landscape is bounded at one hop. A repository named by a repository this
one names is not charted.
