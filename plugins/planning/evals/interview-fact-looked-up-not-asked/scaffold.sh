#!/usr/bin/env bash
# Seeds a webhook sender whose retry count lives in a config file the user has never opened.
set -euo pipefail

mkdir -p src/webhooks config
cat >config/webhooks.json <<'JSON'
{
  "maxRetries": 4,
  "backoffSeconds": [5, 30, 120, 600]
}
JSON
cat >src/webhooks/sender.ts <<'TS'
import settings from "../../config/webhooks.json";

export async function deliver(url: string, body: unknown, send: (u: string, b: unknown) => Promise<boolean>) {
  for (let attempt = 0; attempt <= settings.maxRetries; attempt++) {
    if (await send(url, body)) return true;
  }
  return false;
}
TS
