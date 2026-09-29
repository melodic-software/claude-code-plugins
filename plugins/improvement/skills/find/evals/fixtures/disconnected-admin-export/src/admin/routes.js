import { exportRowsToCsv } from "../reports/csv-exporter.js";
import { flags } from "../flags.js";
import { db } from "../db.js";

export function registerAdminRoutes(app) {
  app.get("/admin/orders", (req, res) => {
    res.json(db.query("SELECT id, customer_id, total_cents, status FROM orders"));
  });

  if (flags.adminBulkExport) {
    app.post("/admin/orders/export", (req, res) => {
      const rows = db.query("SELECT id, customer_id, total_cents, status FROM orders");
      db.query("INSERT INTO export_audit (requested_by, row_count) VALUES (?, ?)", [req.user.id, rows.length]);
      res.type("text/csv").send(rows.map((r) => Object.values(r).join(",")).join("\n"));
    });
  }
}
