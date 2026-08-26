# Treat the plugin, not the skill, as the encapsulation boundary for path citation

- Status: accepted
- Date: 2026-08-26

## Context

Two documents in this repository gave skill authors opposite instructions about citing a path
inside another skill, and both were being followed.

`docs/PLUGIN-PHILOSOPHY.md:337-342` prescribes the citation and regulates only its path form:

```text
Apply the same anchoring rule to bundled assets: one skill citing another skill's supporting file
writes the full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form, optionally paired with a
relative markdown link target for browsing on GitHub
```

`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:31` rules the
citation itself out, whatever form the path takes:

```text
A skill's `scripts/` directory is its declared entry surface. Harness surfaces, CI workflows, git hooks, and automation registries MAY path-cite `scripts/` entry scripts directly. **Sibling skills may NOT** — skill-to-skill stays slash-only. That outbound half of the asymmetry is out of scope for this inbound audit; a consuming repo that wants it enforced wires its own outbound gate.
```

and at `:25` defines every non-public file inside a skill as private, naming `context/`,
`reference/`, `actions/`, `evals/`, `templates/`, `*.schema.json`, and heading anchors.

A repo-wide encapsulation audit resolved 11,641 path citations across the tracked markdown corpus,
dropped 7,903 self-citations, and adjudicated the remaining 407 non-self citations into private
surfaces down to 89 violations across 35 skills in 25 plugins. Thirty of the 89 are sibling-skill
reaches written in the form the philosophy document prescribes.

That makes the 89 not a call-site defect. Rewriting them while the doctrine that produced them
stands would leave the repository self-contradicting, and the citations would come back on the next
authoring pass. The question is which document is wrong.

## Decision

**The plugin, not the skill, is this repository's unit of distribution, and the encapsulation
boundary follows the unit that ships.**

The contract's rationale is rip-and-paste portability, stated at the skill-directory level in
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:27`:

```text
This guarantees skills are rip-and-paste portable: moving `.claude/skills/<name>/` into another repo carries every implementation detail with it; nothing outside the skill depends on internal layout.
```

Nothing in this repository ships that way. Measured on the tree: 71 plugin directories, 71
`plugins/<p>/.claude-plugin/plugin.json` manifests carrying exactly one `version` each, 71
`.claude-plugin/marketplace.json` entries each sourced at `./plugins/<name>`, 235 skill directories,
**zero** per-skill manifests, and **no `.claude/skills/` directory in this repository at all**. A
consumer enables a plugin. Two skills in one plugin cannot be separated by any installation a
consumer can perform, so a citation between them cannot arrive at an absent file.

Four clauses follow, and all four are load-bearing.

1. **Intra-plugin citation into a sibling skill's private surface is legal here.** "Intra-plugin"
   means the citing file sits under `plugins/<p>/` and the cited skill is `plugins/<p>/skills/<s>/`
   for the same `<p>`. It covers sibling skill bodies, plugin-level `context/`, `reference/` and
   `agents/` docs, and plugin READMEs.
2. **Cross-plugin path citation into another plugin's skill privates remains a violation.** Plugins
   install independently, so the cited path can genuinely be absent at runtime. This is the case the
   contract is actually about. The same limit applies to anything outside `plugins/`: `docs/**` and
   `.claude/rules/**` cite skills by slash invocation, never by path.
3. **A citation that does not resolve from the base its own form implies is a defect, whatever its
   form and wherever it sits.** This clause is not decoration. See correction 1.
4. **Heading anchors stay private even intra-plugin.** An anchor binds body structure rather than
   file layout, and renaming a heading is exactly the refactor the contract protects. The
   distribution-unit argument does not reach it.

Measured against the 89: **55 dissolve, 34 remain.** The 34 are 24 cross-plugin, 8 non-resolving
intra-plugin, and 2 heading anchors.

## What the measurement corrected, and why a reader needs it

The ruling was drafted first and then measured against all 89 violations, with the classification
pass instructed to say if the evidence contradicted it. It did, on four points. The conclusion
survived; several of the arguments given for it did not. They are recorded here because a reader who
sees only the conclusion will re-make them.

### Correction 1. The bare-relative clause was factually wrong and is withdrawn

The draft ruling kept 49 findings alive on the grounds that a bare relative cross-skill path "stays
a defect on the philosophy doc's own reasoning". It does not. The doctrine condemns one specific
shape, at `docs/PLUGIN-PHILOSOPHY.md:341-342`:

```text
A bare `context/…`-style path is reserved for a skill's OWN supporting files; it resolves against
the citing skill's directory, so a cross-skill citation written that way points at a file that is
not there.
```

That is `context/x.md` written with **no** `../` prefix from inside a skill. **Zero of the 89
violations use that shape.** The 33 relative intra-plugin citations all compute a correct `../` path
and all 33 resolve on disk, verified individually. Applying the doctrine's breakage claim to them is
a category error.

What is genuinely broken is a shape the draft never named: 8 citations in `plugin-root` form,
`skills/<s>/<path>` written from a plugin-level `reference/` directory, where the implied base is
the plugin root but the real base is the citing file's own directory. Clause 3 exists to catch
those.

### Correction 2. The contract's licence to relax is weaker than the draft claimed

The draft cited
`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md:3` as
authorizing the ruling. The full sentence is:

```text
A consuming repo may layer its own conventions on top, but the surfaces and carve-outs below are what the detector implements.
```

The second clause reasserts the detector against whatever is layered. The sentence permits the
ruling; it does not authorize it, and quoting half of it overstated the case. This decision rests on
the distribution-unit evidence above, not on that sentence. It is a **deliberate narrowing of a
stated guarantee**, not a correct reading of the contract, and it is recorded as one.

### Correction 3. The blast radius is 65, not 30

The draft said the decision blocks 30 violations, the sibling-skill-reach class, and leaves 59
unaffected. Both halves are wrong. Only 26 of the 30 sibling reaches are intra-plugin; the other 4
cross a plugin boundary and are untouched. And "intra-plugin" as defined also reaches 16 plugin
README citations and 23 plugin-level doc citations that the draft counted among the unaffected.
Recomputed split: **65 INTRA, 24 CROSS.**

The 16 plugin READMEs are the substantive thing this decision does, and the draft never discussed
them. The contract names READMEs explicitly as external consumers. Under the distribution-unit
reasoning they are not external, because a plugin's README ships with the plugin. That consequence
is accepted deliberately here rather than absorbed unnoticed.

### Correction 4. The corpus contains no instance of the harm the contract predicts

Across 89 adjudicated violations and 35 leaked skills, **no cited path is missing from disk**. Both
heading anchors resolve. The schema file exists. No skill in this repository has yet renamed a
private file out from under an external citation.

This is recorded rather than argued from, because it cuts both ways: it weakens the urgency of
remediating the 34 that survive, and it equally weakens any claim that the 55 dissolved citations
were doing damage.

### The real defect class the audit found instead

**Ten of the 89 citations do not resolve from the base their own form implies.** The target file
exists; the address written for it does not reach it. All ten are bare code spans, so none renders
as a broken link and nothing greps red, but an agent told to open the path fails on all ten. Eight
of the ten are intra-plugin, which is the case this decision legalises: **proximity did not prevent
them.**

The sharpest single piece of evidence is inside one plugin. `plugins/discovery` cites the same three
targets twice, in two plugin-level docs, one form working and one not.

`plugins/discovery/reference/parent-contract.md:15`, which resolves:

```text
| `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md` | explore-only: the collision rule, the six-dimension cost of a re-dispatch, that family's ladder |
```

`plugins/discovery/reference/topic-docs.md:88`, which does not:

```text
`skills/explore/reference/dispatch.md`, `skills/research/context/dispatch.md` and
```

Same plugin, same targets, one anchored and correct, one bare and unresolvable. That is why clause 3
is binding rather than advisory: legalising the intra-plugin case without also requiring a
resolvable form produces drift inside a single plugin, and already has.

Two of the ten sit in the doctrine document itself, at `docs/PLUGIN-PHILOSOPHY.md:596` and `:1071`,
writing a path with no resolvable base in the same file whose lines 341-342 forbid exactly that. The
first is a live Convention-registry row other plugins consult:

```text
| Fresh-eyes declaration pattern contract | `skill-quality` plugin (`skills/check/reference/fresh-eyes-declarations.md`) |
```

The plugin name carries the base in prose. The path alone resolves against nothing, and this
repository ships two plugins with a `check` skill (`skill-quality` and `instruction-placement`), so
the token is genuinely ambiguous. Both lines are defective under any reading of this decision.

## Where the convention is written down, and where it is not

The classification pass recommended a repo-level `docs/conventions/` entry, on the grounds that
`public-surface-contract.md` ships inside a plugin to other repositories and claims applicability
"to any repo with `.claude/skills/`", so editing it would export this repository's relaxation to
everyone who installs `docs-hygiene`.

That recommendation was **not** taken literally, and the departure is recorded here so it is chosen
rather than inherited. The relaxation was written into both documents instead:

- `docs/PLUGIN-PHILOSOPHY.md` states the cross-plugin limit it previously omitted, which is how 30
  call sites came to read blanket permission into it, and states the anchor limit.
- `public-surface-contract.md` gained a conditional carve-out rather than a relaxation. It is gated
  on the consuming repo actually being built that way (one manifest and one version per plugin, no
  per-skill manifest, no installation path that separates two skills in one plugin) and on that repo
  having declared the convention. A repo that has declared nothing gets the unrelaxed contract.

The gate is what keeps the export from happening, and it is the whole reason the carve-out is
acceptable in a shipped file. A future edit that removes the gate re-opens correction 2's objection
in full.

## Consequences

- **55 citations dissolve with no edit**, including all 16 plugin READMEs. **34 remain**, none of
  them applied as of this record. They are inventoried, with `path:line` and citation form, in
  [`docs/specs/docs-hygiene-sweep-unapplied-remediations.md`](../specs/docs-hygiene-sweep-unapplied-remediations.md).
- **The detector was not changed.**
  `plugins/docs-hygiene/skills/audit-encapsulation/scripts/detect.sh` and the skill's filter
  taxonomy are untouched, so a raw run still surfaces all 65 dissolved citations as candidates. The
  relaxation lives in the contract prose the agent applies when classifying, which is exactly what
  that contract's own line 3 warns about: the surfaces below are what the detector implements.
  Anyone re-running the audit will re-see the 65 and must apply this record to dismiss them.
  Encoding the carve-out mechanically is open work, not done work.
- **This decision does not license the form.** An intra-plugin citation is legal and still has to
  resolve. The anchored `${CLAUDE_PLUGIN_ROOT}/skills/<other>/<path>` form is what makes it resolve
  from any base; 57 intra-plugin citations do not use it today, 8 of which are broken because of it.
  Normalising the other 49 is tidy-up, not a defect.
- **Anchors are under-counted and the clause is therefore under-enforced.** Only 2 heading-anchor
  violations were found, both written as `#fragment`. Citations that pin a section by quoting its
  title in prose bind body structure just as tightly and break just as silently, and are not
  mechanically detectable. `plugins/source-control/skills/worktree/SKILL.md` publishes an anchor as
  the plugin fleet's canonical address for one invariant, which is an argument for a narrow anchor
  carve-out that this record declines to open.
- **Re-opens if** this repository ever ships or versions a skill independently of its plugin, or
  adds a `.claude/skills/` tree, since both premises of the distribution-unit argument would fail.
  It does not re-open on a request to relax cross-plugin citation: that is the case the contract is
  about and the evidence here does not touch it.
