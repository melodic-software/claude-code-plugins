// Which paths an address-feedback fix may change, shared by
// address-feedback.mjs, publish-feedback.mjs and apply-patch.mjs's
// kept-threads rule, and mirrored by the review-thread tool
// (feedback-thread.sh), which reads the pr_paths prPathsOf wrote. It imports
// nothing, so the write runner's copy of it beside apply-patch.mjs's needs no
// other file. It also holds the Lane-Thread trailer that binds a fix commit
// to the kept threads it fixes: apply-patch.mjs writes it, publish-feedback.mjs
// reads it.

// A review thread's GraphQL node id, as the select job keeps it.
export const THREAD_ID = /^PRRT_[A-Za-z0-9_-]{1,100}$/;
// A pr-verify note the select job read from an earlier FAIL's verdict artifact
// (address-feedback.mjs, verify_notes): a work item with a path and no review
// thread, which the Lane-Thread trailer names like a thread.
export const NOTE_ID = /^VNOTE_[1-9][0-9]{0,2}$/;
const THREAD_TRAILER = "Lane-Thread: ";

// The trailer lines naming `ids`, one per thread.
export const threadTrailerLines = (ids) => ids.map((id) => `${THREAD_TRAILER}${id}`);

// The thread ids a commit message's Lane-Thread lines name, each a line of
// its own.
export const threadsNamed = (message) =>
  new Set(
    String(message ?? "")
      .split("\n")
      .map((line) => line.replace(/\r$/, ""))
      .filter((line) => line.startsWith(THREAD_TRAILER))
      .map((line) => line.slice(THREAD_TRAILER.length)),
  );

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
// A plugin's or a skill's eval cases, fixtures and scaffolds.
const EVAL_PATH = /^plugins\/[^/]+\/(skills\/[^/]+\/)?evals\//;
const TEST_FILE = /^(test_[^/]*\.py|[^/]*_test\.py|[^/]*\.(test|spec)\.[^/]+)$/;
const dirOf = (path) => path.slice(0, path.lastIndexOf("/") + 1);

// An empty, . or .. segment, so a leading or doubled / too.
const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;
// ASCII letters, digits and _@+.- in /-separated segments: no backslash,
// space, control or non-ASCII character.
const PLAIN_PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;
// Plain and in normal form.
const isPlainPath = (path) => PLAIN_PATH.test(path) && !BAD_SEGMENT.test(path);

// Control-plane and agent-instruction surfaces outside plugins/<p>/: anything
// under .github/ (which holds the pr-merge HIGH floor's trusted-actor list,
// trusted-trigger check and resolve-config, and this pipeline's own scripts
// and actions), CLAUDE.md, AGENTS.md, .mcp.json, .lsp.json, and a .claude or
// .claude-plugin directory.
const CONTROL_PATH = /^\.github\/|(^|\/)(CLAUDE\.md|AGENTS\.md|\.mcp\.json|\.lsp\.json)$|(^|\/)\.claude(-plugin)?\//i;
const isControlPath = (path) => pluginOf(path) === undefined && CONTROL_PATH.test(path);

// A path a pull request changes that a fix may also change: plain, in normal
// form, and neither under .github/workflows/, an instruction path nor a
// control-plane or agent-instruction surface outside plugins/. A thread on
// such a path still reaches it through the thread's own scope.
const prPathAllowed = (path) =>
  typeof path === "string" &&
  isPlainPath(path) &&
  !isProtectedPath(path) &&
  !isInstructionPath(path) &&
  !isControlPath(path);

// The paths a pull request's file listing (each { filename,
// previous_filename }) changes, rename sources included, that prPathAllowed
// allows; sorted, each once. The select job writes them as pr_paths.
export const prPathsOf = (files) =>
  [...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter(prPathAllowed))].sort();

// The `[canonical, copy]` pairs of a scripts/shared-copies.txt text: each
// line's two fields, with everything from a `#` on stripped as
// scripts/sync-shared-copies.sh strips it, blanks skipped.
export const sharedCopyPairs = (text) =>
  String(text)
    .split("\n")
    .map((line) => line.split("#")[0].trim().split(/\s+/))
    .filter((fields) => fields.length === 2);

// The registered copies (`pairs`, sharedCopyPairs's) whose canonical the pull
// request's file listing changes, that prPathAllowed allows; sorted, each
// once. The select job writes them as copy_paths: a fix that changes a
// canonical may regenerate its copies, which scripts/sync-shared-copies.sh
// writes into other plugins.
export const copyPathsOf = (files, pairs) => {
  const changed = new Set(files.map((file) => file?.filename));
  return [...new Set(pairs.filter(([canonical]) => changed.has(canonical)).map(([, copy]) => copy).filter(prPathAllowed))].sort();
};

// A path a trusted write-access fix request on a kept thread named may join
// that thread's scope: a plain path in normal form, in the same plugins/<p>/
// directory as the thread's own path, and neither under .github/workflows/ nor
// an instruction path.
export function namedInScope(path, threadPath) {
  const plugin = pluginOf(path);
  return (
    isPlainPath(path) &&
    plugin !== undefined &&
    plugin === pluginOf(String(threadPath)) &&
    !isProtectedPath(path) &&
    !isInstructionPath(path)
  );
}

// A kept thread's own path; a file that is no instruction path and is either
// under a plugin's or a skill's evals/ or in a plugins/<p>/ directory a kept
// thread's path or a path the pull request already changes (`prPaths`,
// prPathsOf's) sits in; a test file in the same directory as a kept thread's
// path; a path in a kept thread's named_paths (in `threads`, each { path,
// named_paths }) that namedInScope allows for that thread; or a path the pull
// request already changes, or a copy of a canonical it changes (`copyPaths`,
// copyPathsOf's), that the fix does not add (`added`: the fix creates the
// path, as a new file or a rename's target). Never anything under
// .github/workflows/, and never a path that is not plain and in normal form.
export function inThreadScope(path, threadPaths, threads = [], { prPaths = new Set(), copyPaths = new Set(), added = false } = {}) {
  if (isProtectedPath(path) || !isPlainPath(path)) {
    return false;
  }
  if (threadPaths.has(path)) {
    return true;
  }
  if (!added && (prPaths.has(path) || copyPaths.has(path)) && prPathAllowed(path)) {
    return true;
  }
  if (threads.some((t) => Array.isArray(t?.named_paths) && t.named_paths.includes(path) && namedInScope(path, t.path))) {
    return true;
  }
  const kept = [...threadPaths];
  const plugin = pluginOf(path);
  if (
    plugin !== undefined &&
    !isInstructionPath(path) &&
    (EVAL_PATH.test(path) || [...kept, ...prPaths].some((p) => p.startsWith(plugin)))
  ) {
    return true;
  }
  const dir = dirOf(path);
  return TEST_FILE.test(path.slice(dir.length)) && kept.some((p) => dirOf(p) === dir);
}
