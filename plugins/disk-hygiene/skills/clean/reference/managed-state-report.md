# Managed-state report

The report a managed-state registry match produces. The registry is
[owner-registry.json](owner-registry.json), validated by
[owner-registry.schema.json](owner-registry.schema.json). The engine's eligibility rules for
managed state stay as [the safety model](safety-model.md) states them.

## Report per registry match

1. **Owner.** The entry's `owner` and `id`, with the matched path. The match is a hint for an
   owner claim, not proof of one.
2. **Tool presence.** Before any other command, resolve the entry's `tool` on PATH in the lane
   named under [Who runs the probes](#who-runs-the-probes). Absent: status `absent-tool`, and the
   report offers no command of any kind, including the manual step. Not run: the report says
   presence is unverified and runs nothing further.
3. **Read-only command.** When present and `read_only_command` is set, run it in that lane and
   capture its output into the report verbatim. A null command means the product has none; the
   report shows `manual_step` as information.
4. **Destructive native command.** Neither shown nor run by the report. The registry keeps each one
   as data to inspect. The engine blocks a plan that claims a registry owner with
   `native-managed-report-only` and issues no approval token for it. Whether the report may show a
   destructive command, or offer one behind the engine's tier and exact-list approval, is the
   owner's decision, and no route for either is built.
5. **Unmatched paths.** A managed-looking path with no registry match is reported as a coverage
   gap. It is never `clean` and never removable.

## Who runs the probes

Steps 2 and 3 are tool calls or operator actions, never shipped code. The clean skill's Bash guard
denies both, since neither is a bundled engine shape or a listed supporting command (see the Bash
and PowerShell lane bullets under [Gotchas](../SKILL.md#gotchas)). Where the session has the
PowerShell tool, run them there (`Get-Command <tool>`, then the command): that lane is open for
read-only support work and the guard gives those commands no decision, so the session's ordinary
permissions, and in auto mode its classifier, still decide. Otherwise the operator runs both
outside the session, presence check first, and the report records what they paste. A probe nobody
ran is reported as not run, never as a result.

## Design check

| Design constraint | How this report meets it |
|---|---|
| Containment is untouched | The report adds no deletion capability; engine eligibility is unchanged. |
| Read-only and destructive are different gates | Step 3 is a tool call in the PowerShell lane or an operator action, never the engine and never shipped code. Step 4 shows and runs no destructive command, so none is offered outside the engine's approval; offering one behind that approval is not built. The test fence names both kinds of command, so a shipped probe runner would be a reviewed change to that fence. |
| Tool presence is checked first | Step 2 runs before step 3, in the same lane; absent gives `absent-tool` and no commands. |
| An entry is a hint, never authorization | Step 1 treats a match as a claim to prove. |
| Unmatched stays a coverage gap | Step 5. |
| The registry is inspectable | Plain JSON plus a schema, readable without running anything. |

## Scope

No destructive command is built. Whether a product-native destructive command is ever run stays
the owner's decision.
