import { priceFor } from "./pricing.js";
import { inStock } from "./inventory.js";

export async function buildSummary(cart) {
  const lines = [];
  for (const item of cart.items) {
    const price = await priceFor(item.sku);
    const available = await inStock(item.sku, item.quantity);
    lines.push({ sku: item.sku, quantity: item.quantity, price, available });
  }
  const totalCents = lines.reduce((sum, line) => sum + line.price * line.quantity, 0);
  return { lines, totalCents };
}
