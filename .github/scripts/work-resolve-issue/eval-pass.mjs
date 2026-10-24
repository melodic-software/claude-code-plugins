// eval-pass.mjs: whether an issue's done-when asks for a measured
// `claude plugin eval` pass, the paid run that eval-browser-dispatch.yml runs
// on a pull request carrying EVAL_RUN_LABEL. Pure.
//
// It sits beside report-outcome.mjs because the activity runner copies only
// the script's own directory (collect-base-activity), so a sibling is the
// only module report-outcome can import there.

export const EVAL_RUN_LABEL = "eval: run";

// Done-when wording that asks for a paid, measured eval pass. The first form
// is the paid-eval pattern admission refuses an unattended run on, without
// its no-spend exclusions; the rest are the rollout issues' own wording: a
// shipped description or body that "was measured", a measured eval pass, and
// before-and-after numbers behind a decision.
export const EVAL_PASS = new RegExp(
  [
    String.raw`\b(?:run|execute|launch|start)\b[^,;:]{0,40}\b(?:paid evals?|claude plugin eval\b)`,
    String.raw`\bmeasured\b[^,;:.]{0,40}\b(?:claude plugin eval|evals?|pass(?:es)?)\b`,
    String.raw`\b(?:descriptions?|bod(?:y|ies)|skills?)\b[^,;:.]{0,60}\b(?:was|were|is|are|be) measured\b`,
    String.raw`\bbefore and after numbers\b`,
  ].join("|"),
  "i",
);

// An item that names a no-spend step (the static validator, a dry run) asks
// for no paid pass, whatever else it says.
export const NO_SPEND = /\b(?:validate|dry[- ]run|no-spend)\b/i;

// The text of each list item under a `Done when` heading, and of each
// task-list item anywhere in the body, in body order.
export function doneWhenItems(body) {
  const items = [];
  let inDoneWhen = false;
  for (const line of String(body ?? "").split("\n")) {
    const heading = /^\s{0,3}#{1,6}\s+(.*)$/.exec(line);
    if (heading) {
      inDoneWhen = /^done when\b/i.test(heading[1].trim());
      continue;
    }
    const item = /^\s*[-*+]\s+(\[[ xX]\]\s+)?(.*)$/.exec(line);
    if (item && (inDoneWhen || item[1])) {
      items.push(item[2].trim());
    }
  }
  return items;
}

export const needsMeasuredEval = (body) => doneWhenItems(body).some((text) => EVAL_PASS.test(text) && !NO_SPEND.test(text));
