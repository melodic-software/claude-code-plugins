// Which paths an address-feedback fix may change, shared by
// address-feedback.mjs, publish-feedback.mjs and apply-patch.mjs's
// kept-threads rule, and mirrored by the review-thread tool
// (feedback-thread.sh). It imports nothing, so the write runner's copy of it
// beside apply-patch.mjs's needs no other file.
//
// The rule is path hygiene only. What a fix touches beyond the thread's own
// path is a code-review finding, and a control or instruction surface it
// touches is a security-review finding; apply-patch.mjs withholds the paths it
// keeps (a workflow, a settings file, an agent instruction file) and posts
// them as a proposed diff.

// Under .github/workflows/.
export function isProtectedPath(path) {
  return /^\.github\/workflows(\/|$)/i.test(String(path));
}

// An empty, . or .. segment, so a leading or doubled / too.
const BAD_SEGMENT = /(^|\/)\.{0,2}(\/|$)/;
// ASCII letters, digits and _@+.- in /-separated segments: no backslash,
// space, control or non-ASCII character.
const PLAIN_PATH = /^[A-Za-z0-9_@+.-]+(\/[A-Za-z0-9_@+.-]+)*$/;

const plain = (path) => typeof path === "string" && PLAIN_PATH.test(path) && !BAD_SEGMENT.test(path);

// The paths a pull request's file listing (each { filename,
// previous_filename }) changes, rename sources included, that are plain and
// in normal form; sorted, each once. The select job writes them as pr_paths.
export const prPathsOf = (files) => [...new Set(files.flatMap((file) => [file?.filename, file?.previous_filename]).filter(plain))].sort();

// A path a trusted write-access fix request on a kept thread named may join
// that thread's scope: a plain path in normal form.
export const namedInScope = (path) => plain(path);

// A path a fix may change: plain and in normal form. The other arguments are
// the callers' thread context, which no longer narrows the scope.
export const inThreadScope = (path) => plain(path);
