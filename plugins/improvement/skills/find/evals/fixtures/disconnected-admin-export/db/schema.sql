CREATE TABLE orders (
  id INTEGER PRIMARY KEY,
  customer_id INTEGER NOT NULL,
  total_cents INTEGER NOT NULL,
  status TEXT NOT NULL
);

CREATE TABLE export_audit (
  id INTEGER PRIMARY KEY,
  requested_by INTEGER NOT NULL,
  row_count INTEGER NOT NULL,
  requested_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);
