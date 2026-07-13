import assert from "node:assert/strict";

import { expect } from "vitest";

export function soleElement<T>(items: readonly T[]): T {
  expect(items).toHaveLength(1);
  const item = items[0];
  assert(item !== undefined);
  return item;
}

export function elementAt<T>(items: readonly T[], index: number): T {
  const item = items[index];
  assert(item !== undefined);
  return item;
}
