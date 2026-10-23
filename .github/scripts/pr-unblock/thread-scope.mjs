// Which paths an address-feedback fix may change, shared by
// address-feedback.mjs, publish-feedback.mjs and apply-patch.mjs's
// kept-threads rule, and mirrored by the review-thread tool
// (feedback-thread.sh), which reads the pr_paths prPathsOf wrote. It imports
// nothing, so the write runner's copy of it beside apply-patch.mjs's needs no
// other file.

// Under .github/workflows/, which the lane token has no permission to push.
export function isProtectedPath(path) {
  return /^\.github\/workflows(\/|$)/i.test(String(path));
}

// Submodule, code-owner, agent permission and package manifest files, each
// matched as the whole last segment.
const INSTRUCTION_PATH =
  /(^|\/)(\.gitmodules|codeowners|settings[^/]*\.json|package(-lock)?\.json|requirements[^/]*\.txt)$/i;
export const isInstructionPath = (path) => INSTRUCTION_PATH.test(String(path));

const PLUGIN_DIR = /^plugins\/[^/]+\//;
const pluginOf = (path) => PLUGIN_DIR.exec(path)?.[0];
// Script or code files, run by a shell or an interpreter, so out of the
// plugin-wide part of a thread's scope.
const CODE_FILE = /\.(sh|bash|zsh|ps1|py|mjs|cjs|js|ts|mts|cts)$/i;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

// An empty, . or .. segment, so a leading or doubled / too.
const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;
// ASCII letters, digits and _@+.- in /-separated segments: no backslash,
// space, control or non-ASCII character.
const PLAIN_PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;

// The pr-merge HIGH floor's paths (babysit_risk.py HIGH_FLOOR) besides
// CODEOWNERS and .gitmodules, which isInstructionPath holds: the trusted-actor
// list, the trusted-trigger check and resolve-config.
const HIGH_FLOOR_PATH = /^\.github\/(standards\/trusted-actors|actions\/check-trusted-trigger|actions\/resolve-config)\//i;

// A path a pull request changes that a fix may also change: plain, in normal
// form, and neither under .github/workflows/, an instruction path nor on the
// HIGH floor.
const prPathAllowed = (path) =>
  typeof path === "string" &&
  PLAIN_PATH.test(path) &&
  !BAD_SEGMENT.test(path) &&
  !isProtectedPath(path) &&
  !isInstructionPath(path) &&
  !HIGH_FLOOR_PATH.test(path);

// The paths a pull request's file listing (each { filename,
// previous_filename }) changes, rename sources included, that prPathAllowed
// allows; sorted, each once. The select job writes them as pr_paths.
export const prPathsOf = (files) =>
  [...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter(prPathAllowed))].sort();

// A path a trusted write-access fix request on a kept thread named may join
// that thread's scope: a plain path in normal form, in the same plugins/<p>/
// directory as the thread's own path, and neither under .github/workflows/ nor
// an instruction path.
export function namedInScope(path, threadPath) {
  const plugin = pluginOf(path);
  return (
    PLAIN_PATH.test(path) &&
    !BAD_SEGMENT.test(path) &&
    plugin !== undefined &&
    plugin === pluginOf(String(threadPath)) &&
    !isProtectedPath(path) &&
    !isInstructionPath(path)
  );
}

// A kept thread's own path, a file in the plugins/<p>/ directory a kept
// thread's path sits in that is no instruction path and no script or code
// file, a test file in the same directory as a kept thread's path,
// a path in a kept thread's named_paths (in `threads`, each { path,
// named_paths }) that namedInScope allows for that thread, or a path the pull
// request already changes (`prPaths`, prPathsOf's) that the fix does not add
// (`added`: the fix creates the path, as a new file or a rename's target);
// never anything under .github/workflows/, and never a path that is not plain
// and in normal form.
export function inThreadScope(path, threadPaths, threads = [], { prPaths = new Set(), added = false } = {}) {
  if (isProtectedPath(path) || BAD_SEGMENT.test(path) || !PLAIN_PATH.test(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  if (!added && prPaths.has(path) && prPathAllowed(path)) {
    return true;
  }
  if (threads.some((t) => Array.isArray(t?.named_paths) && t.named_paths.includes(path) && namedInScope(path, t.path))) {
    return true;
  }
  const kept = [...threadPaths];
  const plugin = pluginOf(path);
  if (plugin !== undefined && !CODE_FILE.test(path) && !isInstructionPath(path) && kept.some((p) => p.startsWith(plugin))) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
