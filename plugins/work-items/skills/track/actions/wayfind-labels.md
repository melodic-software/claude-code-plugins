# Action: `wayfind-labels`

Print the wayfind label prefix and the human-gated label the tracker binding sets, for
`/planning:wayfind`. Read-only.

## Usage

```
/work-items:track wayfind-labels
```

## Workflow

1. **Run the seam verb** `wayfind-labels`, with no arguments, through the dispatcher SKILL.md
   "Shared tracker context" names: `bash "<dispatcher>" wayfind-labels`.

1. **Exit `0`: print its JSON object** in one fenced block, for example
   `{"schema_version":"1.0","prefix":"wayfind:","prefix_source":"default","human_gated":"needs-human","human_gated_source":"default"}`.
   **Any other exit: print nothing but the refusal**, `REFUSED: <stderr>`, and stop. The caller
   takes no default on a refusal. Field meanings and the refusals: the seam's `CONTRACT.md`
   "Verbs", beside the dispatcher.
