/**
 * Terminal output helpers — process.stdout/stderr instead of console.*
 */

/** @param {unknown[]} args */
function formatArgs(args) {
  return args
    .map((/** @type {unknown} */ arg) => {
      if (typeof arg === "string") return arg;
      if (arg instanceof Error) return arg.stack ?? arg.message;
      try {
        return JSON.stringify(arg);
      } catch {
        return String(arg);
      }
    })
    .join(" ");
}

/** @param {...unknown} args */
export function writeStdout(...args) {
  process.stdout.write(`${formatArgs(args)}\n`);
}

/** @param {...unknown} args */
export function writeStderr(...args) {
  process.stderr.write(`${formatArgs(args)}\n`);
}
