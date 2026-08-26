# L4 encapsulation. Leaked skills in `plugins/discovery`

7 violations into three skills (`explore`, `research`, `trace-intent`), all from plugin-level
surfaces in the same plugin: `reference/parent-contract.md`, `reference/topic-docs.md`, and the agent
definition `agents/intent-tracer.md`. Agent definitions are named explicitly in the contract as
external consumers.

**Leak kind:** private subdir (7 of 7).

The shape here is different from the other plugins in this lane, and it matters for remediation.
`reference/parent-contract.md` is a deliberate anti-duplication doc: it hoisted five statements out
of three skills and then wrote a table saying which skill still owns which family-specific rule.
That table is a routing index, and its rows currently spell private file paths. The index itself is
correct and worth keeping. Only its addressing is wrong, so every one of these is **Path B. route**,
with no promotion needed. Each of the three skills has a public slash invocation
(`/discovery:explore`, `/discovery:research`, `/discovery:trace-intent`) that names exactly the
family the row is about.

## V-disc-01, V-disc-02, V-disc-03. `plugins/discovery/reference/parent-contract.md:15-17`

**Owning skills:** `discovery:explore`, `discovery:research`, `discovery:trace-intent`.
**Private surfaces:** `explore/reference/dispatch.md`, `research/context/dispatch.md`,
`trace-intent/context/dispatch.md`.

Verbatim:

```text
| `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md` | explore-only: the collision rule, the six-dimension cost of a re-dispatch, that family's ladder |
| `${CLAUDE_PLUGIN_ROOT}/skills/research/context/dispatch.md` | research-only: the coverage ledger, the fan-out sub-slice rule, that family's ladder |
| `${CLAUDE_PLUGIN_ROOT}/skills/trace-intent/context/dispatch.md` | intent-only: the reason-per-skip check that stands in for a coverage ledger, why a thin tier census is a pass, that family's ladder |
```

The table header on line 11 reads `| File | Owns |`, which has to change with the rows.

**Replacement text** (lines 11 and 15-17; line 13's `**this file**` row keeps its cell unchanged):

```text
| Surface | Owns |
```

```text
| `/discovery:explore` | explore-only: the collision rule, the six-dimension cost of a re-dispatch, that family's ladder |
| `/discovery:research` | research-only: the coverage ledger, the fan-out sub-slice rule, that family's ladder |
| `/discovery:trace-intent` | intent-only: the reason-per-skip check that stands in for a coverage ledger, why a thin tier census is a pass, that family's ladder |
```

## V-disc-04, V-disc-05, V-disc-06. `plugins/discovery/reference/topic-docs.md:88-89`

**Owning skills:** `discovery:explore`, `discovery:research`, `discovery:trace-intent`.
**Private surfaces:** the same three dispatch files. Three cites across two lines.

Verbatim:

```text
`skills/explore/reference/dispatch.md`, `skills/research/context/dispatch.md` and
`skills/trace-intent/context/dispatch.md`.
```

**Replacement text:**

```text
`/discovery:explore`, `/discovery:research` and
`/discovery:trace-intent`.
```

The surrounding sentence ("the parent acts on it at the `persistence: by-value` rung of each
family's recovery ladder") already reads correctly against the slash form, since the ladder is a
behavior each skill performs rather than a document the reader opens.

## V-disc-07. `plugins/discovery/agents/intent-tracer.md:191`

**Owning skill:** `discovery:trace-intent`. **Private surface:** `context/artifact-shape.md`.

```text
  `${CLAUDE_PLUGIN_ROOT}/skills/trace-intent/context/artifact-shape.md`, so a consumer can grep
```

This one is not purely a routing cite: the agent is told the YAML header shape is *defined* in that
file, so the agent has a content dependency on a private surface. The sidecar header format is also
consumed downstream ("so a consumer can grep headers for a tier"), which is the signature of shared
vocabulary rather than skill-private detail.

**Preferred remedy, Path A within the plugin:** promote the sidecar YAML header definition to
`plugins/discovery/reference/artifact-shape.md`, alongside the existing plugin-level contract docs,
and have `trace-intent` cite it from inside.

**Replacement text (post-promotion):**

```text
  [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-shape.md`](../reference/artifact-shape.md), so a consumer can grep
```

**Replacement text (route-only, if the promotion is deferred):**

```text
  the sidecar header `/discovery:trace-intent` defines, so a consumer can grep
```

## Cross-lane observations

- L3 (SSOT): `reference/parent-contract.md` is itself the product of a prior dedup pass. If L3 finds
  the three `dispatch` docs still share ladder text, the fix belongs in that file, not a new one.
