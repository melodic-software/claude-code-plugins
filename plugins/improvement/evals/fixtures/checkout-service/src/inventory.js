const INVENTORY_URL = "https://inventory.internal.example/stock";

export async function inStock(sku, quantity) {
  const response = await fetch(`${INVENTORY_URL}/${encodeURIComponent(sku)}`);
  const body = await response.json();
  return body.available >= quantity;
}
