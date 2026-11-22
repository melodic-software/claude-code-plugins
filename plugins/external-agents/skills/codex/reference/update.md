# Update

```bash
external-agents update codex
```

Checks that Codex is ready and refreshes what the plugin knows about it. It never installs or
upgrades anything: a missing Codex is installed through the user's dotfiles install, and an
upgrade follows the hint the user set in `codex.update_hint`.

Run it when a run reports Codex unavailable or the breaker open, when the user asks whether Codex
is ready, and after a Codex upgrade. Exit `0` when Codex is ready, `4` when it is missing or logged
out.

## Reading the output

One line per check; act on each:

| Line | What to do |
|---|---|
| `codex: ready` | Ready; the breaker is closed. `ready (check: ...)` names checks below that need a look |
| `codex: unavailable: ...` | Relay it: it says what to install or log in to. Stop |
| `version:`, `login:` | Report them when the user asked about readiness |
| `cli facts: <path>` | Codex's own help for this version, and `models.txt` (`codex debug models`). Read these files for any flag or subcommand question; for models and effort levels run `external-agents models codex` |
| `version check:` | A newer release: tell the user once |
| `docs index:` | `unreachable`: say the routing pointers could not be checked |
| `routing: due; re-read the routing pointers` | Do the routing refresh below |
| `routing: checked earlier today` | Nothing |
| `config keys: drift` or `unverified` | The keys the command passes to Codex may have changed. Report it as a defect in this plugin; runs still go out, but the sandbox setting may not hold |

## Routing refresh

On `routing: due`, fetch the pages [routing.md](routing.md) lists and compare them with the
model and effort the user configured (`codex.model` and `codex.effort` in `<home>/external-agents.yaml` and
`<home>/external-agents.local.yaml`). When a configured model is no longer listed or is marked retired or
deprecated, tell the user, name the config key and link the page. Change no config file
yourself. With nothing configured, there is nothing to compare: say nothing.
