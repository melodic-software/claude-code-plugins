import { spawnSync } from "node:child_process";
import { realpathSync } from "node:fs";
import { fileURLToPath } from "node:url";

const FIX =
  "Fix: rename the function's flag in melodic-software/dotfiles, or follow the upstream change there and in plugin-profiles (claude-code-plugins#17030).";
const FUNCTION = "the dotfiles `claude` shell function (melodic-software/dotfiles#1646)";

/** A flag-column row naming `--<name>`: two spaces, an optional short form, any aliases, then the flag. */
const row = (name) => new RegExp(`^  (?:-[A-Za-z], )?(?:--[A-Za-z0-9-]+, )*--${name}(?![A-Za-z0-9-])`, "m");

/** Each way a help text breaks the function, as one message naming the function and both fixes. */
export function flagProblems(help) {
  const problems = [];
  if (row("profile").test(help)) {
    problems.push(`\`claude --help\` lists --profile, which ${FUNCTION} intercepts, so the upstream flag is unreachable. ${FIX}`);
  }
  if (!/^  -r, --resume(?![A-Za-z0-9-])/m.test(help)) {
    problems.push(`\`claude --help\` no longer lists -r, --resume, which ${FUNCTION} hands to profiles.mjs start. ${FIX}`);
  }
  if (!row("settings").test(help)) {
    problems.push(`\`claude --help\` no longer lists --settings, which profiles.mjs start passes for ${FUNCTION}. ${FIX}`);
  }
  return problems;
}

/** Runs `<claude binary> --help`; exits 0 when every flag is as the function needs, 1 with one ::error:: line per problem, 2 on usage. */
function main(argv) {
  const [bin] = argv;
  if (!bin || argv.length > 1) {
    console.error("usage: node check-claude-function-flags.mjs <claude binary>");
    return 2;
  }
  const run = spawnSync(bin, ["--help"], { encoding: "utf8", timeout: 60_000 });
  if (run.error || run.status !== 0 || !run.stdout) {
    console.log(`::error::${bin} did not print its help (${run.error?.code ?? `exit ${run.status}`}). ${FIX}`);
    return 1;
  }
  const problems = flagProblems(run.stdout);
  for (const problem of problems) console.log(`::error::${problem}`);
  if (!problems.length) console.log("claude --help lists -r, --resume and --settings and no --profile");
  return problems.length ? 1 : 0;
}

if (process.argv[1] && realpathSync(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.exitCode = main(process.argv.slice(2));
}
