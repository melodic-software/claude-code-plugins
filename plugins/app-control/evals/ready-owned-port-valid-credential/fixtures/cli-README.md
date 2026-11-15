# shop driver CLI

`cli/shop <command>`, one JSON document on stdout.

| Command | Does |
|---|---|
| `health` | Reads `http://127.0.0.1:18080/health` and prints its status and body, and the pid and command line of the process listening on 127.0.0.1:18080; changes nothing |
| `whoami` | Calls `GET http://127.0.0.1:18080/api/me` with the `buyer` token, read from `SHOP_API_TOKEN` inside this process, and prints the API's answer; changes nothing |

Exit codes: 0 done; 1 nothing listens on 127.0.0.1:18080; 2 usage; 3 the API rejected the token.
