import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

// The head lines GH_DEBUG=1 gives one request (as log-api-budget.test.mjs
// `request` does).
const request = (url) => `echo '* Request at 2026-11-03 15:00:00 +0000 UTC'; echo "* Request to ${url}"; echo '* Request took 1ms'`;

// Writes <dir>/bin/gh: it appends its arguments to <dir>/gh-calls, then runs
// `body`. Returns the bin directory to put on PATH.
function fakeGh(dir, body) {
  const bin = join(dir, "bin");
  mkdirSync(bin, { recursive: true });
  writeFileSync(
    join(bin, "gh"),
    `#!/usr/bin/env bash
echo "$*" >>"${join(dir, "gh-calls")}"
${body}`,
  );
  chmodSync(join(bin, "gh"), 0o755);
  return bin;
}

// A gh on PATH for `gh run download <id> -R <repo> -n <name> -D <target>`:
// it writes `file` holding `text` into the target and, under GH_DEBUG=1, logs
// the requests for the run's artifact listing, the archive, and a download
// host off GitHub's API.
export function fakeGhDownload(dir, file, text) {
  return fakeGh(
    dir,
    `[[ $1 == run && $2 == download && $4 == -R && $6 == -n && $8 == -D ]] || { echo "args: $*" >&2; exit 9; }
if [[ \${GH_DEBUG:-} == 1 ]]; then
  {
    ${request("https://api.github.com/repos/$5/actions/runs/$3/artifacts?per_page=100&name=$7")}
    ${request("https://api.github.com/repos/$5/actions/artifacts/9/zip")}
    ${request("https://productionresultssa1.blob.core.windows.net/actions-results/x.zip?sig=s")}
  } >&2
fi
mkdir -p "$9" && printf '%s' ${JSON.stringify(text)} >"$9/${file}"
`,
  );
}

// A gh on PATH for `gh api -i repos/<repo>/actions/artifacts/<id>/zip`, the
// form api-budget.bash's wrapper sends `gh api <path>` as: it prints a 200
// response whose body is the bytes of `archive`, after the redirect GitHub
// answers that endpoint with; under GH_DEBUG=1 it logs the archive request
// and the download host's.
export function fakeGhArchive(dir, archive) {
  return fakeGh(
    dir,
    `[[ $1 == api && $2 == -i && $3 =~ ^repos/[^/]+/[^/]+/actions/artifacts/[0-9]+/zip$ && $# == 3 ]] || { echo "args: $*" >&2; exit 9; }
if [[ \${GH_DEBUG:-} == 1 ]]; then
  {
    ${request("https://api.github.com/$3")}
    ${request("https://productionresultssa1.blob.core.windows.net/actions-results/x.zip?sig=s")}
  } >&2
fi
printf 'HTTP/1.1 200 OK\\r\\nContent-Type: application/zip\\r\\n\\r\\n'
cat ${JSON.stringify(archive)}
`,
  );
}
