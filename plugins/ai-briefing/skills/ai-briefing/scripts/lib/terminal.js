// Stdout/stderr writers — Biome noConsole-safe replacements for test scripts and CLIs.

export function writeStdout(text) {
  process.stdout.write(String(text));
}

export function writeStderr(text) {
  process.stderr.write(String(text));
}

export function writelnStdout(text = "") {
  writeStdout(`${text}\n`);
}

export function writelnStderr(text = "") {
  writeStderr(`${text}\n`);
}

/** Minimal pass/fail reporter for standalone test scripts. */
export function createTestReporter() {
  let pass = 0;
  let fail = 0;

  function ok(label, cond, detail = "") {
    if (cond) {
      writelnStdout(`  ✓ ${label}`);
      pass++;
    } else {
      writelnStdout(`  ✗ ${label}${detail ? ` — ${detail}` : ""}`);
      fail++;
    }
  }

  function section(title) {
    writelnStdout(title);
  }

  function printResults() {
    writelnStdout(`\nResults: ${pass} pass / ${fail} fail`);
  }

  return {
    ok,
    section,
    printResults,
    get pass() {
      return pass;
    },
    get fail() {
      return fail;
    },
  };
}
