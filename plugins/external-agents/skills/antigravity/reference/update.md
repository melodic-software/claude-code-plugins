# Update

```bash
external-agents update antigravity
```

Checks that agy is ready and refreshes what the plugin knows about it. It never installs or
upgrades anything: a missing agy is installed through the user's dotfiles install, and an upgrade
follows the hint the user set in `antigravity.update_hint`.

Run it when a run reports agy unavailable or the breaker open, when the user asks whether agy is
ready, and after an agy upgrade. Exit `0` when agy is ready, `4` when it is missing or logged out.

## Reading the output

One line per check; act on each:

| Line | What to do |
|---|---|
| `antigravity: ready` | Ready; the breaker is closed. `ready (check: ...)` names checks below that need a look |
| `antigravity: unavailable: ...` | Relay it: it says what to install or log in to. Stop |
| `version:`, `login:` | Report them when the user asked about readiness |
| `cli facts: <path>` | `agy.txt` (agy's help) and `models.txt` (`agy models`) for this version. Read them for any flag, subcommand or model question; then do the model check below |
| `version check:` | A newer release: tell the user once |
| `docs index:` | `unreachable`: say the routing pointers could not be checked |
| `routing: due; re-read the routing pointers` | Do the routing refresh below |
| `routing: checked earlier today` | Nothing |
| `config keys: none passed` | Expected: agy takes flags, not config keys |

## Model check

Read `antigravity.model` from `<home>/external-agents.yaml` and `<home>/external-agents.local.yaml`
(the local file wins). When it is set and its slug is not a line's first column in `models.txt`,
tell the user the configured model is not in this agy version's list, name the key, and quote the
closest slugs from the file. Unset: say nothing here; a run reports the skip itself. Change no
config file yourself.

## Routing refresh

On `routing: due`, fetch the pages [routing.md](routing.md) lists and compare them with the model
and effort the user configured (`antigravity.model` and `antigravity.effort`). When a configured
model is marked retired or deprecated there, tell the user, name the config key and link the page.
Change no config file yourself. With nothing configured, there is nothing to compare: say nothing.
