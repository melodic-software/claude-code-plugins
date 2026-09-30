# Managed-state report

The report a managed-state registry match produces. The registry is
[owner-registry.json](owner-registry.json), validated by
[owner-registry.schema.json](owner-registry.schema.json). The engine's eligibility rules for
managed state stay as [the safety model](safety-model.md) states them.

## Report per registry match

1. **Owner.** The entry's `owner` and `id`, with the matched path. The match is a hint for an
   owner claim, not proof of one.
2. **Tool presence.** Resolve the entry's `tool` on PATH before anything else. Absent: status
   `absent-tool`, and the report offers no command of any kind, including the manual step.
3. **Read-only command.** When present and `read_only_command` is set, run it and capture its
   output into the report verbatim. A null command means the product has none; the report shows
   `manual_step` as information.
4. **Destructive native command.** Neither shown nor run by the report. The registry keeps each one
   as data to inspect. The engine blocks a plan that claims a registry owner with
   `native-managed-report-only` and issues no approval token for it. Whether the report may show a
   destructive command, or offer one behind the engine's tier and exact-list approval, is the
   owner's decision, and no route for either is built.
5. **Unmatched paths.** A managed-looking path with no registry match is reported as a coverage
   gap. It is never `clean` and never removable.

## Design check

| Design constraint | How this report meets it |
|---|---|
| Containment is untouched | The report adds no deletion capability; engine eligibility is unchanged. |
| Read-only and destructive are different gates | Step 3 runs freely. Step 4 shows and runs no destructive command, so none is offered outside the engine's approval; offering one behind that approval is not built. |
| Tool presence is checked first | Step 2 precedes every command; absent gives `absent-tool` and no commands. |
| An entry is a hint, never authorization | Step 1 treats a match as a claim to prove. |
| Unmatched stays a coverage gap | Step 5. |
| The registry is inspectable | Plain JSON plus a schema, readable without running anything. |

## Scope

No destructive command is built. Whether a product-native destructive command is ever run stays
the owner's decision.
