#!/usr/bin/env bash
# Seed a finished migration to the jobs registry whose paved-path entry still names plain cron.
set -euo pipefail

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
for target in docs jobs tests deploy; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done

mkdir -p docs/standards jobs tests deploy
cat >docs/standards/README.md <<'MD'
# Standards index

| Topic | Surface | File |
|---|---|---|
| Code review | rule | review.md |
| Chosen ways per concern | paved-path | paved-paths.md |
MD
cat >jobs/registry.ts <<'TS'
import { withRetry } from "./retry";

export type Job = { name: string; schedule: string; run: () => Promise<void> };
export const jobs: Job[] = [];
export function register(job: Job) {
  jobs.push({ ...job, run: () => withRetry(3, job.run) });
}
TS
cat >jobs/retry.ts <<'TS'
export async function withRetry(times: number, fn: () => Promise<void>) {
  let last: unknown;
  for (let i = 0; i < times; i++) {
    try {
      return await fn();
    } catch (e) {
      last = e;
    }
  }
  throw last;
}
TS
cat >tests/jobs-registry.test.ts <<'TS'
import { jobs } from "../jobs/registry";
test("every scheduled job is registered", () => {
  expect(jobs.length).toBeGreaterThan(0);
});
TS
cat >jobs/cleanup.ts <<'TS'
import { register } from "./registry";
register({ name: "cleanup", schedule: "0 3 * * *", run: async () => {} });
TS
cat >jobs/digest.ts <<'TS'
import { register } from "./registry";
register({ name: "digest", schedule: "0 7 * * 1", run: async () => {} });
TS
cat >docs/standards/paved-paths.md <<'MD'
# Paved paths

| ID | Concern | Chosen way | Enforced by |
|---|---|---|---|
| PP-01 | HTTP handlers | `src/http/handler.ts` template | `tests/handlers.test.ts` |
| PP-02 | Scheduled jobs | plain cron entry in the deploy config | none |
MD
cat >deploy/config.yaml <<'YAML'
service: reports
replicas: 2
YAML
