export function formatCents(cents, currency) {
  const amount = (cents / 100).toFixed(2);
  return `${currency} ${amount}`;
}
