# Design principles — settled by the operator

## 1. Cite the source; never transcribe its values

The skill must **cite** official documentation and **measure** the consumer's own machine. It must
never bake in a token figure, a settings-key list, a bundled-skill inventory, or a threshold as
literal content. Every number in this research is a snapshot of CLI v2.1.232 on one machine on
2026-08-17, and every one of them will drift.

Concretely, this forbids:

- shipping "Workflow costs 7.9k" — the skill measures it, at the consumer's version, or says nothing
- shipping an inventory of bundled skills — it enumerates what is live
- shipping "the listing budget is 1% of context" — it detects saturation empirically
- shipping "these are the five Artifact levers" as a fixed list — it probes and reports what exists

And it requires: each mechanism claim carries its official URL, and the marketplace's existing
[upstream-drift convention](../../docs/conventions/upstream-drift/README.md) stamp discipline
governs anything that must be written down.

The one class of durable content is **method**: A/B differencing, bare-vs-scoped rule shape, the
budget-saturation check. Methods survive version churn; values do not.

## 2. Correct the source rather than inherit it

The course material is the *trigger* for this work, not its authority. Where research contradicts
it, the skill follows the research and says so plainly. Four places it is already wrong or
misleading at v2.1.232, all evidenced in `MEASUREMENTS.md` and the run artifacts:

| Source claim | Status |
|---|---|
| `/context` only gives category totals, so you need a request logger | **Outdated** — it itemises per-skill and per-agent with a `Source` column |
| Deferred MCP tools are a large saving when disabled | **Misleading** — deferral does not shrink the request; the schema ships every turn |
| Trimming skills reclaims their tokens | **False while over budget** — the listing is capped; freed budget is re-spent |
| The 17.9k→3.5k drop is a settings-file mystery | **Explained** — two tool schemas account for ~12.3k of it |

Its arithmetic also does not reconcile (categories sum to ~64k against a ~23k headline; the headline
delta is smaller than the MCP delta alone). Do not reproduce its tables.

What the source gets right and the skill keeps: the **framing** — this maximises the smart zone,
the space in which the model reasons, and is not a cost-minimisation exercise.

## 3. Report honesty categories

Every lever the wizard presents is classified, and the classification is load-bearing:

- **Removes weight** — bare-name deny, `disableWorkflows`, the `disableArtifact` family
- **Works but saves nothing here** — `skillOverrides` while the listing is over budget
- **Blocks without saving** — scoped deny rules; a runtime guard whose schema still ships
- **Vendor weight** — measurable, not reducible (built-in system-prompt text, tool-description prose)
- **Unverified / undocumented** — reported if detected, never recommended
  (per `claude-config:unhobble`'s existing `CLAUDE_CODE_SIMPLE=1` precedent)

A wizard that cannot say which category a lever is in must not offer that lever.
