export function applyDiscount(totalCents, code) {
  if (code == null) {
    return totalCents;
  }
  const rate = code === "STAFF" ? 0.2 : 0.1;
  return Math.round(totalCents * (1 - rate));
}
