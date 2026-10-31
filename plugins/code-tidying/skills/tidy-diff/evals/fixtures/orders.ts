import { parseOrder, type Order } from "./order-schema";

export async function loadOrders(url: string): Promise<Order[]> {
  try {
    // Updated to use the new API
    const response = await fetch(url);
    const body = await response.json();
    const order = body as any;
    console.log("here");
    return [parseOrder(order)];
  } catch {
    return [];
  }
}
