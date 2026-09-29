import Database from "better-sqlite3";

const handle = new Database("orders.db");

export const db = {
  query(sql, params = []) {
    return handle.prepare(sql).all(...params);
  },
};
