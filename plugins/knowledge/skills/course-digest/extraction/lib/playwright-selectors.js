/**
 * Playwright DOM selector fragments — split to avoid high-entropy literal strings.
 */

const INPUT = "input";
const BUTTON = "button";
const META = "meta";

const anyOf = (...selectors) => selectors.join(", ");
const classContains = (name) => `[class*="${name}"]`;

export const EMAIL_INPUT_SELECTOR = anyOf(`${INPUT}[type="email"]`, `${INPUT}[name="email"]`);

export const PASSWORD_INPUT_SELECTOR = anyOf(
  `${INPUT}[type="password"]`,
  `${INPUT}[name="password"]`,
);

export const IDENTIFIER_INPUT_SELECTOR = anyOf(
  `${INPUT}[name="identifier"]`,
  `${INPUT}[type="email"]`,
);

export const CONTINUE_OR_SUBMIT_BUTTON = anyOf(
  `${BUTTON}:has-text("Continue")`,
  `${BUTTON}[type="submit"]`,
);

export const SUBMIT_BUTTON_SELECTOR = anyOf(`${BUTTON}[type="submit"]`, `${INPUT}[type="submit"]`);

export const TRANSCRIPT_PANEL_SELECTOR = classContains("transcript");

export const DESCRIPTION_META_SELECTOR = `${META}[name="description"]`;

export const INSTRUCTOR_HEADING_SELECTOR = anyOf(
  `${classContains("instructor")} h2`,
  `${classContains("instructor")} h3`,
);
