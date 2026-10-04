# Upstream source: trailofbits/skills

This page credits [trailofbits/skills](https://github.com/trailofbits/skills), the agent skill
collection published by Trail of Bits under CC-BY-SA-4.0, for the one part of this marketplace that
drew on it. Credit lives on this page only; the skill that drew on it carries no citation. The row
below links upstream at the pinned commit and holds our decision only, in our words; read upstream
at the link for what it says.

**Last audited upstream state:** `trailofbits/skills@82fe8226252622fa807643bdca1710901198553a` under `plugins/property-based-testing/` (upstream HEAD of `main` when read, committed 2026-09-28)

**Recheck trigger:** between the pinned commit and upstream HEAD, a path that a row below links
changes, or a unit under the scope is added or removed: re-audit the affected rows. `scripts/check-upstream-drift.sh` detects these
([upstream-drift convention, "Pinned git upstreams"](../conventions/upstream-drift/README.md#pinned-git-upstreams)).
Re-auditing moves the pin and records the outcome per row.

## License

The upstream is licensed [CC-BY-SA-4.0](https://creativecommons.org/licenses/by-sa/4.0/), a
share-alike license. Nothing from it was copied: no file is vendored here, and the guidance below
was written from scratch, with our own examples and our own ordering. The testing plugin therefore
stays MIT. A later edit that brings upstream wording into a plugin file would change that, so a
re-audit keeps the same rule: read upstream as data, write ours fresh.

## Attribution table

| Upstream (links at the pin) | Ours | Relation | Decision |
|---|---|---|---|
| [`property-based-testing` skill](https://github.com/trailofbits/skills/tree/82fe8226252622fa807643bdca1710901198553a/plugins/property-based-testing/skills/property-based-testing) | `testing:write`: the Step 0 route row in `plugins/testing/skills/write/SKILL.md`, `plugins/testing/skills/write/context/property-based.md`, and the per-language files `context/property-based/python.md`, `typescript.md` and `csharp.md` | Source read, own words | Taken as topics only: spotting code that has an invariant worth a property, building generators, reading a shrunk failure, and picking a library per language. Ours adds what upstream has no reason to hold: the oracle rule points at `/testing:test-value`, the guidance states how `/testing:audit` exempts property files from its recomputed-value rule, and a language file loads only when the code under test is in that language. Not taken: the plugin's eval suites, its smart-contract tooling, and its Codex agent sidecar (this marketplace has no Codex target) |
