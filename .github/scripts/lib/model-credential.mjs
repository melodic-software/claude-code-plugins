import assert from "node:assert/strict";

import { contractAtPin } from "./ci-workflows-at-pin.mjs";
import { evaluate, truthy } from "./gate-expression.mjs";

// The one pin every select-model-credential step in the given workflows names.
export function selectPin(...workflowTexts) {
  const pins = new Set(workflowTexts.flatMap((text) => [...text.matchAll(/uses: melodic-software\/ci-workflows\/\.github\/actions\/select-model-credential@(main)/g)].map((m) => m[1])));
  assert.equal(pins.size, 1, `one select-model-credential pin, found ${[...pins].join(", ")}`);
  return [...pins][0];
}

export async function loadSelect(pin) {
  const { HANDOFF_REASONS, handoffReason, leg, next, start } = await contractAtPin(pin);
  return { HANDOFF_REASONS, handoffReason, leg, next, start };
}

const status = (context) => (context["cancelled()"] === true ? "cancelled" : "success");
export const runs = (condition, context) => truthy(evaluate(condition, context, { status: status(context) }));

// An input value, as the string the step receives: a literal as written,
// a `${{ }}` expression evaluated.
export const value = (input, context) => {
  if (!/^\s*\$\{\{[\s\S]*\}\}\s*$/.test(input)) return input.trim().replace(/^"(.*)"$/, "$1");
  const v = evaluate(input, context, { status: status(context) });
  return typeof v === "boolean" ? String(v) : v;
};

// Every launcher outcome run-claude-cli can produce on `leg` (api-key,
// subscription or fallback), as { handoff, reason }: its own handoffReason
// over every failure class and API status, with and without a limit or
// credit stop.
export function launcherOutcomes(handoffReason, leg, fallbackReady) {
  const seen = new Map();
  for (const failureClass of ["", "credit-stop", "auth", "rate-limit", "other", "timeout"]) {
    for (const status of [undefined, 401, 402, 403, 429, 500]) {
      for (const limitStop of [false, true]) {
        for (const creditStop of [false, true]) {
          const reason = handoffReason({ leg }, failureClass, status, { fallbackReady, limitStop, creditStop });
          seen.set(reason, { handoff: String(reason !== ""), reason });
        }
      }
    }
  }
  return [...seen.values()];
}
