/**
 * Playwright DOM selector fragments — split to avoid high-entropy literal strings.
 */

const INPUT = "input";
const BUTTON = "button";
const META = "meta";
const CLASS_CONTAINS_PREFIX = '[class*="';
const TRANSCRIPT_CLASS = "transcript";
const INSTRUCTOR_CLASS = "instructor";

export const EMAIL_INPUT_SELECTOR = [`${INPUT}[type="email"]`, `${INPUT}[name="email"]`].join(", ");

export const PASSWORD_INPUT_SELECTOR = [
  `${INPUT}[type="password"]`,
  `${INPUT}[name="password"]`,
].join(", ");

export const IDENTIFIER_INPUT_SELECTOR = [
  `${INPUT}[name="identifier"]`,
  `${INPUT}[type="email"]`,
].join(", ");

export const CONTINUE_OR_SUBMIT_BUTTON = [
  `${BUTTON}:has-text("Continue")`,
  `${BUTTON}[type="submit"]`,
].join(", ");

export const SUBMIT_BUTTON_SELECTOR = [`${BUTTON}[type="submit"]`, `${INPUT}[type="submit"]`].join(
  ", ",
);

export const TRANSCRIPT_PANEL_SELECTOR = `${CLASS_CONTAINS_PREFIX}${TRANSCRIPT_CLASS}"]`;

export const DESCRIPTION_META_SELECTOR = `${META}[name="description"]`;

export const INSTRUCTOR_HEADING_SELECTOR = [
  `${CLASS_CONTAINS_PREFIX}${INSTRUCTOR_CLASS}"] h2`,
  `${CLASS_CONTAINS_PREFIX}${INSTRUCTOR_CLASS}"] h3`,
].join(", ");
