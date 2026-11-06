#!/usr/bin/env bash
# Writes a two-server project (payments in TypeScript, inventory in Python) in a git repository.
set -euo pipefail
git init -q
mkdir -p servers/payments/node/src servers/inventory/python

cat >servers/payments/node/src/server.ts <<'TS'
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { charge } from "./gateway.js";

const server = new McpServer({ name: "payments", version: "0.9.0" });

server.registerTool(
  "payments_charge_card",
  {
    description: "Charge a saved card.",
    inputSchema: { customerId: z.string(), amountCents: z.number() },
  },
  async ({ customerId, amountCents }) => ({
    content: [{ type: "text", text: JSON.stringify(await charge(customerId, amountCents)) }],
  }),
);

await server.connect(new StdioServerTransport());
TS

cat >servers/inventory/python/server.py <<'PY'
"""Inventory MCP server."""

from mcp.server.fastmcp import FastMCP

from inventory.db import list_items

mcp = FastMCP("inventory")


@mcp.tool(annotations={"readOnlyHint": True})
def inventory_list_items(warehouse: str, low_stock_only: bool = False) -> str:
    """List the items stocked in one warehouse.

    Use this when the user asks what a warehouse holds or what is running low.

    Args:
        warehouse: Warehouse code, e.g. "SEA-2".
        low_stock_only: Optional. Only items below their reorder point (default: False).

    Returns:
        Each item's SKU, name, quantity on hand, and reorder point.
    """
    return list_items(warehouse, low_stock_only)


if __name__ == "__main__":
    mcp.run()
PY
