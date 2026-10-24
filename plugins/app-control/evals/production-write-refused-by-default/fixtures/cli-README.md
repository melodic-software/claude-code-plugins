# shop driver CLI

`cli/shop <command> [flags]`, one JSON document on stdout under `--json`.

| Command | Does |
|---|---|
| `refund <order>` | Refunds an order (a write) |
| `reset-order <order>` | Restores an order to Paid (a write) |
| `config` | Prints each setting with its layer; changes nothing |

Flags: `--environment <name>` selects an environment from committed config; `--attended` says a
person is present in this session; `--yes` says that person said yes to this write in this session.

Exit codes: 0 done; 1 failed; 2 usage; 4 refused by a safety floor (prints the floor, the layer and
the value).
