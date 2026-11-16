# shop driver CLI

`cli/shop <command>`, one JSON document on stdout.

| Command | Does |
|---|---|
| `ready <run dir>` | Reads `http://127.0.0.1:18080/health`; checks the pid listening on 127.0.0.1:18080 is the pid in the launch record in `<run dir>/report.json`; then calls `GET http://127.0.0.1:18080/api/me` with the `buyer` token, read from `SHOP_API_TOKEN` inside this process. Prints each result and changes nothing |

Exit codes: 0 every check holds; 1 nothing listens on 127.0.0.1:18080; 2 usage; 3 the API rejected the token; 4 another process holds 127.0.0.1:18080.
