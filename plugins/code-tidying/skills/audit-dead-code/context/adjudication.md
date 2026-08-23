# Adjudication reference

How a candidate becomes a verdict, and what the human gets to paste afterwards. The bounded loop
itself is in SKILL.md "Adjudication"; this file carries the evidence catalogue, the verdict rules,
and the native suppression formats.

## Evidence patterns

A detector sees the static call graph. Everything below is a way code is reached that no static
analyzer in the roster can follow — check each one before condemning a candidate.

| Pattern | What to look for | Typical language |
|---|---|---|
| String-name dispatch | the symbol's name appearing as a **string literal** anywhere in the repo — a handler map, a command table, a plugin registry | all |
| DI / serialization | container registration, `__init__` injection, a constructor invoked only by a framework, a field populated only by a deserializer | C#, Python, TS |
| Reflection | `getattr`, `globals()`, `importlib`, `Object.keys` over a module namespace, `eval` | Python, JS |
| Decorator / route registration | `@app.route`, `@click.command`, `@pytest.fixture`, `@task` — the decorator *is* the caller | Python |
| Config-declared entry point | a name referenced from `pyproject.toml`, `package.json` `scripts`/`bin`, a CI workflow, a Dockerfile, a systemd unit, a cron entry | all |
| Test-only usage | referenced only from a test file. Alive, but say so — a symbol whose only caller is its own test is a real finding of a different kind | all |
| Public API surface | an exported symbol of a published package, or a Go exported identifier. Not decidable from inside the repository | TS, Go, C# |
| Generated / templated code | a symbol emitted by a generator, or one a template writes by name | all |
| Shell dynamic invocation | `"$fn"`, `eval`, `trap ... name`, a dispatch `case` matching a command word to a function | shell |

Cheap checks first, in this order: a repo-wide literal search for the bare name (including inside
strings), then the config surfaces, then the framework-registration patterns for the candidate's
language. Stop at the first piece of real evidence.

The optional `LSP` assist is one more source, never a substitute: `findReferences` with
`includeDeclaration` hard-coded true means the dead threshold is `resultCount == 1`, and an import
counts as a reference, so a re-export still reads alive.

## Verdict rules

- **`dead`** — no static reference and no dynamic-usage pattern applies. Emitted at Tier 1.
- **`uncertain`** — a pattern *might* apply and the evidence does not settle it. Emitted at Tier 2.
  This is the honest verdict for most vulture candidates; do not promote one to `dead` to make the
  report tidier.
- **`alive`** — a specific reference or registration was found. **Never emitted as a record**, and
  every one **cites the evidence that saved it** in the prose report. An unevidenced `alive` is a
  guess wearing a verdict's clothes.

Tier drift is an alarm: a candidate that arrives at Tier 3 is detector drift — an output line no
parser recognized — and it is a bug report about the detector, not a finding about the code.

## Bounding the pass

- **Order:** git recency, **oldest-untouched first**. The script emits candidates in that order
  already. Neither detector offers a usable confidence key to order by instead.
- **The cap is a candidate cap**, so a file's block can be truncated mid-way. `Summary file:`
  reports what was emitted, not what exists.
- **The consent gate prints the candidate count and the cap** — never a fabricated time or token
  estimate. There is no measurement behind one.
- **Fan-out:** batch the capped set to fresh-context subagents. If spawn depth is exhausted, say so
  and adjudicate inline at the same cap. Silently shrinking the set is the failure mode to avoid.

## Suppression formats

The skill writes nothing. It emits ready-to-paste text and the human decides.

**knip** — `knip.json` (or the `knip` key in `package.json`):

```json
{
  "ignore": ["src/legacy/format.ts"],
  "ignoreExportsUsedInFile": true
}
```

Note that a `knip.config.ts` is a **code module** knip evaluates through jiti; the JSON form does
not cross that boundary and is the safer paste when either will do.

**vulture** — a whitelist file passed alongside the sources:

```python
# whitelist.py — names vulture must treat as used.
format_legacy_row  # adjudicated alive: dispatched by name from handlers.py
```

**A committed vulture whitelist raises `F821` (undefined name) under a consumer's ruff config.**
Say so whenever you emit one; the consumer either excludes the file in `ruff.toml` or keeps the
whitelist out of the linted tree.

**Go** — the analyzer directive on the declaration:

```go
//lint:ignore U1000 kept as the exported shape of the v1 API
func deadHandler() {}
```

**Shell / the grep lane** — no native suppression exists. Record the decision in a comment at the
definition, which is also what the next run's reader will see:

```bash
# audit-dead-code: alive — invoked by name from the dispatch case in main().
format_legacy_row() {
```

## What convergence means here

`dead` and `uncertain` verdicts are **session-scoped**: nothing on disk remembers them. The only
memory is the native suppression the human pastes. So the loop is: adjudicate a bounded batch →
paste the suppressions for what was settled → the next run's candidate list is shorter and reaches
code the cap had not yet touched. An `uncertain` left un-suppressed comes back as a candidate every
time, which is the honest cost of writing no file.
