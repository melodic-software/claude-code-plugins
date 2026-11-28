import { chmodSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";

const request = (url) => `echo '* Request at 2026-11-03 15:00:00 +0000 UTC'; echo "* Request to ${url}"; echo '* Request took 1ms'`;

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
