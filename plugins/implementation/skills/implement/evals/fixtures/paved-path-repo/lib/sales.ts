import { db } from "./db";

export async function salesTotalFor(day: Date): Promise<number> {
  const date = day.toISOString().slice(0, 10);
  const row = await db.one("select coalesce(sum(amount), 0) as total from orders where placed_on = $1", [date]);
  return Number(row.total);
}
