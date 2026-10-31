const PRICING_URL = "https://pricing.internal.example/prices";

export async function priceFor(sku) {
  const response = await fetch(`${PRICING_URL}/${encodeURIComponent(sku)}`);
  const body = await response.json();
  return body.cents;
}
